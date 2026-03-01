# HumanServer.gd (Godot 4.x)
extends CharacterBody2D

@export var speed: float = 180.0
@export var interact_radius: float = 48.0   # 与机器人交互半径（像素）

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

const InventoryScript = preload("res://scripts/Inventory.gd")
var inventory: Inventory

var last_dir: Vector2 = Vector2.DOWN

func _ready() -> void:
	add_to_group("player")  # 让门/物品的 Area2D 能识别你
	
	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	inventory.capacity = 5 # Player has bigger bag
	add_child(inventory)
	
	print("[HumanServer] ready OK; node=", name)

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
		if _try_progress_player_task_by_interact():
			return
		# E key is reserved for world interactions (door/items) only.
		get_tree().call_group("interaction", "on_player_interact", self)

func _try_progress_player_task_by_interact() -> bool:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee"):
		return false
	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee("player")
	if tasks.is_empty():
		return false

	# Kitchen pickup: press E in kitchen to collect requested food for current pickup step.
	if global_position.y >= -150.0:
		return false
	for task in tasks:
		var task_id := str(task.get("id", ""))
		var step_name := str(board.get_current_step_name(task_id))
		if step_name != "PICKUP_FROM_KITCHEN":
			continue
		var payload: Dictionary = task.get("payload", {})
		var item_name := str(payload.get("food_item", "")).strip_edges()
		if item_name == "" or item_name == "unknown":
			item_name = "pizza"
		if inventory.find_item(item_name) != -1:
			continue
		if inventory.add_item(item_name, null, Rect2i()):
			board.complete_current_step(task_id, "PICKUP_FROM_KITCHEN")
			print("[HumanServer] Picked assigned order item in kitchen: ", item_name, " task=", task_id)
			return true
		return false
	return false
