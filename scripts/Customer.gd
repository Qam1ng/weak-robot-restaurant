extends CharacterBody2D
class_name Customer

signal request_emitted(customer: Node)

@export var request_text: String = "Can I order a pizza?"
@export var start_delay_sec: float = 10.0
@export var spawn_path: NodePath
@export var move_speed: float = 110.0

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var _arrived: bool = false
var _seat_target: Node2D = null
var _last_dir: Vector2 = Vector2.DOWN  # 记录最后一个非零运动方向

func _ready() -> void:
	add_to_group("customer")

	# 起始位置
	if spawn_path != NodePath():
		var s := get_node(spawn_path) as Node2D
		global_position = s.global_position

	# 导航+避障配置
	agent.avoidance_enabled = true
	agent.max_speed = move_speed
	agent.target_reached.connect(_on_reached)
	agent.navigation_finished.connect(_on_reached)
	agent.velocity_computed.connect(_on_velocity_computed)  # 避障给出的安全速度回调

	# 延迟入场再随机选座
	await get_tree().create_timer(start_delay_sec).timeout
	var seats := get_tree().get_nodes_in_group("seats")
	if seats.is_empty():
		push_error("No seats in 'seats' group.")
		return
	_seat_target = (seats[randi() % seats.size()]) as Node2D
	agent.target_position = _seat_target.global_position

func _physics_process(_dt: float) -> void:
	if _arrived:
		return

	# 期望速度（沿路径的下一点）
	var next_pos: Vector2 = agent.get_next_path_position()
	var to_next: Vector2 = next_pos - global_position
	var desired_vel: Vector2 = Vector2.ZERO
	if to_next.length() > 1e-3:
		desired_vel = to_next.normalized() * move_speed

	# 提交给避障系统；真正移动在 _on_velocity_computed 里做
	agent.set_velocity(desired_vel)

	# 先用期望速度更新动画方向（更跟手）
	_update_anim_by_velocity(desired_vel)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	# 用“安全速度”移动（包含避障修正）
	if _arrived:
		agent.set_velocity(Vector2.ZERO)
		return
	velocity = safe_velocity
	move_and_slide()

func _on_reached() -> void:
	if _arrived:
		return
	_arrived = true
	agent.set_velocity(Vector2.ZERO)
	velocity = Vector2.ZERO

	# 到达后坐下
	if _seat_target != null:
		if global_position.x <= _seat_target.global_position.x:
			anim.play("sit_right")
		else:
			anim.play("sit_left")
	else:
		# 没有座位目标就停在原地 idle
		_update_anim_by_velocity(Vector2.ZERO)

	print("[Customer] request:", request_text)
	emit_signal("request_emitted", self)

func _update_anim_by_velocity(v: Vector2) -> void:
	var moving := v.length() > 1.0
	if moving:
		_last_dir = v

	var dir_name := ""
	if abs(_last_dir.x) > abs(_last_dir.y):
		if _last_dir.x > 0.0:
			dir_name = "right"
		else:
			dir_name = "left"
	else:
		if _last_dir.y > 0.0:
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
