extends Node

const DEFAULT_DURATION := 2.4
const DEFAULT_COLOR := Color(1, 1, 1, 1)
const LABEL_MAX_WIDTH := 360.0

var _layer: CanvasLayer
var _entries: Array[Dictionary] = []

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)

func _process(_dt: float) -> void:
	if _entries.is_empty():
		return
	var now := Time.get_ticks_msec()
	for i in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[i]
		var label: Label = entry.get("label", null)
		var target = entry.get("target", null)
		var expiry := int(entry.get("expiry_ms", 0))
		if now >= expiry or label == null or not is_instance_valid(label):
			if label and is_instance_valid(label):
				label.queue_free()
			_entries.remove_at(i)
			continue
		if target == null or not is_instance_valid(target):
			label.queue_free()
			_entries.remove_at(i)
			continue
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			continue
		var world_pos: Vector2 = target.global_position + Vector2(0, -56)
		var screen_pos := cam.get_screen_center_position() + (world_pos - cam.global_position)
		label.position = screen_pos

func say(target: Node2D, text: String, duration_sec: float = DEFAULT_DURATION, color: Color = DEFAULT_COLOR) -> void:
	if target == null or not is_instance_valid(target):
		return
	var content := text.strip_edges()
	if content == "":
		return

	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(LABEL_MAX_WIDTH, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_layer.add_child(label)

	var expiry := Time.get_ticks_msec() + int(maxf(0.6, duration_sec) * 1000.0)
	_entries.append({
		"target": target,
		"label": label,
		"expiry_ms": expiry
	})
