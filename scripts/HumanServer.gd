# HumanServer.gd (Godot 4.x)
extends CharacterBody2D

@export var speed: float = 180.0
@export var interact_radius: float = 48.0   # 与机器人交互半径（像素）
@export var player_max_active_tasks: int = 3  # Soft threshold only; does not hard-block delegation

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

const InventoryScript = preload("res://scripts/Inventory.gd")
var inventory: Inventory

var last_dir: Vector2 = Vector2.DOWN
const KITCHEN_PICK_OPTIONS: Array[String] = ["pizza", "hotdog", "sandwich"]

func _ready() -> void:
	add_to_group("player")  # 让门/物品的 Area2D 能识别你

	var cam := get_node_or_null("Camera2D")
	if cam and cam is Camera2D:
		var camera := cam as Camera2D
		camera.process_mode = Node.PROCESS_MODE_ALWAYS
		camera.make_current()
		camera.force_update_scroll()
		call_deferred("_ensure_camera_current")
	
	var existing_inv := get_node_or_null("Inventory")
	if existing_inv and existing_inv is Inventory:
		inventory = existing_inv as Inventory
	else:
		inventory = InventoryScript.new()
		inventory.name = "Inventory"
		add_child(inventory)
	inventory.capacity = 3

	_connect_hud_signals()
	
	print("[HumanServer] ready OK; node=", name)

func _ensure_camera_current() -> void:
	var cam := get_node_or_null("Camera2D")
	if cam and cam is Camera2D:
		var camera := cam as Camera2D
		camera.make_current()
		camera.force_update_scroll()

func _physics_process(_dt: float) -> void:
	var vx: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vy: float = Input.get_action_strength("move_down")  - Input.get_action_strength("move_up")
	var v: Vector2 = Vector2(vx, vy)

	if v.length() > 0.0:
		velocity = v.normalized() * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	_update_animation(v)
	_auto_close_kitchen_pick_popup_if_left_zone()

func _update_animation(input_dir: Vector2) -> void:
	var moving: bool = input_dir.length() > 0.0
	if moving:
		last_dir = input_dir

	var dir_name := ""
	if abs(last_dir.x) > abs(last_dir.y):
		if last_dir.x > 0.0:
			dir_name = "right"
		else:
			dir_name = "left"
	else:
		if last_dir.y > 0.0:
			dir_name = "down"
		else:
			dir_name = "up"

	var anim_name := ""
	if moving:
		anim_name = "walk_" + dir_name
	else:
		anim_name = "idle_" + dir_name

	if anim.animation != anim_name:
		anim.play(anim_name)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		print("[HumanServer] interact pressed (E/Space)")
		if _handle_kitchen_pick_interact():
			return
		if _try_progress_player_delivery_interact():
			return
		# E key is reserved for world interactions (door/items) only.
		get_tree().call_group("interaction", "on_player_interact", self)

func _handle_kitchen_pick_interact() -> bool:
	# Kitchen zone only.
	if global_position.y >= -150.0:
		return false
	var hud := _get_hud()
	if hud == null:
		return false
	if hud.has_method("is_help_request_popup_visible") and bool(hud.call("is_help_request_popup_visible")):
		return false
	if hud.has_method("is_kitchen_pick_popup_visible") and bool(hud.call("is_kitchen_pick_popup_visible")):
		hud.call("hide_kitchen_pick_popup")
		return true
	hud.call("show_kitchen_pick_popup", KITCHEN_PICK_OPTIONS)
	return true

func _auto_close_kitchen_pick_popup_if_left_zone() -> void:
	if global_position.y < -150.0:
		return
	var hud := _get_hud()
	if hud == null:
		return
	if hud.has_method("is_kitchen_pick_popup_visible") and bool(hud.call("is_kitchen_pick_popup_visible")):
		hud.call("hide_kitchen_pick_popup")

func _try_progress_player_delivery_interact() -> bool:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee"):
		return false
	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee("player")
	if tasks.is_empty():
		return false

	return false

func _connect_hud_signals() -> void:
	await get_tree().process_frame
	var hud := _get_hud()
	if hud == null:
		return
	if hud.has_signal("kitchen_pick_selected") and not hud.kitchen_pick_selected.is_connected(_on_kitchen_pick_selected):
		hud.kitchen_pick_selected.connect(_on_kitchen_pick_selected)

func _get_hud() -> Node:
	var huds := get_tree().get_nodes_in_group("hud")
	if huds.is_empty():
		return null
	return huds[0]

func _on_kitchen_pick_selected(item_name: String) -> void:
	var wanted := item_name.strip_edges().to_lower()
	if wanted == "":
		return
	if not inventory.add_item(wanted, null, Rect2i()):
		_notify_player("Bag full. Cannot pick more.")
		return
	_complete_one_matching_pickup_step(wanted)
	_notify_player("Picked: " + wanted.capitalize())

func _complete_one_matching_pickup_step(item_name: String) -> void:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee"):
		return
	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee("player")
	for task in tasks:
		var task_id := str(task.get("id", ""))
		var step_name := str(board.get_current_step_name(task_id))
		if step_name != "PICKUP_FROM_KITCHEN":
			continue
		var payload: Dictionary = task.get("payload", {})
		var food := str(payload.get("food_item", "")).strip_edges().to_lower()
		if food == "":
			food = "pizza"
		if food != item_name:
			continue
		board.complete_current_step(task_id, "PICKUP_FROM_KITCHEN")
		print("[HumanServer] Picked assigned order item in kitchen: ", item_name, " task=", task_id)
		return

func _notify_player(text: String) -> void:
	var hud := _get_hud()
	if hud and hud.has_method("show_quick_notice"):
		hud.call("show_quick_notice", text)
