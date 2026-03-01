extends CharacterBody2D
class_name Customer

# ==================== 信号 ====================
signal customer_left(customer: Node)

# ==================== 导出变量 ====================
@export var request_text: String = "Can I order a pizza?"
@export var start_delay_sec: float = 10.0
@export var spawn_path: NodePath
@export var move_speed: float = 110.0
@export var eating_duration: float = 15.0
@export var leave_delay: float = 3.0
@export var patience_seconds: float = 90.0
@export var interact_radius: float = 64.0
const MIN_PATIENCE_SECONDS := 90.0

# ==================== 节点引用 ====================
@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# ==================== 内部状态 ====================
const InventoryScript = preload("res://scripts/Inventory.gd")
var inventory: Inventory

enum State { ENTERING, WAITING_FOR_FOOD, EATING, LEAVING, LEFT }
var current_state: State = State.ENTERING

var _arrived: bool = false
var _seat_target: Node2D = null
var _last_dir: Vector2 = Vector2.DOWN
var _target_set: bool = false
var _has_received_food: bool = false
var _spawn_position: Vector2 = Vector2.ZERO
var _final_target: Vector2 = Vector2.ZERO
var _task_deadline_ms: int = 0
var _patience_timed_out: bool = false

# 座位信息
var current_seat: String = ""

# ==================== 智能导航系统 ====================
# 卡住检测
var _last_pos: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0

# 绕行状态 - 与 Robot 一致的基于距离的设计
var _evasion_active: bool = false
var _evasion_dir: Vector2 = Vector2.ZERO
var _evasion_start_pos: Vector2 = Vector2.ZERO
var _evasion_count: int = 0

const EVASION_DISTANCE: float = 80.0  # 每次绕行移动的距离
const STUCK_THRESHOLD: float = 0.3  # 卡住判定时间
const ARRIVAL_DIST: float = 30.0  # 到达判定距离

# ==================== 生命周期 ====================
func _ready() -> void:
	add_to_group("customer")
	add_to_group("interaction")
	patience_seconds = maxf(patience_seconds, MIN_PATIENCE_SECONDS)
	_spawn_position = global_position

	if spawn_path != NodePath():
		var s := get_node(spawn_path) as Node2D
		if s:
			global_position = s.global_position
			_spawn_position = s.global_position

	# 碰撞体尺寸
	var col_shape = $CollisionShape2D.shape
	if col_shape is RectangleShape2D:
		col_shape.size = Vector2(18, 14)
	elif col_shape is CircleShape2D:
		col_shape.radius = 9.0
	
	# NavigationAgent 配置（仅用于避障参考，不用于路径规划）
	agent.avoidance_enabled = true
	agent.max_speed = move_speed
	agent.radius = 20.0
	agent.velocity_computed.connect(_on_velocity_computed)

	print("[Customer] Waiting %.1f seconds before entering..." % start_delay_sec)
	await get_tree().create_timer(start_delay_sec).timeout
	
	_spawn_position = global_position
	print("[Customer] Ready to enter. Position: ", global_position)
	
	# 随机食物
	var food_choices = ["pizza", "hotdog", "skewers", "sandwich"]
	request_text = "Can I order a " + food_choices[randi() % food_choices.size()] + "?"
	
	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	inventory.capacity = 1
	add_child(inventory)
	
	_pick_seat_and_go()

func receive_item(item: Dictionary) -> void:
	if inventory and not inventory.is_full():
		inventory.add_item(item.get("name", "unknown"), item.get("atlas"), item.get("region"))
		print("[Customer] Received item: ", item.get("name"))
		_has_received_food = true
		_start_eating()
	else:
		print("[Customer] Cannot receive item, inventory full or missing.")

func _start_eating() -> void:
	if current_state != State.WAITING_FOR_FOOD:
		return
	current_state = State.EATING
	print("[Customer] Started eating. Will finish in %.1f seconds." % eating_duration)
	await get_tree().create_timer(eating_duration).timeout
	_finish_eating()

func _finish_eating() -> void:
	if current_state != State.EATING:
		return
	print("[Customer] Finished eating. Preparing to leave...")
	await get_tree().create_timer(leave_delay).timeout
	_start_leaving()

func _start_leaving() -> void:
	current_state = State.LEAVING
	_arrived = false
	_target_set = false
	_evasion_count = 0
	_evasion_active = false
	
	var cs1 = _find_exit_point()
	_final_target = cs1.global_position if cs1 else _spawn_position
	_target_set = true
	
	print("[Customer] Leaving restaurant, heading to exit at ", _final_target)

func _find_exit_point() -> Node2D:
	for marker in get_tree().get_nodes_in_group("spawn"):
		if marker.name == "CS1":
			return marker
	return null

func _pick_seat_and_go():
	var seats := get_tree().get_nodes_in_group("seats")
	print("[Customer] Found %d seats in 'seats' group" % seats.size())
	if seats.is_empty():
		push_error("[Customer] No seats in 'seats' group.")
		return
	
	# 获取已占用座位
	var occupied_seats: Array[String] = []
	for c in get_tree().get_nodes_in_group("customer"):
		if c != self and "current_seat" in c and c.current_seat != "":
			occupied_seats.append(c.current_seat)
	
	# 筛选可用座位
	var available_seats: Array[Node2D] = []
	for seat in seats:
		if seat.name not in occupied_seats:
			available_seats.append(seat as Node2D)
	
	print("[Customer] Available seats: %d (occupied: %s)" % [available_seats.size(), str(occupied_seats)])
	
	if available_seats.is_empty():
		print("[Customer] No available seats! Waiting...")
		await get_tree().create_timer(3.0).timeout
		_pick_seat_and_go()
		return
	
	_seat_target = available_seats[randi() % available_seats.size()]
	current_seat = _seat_target.name
	_final_target = _seat_target.global_position
	_target_set = true
	_evasion_count = 0
	_evasion_active = false
	
	print("[Customer] Selected seat: %s at %s" % [_seat_target.name, _final_target])
	print("[Customer] Navigating to seat...")

func _physics_process(dt: float) -> void:
	if current_state == State.LEFT:
		return

	_tick_patience_timeout()
	
	if _arrived and current_state in [State.WAITING_FOR_FOOD, State.EATING]:
		return
	
	if not _target_set:
		return

	var to_target = _final_target - global_position
	var dist = to_target.length()
	
	# 到达检测
	if dist < ARRIVAL_DIST:
		_on_reached()
		return
	
	# Evasion mode - 持续绕行直到移动足够距离
	if _evasion_active:
		var evaded_dist = global_position.distance_to(_evasion_start_pos)
		
		if evaded_dist >= EVASION_DISTANCE:
			# 绕行完成，恢复正常导航
			_evasion_active = false
			_stuck_timer = 0.0
			print("[Customer] Evasion complete, moved ", int(evaded_dist), "px")
		else:
			# 继续绕行
			velocity = _evasion_dir * move_speed
			move_and_slide()
			_update_anim_by_velocity(velocity)
			return
	
	# 卡住检测
	var current_pos = global_position
	var moved = current_pos.distance_to(_last_pos)
	
	if moved < 1.5:
		_stuck_timer += dt
		if _stuck_timer > STUCK_THRESHOLD:
			_start_evade(to_target)
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
	
	_last_pos = current_pos
	
	# 正常朝目标移动
	velocity = to_target.normalized() * move_speed
	move_and_slide()
	_update_anim_by_velocity(velocity)

func _start_evade(to_target: Vector2) -> void:
	"""开始绕行 - 与 Robot 一致的 4 方向轮换"""
	var perpendicular = Vector2(-to_target.y, to_target.x).normalized()
	var backward = -to_target.normalized()
	
	# 根据尝试次数选择方向：左、右、后左、后右
	var dir_names = ["LEFT", "RIGHT", "BACK-LEFT", "BACK-RIGHT"]
	var dir_idx = _evasion_count % 4
	
	match dir_idx:
		0: _evasion_dir = perpendicular  # 左
		1: _evasion_dir = -perpendicular  # 右
		2: _evasion_dir = (perpendicular + backward).normalized()  # 后左
		3: _evasion_dir = (-perpendicular + backward).normalized()  # 后右
	
	_evasion_active = true
	_evasion_start_pos = global_position
	_evasion_count += 1
	
	print("[Customer] Starting evasion: %s for %dpx (attempt #%d)" % [dir_names[dir_idx], EVASION_DISTANCE, _evasion_count])

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	# 仅在避障时使用
	if _arrived:
		return
	if safe_velocity.length() > 10.0:
		velocity = safe_velocity
		move_and_slide()

func _on_reached() -> void:
	if current_state == State.ENTERING:
		if _arrived:
			return
		_arrived = true
		velocity = Vector2.ZERO

		if _seat_target != null:
			if global_position.x <= _seat_target.global_position.x:
				anim.play("sit_right")
			else:
				anim.play("sit_left")
		else:
			_update_anim_by_velocity(Vector2.ZERO)

		current_state = State.WAITING_FOR_FOOD
		_task_deadline_ms = Time.get_ticks_msec() + int(maxf(1.0, patience_seconds) * 1000.0)
		_patience_timed_out = false
		print("[Customer] Arrived at seat! Requesting: %s" % request_text)
		var bubble_mgr = get_node_or_null("/root/BubbleManager")
		if bubble_mgr and bubble_mgr.has_method("say"):
			bubble_mgr.say(self, request_text, 3.0, Color(1.0, 0.96, 0.88, 1.0))
		_post_taskboard_request()
		
	elif current_state == State.LEAVING:
		_arrived = true
		velocity = Vector2.ZERO
		current_state = State.LEFT
		print("[Customer] Left the restaurant.")
		customer_left.emit(self)
		queue_free()

func _post_taskboard_request() -> void:
	var task_board = get_node_or_null("/root/TaskBoard")
	if not task_board:
		print("[Customer] TaskBoard not found. Fallback to legacy signal only.")
		return
	if not task_board.has_method("create_fulfill_order"):
		print("[Customer] TaskBoard missing create_fulfill_order().")
		return

	var task = task_board.create_fulfill_order(self)
	if task.is_empty():
		print("[Customer] Failed to create FULFILL_ORDER task.")
		return
	print("[Customer] Task created: ", task.get("id", "unknown"), " | state=", task.get("state", "unknown"))

func _update_anim_by_velocity(v: Vector2) -> void:
	var moving := v.length() > 1.0
	if moving:
		_last_dir = v

	var dir_name := ""
	if abs(_last_dir.x) > abs(_last_dir.y):
		dir_name = "right" if _last_dir.x > 0.0 else "left"
	else:
		dir_name = "down" if _last_dir.y > 0.0 else "up"

	var anim_name := ("walk_" if moving else "idle_") + dir_name
	if anim.animation != anim_name:
		anim.play(anim_name)

# ==================== 公共 API ====================
func get_state_name() -> String:
	return State.keys()[current_state]

func is_waiting_for_food() -> bool:
	return current_state == State.WAITING_FOR_FOOD

func has_received_food() -> bool:
	return _has_received_food

func force_leave() -> void:
	if current_state == State.LEFT:
		return
	print("[Customer] Forced to leave.")
	_start_leaving()

func get_task_deadline_ms() -> int:
	var task_board = get_node_or_null("/root/TaskBoard")
	if task_board and task_board.has_method("get_open_task_for_customer"):
		var task: Dictionary = task_board.get_open_task_for_customer(get_instance_id())
		if not task.is_empty():
			return int(task.get("deadline_ms", Time.get_ticks_msec()))
	if _task_deadline_ms <= 0:
		return Time.get_ticks_msec() + int(maxf(1.0, patience_seconds) * 1000.0)
	return _task_deadline_ms

func on_player_interact(player: Node) -> void:
	if player == null:
		return
	if global_position.distance_to(player.global_position) > interact_radius:
		return

	var task_board = get_node_or_null("/root/TaskBoard")
	if task_board and task_board.has_method("get_in_progress_task_for_customer"):
		var task: Dictionary = task_board.get_in_progress_task_for_customer(get_instance_id(), "player")
		if not task.is_empty():
			var task_id := str(task.get("id", ""))
			var step_name := str(task_board.get_current_step_name(task_id))
			if step_name == "TAKE_ORDER":
				if task_board.complete_current_step(task_id, "TAKE_ORDER"):
					print("[Customer] Player took order for ", task_id)
				return
			if step_name != "DELIVER_AND_SERVE":
				return

	if current_state != State.WAITING_FOR_FOOD:
		return

	var p_inv = player.get_node_or_null("Inventory")
	if p_inv == null:
		return

	var wanted := _extract_food_from_request(request_text)
	var idx: int = p_inv.find_item(wanted)
	if idx == -1:
		print("[Customer] Player does not have requested item: ", wanted)
		return

	var item = p_inv.items.pop_at(idx)
	p_inv.emit_signal("inventory_changed", p_inv.items)
	receive_item(item)
	if task_board and task_board.has_method("get_in_progress_task_for_customer"):
		var ptask: Dictionary = task_board.get_in_progress_task_for_customer(get_instance_id(), "player")
		if not ptask.is_empty():
			var ptask_id := str(ptask.get("id", ""))
			task_board.complete_current_step(ptask_id, "DELIVER_AND_SERVE")

func _tick_patience_timeout() -> void:
	if current_state != State.WAITING_FOR_FOOD:
		return
	if _patience_timed_out:
		return
	if _task_deadline_ms <= 0:
		_task_deadline_ms = get_task_deadline_ms()
	if Time.get_ticks_msec() < get_task_deadline_ms():
		return

	_patience_timed_out = true
	print("[Customer] Patience timeout reached. Leaving now.")

	var task_board = get_node_or_null("/root/TaskBoard")
	if task_board and task_board.has_method("fail_task_by_customer"):
		task_board.fail_task_by_customer(get_instance_id(), "customer_patience_timeout")

	var logger = get_node_or_null("/root/EpisodeLogger")
	if logger and logger.has_method("log_replay_event"):
		logger.log_replay_event("customer_patience_timeout", {
			"customer_instance_id": get_instance_id(),
			"seat": current_seat,
			"request_text": request_text
		})

	_start_leaving()

func _extract_food_from_request(request: String) -> String:
	var request_lower = request.to_lower()
	var foods = ["pizza", "hotdog", "skewers", "sandwich"]
	for food in foods:
		if food in request_lower:
			return food
	return "unknown"
