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
const HELP_TYPE_HANDOFF := "HANDOFF"
const HELP_TYPE_OPEN_DOOR := "OPEN_DOOR"
var _active_task_id: String = ""
var _active_task_step: String = ""
var _active_step_started: bool = false
var _last_replan_ms: int = 0
var _last_blocked_notice_ms: int = 0

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

# ---------- Autonomous Fallback (Spare Key) ----------
const FALLBACK_NONE := ""
const FALLBACK_TO_CHARGER := "to_charger"
const FALLBACK_COLLECT_KEY := "collect_key"
const FALLBACK_TO_DOOR := "to_door"
var _fallback_state: String = FALLBACK_NONE
var _fallback_wait_until_ms: int = 0
var _has_spare_key: bool = false
var _returning_spare_key: bool = false

# ---------- OpenAI ----------
const OPENAI_URL: String   = "https://api.openai.com/v1/chat/completions"
const OPENAI_MODEL: String = "gpt-4o-mini"
var OPENAI_KEY: String     = "" # Set via environment variable or config file
@onready var http: HTTPRequest = $HTTPRequest

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

	http.request_completed.connect(_on_http_completed)
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

	if _fallback_state != FALLBACK_NONE:
		_tick_autonomous_fallback(has_plan)
		return

	# No active task: try to claim new work when idle.
	if _active_task_id == "":
		if not has_plan and _has_spare_key:
			_tick_return_spare_key()
			return
		if not has_plan and not _waiting_for_help:
			_try_claim_next_task()
		return

	# Active task exists: wait until current step plan ends.
	if has_plan or _waiting_for_help:
		return

	# Step cannot start yet (e.g. blocked by door), keep waiting and re-check constraints.
	if not _active_step_started:
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_replan_ms >= 300:
			_last_replan_ms = now_ms
			_plan_current_task_step()
		return

	_on_active_step_finished()

func _end_current_episode(success: bool, failure_reason: String = "") -> void:
	if not _episode_active:
		return
	
	var logger = get_node_or_null("/root/EpisodeLogger")
	if logger:
		logger.end_episode(success, failure_reason)
	
	_episode_active = false
	_current_food_item = ""

func _extract_food_from_request(request: String) -> String:
	var request_lower = request.to_lower()
	var foods = ["pizza", "hotdog", "skewers", "sandwich"]
	for food in foods:
		if food in request_lower:
			return food
	return "unknown"

func _task_board() -> Node:
	return get_node_or_null("/root/TaskBoard")

func _help_manager() -> Node:
	return get_node_or_null("/root/HelpRequestManager")

func _try_claim_next_task() -> void:
	if _has_spare_key or _returning_spare_key or _fallback_state != FALLBACK_NONE:
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
	if _constraint_blocks_current_step():
		_ensure_help_request(HELP_TYPE_OPEN_DOOR, {
			"reason": "door_blocked_pickup",
			"door_position": _get_door_position(),
			"slack_ms": int(_constraint_input.get("slack_ms", 0))
		}, {
			"require_beacon": true,
			"cooldown_ms": 4500,
			"urgency": _estimate_help_urgency()
		})
		_try_speak_blocked_notice("Door is closed. Waiting for access before pickup.")
		return

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
	if _constraint_blocks_current_step():
		_ensure_help_request(HELP_TYPE_OPEN_DOOR, {
			"reason": "door_blocked_delivery",
			"door_position": _get_door_position(),
			"slack_ms": int(_constraint_input.get("slack_ms", 0))
		}, {
			"require_beacon": true,
			"cooldown_ms": 4500,
			"urgency": _estimate_help_urgency()
		})
		_try_speak_blocked_notice("Door is closed. Waiting for access before delivery.")
		return

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
	bt_runner.bb.erase("target_customer")
	_clear_help_request_runtime()

func _try_speak_blocked_notice(text: String) -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_blocked_notice_ms < 1500:
		return
	_last_blocked_notice_ms = now_ms
	speak(text)

func _set_step_plan(actions: Array) -> void:
	if actions.is_empty():
		bt_runner.bb["planned_actions"] = []
		_active_step_started = false
		return
	bt_runner.bb["planned_actions"] = actions
	_active_step_started = true
	if _active_help_request_type == HELP_TYPE_OPEN_DOOR and _active_help_request_id != "":
		var help_mgr = _help_manager()
		if help_mgr and help_mgr.has_method("complete_request"):
			help_mgr.complete_request(_active_help_request_id, "cooperative_open_door")
		_active_help_request_id = ""
		_active_help_request_type = ""
		set_waiting_for_help(false, "")

func _collect_constraint_input() -> Dictionary:
	var now_ms := Time.get_ticks_msec()
	var door_open := _is_restricted_door_open()
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
		"door_open": door_open,
		"active_task_id": _active_task_id,
		"active_step": _active_task_step,
		"deadline_ms": deadline_ms,
		"slack_ms": slack_ms,
		"is_door_blocked": _is_step_blocked_by_door(_active_task_step, door_open),
		"deadline_urgency_weight": 1.0
	}

	if _battery_mode == BATTERY_MODE_EMERGENCY:
		input["deadline_urgency_weight"] = 0.7
	elif _battery_mode == BATTERY_MODE_CONSERVE:
		input["deadline_urgency_weight"] = 0.9

	return input

func _constraint_blocks_current_step() -> bool:
	_constraint_input = _collect_constraint_input()
	return bool(_constraint_input.get("is_door_blocked", false))

func _is_step_blocked_by_door(step_name: String, door_open: bool) -> bool:
	if door_open:
		return false
	if step_name != STEP_PICKUP_FROM_KITCHEN and step_name != STEP_DELIVER_AND_SERVE:
		return false

	var locations: Dictionary = bt_runner.bb.get("locations", {})
	var item_pos: Vector2 = locations.get(_current_food_item, Vector2.ZERO)
	var in_kitchen_target: bool = item_pos != Vector2.ZERO and item_pos.y < -150.0
	var robot_in_kitchen: bool = global_position.y < -150.0

	if step_name == STEP_PICKUP_FROM_KITCHEN:
		# Need kitchen access.
		return not robot_in_kitchen and in_kitchen_target
	if step_name == STEP_DELIVER_AND_SERVE:
		# Need to go from kitchen back to dining.
		return robot_in_kitchen
	return false

func _is_restricted_door_open() -> bool:
	var doors = get_tree().get_nodes_in_group("door")
	for d in doors:
		if "is_open" in d:
			return bool(d.is_open)

	var root = get_tree().current_scene
	if not root:
		return true
	var door_node = root.find_child("Door", true, false)
	if door_node and "is_open" in door_node:
		return bool(door_node.is_open)
	return true

func _update_battery_and_mode(dt: float) -> void:
	var moving := velocity.length() > 1.0
	var drain_rate := battery_drain_idle_per_sec
	if moving:
		drain_rate = battery_drain_move_per_sec

	battery_level -= drain_rate * dt
	if _active_task_id == "" and _is_near_recharge_station():
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

func _update_agent_speed_by_battery_mode() -> void:
	var speed_scale := 1.0
	if _battery_mode == BATTERY_MODE_CONSERVE:
		speed_scale = 0.8
	elif _battery_mode == BATTERY_MODE_EMERGENCY:
		speed_scale = 0.6
	agent.max_speed = move_speed * speed_scale

func _is_near_recharge_station() -> bool:
	var station = bt_runner.bb.get("locations", {}).get("RS1", Vector2.ZERO)
	if station == Vector2.ZERO:
		return false
	return global_position.distance_to(station) <= 36.0

func _get_door_position() -> Vector2:
	var doors = get_tree().get_nodes_in_group("door")
	for d in doors:
		if d is Node2D:
			return d.global_position
	return global_position

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

func _tick_autonomous_fallback(has_plan: bool) -> void:
	match _fallback_state:
		FALLBACK_TO_CHARGER:
			if has_plan:
				return
			_fallback_state = FALLBACK_COLLECT_KEY
			_fallback_wait_until_ms = Time.get_ticks_msec() + 5000
			speak("Retrieving spare key from charging station.")
		FALLBACK_COLLECT_KEY:
			if Time.get_ticks_msec() < _fallback_wait_until_ms:
				return
			_has_spare_key = true
			_fallback_state = FALLBACK_TO_DOOR
			_plan_navigate_to_position(_get_door_position(), "fallback_door")
			speak("Spare key acquired. Heading to door.")
		FALLBACK_TO_DOOR:
			if has_plan:
				return
			_open_door_with_spare_key()
			_fallback_state = FALLBACK_NONE
			_active_step_started = false
			speak("Door unlocked with spare key. Resuming task.")
		_:
			_fallback_state = FALLBACK_NONE

func _start_autonomous_fallback() -> void:
	if _fallback_state != FALLBACK_NONE:
		return
	_fallback_state = FALLBACK_TO_CHARGER
	_waiting_for_help = false
	_plan_navigate_to_location("RS1")
	speak("No further persuasion. Executing autonomous fallback.")

func _tick_return_spare_key() -> void:
	if _fallback_state != FALLBACK_NONE:
		return
	if _returning_spare_key:
		if Time.get_ticks_msec() < _fallback_wait_until_ms:
			return
		_has_spare_key = false
		_returning_spare_key = false
		speak("Spare key returned.")
		return

	var rs1: Vector2 = bt_runner.bb.get("locations", {}).get("RS1", Vector2.ZERO)
	if rs1 == Vector2.ZERO:
		_has_spare_key = false
		return
	if global_position.distance_to(rs1) <= 36.0:
		_returning_spare_key = true
		_fallback_wait_until_ms = Time.get_ticks_msec() + 2500
		speak("Returning spare key at charging station.")
		return

	if bt_runner.bb.has("planned_actions") and not bt_runner.bb["planned_actions"].is_empty():
		return
	_plan_navigate_to_location("RS1")

func _plan_navigate_to_location(location_name: String) -> void:
	_set_step_plan([{"action": "navigate", "params": {"target": location_name}}])

func _plan_navigate_to_position(pos: Vector2, key_prefix: String = "temp_nav") -> void:
	var key = "%s_%d" % [key_prefix, Time.get_ticks_msec()]
	bt_runner.bb["locations"][key] = pos
	_set_step_plan([{"action": "navigate", "params": {"target": key}}])

func _open_door_with_spare_key() -> void:
	var doors = get_tree().get_nodes_in_group("door")
	for d in doors:
		if not (d is Node2D):
			continue
		if d.global_position.distance_to(global_position) > 120.0:
			continue
		if "is_open" in d and bool(d.is_open):
			return
		if d.has_method("toggle"):
			d.toggle()
			return

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
		if _active_help_request_type == HELP_TYPE_OPEN_DOOR:
			speak("Please open the door for me.")
		else:
			speak("Thanks. Please hand me the item.")
	elif status == "resolved" and final_response == "decline":
		_help_request_suppressed = true
		set_waiting_for_help(false, "")

func _on_help_request_resolved(request: Dictionary) -> void:
	if request.is_empty():
		return
	if int(request.get("robot_instance_id", 0)) != get_instance_id():
		return

	var req_id = str(request.get("id", ""))
	var req_type = str(request.get("type", ""))
	var final_response = str(request.get("final_response", ""))
	if _active_help_request_id == req_id:
		_active_help_request_id = ""
		_active_help_request_type = ""

	if req_type == HELP_TYPE_OPEN_DOOR and final_response == "decline":
		_start_autonomous_fallback()

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

func _connect_all_customers() -> void:
	var customers: Array = get_tree().get_nodes_in_group("customer")
	for c in customers:
		_connect_customer(c)

func _on_node_added(n: Node) -> void:
	# 延迟检查，因为 node_added 信号在 _ready() 之前触发
	# 此时节点还没有被添加到 "customer" 组
	call_deferred("_try_connect_customer", n)

func _try_connect_customer(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n.is_in_group("customer"):
		_connect_customer(n)
	elif n is CharacterBody2D and n.has_signal("request_emitted"):
		# 备用检查：如果节点有 request_emitted 信号，也连接
		_connect_customer(n)

func _connect_customer(c: Node) -> void:
	if c.has_signal("request_emitted"):
		if not c.request_emitted.is_connected(_on_customer_request):
			c.request_emitted.connect(_on_customer_request, CONNECT_DEFERRED)

func _on_customer_request(customer: Node) -> void:
	print("[RobotServer] Received request from customer: ", customer.name)
	bt_runner.bb["target_customer"] = customer as Node2D
	
	# Get the actual request text from the customer
	var actual_request = customer.request_text if "request_text" in customer else "Can I order a pizza?"
	print("[RobotServer] Customer request: ", actual_request)
	
	# Extract food item from request for episode tracking
	_current_food_item = _extract_food_from_request(actual_request)
	
	# Start episode logging
	var customer_seat = ""
	if "current_seat" in customer:
		customer_seat = customer.current_seat
	
	if Engine.has_singleton("EpisodeLogger") or has_node("/root/EpisodeLogger"):
		var logger = get_node_or_null("/root/EpisodeLogger")
		if logger:
			logger.start_episode(_current_food_item, customer_seat, customer.global_position, global_position)
			_episode_active = true
	
	# 1. Find nearest "serveposes" marker to customer (Approach Goal)
	var serve_poses = get_tree().get_nodes_in_group("serveposes")
	var nearest_pose: Node2D = null
	var min_dist = INF
	
	for pose in serve_poses:
		var d = pose.global_position.distance_to(customer.global_position)
		if d < min_dist:
			min_dist = d
			nearest_pose = pose
			
	if nearest_pose:
		print("[RobotServer] Will approach customer at: ", nearest_pose.name)
		# Set initial plan to just go to the customer
		var approach_plan = [
			{"action": "navigate", "params": {"target": nearest_pose.name}}
		]
		
		# Ensure the pose is in known locations (it should be if discovered)
		if not bt_runner.bb["locations"].has(nearest_pose.name):
			bt_runner.bb["locations"][nearest_pose.name] = nearest_pose.global_position
			
		bt_runner.bb["planned_actions"] = approach_plan
		
		# Trigger LLM with actual customer request
		_call_openai_for_task(actual_request, true) 
	else:
		# Fallback if no serve pose found
		_call_openai_for_task(actual_request, false)

var _pending_request_text: String = ""  # Store request for mock fallback

func _call_openai_for_task(request_text: String, append_plan: bool = false) -> void:
	_pending_request_text = request_text  # Store for mock fallback
	
	if OPENAI_KEY == "":
		push_error("OPENAI_API_KEY not set.")
		_mock_llm_response(append_plan)
		return

	# Construct context from available locations
	var loc_keys = []
	if bt_runner.bb.has("locations"):
		loc_keys = bt_runner.bb["locations"].keys()
	var locations_str = ", ".join(loc_keys)

	var sys: String = """
You are a robot waiter. Parse the user request into a JSON plan.
Known Locations: [%s]
Available Atomic Actions:
1. navigate(target): target must be one of the Known Locations or "customer"
2. pick(item): item name as string
3. drop(): no params

Output JSON format:
{
  "reply": "Short text to customer",
  "plan": [
    {"action": "navigate", "params": {"target": "exact_location_name"}},
    {"action": "pick", "params": {"item": "pizza"}},
    ...
  ]
}
""" % locations_str
	var user_text: String = "Customer Request: " + request_text

	var payload: Dictionary = {
		"model": OPENAI_MODEL,
		"response_format": {"type": "json_object"},
		"messages": [
			{"role":"system", "content": sys},
			{"role":"user", "content": user_text}
		],
		"temperature": 0.0
	}

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: " + "Bearer " + OPENAI_KEY
	])
	
	# Note: We can't easily pass 'append_plan' through the HTTP callback in Godot 4 without a custom object or lambda binding.
	# But we can check if 'planned_actions' is not empty in _on_http_completed.
	# For simplicity here, we'll assume we always APPEND if the robot is currently busy (approaching).
	
	var err: int = http.request(OPENAI_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		push_error("HTTP request failed: " + str(err))
		_mock_llm_response(append_plan)

func _mock_llm_response(append: bool = false) -> void:
	print("[RobotServer] Using Mock LLM Response for: ", _pending_request_text)
	
	# Parse the food type from the request
	var food_item = "pizza"  # default
	var request_lower = _pending_request_text.to_lower()
	
	if "hotdog" in request_lower:
		food_item = "hotdog"
	elif "skewers" in request_lower:
		food_item = "skewers"
	elif "sandwich" in request_lower:
		food_item = "sandwich"
	elif "pizza" in request_lower:
		food_item = "pizza"
	
	print("[RobotServer] Parsed food item: ", food_item)
	
	# Build COMPLETE plan: navigate -> pick -> deliver to customer -> drop -> return to spawn
	var plan = [
		{"action": "navigate", "params": {"target": food_item}}, 
		{"action": "pick", "params": {"item": food_item}},
		{"action": "navigate", "params": {"target": "customer"}},
		{"action": "drop", "params": {}},
		{"action": "navigate", "params": {"target": "RS1"}}  # Return to robot spawn
	]
	_apply_plan(plan, "Okay, getting your " + food_item + "!", append)

func _on_http_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code < 200 or code >= 300:
		push_error("OpenAI HTTP status: " + str(code))
		print(body.get_string_from_utf8())
		_mock_llm_response(true) # Default to append on fail?
		return

	var txt: String = body.get_string_from_utf8()
	var top: Dictionary = JSON.parse_string(txt)
	
	var choices: Array = top.get("choices", [])
	if choices.is_empty():
		_mock_llm_response(true)
		return
		
	var content_str: String = choices[0].get("message", {}).get("content", "")
	var response_obj: Dictionary = JSON.parse_string(content_str)
	
	var reply = response_obj.get("reply", "...")
	var plan = response_obj.get("plan", [])
	
	print("[RobotServer] LLM Plan: ", plan)
	
	# We append if we are currently running an approach plan
	# A simple heuristic: if planned_actions has items, we append.
	var current_plan = bt_runner.bb.get("planned_actions", [])
	var should_append = not current_plan.is_empty()
	_apply_plan(plan, reply, should_append)

func _apply_plan(plan: Array, reply: String, append: bool):
	if reply != "":
		speak(reply)
	
	# Ensure plan is complete: must have navigate->pick->navigate to customer->drop->return to spawn
	var complete_plan = _ensure_complete_plan(plan)
	
	if append:
		bt_runner.bb["planned_actions"].append_array(complete_plan)
	else:
		bt_runner.bb["planned_actions"] = complete_plan
	
	print("[RobotServer] Final plan: ", bt_runner.bb["planned_actions"])

func _ensure_complete_plan(plan: Array) -> Array:
	# First pass: find what item is being picked
	var picked_item = ""
	var navigate_to_item_idx = -1
	var pick_action_idx = -1
	
	for i in range(plan.size()):
		var action = plan[i]
		var action_name = action.get("action", "")
		var params = action.get("params", {})
		
		if action_name == "pick":
			picked_item = params.get("item", "")
			pick_action_idx = i
		elif action_name == "navigate":
			var target = params.get("target", "")
			# Check if this is the navigate-to-item (before pick)
			if target != "customer" and target != "RS1" and pick_action_idx == -1:
				navigate_to_item_idx = i
	
	# Fix: Ensure navigate target matches pick item
	var result = plan.duplicate(true)
	if picked_item != "" and navigate_to_item_idx >= 0:
		var nav_target = result[navigate_to_item_idx].get("params", {}).get("target", "")
		if nav_target != picked_item:
			print("[RobotServer] FIXING: navigate target '", nav_target, "' -> '", picked_item, "'")
			result[navigate_to_item_idx]["params"]["target"] = picked_item
	
	# Second pass: check for missing steps
	var has_navigate_to_customer = false
	var has_drop = false
	var has_return_to_spawn = false
	
	for action in result:
		var action_name = action.get("action", "")
		var params = action.get("params", {})
		
		if action_name == "navigate":
			var target = params.get("target", "")
			if target == "customer":
				has_navigate_to_customer = true
			elif target == "RS1":
				has_return_to_spawn = true
		elif action_name == "drop":
			has_drop = true
	
	# Add missing steps
	if picked_item != "" and not has_navigate_to_customer:
		result.append({"action": "navigate", "params": {"target": "customer"}})
		print("[RobotServer] Auto-added: navigate to customer")
	
	if picked_item != "" and not has_drop:
		result.append({"action": "drop", "params": {}})
		print("[RobotServer] Auto-added: drop")
	
	if not has_return_to_spawn:
		result.append({"action": "navigate", "params": {"target": "RS1"}})
		print("[RobotServer] Auto-added: return to spawn RS1")
	
	return result

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
	# TODO: Bubble UI integration

# ---------- Interaction Interface ----------
func needs_help() -> bool:
	return _waiting_for_help

func set_waiting_for_help(waiting: bool, item_name: String):
	_waiting_for_help = waiting
	_help_item_needed = item_name
	if not waiting:
		return

	if _active_help_request_type == HELP_TYPE_OPEN_DOOR:
		return

	# Hand-off help is created here (e.g. BT ask_help path).
	_ensure_help_request(HELP_TYPE_HANDOFF, {
		"item_needed": _help_item_needed,
		"reason": "robot_stuck_or_pick_fail",
		"slack_ms": int(_constraint_input.get("slack_ms", 0))
	}, {
		"cooldown_ms": 3500,
		"max_escalation": 2,
		"require_beacon": false,
		"urgency": _estimate_help_urgency()
	})

func receive_player_help():
	if not _waiting_for_help:
		speak("I don't need help right now.")
		return

	var help_mgr = _help_manager()
	if help_mgr and _active_help_request_id != "":
		var req = help_mgr.get_request(_active_help_request_id)
		var req_status = str(req.get("status", ""))
		var req_type = str(req.get("type", ""))
		if req_type == HELP_TYPE_OPEN_DOOR:
			speak("Please open the door first.")
			return
		if req_status != "accepted":
			speak("Please choose Accept first.")
			return
		
	print("[Robot] Player interacting...")
	# Access player inventory (Hack: assume only 1 player for now)
	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0: return
	var player = players[0]
	
	# Check if player has inventory node
	var p_inv = player.get_node_or_null("Inventory")
	if p_inv:
		# Logic: Does player have the item we need?
		var found_idx = -1
		
		# Use the robust find_item method (case-insensitive partial match)
		if _help_item_needed == "" or _help_item_needed == "item":
			if not p_inv.items.is_empty(): 
				found_idx = p_inv.items.size() - 1 # Take last item
		else:
			found_idx = p_inv.find_item(_help_item_needed)
		
		if found_idx != -1:
			# Transfer item
			var item = p_inv.items.pop_at(found_idx) # Remove from player
			p_inv.emit_signal("inventory_changed", p_inv.items)
			
			inventory.add_item(item.get("name"), item.get("atlas"), item.get("region"))
			
			# Update BT Blackboard
			bt_runner.bb["carrying_item"] = true
			
			speak("Thanks for the " + item.get("name") + "!")
			set_waiting_for_help(false, "")
			if help_mgr and _active_help_request_id != "":
				help_mgr.complete_request(_active_help_request_id, "cooperative_handoff")
				_active_help_request_id = ""
				_active_help_request_type = ""
		else:
			print("[Robot] Player inventory: ", p_inv.items) # Debug print
			speak("I need a " + _help_item_needed + ". You don't seem to have it.")
	else:
		speak("You have no inventory!")
