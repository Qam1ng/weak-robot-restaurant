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
var _beacon_active: bool = false
@export var auto_close_delay_sec: float = 5.0
var _auto_close_deadline_ms: int = 0
var _bodies_in_trigger: Dictionary = {}

func _ready() -> void:
	add_to_group("door")

	# 触发区
	if is_instance_valid(trig):
		trig.body_entered.connect(_on_body_entered)
		trig.body_exited.connect(_on_body_exited)
	# 初始化：确保初始状态为“关闭”，并强制播放“idle_close”动画
	is_open = false
	_apply_state_and_idle(true) # 这里改为true，强制应用一次idle动画
	
	# Fix: Remove any wall tile behind the door that might block physics/navigation
	_clear_wall_behind_door()
	
	print("[Door] ready; has anims:",
		_has_anim(ANIM_OPEN_TRANS), _has_anim(ANIM_CLOSE_TRANS),
		_has_anim(ANIM_IDLE_OPEN), _has_anim(ANIM_IDLE_CLOSE))

	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr and not help_mgr.beacon_changed.is_connected(_on_beacon_changed):
		help_mgr.beacon_changed.connect(_on_beacon_changed)

func _process(_dt: float) -> void:
	if not is_instance_valid(spr):
		return
	if _beacon_active:
		var pulse = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 220.0)
		spr.modulate = Color(1.0, pulse, pulse, 1.0)
	else:
		spr.modulate = Color(1, 1, 1, 1)

	_tick_auto_close()

func _clear_wall_behind_door():
	# Attempt to find LayerWalls and clear the tile at this door's position
	# The door is usually child of LayerDoors, which is child of TileMap
	var layer_walls = get_node_or_null("../../LayerWalls")
	if layer_walls and layer_walls is TileMapLayer:
		var map_pos = layer_walls.local_to_map(layer_walls.to_local(global_position))
		# Check if there is a tile
		if layer_walls.get_cell_source_id(map_pos) != -1:
			print("[Door] Found wall tile at ", map_pos, ". Removing to prevent blocking.")
			layer_walls.set_cell(map_pos, -1) # Clear the cell
	else:
		# Try absolute path if relative fails
		var root = get_tree().current_scene
		layer_walls = root.find_child("LayerWalls", true, false)
		if layer_walls and layer_walls is TileMapLayer:
			var map_pos = layer_walls.local_to_map(layer_walls.to_local(global_position))
			if layer_walls.get_cell_source_id(map_pos) != -1:
				print("[Door] Found wall tile at ", map_pos, " (absolute search). Removing.")
				layer_walls.set_cell(map_pos, -1)

func _on_body_entered(n: Node) -> void:
	_bodies_in_trigger[n.get_instance_id()] = true
	if n.is_in_group("player"):
		player_in_range = true
		print("[Door] player entered")

func _on_body_exited(n: Node) -> void:
	_bodies_in_trigger.erase(n.get_instance_id())
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
	if is_open:
		_auto_close_deadline_ms = Time.get_ticks_msec() + int(maxf(0.8, auto_close_delay_sec) * 1000.0)
	else:
		_auto_close_deadline_ms = 0
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

func _has_anim(anim_name: String) -> bool:
	if not is_instance_valid(spr):
		return false
	if spr.sprite_frames == null:
		return false
	return spr.sprite_frames.has_animation(anim_name)

func _on_beacon_changed(active: bool, _position: Vector2, _request_id: String) -> void:
	_beacon_active = active

func _tick_auto_close() -> void:
	if not is_open:
		return
	if _auto_close_deadline_ms <= 0:
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms < _auto_close_deadline_ms:
		return
	if not _bodies_in_trigger.is_empty():
		_auto_close_deadline_ms = now_ms + 800
		return
	toggle()
