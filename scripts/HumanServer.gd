extends CharacterBody2D

@export var speed: float = 180.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
# 如果暂时没用到导航，agent 可以先不取；或者节点不存在会报错
# @onready var agent: NavigationAgent2D = $NavigationAgent2D

var last_dir: Vector2 = Vector2.DOWN

func _ready() -> void:
	add_to_group("player")   # 关键：让门的 Area2D 能识别你
	print("[HumanServer] ready OK; node=", name)

func _physics_process(_dt: float) -> void:
	var vx := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vy := Input.get_action_strength("move_down")  - Input.get_action_strength("move_up")
	var v := Vector2(vx, vy)

	if v.length() > 0.0:
		velocity = v.normalized() * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	_update_animation(v)

func _update_animation(input_dir: Vector2) -> void:
	var moving := input_dir.length() > 0.0
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

# 如果你有全局对话/交互系统可以保留这个；仅控制门则不需要
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		print("[HumanServer] interact pressed (E/Space)")
		# 可选：通知全局系统
		get_tree().call_group("interaction", "on_player_interact", self)
