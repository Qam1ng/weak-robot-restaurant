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

		# ① 先尝试帮最近且“需要帮助”的机器人（完全不影响你原来的门/物品交互）
		var bot: Node2D = _find_nearby_robot_needing_help()
		if bot != null:
			# 只在机器人实现了接口方法时才调用，避免报错
			if bot.has_method("receive_player_help"):
				# 如果机器人有背包，直接尝试交换物品
				bot.receive_player_help()
				return

		# ② 如果附近没有需要帮助的机器人，保持原有逻辑：广播给 interaction 组（门、物品等）
		get_tree().call_group("interaction", "on_player_interact", self)

# —— 私有：查找半径内最近且“需要帮助”的机器人 ——
# 约定：机器人节点属于 "robot" 组；并实现无参方法：
#   func needs_help() -> bool
#   func receive_player_help() -> void
func _find_nearby_robot_needing_help() -> Node2D:
	var best: Node2D = null
	var best_d: float = 1e30

	# 官方推荐：通过分组获取节点列表
	var robots: Array = get_tree().get_nodes_in_group("robot")
	for n in robots:
		# 只对实现了 needs_help() 的对象做判断，防御式检查
		if not n.has_method("needs_help"):
			continue
		var needs: bool = n.needs_help()
		if not needs:
			continue

		# 计算距离并择最近
		#（has_method/分组写法符合 Godot 文档建议）
		var d: float = global_position.distance_to(n.global_position)
		if d < interact_radius:
			if d < best_d:
				best_d = d
				best = n as Node2D

	return best
