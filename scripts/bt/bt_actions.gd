# res://scripts/bt/bt_actions.gd
extends Resource
class_name BT_Actions

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
			_last_pos_time = Time.get_ticks_msec()
			var start_nav := NavigationServer2D.map_get_closest_point(nav_map, actor.global_position)
			if actor.global_position.distance_to(start_nav) > 6.0:
				actor.global_position = start_nav
				_last_pos = actor.global_position
			print("[ActNavigate][Start] from=", actor.global_position, " to=", _final_target, " radius=", agent.radius)

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
				_arrival_time = Time.get_ticks_msec()
				actor.velocity = Vector2.ZERO
				actor.move_and_slide()
			if Time.get_ticks_msec() - _arrival_time >= _arrival_wait:
				return Core.Status.SUCCESS
			return Core.Status.RUNNING

		var start_nav_now: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, actor.global_position)
		var target_nav_now: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, _final_target)
		var server_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, start_nav_now, target_nav_now, true, 1)
		if actor.has_method("set_nav_debug_path"):
			actor.call("set_nav_debug_path", server_path)

		var now_ms: int = Time.get_ticks_msec()
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

				if _retry_count >= MAX_RETRY_ATTEMPTS or _total_stuck_time_ms >= STUCK_TIMEOUT_MS:
					bb["help_reason"] = "too_many_evasions"
					bb["help_stuck_position"] = actor.global_position
					bb["help_evasion_attempts"] = _retry_count
					print("[ActNavigate][Fail] from=", actor.global_position, " to=", _final_target, " retries=", _retry_count, " stuck_ms=", _total_stuck_time_ms, " path_points=", server_path.size())
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
		if has_valid_path and to_next.length() > 1.0:
			actor.velocity = to_next.normalized() * actor.move_speed
		else:
			actor.velocity = Vector2.ZERO
		actor.move_and_slide()

		return Core.Status.RUNNING

	func _set_agent_target(agent: NavigationAgent2D, actor: Node, target: Vector2) -> void:
		agent.set_navigation_map(actor.get_world_2d().navigation_map)
		agent.navigation_layers = 1
		agent.path_desired_distance = 12.0
		agent.target_desired_distance = 10.0
		agent.max_speed = actor.move_speed
		agent.avoidance_enabled = false
		agent.radius = 10.0
		agent.target_position = target


class ActPickItem extends Core.Task:
	var _start_time: int = 0
	var _duration: int = 1500

	func tick(bb: Dictionary, actor: Node) -> int:
		if _start_time == 0:
			_start_time = Time.get_ticks_msec()
			actor.speak("Picking up...")
			var agent = actor.get_node_or_null("NavigationAgent2D")
			if agent:
				agent.set_velocity(Vector2.ZERO)
			return Core.Status.RUNNING

		if Time.get_ticks_msec() - _start_time < _duration:
			return Core.Status.RUNNING

		var item_name: String = str(bb.get("item_name", "Unknown Item"))
		if bb.has("locations") and bb["locations"].has(item_name):
			var target_pos: Vector2 = bb["locations"][item_name]
			if actor.global_position.distance_to(target_pos) > 150.0:
				actor.speak("I'm too far away!")
				return Core.Status.FAILURE

		var inventory = actor.get_node_or_null("Inventory")
		if not inventory:
			return Core.Status.FAILURE
		if inventory.is_full():
			actor.speak("Inventory full!")
			return Core.Status.FAILURE

		var item_node = _find_item_in_scene(actor, item_name)
		if not item_node:
			actor.speak("I can't find " + item_name + " right now.")
			return Core.Status.FAILURE

		var atlas: Texture2D = null
		var region: Rect2i = Rect2i()
		var sprite = item_node.get_node_or_null("Sprite2D")
		if sprite:
			atlas = sprite.texture
			region = Rect2i(sprite.region_rect.position, sprite.region_rect.size)

		item_node.visible = false
		var tree = actor.get_tree()
		if tree:
			tree.create_timer(2.0).timeout.connect(func():
				if is_instance_valid(item_node):
					item_node.visible = true
			)

		inventory.add_item(item_name, atlas, region)
		bb["carrying_item"] = true
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
			_start_time = Time.get_ticks_msec()
			actor.speak("Delivering order...")
			var agent = actor.get_node_or_null("NavigationAgent2D")
			if agent:
				agent.set_velocity(Vector2.ZERO)
			return Core.Status.RUNNING

		if Time.get_ticks_msec() - _start_time < _duration:
			return Core.Status.RUNNING

		var inventory = actor.get_node_or_null("Inventory")
		if not inventory:
			return Core.Status.FAILURE

		var item = inventory.remove_last()
		if item.is_empty():
			actor.speak("Nothing to deliver!")
			return Core.Status.FAILURE

		bb["carrying_item"] = false
		var item_name := str(item.get("name", "item"))
		actor.speak("Here's your " + item_name + "! Enjoy!")

		var target_customer = bb.get("target_customer")
		if target_customer and target_customer.has_method("receive_item"):
			target_customer.receive_item(item)

		return Core.Status.SUCCESS


class ActAskHelp extends Core.Task:
	var _state: int = 0
	var _nav_node: ActNavigate = null
	var _target_item: String = ""
	var _help_reason: String = ""

	func tick(bb: Dictionary, actor: Node) -> int:
		_target_item = bb.get("item_name", "item")
		_help_reason = bb.get("help_reason", "unknown")

		if _state == 0:
			var players = actor.get_tree().get_nodes_in_group("player")
			if players.is_empty():
				return Core.Status.FAILURE
			bb["player_target"] = players[0]
			_nav_node = ActNavigate.new("player_target")
			_state = 1

		if _state == 1:
			var status = _nav_node.tick(bb, actor)
			if status == Core.Status.SUCCESS:
				_state = 2
			elif status == Core.Status.FAILURE:
				return Core.Status.FAILURE
			else:
				return Core.Status.RUNNING

		if _state == 2:
			var help_message: String
			if _help_reason == "evasion_timeout":
				help_message = "I got stuck trying to get the " + _target_item + ". Can you bring it to me?"
			elif _help_reason == "too_many_evasions":
				help_message = "I've tried many times but can't reach the " + _target_item + ". Can you bring it to me?"
			else:
				help_message = "I can't reach the " + _target_item + ". Please give it to me!"

			actor.speak(help_message)
			actor.set_waiting_for_help(true, _target_item)

			var agent = actor.get_node_or_null("NavigationAgent2D")
			if agent:
				agent.set_velocity(Vector2.ZERO)
			_state = 3
			return Core.Status.RUNNING

		if _state == 3:
			if bb.get("carrying_item", false):
				actor.speak("Thank you!")
				actor.set_waiting_for_help(false, "")
				var logger = actor.get_node_or_null("/root/EpisodeLogger")
				if logger:
					logger.log_event("player_help", {
						"item_given": _target_item,
						"position": {"x": actor.global_position.x, "y": actor.global_position.y}
					})
				return Core.Status.SUCCESS
			return Core.Status.RUNNING

		return Core.Status.FAILURE
