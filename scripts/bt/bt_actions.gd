# res://scripts/bt/bt_actions.gd
extends Resource
class_name BT_Actions

const Core = preload("res://scripts/bt/bt_core.gd")

# Room and Door definitions
const DOOR_POS = Vector2(0, -200)  # Center of the door
const DOOR_Y_TOP = -256    # Kitchen side of door
const DOOR_Y_BOTTOM = -144 # Lower room side of door
const WALL_Y = -150        # Y coordinate of the wall between rooms

# ------------------------------------------------------------------------------
# Helper: Determine which room a position is in
# ------------------------------------------------------------------------------
static func get_room(pos: Vector2) -> String:
	if pos.y < WALL_Y:
		return "kitchen"  # Upper room (more negative y)
	else:
		return "lower"    # Lower room (dining area)

# ------------------------------------------------------------------------------
# 1. ActNavigate: Move to position with room-aware pathfinding
# ------------------------------------------------------------------------------
class ActNavigate extends Core.Task:
	var target_key: String
	var _target_set: bool = false
	var _final_target: Vector2 = Vector2.ZERO
	var _waypoints: Array = []  # Queue of positions to visit
	var _current_waypoint_idx: int = 0
	
	var _arrival_time: int = 0
	var _arrival_wait: int = 800 
	
	# Arrival distance thresholds
	var _is_customer_target: bool = false
	var _is_player_target: bool = false
	const ARRIVAL_DIST_NORMAL = 50.0       # Normal waypoint arrival
	const ARRIVAL_DIST_CUSTOMER = 250.0    # Customer interaction area (very large for easier delivery)
	const ARRIVAL_DIST_PLAYER = 250.0      # Player interaction area (same as customer)
	const ARRIVAL_DIST_STUCK = 300.0       # Accept arrival if stuck but close enough

	# Stuck detection
	var _last_pos: Vector2 = Vector2.ZERO
	var _last_pos_time: int = 0
	var _stuck_duration: int = 0
	var _total_stuck_time: int = 0
	
	# Evasion state - 持续绕行直到移动足够距离
	var _evasion_active: bool = false
	var _evasion_dir: Vector2 = Vector2.ZERO
	var _evasion_start_pos: Vector2 = Vector2.ZERO
	var _evasion_count: int = 0  # 尝试次数，用于切换方向
	const EVASION_DISTANCE: float = 80.0   # 每次绕行移动的距离
	const EVASION_TIMEOUT: int = 5000      # 5秒超时后求助 Player (backup)
	const MAX_EVASION_ATTEMPTS: int = 3    # 最多尝试 3 次 evasion 后求助 Player

	func _init(key: String = "target_pos"):
		target_key = key
		# Check if navigating to customer or player (uses special keys)
		_is_customer_target = (key == "target_customer")
		_is_player_target = (key == "player_target")
		
	func tick(bb: Dictionary, actor: Node) -> int:
		var agent: NavigationAgent2D = actor.get_node("NavigationAgent2D")
		if not agent:
			return Core.Status.FAILURE

		# 1. Initialize waypoints if not set
		if not _target_set:
			if not bb.has(target_key):
				print("[ActNavigate] Target key not found: ", target_key)
				return Core.Status.FAILURE
			
			var raw_target = bb[target_key]
			
			if raw_target is Node2D:
				_final_target = raw_target.global_position
			elif raw_target is Vector2:
				_final_target = raw_target
			else:
				print("[ActNavigate] Invalid target type: ", raw_target)
				return Core.Status.FAILURE

			# Plan waypoints based on rooms
			_waypoints = _plan_path(actor.global_position, _final_target)
			_current_waypoint_idx = 0
			_target_set = true
			
			print("[ActNavigate] Planned path with ", _waypoints.size(), " waypoints")
			for i in range(_waypoints.size()):
				print("  [", i, "] ", _waypoints[i])
			
			# Set first waypoint
			if _waypoints.size() > 0:
				_set_agent_target(agent, actor, _waypoints[0])

		# 2. Check if we've reached current waypoint
		var current_target = _waypoints[_current_waypoint_idx] if _current_waypoint_idx < _waypoints.size() else _final_target
		var dist_to_waypoint = actor.global_position.distance_to(current_target)
		
		# Use larger threshold for final waypoint when targeting customer or player (interaction area)
		var is_final_waypoint = (_current_waypoint_idx >= _waypoints.size() - 1)
		var arrival_threshold = ARRIVAL_DIST_NORMAL
		if is_final_waypoint:
			if _is_customer_target:
				arrival_threshold = ARRIVAL_DIST_CUSTOMER
			elif _is_player_target:
				arrival_threshold = ARRIVAL_DIST_PLAYER
		
		if dist_to_waypoint < arrival_threshold or agent.is_navigation_finished():
			# Reached current waypoint, move to next
			_current_waypoint_idx += 1
			
			if _current_waypoint_idx >= _waypoints.size():
				# All waypoints done, we've arrived!
				if _arrival_time == 0:
					_arrival_time = Time.get_ticks_msec()
					agent.set_velocity(Vector2.ZERO)
				
				if Time.get_ticks_msec() - _arrival_time >= _arrival_wait:
					print("[ActNavigate] Arrived at final destination")
					return Core.Status.SUCCESS
				else:
					return Core.Status.RUNNING
			else:
				# Set next waypoint
				_set_agent_target(agent, actor, _waypoints[_current_waypoint_idx])
				_total_stuck_time = 0  # Reset stuck timer for new waypoint
				print("[ActNavigate] Moving to waypoint ", _current_waypoint_idx)

		# 3. Evasion mode - 持续绕行直到移动足够距离
		if _evasion_active:
			var evaded_dist = actor.global_position.distance_to(_evasion_start_pos)
			
			if evaded_dist >= EVASION_DISTANCE:
				# 绕行完成，恢复正常导航
				_evasion_active = false
				_stuck_duration = 0
				print("[ActNavigate] Evasion complete, moved ", int(evaded_dist), "px")
			else:
				# 继续绕行
				actor.velocity = _evasion_dir * actor.move_speed
				actor.move_and_slide()
				return Core.Status.RUNNING
		
		# 4. Stuck detection
		var current_time = Time.get_ticks_msec()
		
		if current_time - _last_pos_time > 200:
			var moved_dist = actor.global_position.distance_to(_last_pos)
			_last_pos = actor.global_position
			_last_pos_time = current_time
			
			if moved_dist < 3.0:
				_stuck_duration += 200
				_total_stuck_time += 200
				
				# Check if stuck but close enough to target (especially for customer or player)
				var dist_to_final = actor.global_position.distance_to(_final_target)
				var close_enough_threshold = 60.0
				if _is_customer_target or _is_player_target:
					close_enough_threshold = ARRIVAL_DIST_STUCK
				
				if _total_stuck_time > 2000 and dist_to_final < close_enough_threshold:
					# Stuck but within acceptable range - count as success
					print("[ActNavigate] Stuck but close enough (", int(dist_to_final), "px). Accepting arrival.")
					agent.set_velocity(Vector2.ZERO)
					return Core.Status.SUCCESS
				
				# 触发绕行模式 - 尝试 4 个方向轮换
				if _stuck_duration > 300:
					var dir_to_target = _final_target - actor.global_position
					var perpendicular = Vector2(-dir_to_target.y, dir_to_target.x).normalized()
					var backward = -dir_to_target.normalized()
					
					# 根据尝试次数选择方向：左、右、后左、后右
					var dir_names = ["LEFT", "RIGHT", "BACK-LEFT", "BACK-RIGHT"]
					var dir_idx = _evasion_count % 4
					
					match dir_idx:
						0: _evasion_dir = perpendicular  # 左
						1: _evasion_dir = -perpendicular  # 右
						2: _evasion_dir = (perpendicular + backward).normalized()  # 后左
						3: _evasion_dir = (-perpendicular + backward).normalized()  # 后右
					
					_evasion_active = true
					_evasion_start_pos = actor.global_position
					_stuck_duration = 0
					_evasion_count += 1  # 递增，下次用不同方向
					
					print("[ActNavigate] Starting evasion: ", dir_names[dir_idx], " for ", EVASION_DISTANCE, "px (attempt #", _evasion_count, ")")
					
					# Log evasion event
					var logger = actor.get_node_or_null("/root/EpisodeLogger")
					if logger:
						logger.log_event("evasion", {
							"position": {"x": actor.global_position.x, "y": actor.global_position.y},
							"direction": dir_names[dir_idx],
							"distance": EVASION_DISTANCE,
							"attempt": _evasion_count
						})
					
					# Check if exceeded max evasion attempts - trigger help request
					if _evasion_count >= MAX_EVASION_ATTEMPTS:
						print("[ActNavigate] MAX EVASION ATTEMPTS REACHED: ", _evasion_count, " attempts. Will ask player for help.")
						
						bb["help_reason"] = "too_many_evasions"
						bb["help_stuck_position"] = actor.global_position
						bb["help_evasion_attempts"] = _evasion_count
						
						# Log max evasion event
						var max_logger = actor.get_node_or_null("/root/EpisodeLogger")
						if max_logger:
							max_logger.log_event("max_evasion_help_needed", {
								"position": {"x": actor.global_position.x, "y": actor.global_position.y},
								"distance_to_target": dist_to_final,
								"evasion_attempts": _evasion_count
							})
						
						if actor.has_method("speak"):
							actor.speak("I've tried " + str(_evasion_count) + " times but can't get through. Need help!")
						
						return Core.Status.FAILURE
				
				# Evasion timeout - need to ask player for help (backup check)
				if _total_stuck_time > EVASION_TIMEOUT:
					print("[ActNavigate] EVASION TIMEOUT: Stuck for ", EVASION_TIMEOUT / 1000.0, "s, dist=", int(dist_to_final), "px. Will ask player for help.")
					
					# Set help reason in blackboard for RobotServer to use
					bb["help_reason"] = "evasion_timeout"
					bb["help_stuck_position"] = actor.global_position
					bb["help_stuck_duration_ms"] = _total_stuck_time
					
					# Log evasion timeout event
					var timeout_logger = actor.get_node_or_null("/root/EpisodeLogger")
					if timeout_logger:
						timeout_logger.log_event("evasion_timeout_help_needed", {
							"position": {"x": actor.global_position.x, "y": actor.global_position.y},
							"duration_ms": _total_stuck_time,
							"distance_to_target": dist_to_final,
							"evasion_attempts": _evasion_count
						})
					
					# Speak to indicate stuck
					if actor.has_method("speak"):
						actor.speak("I'm stuck! Going to ask for help...")
					
					return Core.Status.FAILURE
			else:
				_stuck_duration = 0
				if moved_dist > 15.0:
					_total_stuck_time = 0
					# 注意：不重置 _evasion_count，让它继续轮换方向
		
		# 4. Move toward current waypoint (direct movement, bypass NavAgent if needed)
		var target_wp = _waypoints[_current_waypoint_idx] if _current_waypoint_idx < _waypoints.size() else _final_target
		var to_target = target_wp - actor.global_position
		
		if to_target.length() > 5.0:
			var desired = to_target.normalized() * actor.move_speed
			agent.set_velocity(desired)
		else:
			agent.set_velocity(Vector2.ZERO)
		
		return Core.Status.RUNNING
	
	func _plan_path(start: Vector2, end: Vector2) -> Array:
		var waypoints = []
		var start_room = BT_Actions.get_room(start)
		var end_room = BT_Actions.get_room(end)
		
		print("[ActNavigate] Planning: ", start_room, " -> ", end_room)
		
		if start_room != end_room:
			# Different rooms - must go through door first
			if start_room == "lower":
				# In lower room, going to kitchen
				waypoints.append(Vector2(BT_Actions.DOOR_POS.x, BT_Actions.DOOR_Y_BOTTOM + 20))
				waypoints.append(Vector2(BT_Actions.DOOR_POS.x, BT_Actions.DOOR_Y_TOP - 20))
			else:
				# In kitchen, going to lower room
				waypoints.append(Vector2(BT_Actions.DOOR_POS.x, BT_Actions.DOOR_Y_TOP - 20))
				waypoints.append(Vector2(BT_Actions.DOOR_POS.x, BT_Actions.DOOR_Y_BOTTOM + 20))
		
		# For final destination (or same room), add intermediate waypoints to avoid obstacles
		var approach_start = waypoints[-1] if waypoints.size() > 0 else start
		var approach_waypoints = _plan_approach_around_obstacles(approach_start, end)
		waypoints.append_array(approach_waypoints)
		
		return waypoints
	
	func _plan_approach_around_obstacles(start: Vector2, end: Vector2) -> Array:
		# Try to find a path that avoids tables/obstacles
		var waypoints = []
		var direct_dist = start.distance_to(end)
		
		# If very close, just go direct
		if direct_dist < 100:
			waypoints.append(end)
			return waypoints
		
		# Check if we're in the kitchen (y < WALL_Y)
		# Kitchen has no tables, so just go directly to target
		var start_room = BT_Actions.get_room(start)
		var end_room = BT_Actions.get_room(end)
		
		if start_room == "kitchen" and end_room == "kitchen":
			# Both in kitchen - direct path, no obstacles
			waypoints.append(end)
			return waypoints
		
		# Only use corridor system in the lower (dining) room
		# 座位布局: seat2 (y=43), seat3 (y=88), seat1/seat5 (y=216), seat4 (y=262)
		# 桌子高度约 60px，走廊必须在桌子区域之外
		var corridor_y_positions = [
			0.0,     # 上走廊（门下方，安全）
			165.0,   # 中走廊（seat2/seat3 桌子下方约 77px，seat1/seat5 桌子上方约 51px）
			310.0,   # 下走廊（seat4 桌子下方约 48px，接近入口）
		]
		
		# Find the best corridor to use
		var best_corridor_y = _find_best_corridor(start.y, end.y, corridor_y_positions)
		
		if best_corridor_y != -999:
			# Route through corridor
			# 1. Go to corridor at current x
			var corridor_entry = Vector2(start.x, best_corridor_y)
			# 2. Move along corridor toward target x
			var corridor_exit = Vector2(end.x, best_corridor_y)
			
			# Only add corridor waypoints if they help avoid obstacles
			if abs(start.y - best_corridor_y) > 40:
				waypoints.append(corridor_entry)
			if abs(corridor_entry.x - corridor_exit.x) > 40:
				waypoints.append(corridor_exit)
		
		# Final destination
		waypoints.append(end)
		return waypoints
	
	func _find_best_corridor(start_y: float, end_y: float, corridors: Array) -> float:
		# Find a corridor that's between start and end, or closest to midpoint
		var mid_y = (start_y + end_y) / 2
		var best = -999.0
		var best_score = 999999.0
		
		for corridor_y in corridors:
			# Corridor should be roughly between start and end y
			var is_between = (corridor_y >= min(start_y, end_y) - 50 and 
							  corridor_y <= max(start_y, end_y) + 50)
			
			var dist_to_mid = abs(corridor_y - mid_y)
			
			if is_between and dist_to_mid < best_score:
				best_score = dist_to_mid
				best = corridor_y
		
		# If no corridor between, find closest one
		if best == -999.0:
			for corridor_y in corridors:
				var dist_to_mid = abs(corridor_y - mid_y)
				if dist_to_mid < best_score:
					best_score = dist_to_mid
					best = corridor_y
		
		return best
	
	func _set_agent_target(agent: NavigationAgent2D, actor: Node, target: Vector2):
		agent.path_desired_distance = 25.0 
		agent.target_desired_distance = 15.0
		agent.target_position = target
		agent.max_speed = actor.move_speed
		agent.avoidance_enabled = true 
		agent.radius = 20.0
# ------------------------------------------------------------------------------
# 2. ActPickItem: Pick item into Inventory (with delay)
# ------------------------------------------------------------------------------
class ActPickItem extends Core.Task:
	var _start_time: int = 0
	var _duration: int = 1500  # Reduced from 2500ms
	
	func tick(bb: Dictionary, actor: Node) -> int:
		if _start_time == 0:
			_start_time = Time.get_ticks_msec()
			actor.speak("Picking up...")
			var agent = actor.get_node_or_null("NavigationAgent2D")
			if agent: agent.set_velocity(Vector2.ZERO)
			return Core.Status.RUNNING
			
		if Time.get_ticks_msec() - _start_time < _duration:
			return Core.Status.RUNNING
			
		var item_name = bb.get("item_name", "Unknown Item")
		
		# Check distance to target before picking
		if bb.has("locations") and bb["locations"].has(item_name):
			var target_pos = bb["locations"][item_name]
			var dist = actor.global_position.distance_to(target_pos)
			if dist > 150.0:  # Threshold: 150px
				print("[ActPickItem] FAILED: Too far from item! Dist: ", dist)
				actor.speak("I'm too far away!")
				return Core.Status.FAILURE
			
		var inventory = actor.get_node_or_null("Inventory")
		if not inventory:
			print("[ActPickItem] FAILED: No inventory!")
			return Core.Status.FAILURE
			
		if inventory.is_full():
			actor.speak("Inventory full!")
			return Core.Status.FAILURE
		
		# Find and remove the actual Item node from the scene
		var item_node = _find_item_in_scene(actor, item_name)
		var atlas: Texture2D = null
		var region: Rect2i = Rect2i()
		
		if item_node:
			# Get sprite info before hiding
			var sprite = item_node.get_node_or_null("Sprite2D")
			if sprite:
				atlas = sprite.texture
				region = Rect2i(sprite.region_rect.position, sprite.region_rect.size)
			# Hide the item temporarily (will respawn after 2 seconds)
			item_node.visible = false
			print("[ActPickItem] Hid item from scene: ", item_name)
			# Respawn item after 2 seconds
			var tree = actor.get_tree()
			if tree:
				tree.create_timer(2.0).timeout.connect(func():
					if is_instance_valid(item_node):
						item_node.visible = true
						print("[ActPickItem] Item respawned: ", item_name)
				)
		
		# Add to inventory
		inventory.add_item(item_name, atlas, region)
		bb["carrying_item"] = true
		actor.speak("Got " + item_name + "!")
		print("[ActPickItem] SUCCESS: Picked up ", item_name)
		
		return Core.Status.SUCCESS
	
	func _find_item_in_scene(actor: Node, item_name: String) -> Node:
		# Search in InteractiveItems
		var items_node = actor.get_tree().get_root().find_child("InteractiveItems", true, false)
		if items_node:
			for child in items_node.get_children():
				if "display_name" in child and child.display_name.to_lower() == item_name.to_lower():
					return child
		return null

# ------------------------------------------------------------------------------
# 3. ActDropItem: Drop item from Inventory (with delay)
# ------------------------------------------------------------------------------
class ActDropItem extends Core.Task:
	var _start_time: int = 0
	var _duration: int = 1500  # Reduced from 2500ms

	func tick(bb: Dictionary, actor: Node) -> int:
		if _start_time == 0:
			_start_time = Time.get_ticks_msec()
			actor.speak("Delivering order...")
			var agent = actor.get_node_or_null("NavigationAgent2D")
			if agent: agent.set_velocity(Vector2.ZERO)
			return Core.Status.RUNNING
			
		if Time.get_ticks_msec() - _start_time < _duration:
			return Core.Status.RUNNING
			
		var inventory = actor.get_node_or_null("Inventory")
		if not inventory:
			print("[ActDropItem] FAILED: No inventory!")
			return Core.Status.FAILURE
			
		var item = inventory.remove_last()
		if item.is_empty():
			actor.speak("Nothing to deliver!")
			return Core.Status.FAILURE
			
		bb["carrying_item"] = false
		var item_name = str(item.get("name", "item"))
		actor.speak("Here's your " + item_name + "! Enjoy!")
		print("[ActDropItem] SUCCESS: Delivered ", item_name)
		
		var target_customer = bb.get("target_customer")
		if target_customer and target_customer.has_method("receive_item"):
			target_customer.receive_item(item)
			
		return Core.Status.SUCCESS

# ------------------------------------------------------------------------------
# 4. ActAskHelp: Go to player and ask for item
# ------------------------------------------------------------------------------
class ActAskHelp extends Core.Task:
	var _state: int = 0 # 0: Init, 1: Navigating, 2: Asking, 3: Waiting, 4: Done
	var _nav_node: ActNavigate = null
	var _target_item: String = ""
	var _help_reason: String = ""
	
	func tick(bb: Dictionary, actor: Node) -> int:
		_target_item = bb.get("item_name", "item")
		_help_reason = bb.get("help_reason", "unknown")
		
		if _state == 0:
			# Find player
			var players = actor.get_tree().get_nodes_in_group("player")
			if players.is_empty():
				print("[ActAskHelp] No player found!")
				return Core.Status.FAILURE
			
			bb["player_target"] = players[0]
			_nav_node = ActNavigate.new("player_target")
			_state = 1
			print("[ActAskHelp] Going to player for help. Reason: ", _help_reason)
			
		if _state == 1:
			var status = _nav_node.tick(bb, actor)
			if status == Core.Status.SUCCESS:
				_state = 2
			elif status == Core.Status.FAILURE:
				return Core.Status.FAILURE
			else:
				return Core.Status.RUNNING
				
		if _state == 2:
			# Customize dialogue based on help reason
			var help_message: String
			if _help_reason == "evasion_timeout":
				help_message = "I got stuck trying to get the " + _target_item + ". Can you bring it to me?"
			elif _help_reason == "too_many_evasions":
				help_message = "I've tried many times but can't reach the " + _target_item + ". Can you bring it to me?"
			else:
				help_message = "I can't reach the " + _target_item + ". Please give it to me!"
			
			actor.speak(help_message)
			actor.set_waiting_for_help(true, _target_item) # Custom method on Robot
			
			# STOP MOVING while waiting for help
			var agent = actor.get_node_or_null("NavigationAgent2D")
			if agent: agent.set_velocity(Vector2.ZERO)
			
			_state = 3
			return Core.Status.RUNNING
			
		if _state == 3:
			# Check if we received the item
			# RobotServer should set 'carrying_item' to true when player interacts
			if bb.get("carrying_item", false):
				actor.speak("Thank you!")
				actor.set_waiting_for_help(false, "")
				
				# Log player help event
				var logger = actor.get_node_or_null("/root/EpisodeLogger")
				if logger:
					logger.log_event("player_help", {
						"item_given": _target_item,
						"position": {"x": actor.global_position.x, "y": actor.global_position.y}
					})
				
				return Core.Status.SUCCESS
				
			return Core.Status.RUNNING
			
		return Core.Status.FAILURE
