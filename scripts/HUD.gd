extends CanvasLayer

@onready var interaction_label: Label = $InteractionLabel
@onready var help_panel: PanelContainer = $HelpRequestPanel
@onready var help_title: Label = $HelpRequestPanel/Margin/VBox/Title
@onready var help_body: RichTextLabel = $HelpRequestPanel/Margin/VBox/Body
@onready var accept_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Accept
@onready var decline_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Decline
@onready var later_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Later
@onready var beacon_label: Label = $BeaconLabel
@onready var mbti_panel: PanelContainer = $MBTIPanel
@onready var mbti_progress: Label = $MBTIPanel/Margin/VBox/Progress
@onready var mbti_question: Label = $MBTIPanel/Margin/VBox/Question
@onready var mbti_option_a: Button = $MBTIPanel/Margin/VBox/Options/OptionA
@onready var mbti_option_b: Button = $MBTIPanel/Margin/VBox/Options/OptionB
@onready var mbti_result: Label = $MBTIPanel/Margin/VBox/Result
@onready var mbti_confirm: Button = $MBTIPanel/Margin/VBox/Confirm

var inventory_panel: PanelContainer
var inventory_list: VBoxContainer
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")

	if interaction_label:
		interaction_label.hide()
	if help_panel:
		help_panel.hide()
	if beacon_label:
		beacon_label.hide()
	if mbti_panel:
		mbti_panel.hide()

	accept_btn.pressed.connect(func(): _respond("accept"))
	decline_btn.pressed.connect(func(): _respond("decline"))
	later_btn.pressed.connect(func(): _respond("later"))
	mbti_option_a.pressed.connect(func(): _choose_mbti("A"))
	mbti_option_b.pressed.connect(func(): _choose_mbti("B"))
	mbti_confirm.pressed.connect(_finish_mbti_and_start)

	_setup_inventory_ui()
	_connect_help_signals()
	_connect_robot_inventory()
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
	if not help_mgr.beacon_changed.is_connected(_on_beacon_changed):
		help_mgr.beacon_changed.connect(_on_beacon_changed)

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
	title.text = "ROBOT INVENTORY"
	title.add_theme_color_override("font_color", Color.YELLOW)
	inventory_list.add_child(title)

func _on_robot_inventory_changed(items: Array) -> void:
	if not inventory_list:
		return

	for i in range(inventory_list.get_child_count() - 1, 0, -1):
		inventory_list.get_child(i).queue_free()

	if items.is_empty():
		var l = Label.new()
		l.text = "(Empty)"
		l.add_theme_color_override("font_color", Color.GRAY)
		inventory_list.add_child(l)
	else:
		for i in range(items.size()):
			var item = items[i]
			var l = Label.new()
			var n = item.get("name", "Unknown")
			l.text = "[%d] %s" % [i + 1, n]
			inventory_list.add_child(l)

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
	var request_type = str(request.get("type", "HANDOFF"))
	var escalation = int(request.get("escalation_count", 0))
	var strategy = str(request.get("strategy", ""))
	var payload: Dictionary = request.get("payload", {})
	var utterance = str(request.get("utterance", ""))
	if utterance == "":
		utterance = "Can you help now?"

	if request_type == "OPEN_DOOR":
		return "Strategy: %s\n%s\nEscalation: %d" % [strategy, utterance, escalation]

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

func _on_beacon_changed(active: bool, _position: Vector2, _request_id: String) -> void:
	if not beacon_label:
		return
	if active:
		beacon_label.text = "DOOR BEACON ACTIVE: Please go open the door."
		beacon_label.show()
	else:
		beacon_label.hide()

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
