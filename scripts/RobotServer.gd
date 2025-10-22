extends CharacterBody2D
class_name RobotServer

signal help_requested(robot: RobotServer, reason: String, task_id: String, strategy: String)
signal task_finished(task_id: String)

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var interact_area: Area2D = $InteractArea

enum State { IDLE, GO_PICK, GO_DELIVER, WAIT_HELP }
var state: int = State.IDLE

var current_task: Dictionary = {}  # { id, pickup_pos, deliver_pos, needs_human_step, reason }
var battery: float = 1.0           # 0~1
var help_strategy: String = "POLITE"
var last_dir := Vector2.DOWN       # 动画朝向记忆

func _ready() -> void:
	# 确保代理启用自动避障（如需要，可按需配置）
	agent.avoidance_enabled = true

func assign_task(task: Dictionary) -> void:
	current_task = task
	state = State.GO_PICK
	agent.target_position = task.pickup_pos

func _physics_process(_dt: float) -> void:
	if state == State.GO_PICK or state == State.GO_DELIVER:
		_move_along_path()
	elif state == State.WAIT_HELP:
		_play_idle_anim()

func _move_along_path() -> void:
	# 关键：每帧调用 get_next_path_position 更新内部状态与下一个路径点
	# 直到 is_navigation_finished() 为真。:contentReference[oaicite:3]{index=3}
	var next_pos := agent.get_next_path_position()
	var dir := next_pos - global_position

	if dir.length() > 2.0:
		velocity = dir.normalized() * 110.0
		move_and_slide()  # 4.x 内置步长处理，不要乘 delta。:contentReference[oaicite:4]{index=4}
		_update_walk_anim(dir)
	else:
		if agent.is_navigation_finished():
			_on_reached_path_end()

func _on_reached_path_end() -> void:
	if state == State.GO_PICK:
		# 拿到餐 → 前往桌位
		state = State.GO_DELIVER
		agent.target_position = current_task.deliver_pos

		# 触发“需要人类帮助”的条件（物理/电量/规则）
		var need_help := false
		if current_task.has("needs_human_step") and current_task.needs_human_step:
			need_help = true
		if battery < 0.15:
			need_help = true

		if need_help:
			state = State.WAIT_HELP
			emit_signal("help_requested", self, current_task.reason, current_task.id, help_strategy)
			_play_idle_anim()

	elif state == State.GO_DELIVER:
		state = State.IDLE
		emit_signal("task_finished", current_task.id)
		current_task = {}

func on_player_interact(_player: Node) -> void:
	# 玩家按下 interact 时，GameManager 会 call_group("interaction", "on_player_interact", player)
	if state == State.WAIT_HELP and current_task.size() > 0:
		var dlg := get_node("/root/Restaurant/DialogueManager")
		dlg.open_help_dialog(self, current_task.id, current_task.reason, help_strategy)

# ===== 动画相关 =====

func _update_walk_anim(vec: Vector2) -> void:
	if vec.length() > 0.0:
		last_dir = vec
	var dir_name := _dir_to_name(last_dir)
	var name := "walk_" + dir_name
	if anim.animation != name:
		anim.play(name)

func _play_idle_anim() -> void:
	var dir_name := _dir_to_name(last_dir)
	var name := "idle_" + dir_name
	if anim.animation != name:
		anim.play(name)

func _dir_to_name(v: Vector2) -> String:
	var dir_name := ""
	if abs(v.x) > abs(v.y):
		if v.x > 0.0:
			dir_name = "right"
		else:
			dir_name = "left"
	else:
		if v.y > 0.0:
			dir_name = "down"
		else:
			dir_name = "up"
	return dir_name
