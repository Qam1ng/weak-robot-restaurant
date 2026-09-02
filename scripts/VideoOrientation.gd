extends Node2D

const MANIFEST_PATH := "res://data/video/orientation_manifest.json"
const TTS_AUDIO_ROOT := "res://assets/audio/orientation"
const UI_PANEL_COLOR := Color(0.04, 0.06, 0.09, 0.92)
const UI_TEXT_COLOR := Color(0.89, 0.94, 0.98, 1.0)
const UI_ACCENT_COLOR := Color(0.76, 0.95, 1.0, 1.0)
const UI_GOLD_COLOR := Color(0.74, 0.58, 0.20, 0.98)

var _caption_label: Label
var _system_panel: PanelContainer
var _dialogue_panel: PanelContainer
var _orders_panel: PanelContainer
var _message_panel: PanelContainer
var _progress_panel: PanelContainer
var _focus_frames: Dictionary = {}
var _voice_player: AudioStreamPlayer

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_prepare_restaurant()
	_build_overlay()
	await get_tree().process_frame
	await _play_manifest()
	get_tree().quit()

func _prepare_restaurant() -> void:
	var restaurant := $Restaurant
	var hud := restaurant.get_node_or_null("Hud")
	if hud:
		hud.hide()
	var spawner := restaurant.get_node_or_null("CustomerSpawner")
	if spawner:
		spawner.call("disable")
		spawner.call("clear_all_customers")
	var player := restaurant.get_node_or_null("Player")
	if player:
		player.call("set_input_locked", true)
		player.global_position = Vector2(-20.0, 160.0)
	var robot := restaurant.get_node_or_null("Robot_A") as Node2D
	if robot:
		robot.global_position = Vector2(-100.0, -42.0)

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_system_panel = _make_panel(Vector2(24.0, 136.0), Vector2(286.0, 492.0))
	root.add_child(_system_panel)
	_add_system_content(_system_panel)
	_add_focus_frame(root, "system", _system_panel.position, _system_panel.size)

	_dialogue_panel = _make_panel(Vector2(1260.0, 136.0), Vector2(316.0, 234.0))
	root.add_child(_dialogue_panel)
	_add_dialogue_content(_dialogue_panel)
	_add_focus_frame(root, "dialogue", _dialogue_panel.position, _dialogue_panel.size)

	_orders_panel = _make_panel(Vector2(1260.0, 390.0), Vector2(316.0, 278.0))
	root.add_child(_orders_panel)
	_add_orders_content(_orders_panel)
	_add_focus_frame(root, "orders", _orders_panel.position, _orders_panel.size)

	_progress_panel = _make_progress_panel()
	root.add_child(_progress_panel)
	_add_focus_frame(root, "progress", _progress_panel.position, _progress_panel.size)

	_message_panel = _make_panel(Vector2(490.0, 340.0), Vector2(620.0, 194.0), UI_GOLD_COLOR)
	root.add_child(_message_panel)
	_add_message_content(_message_panel)
	_add_focus_frame(root, "messages", _message_panel.position, _message_panel.size)

	var caption_panel := _make_panel(Vector2(250.0, 842.0), Vector2(1100.0, 112.0))
	root.add_child(caption_panel)
	_caption_label = Label.new()
	_caption_label.position = Vector2(28.0, 16.0)
	_caption_label.size = Vector2(1044.0, 80.0)
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_label.add_theme_font_size_override("font_size", 25)
	_caption_label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98, 1.0))
	caption_panel.add_child(_caption_label)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = &"Master"
	add_child(_voice_player)

func _make_panel(position_value: Vector2, size_value: Vector2, border_color: Color = UI_ACCENT_COLOR) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = position_value
	panel.size = size_value
	var style := StyleBoxFlat.new()
	style.bg_color = UI_PANEL_COLOR
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color * Color(1.0, 1.0, 1.0, 0.55)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_label(text_value: String, font_size: int = 18, color: Color = UI_TEXT_COLOR) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _add_system_content(panel: PanelContainer) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var title := _make_label("SYSTEM", 20, UI_ACCENT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var phase := _make_label("Day 1 | Lunch", 17, Color(0.94, 0.94, 0.94, 1.0))
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(phase)
	content.add_child(HSeparator.new())
	content.add_child(_make_label("PLAYER", 18, UI_ACCENT_COLOR))
	content.add_child(_make_label("Score: 6", 18, Color(0.94, 0.80, 0.34, 1.0)))
	content.add_child(_make_label("Holding (1/3):\n[1] cola", 17))
	content.add_child(_make_label("Assigned Tasks", 17, UI_ACCENT_COLOR))
	content.add_child(_make_label("Table 4 | Cola | Deliver", 16))
	content.add_child(HSeparator.new())
	content.add_child(_make_label("ROBOT", 18, UI_ACCENT_COLOR))
	content.add_child(_make_label("Battery: 62%", 18, Color(0.58, 0.92, 0.62, 1.0)))
	content.add_child(_make_label("Holding (1/2):\n[1] pizza", 17))
	content.add_child(_make_label("Assigned Tasks", 17, UI_ACCENT_COLOR))
	content.add_child(_make_label("Table 8 | Pizza | Deliver", 16))

func _add_dialogue_content(panel: PanelContainer) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var title := _make_label("DIALOGUE", 20, UI_ACCENT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	content.add_child(_make_label("Customer: Can I order a pizza?", 17, Color(1.0, 0.64, 0.72, 1.0)))
	content.add_child(_make_label("Robot: I'll take your order now.", 17, Color(0.43, 0.77, 0.94, 1.0)))
	content.add_child(_make_label("Robot: Heading to the kitchen.", 17, Color(0.43, 0.77, 0.94, 1.0)))
	content.add_child(_make_label("System: Table 4 needs cola.", 17, Color(0.94, 0.80, 0.34, 1.0)))

func _add_orders_content(panel: PanelContainer) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var title := _make_label("Customer Orders", 20, UI_ACCENT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.add_child(_make_tab_label("Live", true))
	tabs.add_child(_make_tab_label("History", false))
	content.add_child(tabs)
	content.add_child(_make_label("Table 4 | Cola | 48s | Waiting", 16))
	content.add_child(_make_label("Table 8 | Pizza | 96s | Deliver", 16))
	content.add_child(_make_label("History", 16, UI_ACCENT_COLOR))
	content.add_child(_make_label("+2  Pizza served", 15, Color(0.58, 0.92, 0.62, 1.0)))
	content.add_child(_make_label("-3  Cola missed", 15, Color(1.0, 0.64, 0.64, 1.0)))

func _make_tab_label(text_value: String, active: bool) -> Label:
	var tab := _make_label(text_value, 16, UI_TEXT_COLOR)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.23, 0.28, 0.36, 1.0) if active else Color(0.11, 0.13, 0.17, 0.98)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.76, 0.95, 1.0, 0.30)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	tab.add_theme_stylebox_override("normal", style)
	tab.custom_minimum_size = Vector2(90.0, 36.0)
	tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return tab

func _make_progress_panel() -> PanelContainer:
	var panel := _make_panel(Vector2(520.0, 28.0), Vector2(560.0, 62.0), UI_GOLD_COLOR)
	var content := Control.new()
	panel.add_child(content)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 38.0
	bar.position = Vector2(20.0, 30.0)
	bar.size = Vector2(520.0, 8.0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.13, 0.16, 0.21, 0.95)
	track.corner_radius_top_left = 4
	track.corner_radius_top_right = 4
	track.corner_radius_bottom_left = 4
	track.corner_radius_bottom_right = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI_GOLD_COLOR
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	content.add_child(bar)
	for anchor in [
		{"label": "Trial", "progress": 0.0}, {"label": "Morning", "progress": 0.10},
		{"label": "Lunch", "progress": 0.30}, {"label": "Afternoon", "progress": 0.50},
		{"label": "Dinner", "progress": 0.65}, {"label": "Night", "progress": 0.95}
	]:
		var x := 20.0 + float(anchor["progress"]) * 520.0
		var label := _make_label(str(anchor["label"]), 10, Color(0.76, 0.95, 1.0, 0.88))
		label.position = Vector2(x, 7.0)
		label.size = Vector2(62.0, 16.0)
		content.add_child(label)
		var tick := ColorRect.new()
		tick.color = Color(0.76, 0.95, 1.0, 0.50)
		tick.position = Vector2(x, 27.0)
		tick.size = Vector2(1.0, 14.0)
		content.add_child(tick)
	return panel

func _add_message_content(panel: PanelContainer) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	var title := _make_label("Robot Request", 28, Color(1.0, 0.84, 0.36, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var body := _make_label("Please take over the pizza order.", 22)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	buttons.add_child(_make_demo_button("Accept"))
	buttons.add_child(_make_demo_button("Decline"))
	content.add_child(buttons)

func _make_demo_button(text_value: String) -> Label:
	var button := _make_label(text_value, 18)
	button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(150.0, 42.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.21, 0.27, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.92, 0.96, 1.0, 0.22)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_top = 9
	button.add_theme_stylebox_override("normal", style)
	return button

func _add_focus_frame(root: Control, focus_id: String, position_value: Vector2, size_value: Vector2) -> void:
	var frame := Panel.new()
	frame.position = position_value - Vector2(5.0, 5.0)
	frame.size = size_value + Vector2(10.0, 10.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(1.0, 0.90, 0.50, 0.98)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	frame.add_theme_stylebox_override("panel", style)
	frame.visible = false
	root.add_child(frame)
	_focus_frames[focus_id] = frame

func _play_manifest() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("[VideoOrientation] Missing manifest: %s" % MANIFEST_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("[VideoOrientation] Invalid manifest JSON")
		return
	var cues: Array = parsed.get("cues", [])
	for index in range(cues.size()):
		var cue: Dictionary = cues[index]
		_apply_cue(cue)
		await get_tree().create_timer(float(cue.get("duration_sec", 8.5))).timeout

func _apply_cue(cue: Dictionary) -> void:
	_caption_label.text = str(cue.get("text", ""))
	var focus := str(cue.get("focus", "overview"))
	for focus_id in _focus_frames:
		var frame: Panel = _focus_frames[focus_id]
		frame.visible = focus_id == focus
	_system_panel.modulate.a = 1.0 if focus in ["overview", "system"] else 0.42
	_dialogue_panel.modulate.a = 1.0 if focus in ["overview", "dialogue"] else 0.42
	_orders_panel.modulate.a = 1.0 if focus in ["overview", "orders"] else 0.42
	_progress_panel.modulate.a = 1.0 if focus in ["overview", "progress"] else 0.42
	_message_panel.visible = focus == "messages"
	_play_cue_voice(str(cue.get("id", "")))

func _play_cue_voice(cue_id: String) -> void:
	if cue_id == "" or _voice_player == null:
		return
	var path := "%s/%s.mp3" % [TTS_AUDIO_ROOT, cue_id]
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_voice_player.stop()
	_voice_player.stream = stream
	_voice_player.play()
