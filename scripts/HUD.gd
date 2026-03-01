extends CanvasLayer

@onready var interaction_label: Label = $InteractionLabel
@onready var help_panel: PanelContainer = $HelpRequestPanel
@onready var help_title: Label = $HelpRequestPanel/Margin/VBox/Title
@onready var help_body: RichTextLabel = $HelpRequestPanel/Margin/VBox/Body
@onready var accept_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Accept
@onready var decline_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Decline
@onready var later_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Later
@onready var mbti_panel: PanelContainer = $MBTIPanel
@onready var mbti_progress: Label = $MBTIPanel/Margin/VBox/Progress
@onready var mbti_question: Label = $MBTIPanel/Margin/VBox/Question
@onready var mbti_option_a: Button = $MBTIPanel/Margin/VBox/Options/OptionA
@onready var mbti_option_b: Button = $MBTIPanel/Margin/VBox/Options/OptionB
@onready var mbti_result: Label = $MBTIPanel/Margin/VBox/Result
@onready var mbti_confirm: Button = $MBTIPanel/Margin/VBox/Confirm

var inventory_panel: PanelContainer
var inventory_list: VBoxContainer
var battery_label: Label
var robot_items_box: VBoxContainer
var player_items_box: VBoxContainer
var customer_items_box: VBoxContainer
var dialogue_panel: PanelContainer
var dialogue_title: Label
var dialogue_log: RichTextLabel
var _left_panel_width: float = 0.0
var _active_request_id: String = ""
var _active_request_type: String = ""
var _last_utterance_by_request: Dictionary = {}
var _auto_open_in_flight: Dictionary = {}
var _mbti_questions: Array[Dictionary] = []
var _mbti_index: int = 0
var _mbti_scores := {
	"E": 0,
	"I": 0,
	"S": 0,
	"N": 0,
	"T": 0,
	"F": 0,
	"J": 0,
	"P": 0
}
const FEED_COLOR_DIALOGUE := Color(0.84, 0.95, 1.0, 1.0)
const HANDOFF_PROMPT_DISTANCE := 120.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")

	if interaction_label:
		interaction_label.hide()
	if help_panel:
		help_panel.hide()
	if mbti_panel:
		mbti_panel.hide()

	accept_btn.pressed.connect(func(): _respond("accept"))
	decline_btn.pressed.connect(func(): _respond("decline"))
	later_btn.pressed.connect(func(): _respond("later"))
	mbti_option_a.pressed.connect(func(): _choose_mbti("A"))
	mbti_option_b.pressed.connect(func(): _choose_mbti("B"))
	mbti_confirm.pressed.connect(_finish_mbti_and_start)

	_setup_inventory_ui()
	_setup_dialogue_feed_ui()
	_connect_help_signals()
	_connect_dialogue_feed_signals()
	_connect_robot_inventory()
	_connect_player_inventory()
	_setup_mbti_survey()

func _connect_help_signals() -> void:
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if not help_mgr:
		return
	if not help_mgr.request_updated.is_connected(_on_help_request_updated):
		help_mgr.request_updated.connect(_on_help_request_updated)
	if not help_mgr.request_created.is_connected(_on_help_request_created):
		help_mgr.request_created.connect(_on_help_request_created)
	if not help_mgr.request_resolved.is_connected(_on_help_request_resolved):
		help_mgr.request_resolved.connect(_on_help_request_resolved)

func _connect_robot_inventory() -> void:
	await get_tree().process_frame
	var robots = get_tree().get_nodes_in_group("robot")
	if robots.size() == 0:
		return
	var robot = robots[0]
	var inv = robot.get_node_or_null("Inventory")
	if inv:
		inv.inventory_changed.connect(_on_robot_inventory_changed)
		_on_robot_inventory_changed(inv.items)

func _connect_player_inventory() -> void:
	await get_tree().process_frame
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player = players[0]
	var inv = player.get_node_or_null("Inventory")
	if inv:
		inv.inventory_changed.connect(_on_player_inventory_changed)
		_on_player_inventory_changed(inv.items)

func _setup_inventory_ui() -> void:
	inventory_panel = PanelContainer.new()
	inventory_panel.name = "InventoryPanel"
	add_child(inventory_panel)
	inventory_panel.position = Vector2(20, 60)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	inventory_panel.add_theme_stylebox_override("panel", style)

	inventory_list = VBoxContainer.new()
	inventory_panel.add_child(inventory_list)

	var title = Label.new()
	title.text = "INVENTORY"
	title.add_theme_color_override("font_color", Color.YELLOW)
	inventory_list.add_child(title)

	var robot_title = Label.new()
	robot_title.text = "ROBOT"
	robot_title.add_theme_color_override("font_color", Color(0.76, 0.95, 1.0, 1.0))
	inventory_list.add_child(robot_title)

	battery_label = Label.new()
	battery_label.text = "Battery: --% (normal)"
	battery_label.add_theme_color_override("font_color", Color(0.78, 1.0, 0.78, 1.0))
	inventory_list.add_child(battery_label)

	robot_items_box = VBoxContainer.new()
	inventory_list.add_child(robot_items_box)

	var sep = HSeparator.new()
	inventory_list.add_child(sep)

	var player_title = Label.new()
	player_title.text = "PLAYER"
	player_title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.74, 1.0))
	inventory_list.add_child(player_title)

	player_items_box = VBoxContainer.new()
	inventory_list.add_child(player_items_box)

	var sep2 = HSeparator.new()
	inventory_list.add_child(sep2)

	var customer_title = Label.new()
	customer_title.text = "Customer Orders"
	customer_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.78, 1.0))
	inventory_list.add_child(customer_title)

	customer_items_box = VBoxContainer.new()
	inventory_list.add_child(customer_items_box)

	_left_panel_width = maxf(250.0, inventory_panel.get_combined_minimum_size().x + 26.0)
	inventory_panel.custom_minimum_size = Vector2(_left_panel_width, 0.0)

func _setup_dialogue_feed_ui() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.name = "DialogueFeedPanel"
	add_child(dialogue_panel)
	dialogue_panel.position = Vector2(20, 430)
	dialogue_panel.custom_minimum_size = Vector2(_left_panel_width, 210)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	dialogue_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	dialogue_panel.add_child(vbox)

	dialogue_title = Label.new()
	dialogue_title.text = "DIALOGUE"
	dialogue_title.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 1.0))
	vbox.add_child(dialogue_title)

	dialogue_log = RichTextLabel.new()
	dialogue_log.custom_minimum_size = Vector2(maxf(170.0, _left_panel_width - 30.0), 160)
	dialogue_log.bbcode_enabled = false
	dialogue_log.scroll_active = true
	dialogue_log.fit_content = false
	vbox.add_child(dialogue_log)

func _connect_dialogue_feed_signals() -> void:
	var bubble_mgr = get_node_or_null("/root/BubbleManager")
	if bubble_mgr and bubble_mgr.has_signal("message_emitted") and not bubble_mgr.message_emitted.is_connected(_on_bubble_message):
		bubble_mgr.message_emitted.connect(_on_bubble_message)

func _on_robot_inventory_changed(items: Array) -> void:
	if not robot_items_box:
		return

	for c in robot_items_box.get_children():
		c.queue_free()

	var holding = Label.new()
	holding.text = "Holding: " + _summarize_holding(items)
	holding.add_theme_color_override("font_color", Color(0.80, 0.94, 1.0, 1.0))
	robot_items_box.add_child(holding)

	if items.is_empty():
		var l = Label.new()
		l.text = "(Empty)"
		l.add_theme_color_override("font_color", Color.GRAY)
		robot_items_box.add_child(l)
	else:
		for i in range(items.size()):
			var item = items[i]
			var l = Label.new()
			var n = item.get("name", "Unknown")
			l.text = "[%d] %s" % [i + 1, n]
			robot_items_box.add_child(l)

func _on_player_inventory_changed(items: Array) -> void:
	if not player_items_box:
		return

	for c in player_items_box.get_children():
		c.queue_free()

	var holding = Label.new()
	holding.text = "Holding: " + _summarize_holding(items)
	holding.add_theme_color_override("font_color", Color(1.0, 0.92, 0.74, 1.0))
	player_items_box.add_child(holding)

	if items.is_empty():
		var l = Label.new()
		l.text = "(Empty)"
		l.add_theme_color_override("font_color", Color.GRAY)
		player_items_box.add_child(l)
	else:
		for i in range(items.size()):
			var item = items[i]
			var l = Label.new()
			var n = item.get("name", "Unknown")
			l.text = "[%d] %s" % [i + 1, n]
			player_items_box.add_child(l)

func _process(_dt: float) -> void:
	_update_battery_label()
	_update_customer_panel()

func _update_battery_label() -> void:
	if battery_label == null:
		return
	var robots = get_tree().get_nodes_in_group("robot")
	if robots.is_empty():
		battery_label.text = "Battery: --% (normal)"
		return
	var robot = robots[0]
	var level := int(round(float(robot.get("battery_level"))))
	var mode := str(robot.get("_battery_mode"))
	if mode == "" or mode == "Null":
		mode = "normal"
	battery_label.text = "Battery: %d%% (%s)" % [clampi(level, 0, 100), mode]

	if mode == "emergency":
		battery_label.add_theme_color_override("font_color", Color(1.0, 0.52, 0.52, 1.0))
	elif mode == "conserve":
		battery_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45, 1.0))
	else:
		battery_label.add_theme_color_override("font_color", Color(0.78, 1.0, 0.78, 1.0))

func _update_customer_panel() -> void:
	if customer_items_box == null:
		return

	for c in customer_items_box.get_children():
		c.queue_free()

	var customers := get_tree().get_nodes_in_group("customer")
	if customers.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(None)"
		empty_label.add_theme_color_override("font_color", Color.GRAY)
		customer_items_box.add_child(empty_label)
		return

	var now_ms := Time.get_ticks_msec()
	for n in customers:
		if not (n is Node):
			continue
		var cnode := n as Node
		var state := "unknown"
		if cnode.has_method("get_state_name"):
			state = str(cnode.call("get_state_name"))

		var food := "item"
		if "request_text" in cnode:
			food = _extract_food_from_request(str(cnode.get("request_text")))

		var seat := ""
		if "current_seat" in cnode:
			seat = str(cnode.get("current_seat"))
		if seat == "":
			seat = "-"

		var countdown_text := "--"
		if cnode.has_method("get_task_deadline_ms"):
			var deadline_ms := int(cnode.call("get_task_deadline_ms"))
			var remain_sec := int(ceili(float(deadline_ms - now_ms) / 1000.0))
			countdown_text = str(maxi(remain_sec, 0)) + "s"

		var line := Label.new()
		line.text = "Order: %s | Table: %s | Status: %s | Time left: %s" % [
			food.capitalize(),
			seat,
			_friendly_customer_state(state),
			countdown_text
		]
		if countdown_text == "0s" and state == "WAITING_FOR_FOOD":
			line.add_theme_color_override("font_color", Color(1.0, 0.52, 0.52, 1.0))
		customer_items_box.add_child(line)

func _extract_food_from_request(request: String) -> String:
	var text := request.to_lower()
	var foods = ["pizza", "hotdog", "skewers", "sandwich"]
	for f in foods:
		if f in text:
			return f
	return "order"

func _summarize_holding(items: Array) -> String:
	if items.is_empty():
		return "None"
	var names: Array[String] = []
	for item in items:
		names.append(str(item.get("name", "item")))
	return ", ".join(names)

func _friendly_customer_state(raw: String) -> String:
	match raw:
		"ENTERING":
			return "Walking to table"
		"WAITING_FOR_FOOD":
			return "Waiting for food"
		"EATING":
			return "Eating"
		"LEAVING":
			return "Leaving"
		"LEFT":
			return "Left"
		_:
			return "Unknown"

func on_interaction_prompt(do_show: bool, text: String) -> void:
	if not interaction_label:
		return
	if do_show:
		interaction_label.text = text
		interaction_label.show()
	else:
		interaction_label.hide()

func show_help_request(request: Dictionary) -> void:
	if request.is_empty():
		return

	_active_request_id = str(request.get("id", ""))
	_active_request_type = str(request.get("type", ""))
	help_title.text = "Robot Request (%s)" % _active_request_type
	help_body.text = _build_help_text(request)
	help_panel.show()
	_maybe_show_help_bubble(request)

func _build_help_text(request: Dictionary) -> String:
	var escalation = int(request.get("escalation_count", 0))
	var strategy = str(request.get("strategy", ""))
	var payload: Dictionary = request.get("payload", {})
	var utterance = str(request.get("utterance", ""))
	if utterance == "":
		utterance = "Can you help now?"

	var item = str(payload.get("item_needed", "item"))
	return "Strategy: %s\n%s\nNeed item: %s\nEscalation: %d" % [strategy, utterance, item, escalation]

func _respond(response: String) -> void:
	if _active_request_id == "":
		return
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if not help_mgr:
		return
	help_mgr.respond(_active_request_id, response)

func _on_help_request_updated(request: Dictionary) -> void:
	if request.is_empty():
		return
	var rid = str(request.get("id", ""))

	var status = str(request.get("status", ""))
	if status == "accepted":
		if rid == _active_request_id:
			help_panel.hide()
	elif status == "cooldown":
		if rid == _active_request_id:
			help_panel.hide()
	elif status == "pending":
		if rid != _active_request_id:
			_auto_open_help_request(request)
		else:
			help_body.text = _build_help_text(request)
			_maybe_show_help_bubble(request)

func _on_help_request_created(request: Dictionary) -> void:
	if request.is_empty():
		return
	if str(request.get("status", "")) != "pending":
		return
	_auto_open_help_request(request)

func _on_help_request_resolved(request: Dictionary) -> void:
	if request.is_empty():
		return
	var rid = str(request.get("id", ""))
	if rid != _active_request_id:
		return
	_active_request_id = ""
	_active_request_type = ""
	help_panel.hide()

func _setup_mbti_survey() -> void:
	_mbti_questions = [
		{
			"text": "At shift start, you are more likely to:",
			"A": {"label": "Talk with teammates first", "trait": "E"},
			"B": {"label": "Settle in quietly first", "trait": "I"}
		},
		{
			"text": "When helping the robot, you trust:",
			"A": {"label": "Concrete details and exact steps", "trait": "S"},
			"B": {"label": "Big-picture intent and patterns", "trait": "N"}
		},
		{
			"text": "If service pressure rises, you decide mainly by:",
			"A": {"label": "Efficiency and objective impact", "trait": "T"},
			"B": {"label": "How everyone feels and fairness", "trait": "F"}
		},
		{
			"text": "Your work style is usually:",
			"A": {"label": "Plan first, then execute", "trait": "J"},
			"B": {"label": "Adapt as things happen", "trait": "P"}
		},
		{
			"text": "In crowded periods, you prefer to:",
			"A": {"label": "Coordinate actively with others", "trait": "E"},
			"B": {"label": "Focus independently", "trait": "I"}
		},
		{
			"text": "For a new situation, you first look for:",
			"A": {"label": "Known examples and practical cues", "trait": "S"},
			"B": {"label": "Possible alternatives and ideas", "trait": "N"}
		},
		{
			"text": "When robot asks for help, what persuades you more?",
			"A": {"label": "Strong evidence it is necessary", "trait": "T"},
			"B": {"label": "A respectful and warm request", "trait": "F"}
		},
		{
			"text": "During a long shift, you feel better with:",
			"A": {"label": "Clear schedule and closure", "trait": "J"},
			"B": {"label": "Flexible pace and options", "trait": "P"}
		}
	]

	var profile = get_node_or_null("/root/PlayerProfile")
	if profile and profile.has_method("has_mbti") and bool(profile.has_mbti()):
		return

	_mbti_index = 0
	for k in _mbti_scores.keys():
		_mbti_scores[k] = 0

	get_tree().paused = true
	mbti_panel.show()
	mbti_result.hide()
	mbti_confirm.hide()
	mbti_option_a.show()
	mbti_option_b.show()
	_refresh_mbti_question()

func _refresh_mbti_question() -> void:
	if _mbti_index < 0 or _mbti_index >= _mbti_questions.size():
		return
	var q: Dictionary = _mbti_questions[_mbti_index]
	mbti_progress.text = "Question %d / %d" % [_mbti_index + 1, _mbti_questions.size()]
	mbti_question.text = str(q.get("text", ""))
	var a: Dictionary = q.get("A", {})
	var b: Dictionary = q.get("B", {})
	mbti_option_a.text = str(a.get("label", "Option A"))
	mbti_option_b.text = str(b.get("label", "Option B"))

func _choose_mbti(option_key: String) -> void:
	if _mbti_index < 0 or _mbti_index >= _mbti_questions.size():
		return
	var q: Dictionary = _mbti_questions[_mbti_index]
	var option: Dictionary = q.get(option_key, {})
	var trait_key := str(option.get("trait", ""))
	if trait_key != "" and _mbti_scores.has(trait_key):
		_mbti_scores[trait_key] = int(_mbti_scores[trait_key]) + 1
	_mbti_index += 1

	if _mbti_index >= _mbti_questions.size():
		_show_mbti_result()
	else:
		_refresh_mbti_question()

func _show_mbti_result() -> void:
	var mbti = _compute_mbti_type()
	var profile = get_node_or_null("/root/PlayerProfile")
	if profile and profile.has_method("set_mbti"):
		profile.set_mbti(mbti, _mbti_scores.duplicate(true), _mbti_questions.size())

	mbti_progress.text = "Survey Complete"
	mbti_question.text = "Your MBTI result: %s" % mbti
	mbti_result.text = "This profile is now used by the persuasion strategy engine."
	mbti_result.show()
	mbti_option_a.hide()
	mbti_option_b.hide()
	mbti_confirm.show()

func _compute_mbti_type() -> String:
	var ei := "I"
	if int(_mbti_scores["E"]) >= int(_mbti_scores["I"]):
		ei = "E"
	var sn := "N"
	if int(_mbti_scores["S"]) >= int(_mbti_scores["N"]):
		sn = "S"
	var tf := "F"
	if int(_mbti_scores["T"]) >= int(_mbti_scores["F"]):
		tf = "T"
	var jp := "P"
	if int(_mbti_scores["J"]) >= int(_mbti_scores["P"]):
		jp = "J"
	return ei + sn + tf + jp

func _finish_mbti_and_start() -> void:
	mbti_panel.hide()
	get_tree().paused = false

func _auto_open_help_request(request: Dictionary) -> void:
	if mbti_panel and mbti_panel.visible:
		return
	if not _can_auto_open_request(request):
		return
	var rid := str(request.get("id", ""))
	if rid == "":
		return
	if bool(_auto_open_in_flight.get(rid, false)):
		return
	if rid == _active_request_id and help_panel.visible:
		return

	_auto_open_in_flight[rid] = true
	_active_request_id = rid
	_active_request_type = str(request.get("type", ""))
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr and help_mgr.has_method("mark_prompted"):
		help_mgr.mark_prompted(rid)
		request = help_mgr.get_request(rid)
	show_help_request(request)
	_auto_open_in_flight.erase(rid)

func _can_auto_open_request(request: Dictionary) -> bool:
	var req_type := str(request.get("type", ""))
	if req_type != "HANDOFF":
		return true

	var robot_iid := int(request.get("robot_instance_id", 0))
	if robot_iid <= 0:
		return false
	var robot_obj = instance_from_id(robot_iid)
	if robot_obj == null or not (robot_obj is Node2D):
		return false
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	if not (players[0] is Node2D):
		return false
	var robot_node := robot_obj as Node2D
	var player_node := players[0] as Node2D
	return robot_node.global_position.distance_to(player_node.global_position) <= HANDOFF_PROMPT_DISTANCE

func _maybe_show_help_bubble(request: Dictionary) -> void:
	var rid := str(request.get("id", ""))
	var utterance := str(request.get("utterance", "")).strip_edges()
	if utterance == "":
		return
	var previous := str(_last_utterance_by_request.get(rid, ""))
	if previous == utterance:
		return
	_last_utterance_by_request[rid] = utterance

	var bubble_mgr = get_node_or_null("/root/BubbleManager")
	if bubble_mgr == null or not bubble_mgr.has_method("say"):
		return
	var robots = get_tree().get_nodes_in_group("robot")
	if robots.is_empty():
		return
	var robot = robots[0]
	if robot is Node2D:
		bubble_mgr.say(robot, utterance, 2.8, Color(0.94, 0.98, 1.0, 1.0))

func _on_bubble_message(_speaker: String, text: String, kind: String) -> void:
	if kind == "system":
		return
	_append_feed_line(text)

func _append_feed_line(text: String) -> void:
	if dialogue_log == null:
		return
	var content := text.strip_edges()
	if content == "":
		return
	var stamp := Time.get_time_string_from_system()
	var line := "[%s] %s\n" % [stamp, content]
	dialogue_log.push_color(FEED_COLOR_DIALOGUE)
	dialogue_log.add_text(line)
	dialogue_log.pop()
	var max_lines := 80
	if dialogue_log.get_line_count() > max_lines:
		dialogue_log.clear()
	dialogue_log.scroll_to_line(max(0, dialogue_log.get_line_count() - 1))
