extends Node2D

# --- 节点引用 ---
@onready var spr: AnimatedSprite2D     = $AnimatedSprite2D
@onready var col: CollisionShape2D     = $StaticBody2D/CollisionShape2D
@onready var nav: NavigationRegion2D   = $NavigationRegion2D
@onready var trig: Area2D              = $Area2D

# --- 动画名（和你的资源一致）---
const ANIM_OPEN_TRANS  : String = "door_open"
const ANIM_CLOSE_TRANS : String = "door_close"
const ANIM_IDLE_OPEN   : String = "idle_open"
const ANIM_IDLE_CLOSE  : String = "idle_close"

var is_open: bool = false
var player_in_range: bool = false

func _ready() -> void:
	# 触发区
	if is_instance_valid(trig):
		trig.body_entered.connect(_on_body_entered)
		trig.body_exited.connect(_on_body_exited)
	# 初始化：只设状态 + idle，不播过渡
	_apply_state_and_idle(false)
	print("[Door] ready; has anims:",
		_has_anim(ANIM_OPEN_TRANS), _has_anim(ANIM_CLOSE_TRANS),
		_has_anim(ANIM_IDLE_OPEN), _has_anim(ANIM_IDLE_CLOSE))

func _on_body_entered(n: Node) -> void:
	if n.is_in_group("player"):
		player_in_range = true
		print("[Door] player entered")

func _on_body_exited(n: Node) -> void:
	if n.is_in_group("player"):
		player_in_range = false
		print("[Door] player exited")

# 建议用 _unhandled_input，避免 UI 抢事件
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and player_in_range:
		toggle()

func toggle() -> void:
	var was_open := is_open
	is_open = not is_open
	print("[Door] toggle; was_open=", was_open, " -> is_open=", is_open)
	# 切物理/导航 + 播放过渡动画
	_apply_state_and_play_transition()

func _apply_state_and_idle(play_idle: bool) -> void:
	# 物理/导航
	if is_instance_valid(col):
		col.disabled = is_open          # 开门=不挡路
	if is_instance_valid(nav):
		nav.enabled = is_open           # 开门=可走

	# idle 外观
	if is_instance_valid(spr):
		if play_idle:
			if is_open:
				if _has_anim(ANIM_IDLE_OPEN):
					spr.play(ANIM_IDLE_OPEN)
			else:
				if _has_anim(ANIM_IDLE_CLOSE):
					spr.play(ANIM_IDLE_CLOSE)

func _apply_state_and_play_transition() -> void:
	# 先切物理/导航
	_apply_state_and_idle(false)

	# 再播过渡动画，播完落到对应 idle
	if not is_instance_valid(spr):
		return

	if is_open:
		if _has_anim(ANIM_OPEN_TRANS):
			print("[Door] play:", ANIM_OPEN_TRANS)
			spr.play(ANIM_OPEN_TRANS)
			await spr.animation_finished
		if _has_anim(ANIM_IDLE_OPEN):
			spr.play(ANIM_IDLE_OPEN)
	else:
		if _has_anim(ANIM_CLOSE_TRANS):
			print("[Door] play:", ANIM_CLOSE_TRANS)
			spr.play(ANIM_CLOSE_TRANS)
			await spr.animation_finished
		if _has_anim(ANIM_IDLE_CLOSE):
			spr.play(ANIM_IDLE_CLOSE)

func _has_anim(name: String) -> bool:
	if not is_instance_valid(spr):
		return false
	if spr.sprite_frames == null:
		return false
	return spr.sprite_frames.has_animation(name)
