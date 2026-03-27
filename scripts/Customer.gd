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
@export var drink_order_probability: float = 0.24
const MIN_PATIENCE_SECONDS := 90.0
const DRINK_CHOICES := ["cola", "tea", "coffee"]

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
var _has_received_drink: bool = false
var _spawn_position: Vector2 = Vector2.ZERO
var _final_target: Vector2 = Vector2.ZERO
var _task_deadline_ms: int = 0
var _patience_timed_out: bool = false
var _pending_player_line_request_id: String = ""
var _drink_request_text: String = ""
var _drink_item: String = ""
var _drink_required: bool = false
var _drink_order_activated: bool = false
var _drink_timeout_handled: bool = false
var _order_bubble_root: Node2D = null
var _order_bubble_panel: PanelContainer = null
var _order_bubble_label: Label = null

# 座位信息
var current_seat: String = ""

# ==================== 智能导航系统 ====================
# 卡住检测
var _last_pos: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0

const ARRIVAL_DIST: float = 30.0  # 默认到达判定距离
const ARRIVAL_DIST_SEAT: float = 56.0  # 入座判定半径（seat 点可在不可走区边缘）
const ARRIVAL_DIST_STUCK: float = 80.0  # 导航结束但与目标有偏差时的容错
const ENTERING_STUCK_TIMEOUT_SEC: float = 3.0
var _path_initialized: bool = false

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
	
	# NavigationAgent 配置
	agent.set_navigation_map(get_world_2d().navigation_map)
	agent.avoidance_enabled = true
	agent.max_speed = move_speed
	agent.radius = 14.0
	agent.path_desired_distance = 12.0
	agent.target_desired_distance = 14.0
	agent.velocity_computed.connect(_on_velocity_computed)
	_connect_dialogue_manager()

	print("[Customer] Waiting %.1f seconds before entering..." % start_delay_sec)
	await get_tree().create_timer(start_delay_sec).timeout
	
	_spawn_position = global_position
	print("[Customer] Ready to enter. Position: ", global_position)
	
	# 随机食物
	var food_choices = ["pizza", "hotdog", "sandwich"]
	request_text = "Can I order a " + food_choices[randi() % food_choices.size()] + "?"
	_roll_optional_drink_order()
	
	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	inventory.capacity = 2
	add_child(inventory)
	
	_pick_seat_and_go()
	_setup_order_bubble()

func receive_item(item: Dictionary) -> void:
	var item_name := str(item.get("name", "unknown")).strip_edges().to_lower()
	_receive_service_item(item_name, item)

func receive_drink(item_name: String) -> void:
	var item := {
		"name": item_name,
		"atlas": null,
		"region": Rect2i()
	}
	_receive_service_item(item_name, item)

func _receive_service_item(item_name: String, item: Dictionary) -> void:
	if inventory == null or inventory.is_full():
		print("[Customer] Cannot receive item, inventory full or missing.")
		return
	inventory.add_item(item.get("name", item_name), item.get("atlas"), item.get("region"))
	print("[Customer] Received item: ", item_name)
	if item_name == _drink_item:
		_has_received_drink = true
	else:
		_has_received_food = true
	_try_begin_eating_if_ready()

func _try_begin_eating_if_ready() -> void:
	if not _has_received_food:
		return
	if _drink_required and not _has_received_drink:
		return
	_start_eating()

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
	_path_initialized = false
	
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
	_path_initialized = false
	_stuck_timer = 0.0
	_last_pos = global_position
	
	print("[Customer] Selected seat: %s at %s" % [_seat_target.name, _final_target])
	print("[Customer] Navigating to seat...")

func _roll_optional_drink_order() -> void:
	_drink_required = randf() < clampf(drink_order_probability, 0.0, 1.0)
	if not _drink_required:
		_drink_item = ""
		_drink_request_text = ""
		return
	_drink_item = DRINK_CHOICES[randi() % DRINK_CHOICES.size()]
	_drink_request_text = "Can I also get a " + _drink_item + "?"

func _setup_order_bubble() -> void:
	if _order_bubble_root != null:
		return
	_order_bubble_root = Node2D.new()
	_order_bubble_root.name = "OrderBubble"
	_order_bubble_root.position = Vector2(-28, -118)
	add_child(_order_bubble_root)

	_order_bubble_panel = PanelContainer.new()
	_order_bubble_panel.visible = false
	_order_bubble_root.add_child(_order_bubble_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.99, 1.0, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.18, 0.22, 0.28, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	_order_bubble_panel.add_theme_stylebox_override("panel", style)
	_order_bubble_panel.size = Vector2(56, 56)

	_order_bubble_label = Label.new()
	_order_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_order_bubble_label.position = Vector2(4, 4)
	_order_bubble_label.size = Vector2(48, 48)
	_order_bubble_label.add_theme_font_size_override("font_size", 28)
	_order_bubble_panel.add_child(_order_bubble_label)
	_refresh_order_bubble()

func _physics_process(dt: float) -> void:
	if current_state == State.LEFT:
		return

	_tick_order_timeouts()
	_refresh_order_bubble()
	
	if _arrived and current_state in [State.WAITING_FOR_FOOD, State.EATING]:
		return
	
	if not _target_set:
		return

	if not _path_initialized:
		agent.target_position = _final_target
		_path_initialized = true
		_last_pos = global_position

	# ENTERING 卡住保护：3 秒几乎不前进则重选座位
	if current_state == State.ENTERING:
		var moved_dist := global_position.distance_to(_last_pos)
		if moved_dist < 0.8:
			_stuck_timer += dt
		else:
			_stuck_timer = 0.0
		_last_pos = global_position
		if _stuck_timer >= ENTERING_STUCK_TIMEOUT_SEC:
			_stuck_timer = 0.0
			_path_initialized = false
			_target_set = false
			agent.set_velocity(Vector2.ZERO)
			print("[Customer] Entering stuck for %.1fs, reselecting seat..." % ENTERING_STUCK_TIMEOUT_SEC)
			_pick_seat_and_go()
			return

	var dist = global_position.distance_to(_final_target)
	var arrival_dist := ARRIVAL_DIST
	if current_state == State.ENTERING:
		arrival_dist = ARRIVAL_DIST_SEAT
	if dist < arrival_dist:
		_on_reached()
		return

	# NavigationAgent 认为完成且距离可接受时，也视作到达。
	if agent.is_navigation_finished() and dist <= ARRIVAL_DIST_STUCK:
		_on_reached()
		return

	# 跟随 navmesh 路径，不再直线硬走。
	var nav_next := agent.get_next_path_position()
	var to_next := nav_next - global_position
	if to_next.length() > 2.0:
		agent.set_velocity(to_next.normalized() * move_speed)
	else:
		agent.set_velocity(Vector2.ZERO)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if _arrived:
		return
	if safe_velocity.length() < 0.1:
		velocity = Vector2.ZERO
	else:
		velocity = safe_velocity
	move_and_slide()
	_update_anim_by_velocity(velocity)

func _on_reached() -> void:
	if current_state == State.ENTERING:
		if _arrived:
			return
		_arrived = true
		_target_set = false
		_path_initialized = false
		velocity = Vector2.ZERO
		_stuck_timer = 0.0

		if _seat_target != null:
			# Snap to seat anchor so larger arrival radius does not leave visual offset.
			global_position = _seat_target.global_position
			anim.play(_resolve_seat_sit_anim(_seat_target))
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
		_target_set = false
		_path_initialized = false
		velocity = Vector2.ZERO
		current_state = State.LEFT
		print("[Customer] Left the restaurant.")
		customer_left.emit(self)
		queue_free()

func _post_taskboard_request() -> void:
	var task_board = get_node_or_null("/root/TaskBoard")
	if not task_board:
		print("[Customer] TaskBoard not found.")
		return
	if not task_board.has_method("create_fulfill_order"):
		print("[Customer] TaskBoard missing create_fulfill_order().")
		return

	var task = task_board.create_fulfill_order(self)
	if task.is_empty():
		print("[Customer] Failed to create FULFILL_ORDER task.")
		return
	print("[Customer] Task created: ", task.get("id", "unknown"), " | state=", task.get("state", "unknown"))
	_activate_drink_order_if_needed(true)
	_refresh_order_bubble()

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
	var food_task := _get_open_task_by_kind("food")
	if not food_task.is_empty():
		var deadline_ms := int(food_task.get("deadline_ms", 0))
		if deadline_ms > 0:
			return deadline_ms
		return -1
	if _task_deadline_ms <= 0:
		return -1
	return _task_deadline_ms

func get_drink_task_deadline_ms() -> int:
	var drink_task := _get_open_task_by_kind("drink")
	if drink_task.is_empty():
		return -1
	var deadline_ms := int(drink_task.get("deadline_ms", 0))
	if deadline_ms > 0:
		return deadline_ms
	return -1

func get_drink_item_name() -> String:
	return _drink_item

func has_pending_drink_order() -> bool:
	return not _get_open_task_by_kind("drink").is_empty()

func on_player_interact(player: Node) -> void:
	if player == null:
		return
	if not (player is Node2D):
		return
	if global_position.distance_to(player.global_position) > interact_radius:
		return

	var task_board = get_node_or_null("/root/TaskBoard")
	if task_board == null or not task_board.has_method("get_in_progress_tasks_for_customer"):
		return

	if current_state != State.WAITING_FOR_FOOD:
		return

	var tasks: Array[Dictionary] = task_board.get_in_progress_tasks_for_customer(get_instance_id(), "player")
	var open_tasks: Array[Dictionary] = task_board.get_open_tasks_for_customer(get_instance_id())
	if tasks.is_empty() and open_tasks.is_empty() and _drink_required and not _drink_order_activated:
		_activate_drink_order_if_needed(true)
		tasks = task_board.get_in_progress_tasks_for_customer(get_instance_id(), "player")
		open_tasks = task_board.get_open_tasks_for_customer(get_instance_id())
	if tasks.is_empty() and open_tasks.is_empty():
		_notify_player("No player order for this customer.")
		return

	var p_inv = player.get_node_or_null("Inventory")
	var prioritized_delivery: Dictionary = {}
	var prioritized_take_order: Dictionary = {}
	for task in tasks:
		var task_id := str(task.get("id", ""))
		var step_name := str(task_board.get_current_step_name(task_id))
		var payload: Dictionary = task.get("payload", {})
		var order_kind := str(payload.get("order_kind", "food"))
		if step_name == "DELIVER_AND_SERVE" and p_inv != null:
			var wanted_item := _task_payload_item_name(payload)
			if p_inv.find_item(wanted_item) != -1:
				if prioritized_delivery.is_empty() or order_kind == "food":
					prioritized_delivery = task
		elif step_name == "TAKE_ORDER":
			if prioritized_take_order.is_empty() or order_kind == "drink":
				prioritized_take_order = task
	if prioritized_take_order.is_empty():
		for task in open_tasks:
			var task_id := str(task.get("id", ""))
			var step_name := str(task_board.get_current_step_name(task_id))
			var payload: Dictionary = task.get("payload", {})
			var order_kind := str(payload.get("order_kind", "food"))
			var assignee := str(task.get("assigned_to", ""))
			if order_kind != "drink":
				continue
			if step_name != "TAKE_ORDER":
				continue
			if assignee != "" and assignee != "player":
				continue
			prioritized_take_order = task
			break

	if not prioritized_delivery.is_empty():
		_deliver_player_task_item(player as Node2D, p_inv, prioritized_delivery)
		return

	if not prioritized_take_order.is_empty():
		_take_player_order(player as Node2D, prioritized_take_order)
		return

	_notify_player("Nothing to do here yet.")

func _notify_player(text: String) -> void:
	var huds := get_tree().get_nodes_in_group("hud")
	if huds.is_empty():
		return
	var hud := huds[0]
	if hud and hud.has_method("show_quick_notice"):
		hud.call("show_quick_notice", text)

func on_food_order_taken() -> void:
	_activate_drink_order_if_needed(false)
	_refresh_order_bubble()

func _activate_drink_order_if_needed(notify_player: bool) -> void:
	if not _drink_required or _drink_order_activated:
		return
	var task_board = get_node_or_null("/root/TaskBoard")
	if task_board == null or not task_board.has_method("create_drink_order"):
		return
	var drink_task: Dictionary = task_board.create_drink_order(self, _drink_item, "")
	if not drink_task.is_empty():
		_drink_order_activated = true
		_drink_timeout_handled = false
		var players := get_tree().get_nodes_in_group("player")
		var bubble_mgr = get_node_or_null("/root/BubbleManager")
		if notify_player and bubble_mgr and bubble_mgr.has_method("say_to") and not players.is_empty() and players[0] is Node2D:
			bubble_mgr.say_to(self, players[0] as Node2D, _drink_request_text, 2.8, Color(0.92, 0.98, 1.0, 1.0))
		_refresh_order_bubble()

func _deliver_player_task_item(player: Node2D, player_inventory: Node, task: Dictionary) -> void:
	if player == null or player_inventory == null:
		return
	var task_board = get_node_or_null("/root/TaskBoard")
	if task_board == null:
		return
	var task_id := str(task.get("id", ""))
	var payload: Dictionary = task.get("payload", {})
	var item_name := _task_payload_item_name(payload)
	var idx: int = player_inventory.find_item(item_name)
	if idx == -1:
		_notify_player("You don't have the requested item.")
		return
	var item = player_inventory.items.pop_at(idx)
	player_inventory.emit_signal("inventory_changed", player_inventory.items)
	var order_kind := str(payload.get("order_kind", "food"))
	if order_kind == "drink":
		_request_player_line(
			player,
			self,
			"player_deliver_drink",
			"Here is your " + item_name + ".",
			{
				"item_name": item_name,
				"context_note": "The player is handing the requested drink to the customer."
			}
		)
		receive_drink(item_name)
	else:
		_request_player_line(
			player,
			self,
			"player_deliver_food",
			"Here is your " + item_name + ".",
			{
				"item_name": item_name,
				"context_note": "The player is handing the requested dish to the customer."
			}
		)
		receive_item(item)
	task_board.complete_current_step(task_id, "DELIVER_AND_SERVE")
	_refresh_order_bubble()

func _take_player_order(_player: Node2D, task: Dictionary) -> void:
	var task_board = get_node_or_null("/root/TaskBoard")
	if task_board == null:
		return
	var task_id := str(task.get("id", ""))
	if str(task.get("state", "")) == "unassigned" and task_board.has_method("claim_task"):
		var claimed: Dictionary = task_board.claim_task(task_id, "player")
		if claimed.is_empty():
			_notify_player("This order was already taken.")
			return
		task = claimed
	var payload: Dictionary = task.get("payload", {})
	var order_kind := str(payload.get("order_kind", "food"))
	if order_kind == "drink":
		_notify_player("Drink order taken: " + _task_payload_item_name(payload).capitalize())
	else:
		_notify_player("Order taken.")
	task_board.complete_current_step(task_id, "TAKE_ORDER")
	_refresh_order_bubble()

func _get_open_task_by_kind(order_kind: String) -> Dictionary:
	var task_board = get_node_or_null("/root/TaskBoard")
	if task_board == null or not task_board.has_method("get_open_tasks_for_customer"):
		return {}
	var tasks: Array[Dictionary] = task_board.get_open_tasks_for_customer(get_instance_id())
	for task in tasks:
		var payload: Dictionary = task.get("payload", {})
		if str(payload.get("order_kind", "food")) == order_kind:
			return task
	return {}

func _task_payload_item_name(payload: Dictionary) -> String:
	var order_kind := str(payload.get("order_kind", "food"))
	if order_kind == "drink":
		return str(payload.get("drink_item", payload.get("display_item", "drink"))).strip_edges().to_lower()
	return str(payload.get("food_item", payload.get("display_item", "food"))).strip_edges().to_lower()

func _refresh_order_bubble() -> void:
	if _order_bubble_panel == null or _order_bubble_label == null:
		return
	if current_state != State.WAITING_FOR_FOOD:
		_order_bubble_panel.visible = false
		return

	var food_task := _get_open_task_by_kind("food")
	var drink_task := _get_open_task_by_kind("drink")
	var label_text := ""
	var label_color := Color(0.22, 0.26, 0.32, 1.0)
	var task_board = get_node_or_null("/root/TaskBoard")
	var border_color := Color(0.18, 0.22, 0.28, 0.95)

	if not drink_task.is_empty():
		var drink_step := ""
		if task_board and task_board.has_method("get_current_step_name"):
			drink_step = str(task_board.get_current_step_name(str(drink_task.get("id", ""))))
		if drink_step == "TAKE_ORDER":
			label_text = _order_icon_for("drink", _drink_item)
			label_color = Color(0.18, 0.44, 0.72, 1.0)
			border_color = label_color

	if label_text == "" and not food_task.is_empty():
		var food_step := ""
		if task_board and task_board.has_method("get_current_step_name"):
			food_step = str(task_board.get_current_step_name(str(food_task.get("id", ""))))
		if food_step == "TAKE_ORDER":
			label_text = _order_icon_for("food", _extract_food_from_request(request_text))
			label_color = Color(0.72, 0.28, 0.16, 1.0)
			border_color = label_color

	if label_text == "":
		_order_bubble_panel.visible = false
		return

	_order_bubble_label.text = label_text
	_order_bubble_label.add_theme_color_override("font_color", label_color)
	var panel_style := _order_bubble_panel.get_theme_stylebox("panel")
	if panel_style is StyleBoxFlat:
		var bubble_style := panel_style.duplicate() as StyleBoxFlat
		bubble_style.border_color = border_color
		_order_bubble_panel.add_theme_stylebox_override("panel", bubble_style)
	_order_bubble_panel.visible = true

func _order_icon_for(order_kind: String, item_name: String) -> String:
	var item := item_name.strip_edges().to_lower()
	if order_kind == "drink":
		match item:
			"cola":
				return "🥤"
			"tea":
				return "🍵"
			"coffee":
				return "☕"
		return "🥤"
	match item:
		"pizza":
			return "🍕"
		"hotdog":
			return "🌭"
		"sandwich":
			return "🥪"
	return "🍽"

func _tick_order_timeouts() -> void:
	if current_state != State.WAITING_FOR_FOOD:
		return
	if _patience_timed_out:
		return
	var task_board = get_node_or_null("/root/TaskBoard")
	var now_ms := Time.get_ticks_msec()
	var food_deadline_ms := get_task_deadline_ms()
	if food_deadline_ms > 0 and now_ms >= food_deadline_ms:
		_patience_timed_out = true
		print("[Customer] Patience timeout reached. Leaving now.")
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
		return

	if _drink_timeout_handled:
		return
	var drink_task := _get_open_task_by_kind("drink")
	if drink_task.is_empty():
		return
	var drink_deadline_ms := int(drink_task.get("deadline_ms", 0))
	if drink_deadline_ms <= 0 or now_ms < drink_deadline_ms:
		return
	_drink_timeout_handled = true
	if task_board and task_board.has_method("fail_task"):
		task_board.fail_task(str(drink_task.get("id", "")), "customer_drink_timeout")
	_drink_required = false
	_notify_player("Drink order expired for " + current_seat + ".")
	_refresh_order_bubble()
	_try_begin_eating_if_ready()

func _extract_food_from_request(request: String) -> String:
	var request_lower = request.to_lower()
	var foods = ["pizza", "hotdog", "sandwich"]
	for food in foods:
		if food in request_lower:
			return food
	return "unknown"

func _resolve_seat_sit_anim(seat: Node2D) -> String:
	# Preferred: explicit seat metadata.
	# In Godot Inspector -> Node -> Metadata, set key "sit_anim" to:
	# sit_left / sit_right (and optionally sit_up / sit_down if those animations exist).
	if seat != null and seat.has_meta("sit_anim"):
		var sit_anim := str(seat.get_meta("sit_anim")).strip_edges()
		if sit_anim != "":
			return sit_anim

	# Fallback: keep legacy behavior if metadata is missing.
	if seat != null and global_position.x <= seat.global_position.x:
		return "sit_right"
	return "sit_left"

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
	_pending_player_line_request_id = "customer_player_%s_%d" % [str(get_instance_id()), Time.get_ticks_msec()]
	var request := {
		"id": _pending_player_line_request_id,
		"source_role": "player",
		"recipient_role": "customer",
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
