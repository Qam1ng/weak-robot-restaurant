# res://scripts/bt/bt_actions.gd
extends Resource
class_name BT_Actions

static func _gameplay_now_ms(actor: Node) -> int:
	var game_mgr = null
	if actor != null:
		game_mgr = actor.get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_gameplay_time_ms"):
		return int(game_mgr.get_gameplay_time_ms())
	return Time.get_ticks_msec()

static func _emit_runtime_debug(actor: Node, event_type: String, data: Dictionary = {}) -> void:
	if actor != null and actor.has_method("_log_runtime_debug_event"):
		actor.call("_log_runtime_debug_event", event_type, data)

const Core = preload("res://scripts/bt/bt_core.gd")

class ActNavigate extends Core.Task:
	var target_key: String
	var _target_set: bool = false
	var _final_target: Vector2 = Vector2.ZERO
	var _arrival_time: int = 0
	var _arrival_wait: int = 800

	var _is_customer_target: bool = false
	var _is_player_target: bool = false
	const ARRIVAL_DIST_NORMAL := 50.0
	const ARRIVAL_DIST_CUSTOMER := 250.0
	const ARRIVAL_DIST_PLAYER := 90.0
	const ARRIVAL_DIST_STUCK := 300.0

	var _last_pos: Vector2 = Vector2.ZERO
	var _last_pos_time: int = 0
	var _stuck_duration_ms: int = 0
	var _total_stuck_time_ms: int = 0
	var _retry_count: int = 0
	const MAX_RETRY_ATTEMPTS := 3
	const STUCK_TIMEOUT_MS := 5000

	func _init(key: String = "target_pos"):
		target_key = key
		_is_customer_target = (key == "target_customer")
		_is_player_target = (key == "player_target")

	func tick(bb: Dictionary, actor: Node) -> int:
		var agent := actor.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
		if agent == null:
			return Core.Status.FAILURE
		var nav_map: RID = actor.get_world_2d().navigation_map
		if not nav_map.is_valid():
			return Core.Status.FAILURE

		# Help requests are choice points for the player. Once the robot is waiting
		# for a response, freeze the current navigation action instead of letting
		# stale path-following continue to drag the robot away.
		if actor.has_method("needs_help") and bool(actor.call("needs_help")):
			actor.velocity = Vector2.ZERO
			actor.move_and_slide()
			return Core.Status.RUNNING

		if not _target_set:
			if not bb.has(target_key):
				return Core.Status.FAILURE
			var raw_target = bb[target_key]
			if raw_target is Node2D:
				_final_target = (raw_target as Node2D).global_position
			elif raw_target is Vector2:
				_final_target = raw_target
			else:
				return Core.Status.FAILURE

			_set_agent_target(agent, actor, _final_target)
			_target_set = true
			_last_pos = actor.global_position
			_last_pos_time = BT_Actions._gameplay_now_ms(actor)
			var start_nav := NavigationServer2D.map_get_closest_point(nav_map, actor.global_position)
			if actor.global_position.distance_to(start_nav) > 6.0:
				actor.global_position = start_nav
				_last_pos = actor.global_position
			print("[ActNavigate][Start] from=", actor.global_position, " to=", _final_target, " radius=", agent.radius)
			BT_Actions._emit_runtime_debug(actor, "navigation_start", {
				"robot_target_x": _final_target.x,
				"robot_target_y": _final_target.y
			})

		if target_key == "target_customer" or target_key == "player_target":
			_set_agent_target(agent, actor, _final_target)

		var dist_to_target: float = actor.global_position.distance_to(_final_target)
		var arrival_threshold: float = ARRIVAL_DIST_NORMAL
		if _is_customer_target:
			arrival_threshold = ARRIVAL_DIST_CUSTOMER
		elif _is_player_target:
			arrival_threshold = ARRIVAL_DIST_PLAYER

		if dist_to_target <= arrival_threshold:
			if _arrival_time == 0:
				_arrival_time = BT_Actions._gameplay_now_ms(actor)
				actor.velocity = Vector2.ZERO
				actor.move_and_slide()
			if BT_Actions._gameplay_now_ms(actor) - _arrival_time >= _arrival_wait:
				return Core.Status.SUCCESS
			return Core.Status.RUNNING

		var start_nav_now: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, actor.global_position)
		var target_nav_now: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, _final_target)
		var server_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, start_nav_now, target_nav_now, true, 1)

		var now_ms: int = BT_Actions._gameplay_now_ms(actor)
		if now_ms - _last_pos_time >= 200:
			var moved_dist: float = actor.global_position.distance_to(_last_pos)
			_last_pos = actor.global_position
			_last_pos_time = now_ms

			if moved_dist < 2.0:
				_stuck_duration_ms += 200
				_total_stuck_time_ms += 200
				if _total_stuck_time_ms > 2000:
					var close_enough: float = ARRIVAL_DIST_NORMAL
					if _is_customer_target:
						close_enough = ARRIVAL_DIST_STUCK
					elif _is_player_target:
						close_enough = ARRIVAL_DIST_PLAYER
					if dist_to_target <= close_enough:
						actor.velocity = Vector2.ZERO
						actor.move_and_slide()
						return Core.Status.SUCCESS

				if _stuck_duration_ms >= 800:
					_stuck_duration_ms = 0
					_retry_count += 1
					_set_agent_target(agent, actor, _final_target)
					BT_Actions._emit_runtime_debug(actor, "navigation_retry", {
						"event_reason": "stuck_retry",
						"robot_target_x": _final_target.x,
						"robot_target_y": _final_target.y,
						"has_navigation_path": server_path.size() >= 2,
						"path_length": server_path.size(),
						"moved_distance_px": moved_dist,
						"stuck_duration_ms": _stuck_duration_ms,
						"total_stuck_time_ms": _total_stuck_time_ms,
						"retry_count": _retry_count
					})

				if _retry_count >= MAX_RETRY_ATTEMPTS or _total_stuck_time_ms >= STUCK_TIMEOUT_MS:
					bb["help_reason"] = "too_many_evasions"
					bb["help_stuck_position"] = actor.global_position
					bb["help_evasion_attempts"] = _retry_count
					print("[ActNavigate][Fail] from=", actor.global_position, " to=", _final_target, " retries=", _retry_count, " stuck_ms=", _total_stuck_time_ms, " path_points=", server_path.size())
					BT_Actions._emit_runtime_debug(actor, "navigation_failed", {
						"event_reason": "too_many_evasions" if server_path.size() >= 2 else "no_navigation_path",
						"robot_target_x": _final_target.x,
						"robot_target_y": _final_target.y,
						"has_navigation_path": server_path.size() >= 2,
						"path_length": server_path.size(),
						"moved_distance_px": moved_dist,
						"stuck_duration_ms": _stuck_duration_ms,
						"total_stuck_time_ms": _total_stuck_time_ms,
						"retry_count": _retry_count
					})
					if actor.has_method("speak"):
						actor.speak("I've tried " + str(_retry_count) + " times but can't get through. Need help!")
					return Core.Status.FAILURE
			else:
				_stuck_duration_ms = 0
				if moved_dist > 8.0:
					_total_stuck_time_ms = 0

		var next_path_pos: Vector2 = actor.global_position
		var has_valid_path := false
		if server_path.size() >= 2:
			var next_idx := 1
			while next_idx < server_path.size() and actor.global_position.distance_to(server_path[next_idx]) < 10.0:
				next_idx += 1
			if next_idx >= server_path.size():
				next_path_pos = target_nav_now
			else:
				next_path_pos = server_path[next_idx]
			has_valid_path = true
		else:
			# No valid nav path: do not drift to (0,0) or force straight-line through colliders.
			# Stay still and let stuck logic fail fast with precise logs.
			has_valid_path = false

		var to_next: Vector2 = next_path_pos - actor.global_position
		var desired_velocity := Vector2.ZERO
		if has_valid_path and to_next.length() > 1.0:
			desired_velocity = to_next.normalized() * actor.move_speed
		actor.velocity = desired_velocity
		actor.move_and_slide()

		return Core.Status.RUNNING

	func _set_agent_target(agent: NavigationAgent2D, actor: Node, target: Vector2) -> void:
		agent.set_navigation_map(actor.get_world_2d().navigation_map)
		agent.navigation_layers = 1
		agent.path_desired_distance = 12.0
		agent.target_desired_distance = 10.0
		agent.max_speed = actor.move_speed
		agent.avoidance_enabled = false
		agent.target_position = target


class ActPickItem extends Core.Task:
	var _start_time: int = 0
	var _duration: int = 1500

	func tick(bb: Dictionary, actor: Node) -> int:
		if _start_time == 0:
			_start_time = BT_Actions._gameplay_now_ms(actor)
			actor.speak("Picking up...")
			BT_Actions._emit_runtime_debug(actor, "pickup_started", {
				"item_name": str(bb.get("item_name", "Unknown Item"))
			})
			actor.velocity = Vector2.ZERO
			return Core.Status.RUNNING

		if BT_Actions._gameplay_now_ms(actor) - _start_time < _duration:
			return Core.Status.RUNNING

		var item_name: String = str(bb.get("item_name", "Unknown Item"))
		if bb.has("locations") and bb["locations"].has(item_name):
			var target_pos: Vector2 = bb["locations"][item_name]
			if actor.global_position.distance_to(target_pos) > 150.0:
				actor.speak("I'm too far away!")
				BT_Actions._emit_runtime_debug(actor, "pickup_failed", {"event_reason": "too_far_from_item", "item_name": item_name})
				return Core.Status.FAILURE

		var inventory = actor.get_node_or_null("Inventory")
		if not inventory:
			BT_Actions._emit_runtime_debug(actor, "pickup_failed", {"event_reason": "missing_inventory"})
			return Core.Status.FAILURE
		if inventory.is_full():
			if actor.has_method("_handle_pickup_inventory_full"):
				actor.call("_handle_pickup_inventory_full", item_name)
			BT_Actions._emit_runtime_debug(actor, "pickup_failed", {"event_reason": "inventory_full", "item_name": item_name})
			return Core.Status.FAILURE

		var item_node = _find_item_in_scene(actor, item_name)
		if not item_node:
			actor.speak("I can't find " + item_name + " right now.")
			BT_Actions._emit_runtime_debug(actor, "pickup_failed", {"event_reason": "item_missing", "item_name": item_name})
			return Core.Status.FAILURE

		var atlas: Texture2D = null
		var region: Rect2i = Rect2i()
		var sprite = item_node.get_node_or_null("Sprite2D")
		if sprite:
			atlas = sprite.texture
			region = Rect2i(sprite.region_rect.position, sprite.region_rect.size)
		var item_meta: Dictionary = {}
		if actor.has_method("_pickup_item_meta"):
			item_meta = actor.call("_pickup_item_meta", item_name)

		item_node.visible = false
		var restore_timer := Timer.new()
		restore_timer.one_shot = true
		restore_timer.wait_time = 2.0
		item_node.add_child(restore_timer)
		restore_timer.timeout.connect(Callable(item_node, "show"))
		restore_timer.timeout.connect(Callable(restore_timer, "queue_free"))
		restore_timer.start()

		inventory.add_item(item_name, atlas, region, item_meta)
		actor.speak("Got " + item_name + "!")
		return Core.Status.SUCCESS

	func _find_item_in_scene(actor: Node, item_name: String) -> Node:
		var items_node = actor.get_tree().get_root().find_child("InteractiveItems", true, false)
		if items_node:
			for child in items_node.get_children():
				if "display_name" in child and child.display_name.to_lower() == item_name.to_lower():
					return child
		return null


class ActDropItem extends Core.Task:
	var _start_time: int = 0
	var _duration: int = 1500

	func tick(bb: Dictionary, actor: Node) -> int:
		if _start_time == 0:
			_start_time = BT_Actions._gameplay_now_ms(actor)
			actor.speak("Delivering order...")
			BT_Actions._emit_runtime_debug(actor, "delivery_started")
			actor.velocity = Vector2.ZERO
			return Core.Status.RUNNING

		if BT_Actions._gameplay_now_ms(actor) - _start_time < _duration:
			return Core.Status.RUNNING

		var inventory = actor.get_node_or_null("Inventory")
		if not inventory:
			bb["action_failure_reason"] = "missing_inventory"
			BT_Actions._emit_runtime_debug(actor, "delivery_failed", {"event_reason": "missing_inventory"})
			return Core.Status.FAILURE
		if not actor.has_method("_can_complete_active_delivery_after_drop") or not actor.call("_can_complete_active_delivery_after_drop"):
			bb["action_failure_reason"] = "delivery_state_invalid"
			BT_Actions._emit_runtime_debug(actor, "delivery_failed", {"event_reason": "delivery_state_invalid"})
			return Core.Status.FAILURE

		var target_customer = bb.get("target_customer")
		if not target_customer or not target_customer.has_method("receive_item"):
			bb["action_failure_reason"] = "customer_missing"
			BT_Actions._emit_runtime_debug(actor, "delivery_failed", {"event_reason": "customer_missing"})
			return Core.Status.FAILURE

		var item: Dictionary = {}
		if actor.has_method("_take_inventory_item_for_active_task"):
			item = actor.call("_take_inventory_item_for_active_task")
		else:
			item = inventory.remove_last()
		if item.is_empty():
			push_error("ActDropItem: missing bound item for active delivery task.")
			return Core.Status.FAILURE

		if not bool(target_customer.receive_item(item)):
			if actor.has_method("_restore_inventory_item_for_active_task"):
				actor.call("_restore_inventory_item_for_active_task", item)
			bb["action_failure_reason"] = "customer_cannot_receive_item"
			BT_Actions._emit_runtime_debug(actor, "delivery_failed", {"event_reason": "customer_cannot_receive_item"})
			return Core.Status.FAILURE
		if not actor.call("_complete_active_delivery_after_drop"):
			push_error("ActDropItem: delivered item but could not complete active delivery task.")
			return Core.Status.FAILURE

		var item_name := str(item.get("name", "item"))
		actor.speak("Here's your " + item_name + "! Enjoy!")

		return Core.Status.SUCCESS
