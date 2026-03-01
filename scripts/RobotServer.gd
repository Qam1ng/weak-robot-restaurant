# RobotServer.gd  (Godot 4.x)
extends CharacterBody2D
class_name RobotServer

# ---------- Movement / spawn ----------
@export var spawn_path: NodePath
@export var move_speed: float = 120.0
@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var anim: AnimatedSprite2D   = $AnimatedSprite2D
@onready var ray: RayCast2D = null # Created in _ready

var _moving: bool = false
var _last_dir: Vector2 = Vector2.DOWN

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
const EMERGENCY_RECHARGE_RESUME_LEVEL := 55.0
const ROBOT_MAX_ACTIVE_TASKS := 1
var _active_task_id: String = ""
var _active_task_step: String = ""
var _active_step_started: bool = false
var _last_replan_ms: int = 0

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
var _recharge_override_active: bool = false
var _last_recharge_notice_ms: int = 0

# ---------- Custom BT Tasks ----------
# Execute actions from "planned_actions" queue one by one
class ActExecutePlan extends Core.Task:
	var current_node: Core.Task = null
	
	func tick(bb: Dictionary, actor: Node) -> int:
		# 1. Check if we have a plan
		if not bb.has("planned_actions") or bb.planned_actions.is_empty():
			return Core.Status.FAILURE
			
		# 2. Instantiate Action Node if needed
		if current_node == null:
			# Peek at the first action
			var action_data = bb.planned_actions[0]
			var action_name = action_data.get("action")
			var params = action_data.get("params", {})
			
			print("[BT] Creating node for action: ", action_name)
			current_node = _create_action_node(action_name, params, bb)
			
			# Log action start
			var logger = actor.get_node_or_null("/root/EpisodeLogger")
			if logger:
				logger.log_event("action_start", {"action": action_name, "params": params})
			
			if not current_node:
				print("[BT] Unknown action or failed to create: ", action_name)
				# Remove the bad action to avoid infinite loop
				bb.planned_actions.pop_front()
				return Core.Status.FAILURE
		
		# 3. Tick current node
		var status = current_node.tick(bb, actor)
		
		if status == Core.Status.SUCCESS:
			var completed_action = bb.planned_actions[0].get("action")
			print("[BT] Action completed: ", completed_action)
			
			# Log action completion
			var logger = actor.get_node_or_null("/root/EpisodeLogger")
			if logger:
				logger.log_event("action_complete", {"action": completed_action, "success": true})
			
			# Action done, remove from queue
			bb.planned_actions.pop_front()
			bb["last_plan_failed"] = false
			current_node = null
			return Core.Status.RUNNING 
			
		elif status == Core.Status.FAILURE:
			var failed_action = bb.planned_actions[0]
			var action_name = failed_action.get("action")
			print("[BT] Action failed: ", action_name)

			# Fallback Logic for Navigate/Pick Failure (e.g., evasion timeout)
			if action_name == "navigate" or action_name == "pick":
				var help_reason = bb.get("help_reason", "unknown")
				print("[BT] Action failed: ", action_name, ". Reason: ", help_reason, ". Entering Fallback Logic.")
				
				# Check if next (or current failed) action relates to picking an item
				var item_needed = ""
				if action_name == "pick":
					item_needed = failed_action.get("params", {}).get("item", "item")
				elif bb.planned_actions.size() > 0:
					# If nav failed, check if next action was pick
					# bb.planned_actions[0] is the failed action itself
					# If failed action is navigate, check if there is a subsequent pick
					if bb.planned_actions.size() > 1:
						var next = bb.planned_actions[1]
						if next.get("action") == "pick":
							item_needed = next.get("params", {}).get("item", "item")
				
				if item_needed != "":
					var reason_text = "navigation failed"
					if help_reason == "evasion_timeout":
						reason_text = "stuck for 5+ seconds (evasion timeout)"
					elif help_reason == "too_many_evasions":
						reason_text = "exceeded max evasion attempts (6+)"
					print("[BT] ", reason_text, ". Switching to AskHelp for: ", item_needed)
					
					# Clear the problematic actions (Navigate + Pick)
					# If Navigate failed: pop navigate, pop pick
					# If Pick failed: pop pick
					
					if action_name == "navigate":
						bb.planned_actions.pop_front() # Remove failed nav
						if not bb.planned_actions.is_empty() and bb.planned_actions[0].get("action") == "pick":
							bb.planned_actions.pop_front() # Remove associated pick
					elif action_name == "pick":
						bb.planned_actions.pop_front() # Remove failed pick
						
					var ask_action = {"action": "ask_help", "params": {"item": item_needed}}
					bb.planned_actions.push_front(ask_action)
					
					current_node = null # Reset to process new action immediately
					return Core.Status.RUNNING

			# If not recoverable or unknown failure, abort plan
			bb["last_plan_failed"] = true
			bb.erase("planned_actions")
			current_node = null
			return Core.Status.FAILURE
			
		return Core.Status.RUNNING

	func _create_action_node(name: String, params: Dictionary, bb: Dictionary) -> Core.Task:
		# Dynamic Action Mapping Factory
		var Act = load("res://scripts/bt/bt_actions.gd")
		match name:
			"navigate":
				var target_name = params.get("target", "")
				var node = Act.ActNavigate.new()
				
				print("[BT] Resolving navigation target: ", target_name)
				
				# Resolve target:
				# 1. Check blackboard "locations" (discovered markers)
				if bb.has("locations") and bb["locations"].has(target_name):
					# Temporarily store the resolved Vector2 for ActNavigate to consume
					var temp_key = "nav_target_" + str(Time.get_ticks_msec()) + "_" + str(randi())
					bb[temp_key] = bb["locations"][target_name]
					node.target_key = temp_key
					print("[BT] Target resolved to coordinates: ", bb[temp_key])
				# 2. Check special keys
				elif target_name == "customer":
					node.target_key = "target_customer"
					print("[BT] Target is customer")
				elif target_name == "counter": # Fallback if 'counter' not in locations
					node.target_key = "counter_pos"
					print("[BT] Target is default counter")
				else:
					print("[BT] Unknown nav target: ", target_name)
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

	if spawn_path != NodePath():
		var rs := get_node(spawn_path) as Node2D
		global_position = rs.global_position

	await get_tree().physics_frame
	
	# Configure Navigation Agent
	agent.avoidance_enabled = true
	agent.max_speed = move_speed
	agent.radius = 20.0  # Match the robot's approximate size (width ~40-50px)
	agent.neighbor_distance = 500.0
	agent.time_horizon = 1.0
	agent.debug_enabled = true # Enable debug visuals for pathfinding
	
	agent.velocity_computed.connect(_on_agent_velocity_computed)

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

	# ---------- BT Construction ----------
	var exec_plan = ActExecutePlan.new()
	var root := Core.Selector.new()
	root.children = [exec_plan]
	
	bt_runner.root = root
	bt_runner.bb = {
		"counter_pos": Vector2(500, 160), # Default
		"carrying_item": false,
		"planned_actions": [], # Queue of {action, params}
		"last_plan_failed": false,
		"locations": {} # Will be populated immediately
	}
	add_child(bt_runner)
	
	# ---------- Discover Locations IMMEDIATELY ----------
	_discover_locations()
	print("[RobotServer] Ready with ", bt_runner.bb["locations"].size(), " locations")

func _discover_locations():
	print("[RobotServer] Discovering locations...")
	
	# Try to get locations from RestaurantMain first (centralized data)
	var restaurant = get_tree().get_root().find_child("Restaurant", true, false)
	if restaurant and restaurant.has_method("get_all_locations"):
		var locs = restaurant.get_all_locations()
		if not locs.is_empty():
			bt_runner.bb["locations"] = locs.duplicate()
			print("[RobotServer] Got ", locs.size(), " locations from Restaurant")
			return
	
	# Fallback: discover directly from LocationMarkers
	var markers_node = get_tree().get_root().find_child("LocationMarkers", true, false)
	if markers_node:
		for child in markers_node.get_children():
			if child is Marker2D:
				bt_runner.bb["locations"][child.name] = child.global_position
				print("  -> Found: ", child.name, " at ", child.global_position)
	
	print("[RobotServer] Discovered ", bt_runner.bb["locations"].size(), " locations")

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

	if _tick_recharge_override(has_plan):
		return

	# No active task: try to claim new work when idle.
	if _active_task_id == "":
		if not has_plan and not _waiting_for_help:
			_try_claim_next_task()
		return

	if _sync_active_task_state():
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
		_end_current_episode(false, "task_missing")
		_clear_active_task_runtime()
		return true

	var state := str(task.get("state", ""))
	if state == TASK_STATE_FAILED:
		var reason := str(task.get("failure_reason", "task_failed"))
		_end_current_episode(false, reason)
		_clear_active_task_runtime()
		return true
	if state == TASK_STATE_COMPLETED:
		_end_current_episode(true)
		_clear_active_task_runtime()
		return true
	if state != TASK_STATE_IN_PROGRESS:
		_end_current_episode(false, "task_invalid_state:" + state)
		_clear_active_task_runtime()
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

func _try_claim_next_task() -> void:
	if _active_task_id != "" and ROBOT_MAX_ACTIVE_TASKS <= 1:
		return

	# Conserve mode: while idle, prefer charging before taking new tasks.
	if _battery_mode == BATTERY_MODE_CONSERVE:
		if _is_near_recharge_station():
			return
		if battery_level <= battery_conserve_threshold + 5.0:
			_plan_navigate_to_location(CHARGING_MARKER)
			_try_speak_recharge_notice("Battery low. Recharging before next task.")
			return

	var board = _task_board()
	if not board:
		return
	var constraints = _collect_constraint_input()
	var task = board.get_best_unassigned_task(TASK_TYPE_FULFILL_ORDER, constraints)
	if task.is_empty():
		return
	
	var task_slack_ms = int(task.get("deadline_ms", Time.get_ticks_msec()) - Time.get_ticks_msec())
	var battery_mode = str(constraints.get("battery_mode", BATTERY_MODE_NORMAL))
	if battery_mode == BATTERY_MODE_EMERGENCY and task_slack_ms > 20_000:
		print("[RobotServer] Emergency battery; deferring new claim. slack_ms=", task_slack_ms)
		return

	var task_id = str(task.get("id", ""))
	if task_id == "":
		return

	var claimed = board.claim_task(task_id, name)
	if claimed.is_empty():
		return

	_start_claimed_task(claimed)

func _tick_offer_take_order_handoff() -> void:
	if _active_task_id == "":
		return
	if _active_help_request_id != "":
		return
	if _waiting_for_help:
		return
	var board = _task_board()
	if board == null or not board.has_method("get_best_handoff_candidate_for_player"):
		return
	var candidate: Dictionary = board.get_best_handoff_candidate_for_player()
	if candidate.is_empty():
		return
	var candidate_id := str(candidate.get("id", ""))
	if candidate_id == "":
		return
	_ensure_help_request(HELP_TYPE_HANDOFF, {
		"handoff_mode": "TAKEOVER_TASK",
		"task_id": candidate_id,
		"item_needed": str(candidate.get("payload", {}).get("food_item", "item")),
		"reason": "robot_busy_take_order_handoff",
		"slack_ms": int(board.get_task_slack_ms(candidate_id))
	}, {
		"cooldown_ms": 3000,
		"max_escalation": 2,
		"urgency": clampf(1.0 - float(board.get_task_slack_ms(candidate_id)) / 90000.0, 0.1, 1.0)
	})

func _start_claimed_task(task: Dictionary) -> void:
	_active_task_id = str(task.get("id", ""))
	_active_task_step = ""
	if _active_task_id == "":
		return

	var payload: Dictionary = task.get("payload", {})
	var customer = _resolve_customer_from_payload(payload)
	if customer == null:
		print("[RobotServer] Task ", _active_task_id, " has no valid customer. Skipping.")
		var board = _task_board()
		if board and board.has_method("complete_task"):
			board.complete_task(_active_task_id)
		_clear_active_task_runtime()
		return

	bt_runner.bb["target_customer"] = customer
	_current_food_item = str(payload.get("food_item", "unknown"))
	if _current_food_item == "":
		_current_food_item = "unknown"

	var customer_seat = str(payload.get("seat", ""))
	var logger = get_node_or_null("/root/EpisodeLogger")
	if logger:
		logger.start_episode(_current_food_item, customer_seat, customer.global_position, global_position)
		_episode_active = true

	_plan_current_task_step()

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
			print("[RobotServer] Unknown task step: ", _active_task_step)

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
		if not bt_runner.bb["locations"].has(nearest_pose.name):
			bt_runner.bb["locations"][nearest_pose.name] = nearest_pose.global_position
		_set_step_plan([
			{"action": "navigate", "params": {"target": nearest_pose.name}}
		])
		speak("I'll take your order now.")

func _plan_pickup_step() -> void:
	var item_name := _current_food_item
	if item_name == "" or not bt_runner.bb["locations"].has(item_name):
		item_name = "pizza"

	bt_runner.bb["item_name"] = item_name
	_set_step_plan([
		{"action": "navigate", "params": {"target": item_name}},
		{"action": "pick", "params": {"item": item_name}}
	])
	speak("Heading to kitchen for " + item_name + ".")

func _plan_deliver_step() -> void:
	_set_step_plan([
		{"action": "navigate", "params": {"target": "customer"}},
		{"action": "drop", "params": {}},
		{"action": "navigate", "params": {"target": "RS1"}}
	])
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
		print("[RobotServer] Failed to complete step for task: ", _active_task_id)
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

	print("[RobotServer] Task completed: ", _active_task_id)
	_end_current_episode(true)
	_clear_active_task_runtime()

func _clear_active_task_runtime() -> void:
	_active_task_id = ""
	_active_task_step = ""
	_active_step_started = false
	_last_replan_ms = 0
	_recharge_override_active = false
	bt_runner.bb.erase("target_customer")
	bt_runner.bb["last_plan_failed"] = false
	_clear_help_request_runtime()

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
		print("[RobotServer] Battery mode: ", previous, " -> ", _battery_mode, " (", int(battery_level), "%)")
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
	return global_position.distance_to(station) <= 36.0

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
	if _help_request_suppressed:
		return

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
	_active_help_request_id = req_id
	_active_help_request_type = str(request.get("type", ""))

	if status == "accepted":
		_help_request_suppressed = false
		_apply_handoff_accept(request)
	elif status == "resolved" and final_response == "decline":
		_help_request_suppressed = true
		set_waiting_for_help(false, "")

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
		_transfer_item_to_player_for_handoff(payload)

	var updated: Dictionary = {}
	var task_snapshot: Dictionary = board.get_task(task_id) if board.has_method("get_task") else {}
	var task_state := str(task_snapshot.get("state", ""))
	if task_state == "unassigned" and board.has_method("claim_task"):
		updated = board.claim_task(task_id, "player")
	elif board.has_method("reassign_task"):
		updated = board.reassign_task(task_id, "player")
	if updated.is_empty():
		return

	if task_id == _active_task_id:
		_end_current_episode(false, "task_handoff_to_player")
		_clear_active_task_runtime()
		bt_runner.bb["planned_actions"] = []
		_active_step_started = false

	set_waiting_for_help(false, "")
	speak("Task handoff accepted. You take over this order.")
	var help_mgr = _help_manager()
	if help_mgr and _active_help_request_id != "":
		help_mgr.complete_request(_active_help_request_id, "cooperative_handoff_task_transfer")
	_active_help_request_id = ""
	_active_help_request_type = ""

func _transfer_item_to_player_for_handoff(payload: Dictionary) -> void:
	if inventory == null or inventory.items.is_empty():
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player = players[0]
	if not (player is Node2D):
		return
	if global_position.distance_to((player as Node2D).global_position) > 130.0:
		return
	var p_inv = player.get_node_or_null("Inventory")
	if p_inv == null:
		return
	var preferred := str(payload.get("item_needed", "")).strip_edges()
	var idx := -1
	if preferred != "":
		idx = inventory.find_item(preferred)
	if idx == -1:
		idx = inventory.items.size() - 1
	if idx < 0 or idx >= inventory.items.size():
		return
	var item: Dictionary = inventory.items.pop_at(idx)
	inventory.emit_signal("inventory_changed", inventory.items)
	if inventory.items.is_empty():
		bt_runner.bb["carrying_item"] = false
	var item_name := str(item.get("name", "item"))
	p_inv.add_item(item_name, item.get("atlas", null), item.get("region", Rect2i()))

func _on_help_request_resolved(request: Dictionary) -> void:
	if request.is_empty():
		return
	if int(request.get("robot_instance_id", 0)) != get_instance_id():
		return

	var req_id = str(request.get("id", ""))
	if _active_help_request_id == req_id:
		_active_help_request_id = ""
		_active_help_request_type = ""

func _clear_help_request_runtime() -> void:
	_active_help_request_id = ""
	_active_help_request_type = ""
	_help_request_suppressed = false

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
	print("[Robot] Says: ", text)
	var bubble_mgr = get_node_or_null("/root/BubbleManager")
	if bubble_mgr and bubble_mgr.has_method("say"):
		bubble_mgr.say(self, text, 2.6, Color(0.88, 0.96, 1.0, 1.0))

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
