# RobotServer.gd  (Godot 4.x)
extends CharacterBody2D
class_name RobotServer

# ---------- Movement / spawn ----------
@export var move_speed: float = 100.0
@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var anim: AnimatedSprite2D   = $AnimatedSprite2D
@onready var ray: RayCast2D = null # Created in _ready

var _moving: bool = false
var _last_dir: Vector2 = Vector2.DOWN
var _nav_debug_line: Line2D = null

# ---------- BT ----------
const Core = preload("res://scripts/bt/bt_core.gd")
# const Act  = preload("res://scripts/bt/bt_actions.gd") # Removed to avoid cyclic ref
const BTRunnerScript = preload("res://scripts/bt/bt_runner.gd")
@onready var bt_runner := BTRunnerScript.new()

# ---------- Inventory ----------
const InventoryScript = preload("res://scripts/Inventory.gd")
var inventory: Inventory

# ---------- Interaction ----------
var _waiting_for_help: bool = false
var _help_item_needed: String = ""

# ---------- Episode Tracking ----------
var _episode_active: bool = false
var _current_food_item: String = ""

# ---------- TaskBoard ----------
const TASK_TYPE_FULFILL_ORDER := "FULFILL_ORDER"
const STEP_TAKE_ORDER := "TAKE_ORDER"
const STEP_PICKUP_FROM_KITCHEN := "PICKUP_FROM_KITCHEN"
const STEP_DELIVER_AND_SERVE := "DELIVER_AND_SERVE"
const TASK_STATE_IN_PROGRESS := "in_progress"
const TASK_STATE_COMPLETED := "completed"
const TASK_STATE_FAILED := "failed"
const HELP_TYPE_HANDOFF := "HANDOFF"
const CHARGING_MARKER := "RS1"
const IDLE_WAIT_MARKER := "RG4"
const EMERGENCY_RECHARGE_RESUME_LEVEL := 55.0
const EMERGENCY_HANDOFF_APPROACH_DISTANCE := 120.0
const DEADLINE_HANDOFF_TRIGGER_MS := 30_000
var _active_task_id: String = ""
var _active_task_step: String = ""
var _active_step_started: bool = false
var _last_replan_ms: int = 0
var _pending_overload_handoff_task_id: String = ""

# ---------- Unified Constraints ----------
const BATTERY_MODE_NORMAL := "normal"
const BATTERY_MODE_CONSERVE := "conserve"
const BATTERY_MODE_EMERGENCY := "emergency"
@export var battery_capacity: float = 100.0
@export var battery_level: float = 100.0
@export var battery_drain_move_per_sec: float = 1.2
@export var battery_drain_idle_per_sec: float = 0.08
@export var battery_conserve_threshold: float = 50.0
@export var battery_emergency_threshold: float = 20.0
@export var battery_charge_per_sec: float = 14.0
var _battery_mode: String = BATTERY_MODE_NORMAL
var _constraint_input: Dictionary = {}
var _active_help_request_id: String = ""
var _active_help_request_type: String = ""
var _help_request_suppressed: bool = false
var _overload_handoff_declined_task_id: String = ""
var _deadline_handoff_declined_task_id: String = ""
var _recharge_override_active: bool = false
var _last_recharge_notice_ms: int = 0
var _battery_emergency_handoff_attempted_task_id: String = ""
var _last_emergency_approach_notice_ms: int = 0
var _last_overload_approach_notice_ms: int = 0
var _pending_player_line_request_id: String = ""

func _has_property(obj: Object, prop_name: String) -> bool:
	for p in obj.get_property_list():
		if str(p.get("name", "")) == prop_name:
			return true
	return false

# ---------- Custom BT Tasks ----------
# Execute actions from "planned_actions" queue one by one
class ActExecutePlan extends Core.Task:
	var current_node: Core.Task = null
	
	func tick(bb: Dictionary, actor: Node) -> int:
		if not bb.has("planned_actions") or bb.planned_actions.is_empty():
			return Core.Status.FAILURE
			
		if current_node == null:
			var action_data = bb.planned_actions[0]
			var action_name = action_data.get("action")
			var params = action_data.get("params", {})
			current_node = _create_action_node(action_name, params, bb, actor)
			var logger = actor.get_node_or_null("/root/EpisodeLogger")
			if logger:
				logger.log_event("action_start", {"action": action_name, "params": params})
			
			if not current_node:
				bb.planned_actions.pop_front()
				return Core.Status.FAILURE
		
		var status = current_node.tick(bb, actor)
		
		if status == Core.Status.SUCCESS:
			var completed_action = bb.planned_actions[0].get("action")
			var logger = actor.get_node_or_null("/root/EpisodeLogger")
			if logger:
				logger.log_event("action_complete", {"action": completed_action, "success": true})
			
			bb.planned_actions.pop_front()
			bb["last_plan_failed"] = false
			current_node = null
			return Core.Status.RUNNING 
			
		elif status == Core.Status.FAILURE:
			bb["last_plan_failed"] = true
			bb.erase("planned_actions")
			current_node = null
			return Core.Status.FAILURE
			
		return Core.Status.RUNNING

	func _create_action_node(name: String, params: Dictionary, bb: Dictionary, actor: Node) -> Core.Task:
		var Act = preload("res://scripts/bt/bt_actions.gd")
		match name:
			"navigate":
				var target_name = params.get("target", "")
				var node = Act.ActNavigate.new()
				if bb.has("locations") and bb["locations"].has(target_name):
					var raw_target: Vector2 = bb["locations"][target_name]
					var resolved_target: Vector2 = raw_target
					var nav_map: RID = actor.get_world_2d().navigation_map
					if nav_map.is_valid():
						var nav_closest := NavigationServer2D.map_get_closest_point(nav_map, raw_target)
						resolved_target = nav_closest
					var temp_key = "nav_target_" + str(Time.get_ticks_msec()) + "_" + str(randi())
					bb[temp_key] = resolved_target
					node.target_key = temp_key
				elif target_name == "customer":
					node.target_key = "target_customer"
				else:
					return null
				return node
				
			"pick":
				var item = params.get("item", "unknown_item")
				bb["item_name"] = item # Set for Pick action to read
				return Act.ActPickItem.new()
				
			"drop":
				return Act.ActDropItem.new()
				
			"ask_help":
				var item = params.get("item", "item")
				bb["item_name"] = item
				return Act.ActAskHelp.new()
				
			_:
				return null

func _ready() -> void:
	add_to_group("robot")
	
	if not has_node("Inventory"):
		inventory = InventoryScript.new()
		inventory.name = "Inventory"
		inventory.capacity = 2
		add_child(inventory)
	else:
		inventory = get_node("Inventory")

	await get_tree().physics_frame
	
	# Configure Navigation Agent
	agent.set_navigation_map(get_world_2d().navigation_map)
	agent.navigation_layers = 1
	# Use native path points from NavigationAgent2D, but apply movement directly in actor.
	# Avoidance callback path can be flaky when nav sources are rebuilt at runtime.
	agent.avoidance_enabled = false
	agent.max_speed = move_speed
	agent.radius = 10.0
	# Avoid over-reacting to far-away agents, which can skew local steering.
	agent.neighbor_distance = 120.0
	agent.time_horizon = 1.0
	agent.debug_enabled = true
	if _has_property(agent, "debug_use_custom"):
		agent.set("debug_use_custom", true)
	if _has_property(agent, "debug_path_custom_color"):
		agent.set("debug_path_custom_color", Color(1.0, 0.15, 0.15, 1.0))
	if _has_property(agent, "debug_path_custom_line_width"):
		agent.set("debug_path_custom_line_width", 3.0)
	
	if agent.avoidance_enabled:
		agent.velocity_computed.connect(_on_agent_velocity_computed)
	await _wait_for_nav_sync(agent.get_navigation_map(), 120)

	if not has_node("NavDebugPath"):
		var l := Line2D.new()
		l.name = "NavDebugPath"
		l.width = 3.0
		l.default_color = Color(1.0, 0.15, 0.15, 1.0)
		l.z_index = 100
		add_child(l)
		_nav_debug_line = l
	else:
		_nav_debug_line = get_node("NavDebugPath") as Line2D

	# Dynamic RayCast creation for BT Avoidance
	if not has_node("RayCast2D"):
		var r = RayCast2D.new()
		r.name = "RayCast2D"
		r.enabled = true
		r.target_position = Vector2(0, 30) # Default
		r.collision_mask = 1 # World/Physics layer
		add_child(r)
		ray = r
	else:
		ray = get_node("RayCast2D")

	var help_mgr = _help_manager()
	if help_mgr:
		if not help_mgr.request_updated.is_connected(_on_help_request_updated):
			help_mgr.request_updated.connect(_on_help_request_updated)
		if not help_mgr.request_resolved.is_connected(_on_help_request_resolved):
			help_mgr.request_resolved.connect(_on_help_request_resolved)
	_connect_dialogue_manager()

	# ---------- BT Construction ----------
	var exec_plan = ActExecutePlan.new()
	var root := Core.Selector.new()
	root.children = [exec_plan]
	
	bt_runner.root = root
	bt_runner.bb = {
		"carrying_item": false,
		"planned_actions": [], # Queue of {action, params}
		"last_plan_failed": false,
		"locations": {} # Will be populated immediately
	}
	add_child(bt_runner)
	
	# ---------- Discover Locations IMMEDIATELY ----------
	_discover_locations()

func _wait_for_nav_sync(nav_map: RID, max_physics_frames: int = 90) -> void:
	if not nav_map.is_valid():
		return
	for _i in range(max_physics_frames):
		if NavigationServer2D.map_get_iteration_id(nav_map) > 0:
			return
		await get_tree().physics_frame

func _discover_locations():
	# Try to get locations from RestaurantMain first (centralized data)
	var restaurant = get_tree().get_root().find_child("Restaurant", true, false)
	if restaurant and restaurant.has_method("get_all_locations"):
		var locs = restaurant.get_all_locations()
		if not locs.is_empty():
			bt_runner.bb["locations"] = locs.duplicate()
			return
	
	# Fallback: discover directly from LocationMarkers
	var markers_node = get_tree().get_root().find_child("LocationMarkers", true, false)
	if markers_node:
		for child in markers_node.get_children():
			if child is Marker2D:
				bt_runner.bb["locations"][child.name] = child.global_position

func _physics_process(dt: float) -> void:
	_update_battery_and_mode(dt)

	# Animation logic: based on current real velocity, not path preview
	_update_anim(velocity)
	
	# Episode position tracking
	if _episode_active:
		var logger = get_node_or_null("/root/EpisodeLogger")
		if logger:
			logger.log_position(global_position)

	_check_episode_completion()

func _check_episode_completion() -> void:
	var has_plan: bool = bt_runner.bb.has("planned_actions") and not bt_runner.bb["planned_actions"].is_empty()
	_constraint_input = _collect_constraint_input()

	# No active current task: select the next robot job from the claimed queue,
	# or claim a new nearby order if we are still in take-order batching mode.
	if _active_task_id == "":
		if _tick_recharge_override(has_plan):
			return
		if not has_plan and not _waiting_for_help:
			_try_acquire_or_activate_robot_work()
		return

	if _sync_active_task_state():
		return

	# Emergency delegation has highest priority for the active task.
	if _tick_emergency_delegation():
		return

	# Deadline-critical handoff is a separate reason from overload and may still
	# be requested even if the player previously rejected an overload handoff.
	if _tick_deadline_handoff_delegation():
		return

	# Overload delegation: approach player first, then request in-person handoff.
	if _tick_overload_handoff_delegation():
		return

	if _tick_recharge_override(has_plan):
		return

	_tick_offer_take_order_handoff()

	# Active task exists: wait until current step plan ends.
	if has_plan or _waiting_for_help:
		return

	# Keep TaskBoard lifecycle consistent with execution outcome.
	# If BT reported failure for this step, never advance step state.
	if bool(bt_runner.bb.get("last_plan_failed", false)):
		bt_runner.bb["last_plan_failed"] = false
		_active_step_started = false
		return

	# Step cannot start yet, keep waiting and re-check constraints.
	if not _active_step_started:
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_replan_ms >= 300:
			_last_replan_ms = now_ms
			_plan_current_task_step()
		return

	_on_active_step_finished()

func _sync_active_task_state() -> bool:
	if _active_task_id == "":
		return false
	var board = _task_board()
	if board == null:
		return false
	var task: Dictionary = board.get_task(_active_task_id)
	if task.is_empty():
		_invalidate_active_help_request("task_missing")
		_end_current_episode(false, "task_missing")
		_clear_current_task_runtime()
		return true

	var state := str(task.get("state", ""))
	if state == TASK_STATE_FAILED:
		var reason := str(task.get("failure_reason", "task_failed"))
		_invalidate_active_help_request("task_failed")
		_end_current_episode(false, reason)
		_clear_current_task_runtime()
		return true
	if state == TASK_STATE_COMPLETED:
		_invalidate_active_help_request("task_completed")
		_end_current_episode(true)
		_clear_current_task_runtime()
		return true
	if state != TASK_STATE_IN_PROGRESS:
		_invalidate_active_help_request("task_invalid_state")
		_end_current_episode(false, "task_invalid_state:" + state)
		_clear_current_task_runtime()
		return true
	return false

func _end_current_episode(success: bool, failure_reason: String = "") -> void:
	if not _episode_active:
		return
	
	var logger = get_node_or_null("/root/EpisodeLogger")
	if logger:
		logger.end_episode(success, failure_reason)
	
	_episode_active = false
	_current_food_item = ""

func _task_board() -> Node:
	return get_node_or_null("/root/TaskBoard")

func _help_manager() -> Node:
	return get_node_or_null("/root/HelpRequestManager")

func _try_acquire_or_activate_robot_work() -> void:
	if _active_task_id != "":
		return
	if _get_robot_assigned_food_tasks().is_empty():
		_try_claim_next_task()
		return
	if _should_continue_collecting_orders():
		_try_claim_next_task()
		return
	if _try_activate_pickup_task():
		return
	if _try_activate_delivery_task():
		return
	if _try_activate_take_order_task():
		return

func _try_claim_next_task() -> void:
	var board = _task_board()
	if not board:
		return
	var task = _get_best_unassigned_food_task()
	if task.is_empty():
		# Idle behavior by battery mode:
		# - emergency: handled by recharge override earlier in tick loop.
		# - conserve: no pending orders -> go charge.
		# - normal: stay on dining side for quicker next-customer response.
		if _battery_mode == BATTERY_MODE_CONSERVE:
			if not _is_near_recharge_station():
				_plan_navigate_to_location(CHARGING_MARKER)
				_try_speak_recharge_notice("Battery low. Recharging while idle.")
			return
		if _battery_mode == BATTERY_MODE_NORMAL and not _is_in_dining_side():
			var locations: Dictionary = bt_runner.bb.get("locations", {})
			if locations.has(IDLE_WAIT_MARKER):
				_plan_navigate_to_location(IDLE_WAIT_MARKER)
		return
	# Pending work exists: in conserve/normal we should still serve orders.
	if _battery_mode == BATTERY_MODE_EMERGENCY:
		var task_slack_ms = int(task.get("deadline_ms", Time.get_ticks_msec()) - Time.get_ticks_msec())
		if task_slack_ms > 20_000:
			return

	var task_id = str(task.get("id", ""))
	if task_id == "":
		return

	var claimed = board.claim_task(task_id, name)
	if claimed.is_empty():
		return

	_start_claimed_task(claimed)

func _tick_offer_take_order_handoff() -> void:
	# Disabled by design: take-order ownership is robot-only now.
	# Overload handoff is triggered only after robot completes TAKE_ORDER for a claimed task.
	return

func _start_claimed_task(task: Dictionary) -> void:
	if not _activate_task_context(task):
		return
	if not _episode_active:
		var payload: Dictionary = task.get("payload", {})
		var customer = _resolve_customer_from_payload(payload)
		var customer_seat = str(payload.get("seat", ""))
		var logger = get_node_or_null("/root/EpisodeLogger")
		if logger and customer != null:
			logger.start_episode(_current_food_item, customer_seat, customer.global_position, global_position)
			_episode_active = true
	_plan_current_task_step()

func _robot_handoff_threshold_tasks() -> int:
	return 5

func _activate_task_context(task: Dictionary) -> bool:
	_active_task_id = str(task.get("id", ""))
	_active_task_step = ""
	_pending_overload_handoff_task_id = ""
	if _active_task_id == "":
		return false
	var payload: Dictionary = task.get("payload", {})
	var customer = _resolve_customer_from_payload(payload)
	if customer == null:
		var board = _task_board()
		if board and board.has_method("complete_task"):
			board.complete_task(_active_task_id)
		_clear_current_task_runtime()
		return false
	bt_runner.bb["target_customer"] = customer
	_current_food_item = str(payload.get("food_item", "unknown"))
	if _current_food_item == "":
		_current_food_item = "unknown"
	return true

func _get_robot_assigned_food_tasks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var board = _task_board()
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee"):
		return out
	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee(name)
	for task in tasks:
		if str(task.get("type", "")) != TASK_TYPE_FULFILL_ORDER:
			continue
		out.append(task)
	return out

func _get_best_unassigned_food_task() -> Dictionary:
	var board = _task_board()
	if board == null or not board.has_method("get_all_tasks"):
		return {}
	var best: Dictionary = {}
	var best_dist := INF
	for task in board.get_all_tasks():
		if str(task.get("type", "")) != TASK_TYPE_FULFILL_ORDER:
			continue
		if str(task.get("state", "")) != "unassigned":
			continue
		var payload: Dictionary = task.get("payload", {})
		var customer = _resolve_customer_from_payload(payload)
		if customer == null:
			continue
		var d := global_position.distance_to(customer.global_position)
		if d < best_dist:
			best_dist = d
			best = task
	return best

func _should_continue_collecting_orders() -> bool:
	if inventory and not inventory.items.is_empty():
		return false
	var assigned := _get_robot_assigned_food_tasks()
	if assigned.size() >= _robot_handoff_threshold_tasks():
		return false
	if not _is_in_dining_side():
		return false
	return not _get_best_unassigned_food_task().is_empty()

func _task_step_name(task: Dictionary) -> String:
	var board = _task_board()
	if board == null or not board.has_method("get_current_step_name"):
		return ""
	return str(board.get_current_step_name(str(task.get("id", ""))))

func _task_slack_ms(task: Dictionary) -> int:
	return int(task.get("deadline_ms", 0)) - Time.get_ticks_msec()

func _task_customer_distance(task: Dictionary) -> float:
	var payload: Dictionary = task.get("payload", {})
	var customer = _resolve_customer_from_payload(payload)
	if customer == null:
		return INF
	return global_position.distance_to(customer.global_position)

func _inventory_has_item_for_task(task: Dictionary) -> bool:
	if inventory == null:
		return false
	var payload: Dictionary = task.get("payload", {})
	var item_name := str(payload.get("food_item", "")).strip_edges()
	if item_name == "":
		return false
	return inventory.find_item(item_name) != -1

func _try_activate_take_order_task() -> bool:
	var tasks := _get_robot_assigned_food_tasks()
	var best: Dictionary = {}
	var best_dist := INF
	for task in tasks:
		if _task_step_name(task) != STEP_TAKE_ORDER:
			continue
		var d := _task_customer_distance(task)
		if d < best_dist:
			best_dist = d
			best = task
	if best.is_empty():
		return false
	if not _activate_task_context(best):
		return false
	_plan_current_task_step()
	return true

func _try_activate_pickup_task() -> bool:
	if inventory and inventory.is_full():
		return false
	var tasks := _get_robot_assigned_food_tasks()
	var best: Dictionary = {}
	var best_slack := INF
	for task in tasks:
		if _task_step_name(task) != STEP_PICKUP_FROM_KITCHEN:
			continue
		var slack := _task_slack_ms(task)
		if slack < best_slack:
			best_slack = slack
			best = task
	if best.is_empty():
		return false
	if not _activate_task_context(best):
		return false
	_plan_current_task_step()
	return true

func _try_activate_delivery_task() -> bool:
	var tasks := _get_robot_assigned_food_tasks()
	var best: Dictionary = {}
	var best_score := INF
	for task in tasks:
		if _task_step_name(task) != STEP_DELIVER_AND_SERVE:
			continue
		if not _inventory_has_item_for_task(task):
			continue
		var score := float(_task_slack_ms(task)) + _task_customer_distance(task)
		if score < best_score:
			best_score = score
			best = task
	if best.is_empty():
		return false
	if not _activate_task_context(best):
		return false
	_plan_current_task_step()
	return true

func _resolve_customer_from_payload(payload: Dictionary) -> Node2D:
	var iid = int(payload.get("customer_instance_id", 0))
	if iid > 0:
		var obj = instance_from_id(iid)
		if obj is Node2D and is_instance_valid(obj):
			return obj
	return null

func _plan_current_task_step() -> void:
	var board = _task_board()
	if not board or _active_task_id == "":
		return

	_active_task_step = board.get_current_step_name(_active_task_id)
	_active_step_started = false
	if _active_task_step == "":
		_finish_active_task_if_needed()
		return

	_constraint_input = _collect_constraint_input()

	match _active_task_step:
		STEP_TAKE_ORDER:
			_plan_take_order_step()
		STEP_PICKUP_FROM_KITCHEN:
			_plan_pickup_step()
		STEP_DELIVER_AND_SERVE:
			_plan_deliver_step()
		_:
			pass

func _plan_take_order_step() -> void:
	var customer := bt_runner.bb.get("target_customer", null) as Node2D
	if customer == null:
		return

	var serve_poses = get_tree().get_nodes_in_group("serveposes")
	var nearest_pose: Node2D = null
	var min_dist := INF
	for pose in serve_poses:
		if not (pose is Node2D):
			continue
		var d = pose.global_position.distance_to(customer.global_position)
		if d < min_dist:
			min_dist = d
			nearest_pose = pose

	if nearest_pose:
		var locations: Dictionary = bt_runner.bb.get("locations", {})
		if not locations.has(nearest_pose.name):
			locations[nearest_pose.name] = nearest_pose.global_position
			bt_runner.bb["locations"] = locations
		_set_step_plan([
			{"action": "navigate", "params": {"target": nearest_pose.name}}
		])
		speak("I'll take your order now.")

func _plan_pickup_step() -> void:
	var item_name := _current_food_item
	var locations: Dictionary = bt_runner.bb.get("locations", {})
	if item_name == "" or not locations.has(item_name):
		item_name = "pizza"

	bt_runner.bb["item_name"] = item_name
	var raw_target: Vector2 = locations.get(item_name, Vector2.ZERO)
	_set_step_plan([
		{"action": "navigate", "params": {"target": item_name}},
		{"action": "pick", "params": {"item": item_name}}
	])
	speak("Heading to kitchen for " + item_name + ".")

func _plan_deliver_step() -> void:
	var actions := [
		{"action": "navigate", "params": {"target": "customer"}},
		{"action": "drop", "params": {}}
	]
	# Return to charging station only when battery is already in constrained modes.
	if _battery_mode == BATTERY_MODE_CONSERVE or _battery_mode == BATTERY_MODE_EMERGENCY:
		actions.append({"action": "navigate", "params": {"target": "RS1"}})
	_set_step_plan(actions)
	speak("Delivering now.")

func _on_active_step_finished() -> void:
	var board = _task_board()
	if not board or _active_task_id == "":
		return

	var expected_step := _active_task_step
	if expected_step == "":
		expected_step = board.get_current_step_name(_active_task_id)

	var ok = board.complete_current_step(_active_task_id, expected_step)
	if not ok:
		return

	if expected_step == STEP_TAKE_ORDER:
		var customer: Node = bt_runner.bb.get("target_customer", null)
		if customer != null and customer.has_method("on_food_order_taken"):
			customer.call("on_food_order_taken")
		if _should_continue_collecting_orders():
			_clear_current_task_runtime()
			return

	if expected_step == STEP_PICKUP_FROM_KITCHEN and inventory != null and not inventory.is_full():
		for task in _get_robot_assigned_food_tasks():
			if _task_step_name(task) == STEP_PICKUP_FROM_KITCHEN:
				_clear_current_task_runtime()
				return

	_active_step_started = false
	_finish_active_task_if_needed()
	if _active_task_id != "":
		_plan_current_task_step()

func _finish_active_task_if_needed() -> void:
	var board = _task_board()
	if not board or _active_task_id == "":
		return
	if not board.is_task_completed(_active_task_id):
		return

	_end_current_episode(true)
	_clear_current_task_runtime()

func _clear_current_task_runtime() -> void:
	_active_task_id = ""
	_active_task_step = ""
	_active_step_started = false
	_pending_overload_handoff_task_id = ""
	_last_replan_ms = 0
	_recharge_override_active = false
	_battery_emergency_handoff_attempted_task_id = ""
	bt_runner.bb.erase("target_customer")
	bt_runner.bb["last_plan_failed"] = false
	bt_runner.bb["planned_actions"] = []
	set_nav_debug_path(PackedVector2Array())
	_waiting_for_help = false
	_help_item_needed = ""
	_active_help_request_id = ""
	_active_help_request_type = ""
	_help_request_suppressed = false
	if _get_robot_assigned_food_tasks().is_empty():
		_overload_handoff_declined_task_id = ""
		_deadline_handoff_declined_task_id = ""

func _invalidate_active_help_request(resolution_path: String) -> void:
	if _active_help_request_id == "":
		return
	var help_mgr = _help_manager()
	if help_mgr and help_mgr.has_method("cancel_request"):
		help_mgr.cancel_request(_active_help_request_id, resolution_path)

func _set_step_plan(actions: Array) -> void:
	if actions.is_empty():
		bt_runner.bb["planned_actions"] = []
		_active_step_started = false
		bt_runner.bb["last_plan_failed"] = false
		return
	bt_runner.bb["planned_actions"] = actions
	_active_step_started = true
	bt_runner.bb["last_plan_failed"] = false

func _collect_constraint_input() -> Dictionary:
	var now_ms := Time.get_ticks_msec()
	var deadline_ms := 0
	var slack_ms := 0
	var board = _task_board()
	if board and _active_task_id != "":
		var task = board.get_task(_active_task_id)
		if not task.is_empty():
			deadline_ms = int(task.get("deadline_ms", 0))
			slack_ms = int(task.get("deadline_ms", now_ms) - now_ms)

	var input = {
		"timestamp_ms": now_ms,
		"battery_level": battery_level,
		"battery_mode": _battery_mode,
		"active_task_id": _active_task_id,
		"active_step": _active_task_step,
		"deadline_ms": deadline_ms,
		"slack_ms": slack_ms,
		"deadline_urgency_weight": 1.0
	}

	if _battery_mode == BATTERY_MODE_EMERGENCY:
		input["deadline_urgency_weight"] = 0.7
	elif _battery_mode == BATTERY_MODE_CONSERVE:
		input["deadline_urgency_weight"] = 0.9

	return input

func _tick_emergency_delegation() -> bool:
	if _active_task_id == "":
		return false

	var is_battery_emergency := _battery_mode == BATTERY_MODE_EMERGENCY
	if not is_battery_emergency:
		return false

	# If currently waiting on a help request, keep waiting (highest priority state).
	if _waiting_for_help:
		return true

	var help_mgr = _help_manager()
	if help_mgr == null:
		return false

	var player = _get_primary_player()
	if player == null:
		return false

	if _active_help_request_id != "":
		var existing: Dictionary = help_mgr.get_request(_active_help_request_id)
		if not existing.is_empty():
			var st := str(existing.get("status", ""))
			if st != "resolved":
				_waiting_for_help = true
				return true

	# Emergency handoff must be in-person: approach player first, then request/popup.
	var distance_to_player := global_position.distance_to(player.global_position)
	if distance_to_player > EMERGENCY_HANDOFF_APPROACH_DISTANCE:
		_waiting_for_help = false
		var has_plan: bool = bt_runner.bb.has("planned_actions") and not bt_runner.bb["planned_actions"].is_empty()
		if not has_plan:
			_plan_navigate_to_position(player.global_position, "emergency_player")
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_emergency_approach_notice_ms > 1800:
			_last_emergency_approach_notice_ms = now_ms
			speak("Battery critical. Coming to you for urgent handoff.")
		return true

	var reason := ""
	if is_battery_emergency and _battery_emergency_handoff_attempted_task_id != _active_task_id:
		reason = "battery_emergency"
		_battery_emergency_handoff_attempted_task_id = _active_task_id
	else:
		# Already attempted emergency delegation for this task.
		# Battery emergency should now force recharge override.
		if is_battery_emergency and not _recharge_override_active:
			_activate_recharge_override("Battery critical. Recharging now.")
			return true
		return false

	var board = _task_board()
	var item_needed := "item"
	var slack_ms := int(_constraint_input.get("slack_ms", 0))
	if board and board.has_method("get_task"):
		var task: Dictionary = board.get_task(_active_task_id)
		var payload: Dictionary = task.get("payload", {})
		item_needed = str(payload.get("food_item", "item"))

	_ensure_help_request(HELP_TYPE_HANDOFF, {
		"handoff_mode": "TAKEOVER_TASK",
		"task_id": _active_task_id,
		"item_needed": item_needed,
		"reason": reason,
		"slack_ms": slack_ms
	}, {
		"cooldown_ms": 2500,
		"max_escalation": 1,
		"urgency": 1.0
	})
	_waiting_for_help = true
	speak("Battery critical. Please take this order while I recharge.")
	return true

func _tick_overload_handoff_delegation() -> bool:
	if _active_task_id == "":
		return false
	if _pending_overload_handoff_task_id == "" or _pending_overload_handoff_task_id != _active_task_id:
		return false
	if _overload_handoff_declined_task_id == _active_task_id:
		# Player refused this request episode; continue task execution.
		_pending_overload_handoff_task_id = ""
		return false

	var help_mgr = _help_manager()
	if help_mgr == null:
		return false
	var player = _get_primary_player()
	if player == null:
		return false

	if _active_help_request_id != "":
		var existing: Dictionary = help_mgr.get_request(_active_help_request_id)
		if not existing.is_empty():
			var st := str(existing.get("status", ""))
			if st != "resolved":
				_waiting_for_help = true
				return true

	var distance_to_player := global_position.distance_to(player.global_position)
	if distance_to_player > EMERGENCY_HANDOFF_APPROACH_DISTANCE:
		_waiting_for_help = false
		var has_plan: bool = bt_runner.bb.has("planned_actions") and not bt_runner.bb["planned_actions"].is_empty()
		if not has_plan:
			_plan_navigate_to_position(player.global_position, "overload_player")
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_overload_approach_notice_ms > 1800:
			_last_overload_approach_notice_ms = now_ms
			speak("Task load is high. Coming to you for handoff.")
		return true

	var board = _task_board()
	var item_needed := "item"
	var slack_ms := int(_constraint_input.get("slack_ms", 0))
	if board and board.has_method("get_task"):
		var task: Dictionary = board.get_task(_active_task_id)
		var payload: Dictionary = task.get("payload", {})
		item_needed = str(payload.get("food_item", "item"))

	_ensure_help_request(HELP_TYPE_HANDOFF, {
		"handoff_mode": "TAKEOVER_TASK",
		"task_id": _active_task_id,
		"item_needed": item_needed,
		"reason": "robot_over_threshold_post_take_order",
		"slack_ms": slack_ms
	}, {
		"cooldown_ms": 4000,
		"max_escalation": 2,
		"urgency": _estimate_help_urgency()
	})
	_waiting_for_help = true
	speak("Task load is high. Please take over this order.")
	return true

func _tick_deadline_handoff_delegation() -> bool:
	if _active_task_id == "":
		return false
	if _deadline_handoff_declined_task_id == _active_task_id:
		return false
	if _waiting_for_help:
		return true

	var slack_ms := int(_constraint_input.get("slack_ms", 0))
	if slack_ms <= 0 or slack_ms > DEADLINE_HANDOFF_TRIGGER_MS:
		return false

	var help_mgr = _help_manager()
	if help_mgr == null:
		return false
	var player = _get_primary_player()
	if player == null:
		return false

	if _active_help_request_id != "":
		var existing: Dictionary = help_mgr.get_request(_active_help_request_id)
		if not existing.is_empty():
			var st := str(existing.get("status", ""))
			if st != "resolved":
				_waiting_for_help = true
				return true

	var distance_to_player := global_position.distance_to(player.global_position)
	if distance_to_player > EMERGENCY_HANDOFF_APPROACH_DISTANCE:
		_waiting_for_help = false
		var has_plan: bool = bt_runner.bb.has("planned_actions") and not bt_runner.bb["planned_actions"].is_empty()
		if not has_plan:
			_plan_navigate_to_position(player.global_position, "deadline_player")
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_overload_approach_notice_ms > 1800:
			_last_overload_approach_notice_ms = now_ms
			speak("This order is close to timing out. Coming to you for urgent handoff.")
		return true

	var board = _task_board()
	var item_needed := "item"
	if board and board.has_method("get_task"):
		var task: Dictionary = board.get_task(_active_task_id)
		var payload: Dictionary = task.get("payload", {})
		item_needed = str(payload.get("food_item", "item"))

	_ensure_help_request(HELP_TYPE_HANDOFF, {
		"handoff_mode": "TAKEOVER_TASK",
		"task_id": _active_task_id,
		"item_needed": item_needed,
		"reason": "deadline_critical",
		"slack_ms": slack_ms
	}, {
		"cooldown_ms": 2500,
		"max_escalation": 1,
		"urgency": 1.0
	})
	_waiting_for_help = true
	speak("This order is about to time out. Please take it now.")
	return true

func _get_primary_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	if players[0] is Node2D:
		return players[0] as Node2D
	return null

func _is_in_dining_side() -> bool:
	# Keep normal-idle robot on customer side (lower room).
	return global_position.y >= -150.0

func _update_battery_and_mode(dt: float) -> void:
	var moving := velocity.length() > 1.0
	var drain_rate := battery_drain_idle_per_sec
	if moving:
		drain_rate = battery_drain_move_per_sec

	battery_level -= drain_rate * dt
	# Charge whenever robot is inside recharge zone, even with an active task/recharge override.
	if _is_near_recharge_station():
		battery_level += battery_charge_per_sec * dt

	battery_level = clampf(battery_level, 0.0, battery_capacity)
	_update_battery_mode()
	_update_agent_speed_by_battery_mode()

func _update_battery_mode() -> void:
	var previous := _battery_mode
	if battery_level <= battery_emergency_threshold:
		_battery_mode = BATTERY_MODE_EMERGENCY
	elif battery_level <= battery_conserve_threshold:
		_battery_mode = BATTERY_MODE_CONSERVE
	else:
		_battery_mode = BATTERY_MODE_NORMAL

	if previous != _battery_mode:
		# Emergency mode should immediately interrupt execution and recharge.
		if _battery_mode == BATTERY_MODE_EMERGENCY:
			_activate_recharge_override("Battery critical. Recharging now.")

func _update_agent_speed_by_battery_mode() -> void:
	var speed_scale := 1.0
	if _battery_mode == BATTERY_MODE_CONSERVE:
		speed_scale = 0.8
	elif _battery_mode == BATTERY_MODE_EMERGENCY:
		speed_scale = 0.6
	agent.max_speed = move_speed * speed_scale

func _is_near_recharge_station() -> bool:
	var station = bt_runner.bb.get("locations", {}).get(CHARGING_MARKER, Vector2.ZERO)
	if station == Vector2.ZERO:
		return false
	# Navigation arrival often stops around 40-50px from exact marker.
	return global_position.distance_to(station) <= 60.0

func _estimate_help_urgency() -> float:
	var slack_ms := int(_constraint_input.get("slack_ms", 0))
	var slack_urgency := 0.5
	if slack_ms != 0:
		slack_urgency = clampf(1.0 - (float(slack_ms) / 90000.0), 0.0, 1.0)
	var battery_urgency := 0.0
	if _battery_mode == BATTERY_MODE_EMERGENCY:
		battery_urgency = 1.0
	elif _battery_mode == BATTERY_MODE_CONSERVE:
		battery_urgency = 0.6
	return clampf(maxf(slack_urgency, battery_urgency), 0.0, 1.0)

func _plan_navigate_to_location(location_name: String) -> void:
	_set_step_plan([{"action": "navigate", "params": {"target": location_name}}])

func _plan_navigate_to_position(pos: Vector2, key_prefix: String = "temp_nav") -> void:
	var key = "%s_%d" % [key_prefix, Time.get_ticks_msec()]
	bt_runner.bb["locations"][key] = pos
	_set_step_plan([{"action": "navigate", "params": {"target": key}}])

func _activate_recharge_override(notice: String = "") -> void:
	if _recharge_override_active:
		return
	_recharge_override_active = true
	_waiting_for_help = false
	bt_runner.bb["planned_actions"] = []
	_active_step_started = false
	_plan_navigate_to_location(CHARGING_MARKER)
	_try_speak_recharge_notice(notice)

func _tick_recharge_override(has_plan: bool) -> bool:
	# Enter override proactively on emergency battery.
	if _battery_mode == BATTERY_MODE_EMERGENCY and not _recharge_override_active:
		# Give emergency handoff (if any) a chance before forcing recharge travel.
		if _waiting_for_help:
			return true
		var help_mgr = _help_manager()
		if help_mgr and _active_help_request_id != "":
			var req: Dictionary = help_mgr.get_request(_active_help_request_id)
			if not req.is_empty() and str(req.get("status", "")) != "resolved":
				return true
		_activate_recharge_override("Battery critical. Recharging now.")
		return true

	if not _recharge_override_active:
		return false

	if _is_near_recharge_station():
		# Pause work while charging until safe level.
		if battery_level >= maxf(EMERGENCY_RECHARGE_RESUME_LEVEL, battery_conserve_threshold + 5.0):
			_recharge_override_active = false
			_active_step_started = false
			if _active_task_id != "":
				_try_speak_recharge_notice("Battery stabilized. Resuming task.")
				_plan_current_task_step()
			else:
				_try_speak_recharge_notice("Battery stabilized. Ready for new tasks.")
			return false
		bt_runner.bb["planned_actions"] = []
		return true

	if not has_plan:
		_plan_navigate_to_location(CHARGING_MARKER)
	return true

func _try_speak_recharge_notice(text: String) -> void:
	if text.strip_edges() == "":
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_recharge_notice_ms < 1800:
		return
	_last_recharge_notice_ms = now_ms
	speak(text)

func _ensure_help_request(request_type: String, payload: Dictionary = {}, options: Dictionary = {}) -> void:
	var help_mgr = _help_manager()
	if not help_mgr:
		return

	if _active_help_request_id != "":
		var current = help_mgr.get_request(_active_help_request_id)
		if not current.is_empty():
			var status = str(current.get("status", ""))
			if status != "resolved":
				return

	var req = help_mgr.create_request(request_type, self, payload, options)
	if req.is_empty():
		return

	_active_help_request_id = str(req.get("id", ""))
	_active_help_request_type = request_type
	_waiting_for_help = true

func open_help_request_ui(_player: Node) -> bool:
	var help_mgr = _help_manager()
	if not help_mgr:
		return false

	var req: Dictionary = {}
	if _active_help_request_id != "":
		req = help_mgr.get_request(_active_help_request_id)
		if not req.is_empty() and str(req.get("status", "")) == "cooldown":
			return false
		if req.is_empty() or str(req.get("status", "")) == "resolved":
			req = {}

	if req.is_empty():
		req = help_mgr.get_promptable_request_for_robot(self)
		if req.is_empty():
			return false
		_active_help_request_id = str(req.get("id", ""))
		_active_help_request_type = str(req.get("type", ""))

	help_mgr.mark_prompted(_active_help_request_id)
	_show_help_request_ui(req)
	return true

func _show_help_request_ui(request: Dictionary) -> void:
	var huds = get_tree().get_nodes_in_group("hud")
	if huds.is_empty():
		return
	var hud = huds[0]
	if hud and hud.has_method("show_help_request"):
		hud.show_help_request(request)

func _on_help_request_updated(request: Dictionary) -> void:
	if request.is_empty():
		return
	if int(request.get("robot_instance_id", 0)) != get_instance_id():
		return

	var req_id = str(request.get("id", ""))
	var status = str(request.get("status", ""))
	var final_response = str(request.get("final_response", ""))
	var payload: Dictionary = request.get("payload", {})
	var reason := str(payload.get("reason", ""))
	var task_id := str(payload.get("task_id", ""))
	_active_help_request_id = req_id
	_active_help_request_type = str(request.get("type", ""))

	if status == "accepted":
		_help_request_suppressed = false
		if task_id != "":
			if _overload_handoff_declined_task_id == task_id:
				_overload_handoff_declined_task_id = ""
			if _deadline_handoff_declined_task_id == task_id:
				_deadline_handoff_declined_task_id = ""
		_apply_handoff_accept(request)
	elif status == "resolved" and final_response == "decline":
		if reason == "robot_over_threshold_post_take_order" and task_id != "":
			_overload_handoff_declined_task_id = task_id
		elif reason == "deadline_critical" and task_id != "":
			_deadline_handoff_declined_task_id = task_id
		else:
			_help_request_suppressed = true
		set_waiting_for_help(false, "")
		if _battery_mode == BATTERY_MODE_EMERGENCY and not _recharge_override_active:
			_activate_recharge_override("Battery critical. Recharging now.")

func _apply_handoff_accept(request: Dictionary) -> void:
	var payload: Dictionary = request.get("payload", {})
	var mode := str(payload.get("handoff_mode", "TAKEOVER_TASK"))
	var task_id := str(payload.get("task_id", _active_task_id))
	if task_id == "":
		return
	var board = _task_board()
	if board == null:
		return

	if mode == "TAKEOVER_ITEM":
		if not _transfer_item_to_player_for_handoff(payload):
			var help_mgr_retry = _help_manager()
			if help_mgr_retry and _active_help_request_id != "" and help_mgr_retry.has_method("requeue_request"):
				help_mgr_retry.requeue_request(_active_help_request_id, 1800, "player_inventory_full")
			set_waiting_for_help(false, "")
			_active_help_request_id = ""
			_active_help_request_type = ""
			speak("Your inventory is full. I still have this item.")
			return

	var updated: Dictionary = {}
	var task_snapshot: Dictionary = board.get_task(task_id) if board.has_method("get_task") else {}
	var task_state := str(task_snapshot.get("state", ""))
	var task_payload: Dictionary = task_snapshot.get("payload", {})
	var order_kind := str(task_payload.get("order_kind", "food"))
	var step_before_transfer := str(board.get_current_step_name(task_id)) if board.has_method("get_current_step_name") else ""
	print("[RobotServer][HandoffAccept] task=%s mode=%s order=%s state_before=%s step_before=%s item=%s" % [
		task_id,
		mode,
		order_kind,
		task_state,
		step_before_transfer,
		str(task_payload.get("display_item", task_payload.get("food_item", task_payload.get("drink_item", ""))))
	])
	if task_state == "unassigned" and board.has_method("claim_task"):
		updated = board.claim_task(task_id, "player")
	elif board.has_method("reassign_task"):
		updated = board.reassign_task(task_id, "player")
	if updated.is_empty():
		print("[RobotServer][HandoffAccept] task=%s failed_to_transfer" % task_id)
		return

	# A robot-to-player task handoff already communicates the order details.
	# Force food tasks into pickup state so the player can go straight to the
	# kitchen without being blocked by a stale TAKE_ORDER step.
	if mode == "TAKEOVER_TASK" and order_kind == "food" and board.has_method("complete_current_step"):
		var step_after_transfer := str(board.get_current_step_name(task_id)) if board.has_method("get_current_step_name") else step_before_transfer
		if step_before_transfer == STEP_TAKE_ORDER or step_after_transfer == STEP_TAKE_ORDER:
			board.complete_current_step(task_id, STEP_TAKE_ORDER)
			updated = board.get_task(task_id) if board.has_method("get_task") else updated
	var final_step := str(board.get_current_step_name(task_id)) if board.has_method("get_current_step_name") else ""
	var final_task: Dictionary = board.get_task(task_id) if board.has_method("get_task") else updated
	print("[RobotServer][HandoffAccept] task=%s assignee=%s state_after=%s step_after=%s" % [
		task_id,
		str(final_task.get("assigned_to", "")),
		str(final_task.get("state", "")),
		final_step
	])

	if task_id == _active_task_id:
		_end_current_episode(false, "task_handoff_to_player")
		_clear_current_task_runtime()
		bt_runner.bb["planned_actions"] = []
		_active_step_started = false

	set_waiting_for_help(false, "")
	speak("Task handoff accepted. You take over this order.")
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var player = players[0]
		if player is Node2D:
			_request_player_line(
				player as Node2D,
				self,
				"player_handoff_accept",
				"Okay, I will take over this order.",
				{
					"item_name": _current_food_item,
					"context_note": "The player accepts the robot's task handoff and speaks back to the robot."
				}
			)
	var help_mgr = _help_manager()
	if help_mgr and _active_help_request_id != "":
		help_mgr.complete_request(_active_help_request_id, "cooperative_handoff_task_transfer")
	_active_help_request_id = ""
	_active_help_request_type = ""

func _transfer_item_to_player_for_handoff(payload: Dictionary) -> bool:
	if inventory == null or inventory.items.is_empty():
		print("[RobotServer][ItemHandoff] no_robot_item item_needed=%s" % str(payload.get("item_needed", "")))
		return false
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		print("[RobotServer][ItemHandoff] no_player item_needed=%s" % str(payload.get("item_needed", "")))
		return false
	var player = players[0]
	if not (player is Node2D):
		print("[RobotServer][ItemHandoff] player_not_node2d")
		return false
	var p_inv = player.get_node_or_null("Inventory")
	if p_inv == null:
		print("[RobotServer][ItemHandoff] no_player_inventory")
		return false
	var preferred := str(payload.get("item_needed", "")).strip_edges()
	var idx := -1
	if preferred != "":
		idx = inventory.find_item(preferred)
	if idx == -1:
		idx = inventory.items.size() - 1
	if idx < 0 or idx >= inventory.items.size():
		print("[RobotServer][ItemHandoff] no_matching_robot_item preferred=%s" % preferred)
		return false
	var item: Dictionary = inventory.items.pop_at(idx)
	var item_name := str(item.get("name", "item"))
	var accepted: bool = p_inv.add_item(item_name, item.get("atlas", null), item.get("region", Rect2i()))
	if not accepted:
		inventory.items.insert(idx, item)
		inventory.emit_signal("inventory_changed", inventory.items)
		print("[RobotServer][ItemHandoff] player_inventory_full item=%s" % item_name)
		return false
	inventory.emit_signal("inventory_changed", inventory.items)
	if inventory.items.is_empty():
		bt_runner.bb["carrying_item"] = false
	print("[RobotServer][ItemHandoff] transferred item=%s preferred=%s player_items=%d robot_items=%d" % [
		item_name,
		preferred,
		p_inv.items.size(),
		inventory.items.size()
	])
	return true

func _on_help_request_resolved(request: Dictionary) -> void:
	if request.is_empty():
		return
	if int(request.get("robot_instance_id", 0)) != get_instance_id():
		return

	var req_id = str(request.get("id", ""))
	if _active_help_request_id == req_id:
		_active_help_request_id = ""
		_active_help_request_type = ""

func set_nav_debug_path(world_points: PackedVector2Array) -> void:
	if _nav_debug_line == null:
		return
	if world_points.is_empty():
		_nav_debug_line.points = PackedVector2Array()
		return
	var local_points := PackedVector2Array()
	for p in world_points:
		local_points.push_back(to_local(p))
	_nav_debug_line.points = local_points

func _on_agent_velocity_computed(safe_velocity: Vector2) -> void:
	if _waiting_for_help:
		_moving = false
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if safe_velocity.length() < 0.1:
		_moving = false
		velocity = Vector2.ZERO
	else:
		_moving = true
		velocity = safe_velocity
	move_and_slide()

func _update_anim(v: Vector2) -> void:
	var moving := v.length() > 1.0
	if moving:
		_last_dir = v
	var dir_name := ""
	if abs(_last_dir.x) > abs(_last_dir.y):
		dir_name = "right" if _last_dir.x > 0.0 else "left"
	else:
		dir_name = "down" if _last_dir.y > 0.0 else "up"
	var anim_name := ("walk_" + dir_name) if moving else ("idle_" + dir_name)
	if anim.animation != anim_name:
		anim.play(anim_name)

func speak(text: String) -> void:
	var bubble_mgr = get_node_or_null("/root/BubbleManager")
	if bubble_mgr and bubble_mgr.has_method("say"):
		bubble_mgr.say(self, text, 2.6, Color(0.88, 0.96, 1.0, 1.0))

func _connect_dialogue_manager() -> void:
	var dm = get_node_or_null("/root/DialogueManager")
	if dm and dm.has_signal("directed_utterance_generated") and not dm.directed_utterance_generated.is_connected(_on_directed_utterance_generated):
		dm.directed_utterance_generated.connect(_on_directed_utterance_generated)

func _request_player_line(player: Node2D, recipient: Node2D, intent_type: String, fallback: String, payload: Dictionary = {}) -> void:
	var dm = get_node_or_null("/root/DialogueManager")
	var bubble_mgr = get_node_or_null("/root/BubbleManager")
	if bubble_mgr == null or recipient == null or not is_instance_valid(recipient):
		return
	if dm == null or not dm.has_method("realize_directed_utterance"):
		if bubble_mgr.has_method("say_to"):
			bubble_mgr.say_to(player, recipient, fallback, 2.6, Color(1.0, 0.94, 0.78, 1.0))
		return
	_pending_player_line_request_id = "robot_player_%s_%d" % [str(get_instance_id()), Time.get_ticks_msec()]
	var request := {
		"id": _pending_player_line_request_id,
		"source_role": "player",
		"recipient_role": "robot",
		"intent_type": intent_type,
		"fallback": fallback,
		"item_name": str(payload.get("item_name", "")),
		"context_note": str(payload.get("context_note", ""))
	}
	dm.realize_directed_utterance(request)

func _on_directed_utterance_generated(request_id: String, utterance: String, _meta: Dictionary) -> void:
	if request_id != _pending_player_line_request_id:
		return
	_pending_player_line_request_id = ""
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty() or not (players[0] is Node2D):
		return
	var player := players[0] as Node2D
	var bubble_mgr = get_node_or_null("/root/BubbleManager")
	if bubble_mgr and bubble_mgr.has_method("say_to"):
		bubble_mgr.say_to(player, self, utterance, 2.6, Color(1.0, 0.94, 0.78, 1.0))

# ---------- Interaction Interface ----------
func needs_help() -> bool:
	return _waiting_for_help

func set_waiting_for_help(waiting: bool, item_name: String):
	_waiting_for_help = waiting
	_help_item_needed = item_name
	if not waiting:
		return

	if _help_item_needed.strip_edges() == "":
		return

	var handoff_mode := "TAKEOVER_TASK"
	if _active_task_step == STEP_DELIVER_AND_SERVE and inventory and not inventory.items.is_empty():
		handoff_mode = "TAKEOVER_ITEM"

	# Hand-off help is created here (e.g. BT ask_help path).
	_ensure_help_request(HELP_TYPE_HANDOFF, {
		"handoff_mode": handoff_mode,
		"task_id": _active_task_id,
		"item_needed": _help_item_needed,
		"reason": "robot_stuck_or_pick_fail",
		"slack_ms": int(_constraint_input.get("slack_ms", 0))
	}, {
		"cooldown_ms": 3500,
		"max_escalation": 2,
		"urgency": _estimate_help_urgency()
	})

func receive_player_help():
	# Deprecated: handoff is now explicit task reassignment to player.
	return

func on_player_interact(player: Node) -> void:
	return
