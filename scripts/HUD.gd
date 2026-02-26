extends CanvasLayer

@onready var interaction_label: Label = $InteractionLabel
@onready var help_panel: PanelContainer = $HelpRequestPanel
@onready var help_title: Label = $HelpRequestPanel/Margin/VBox/Title
@onready var help_body: RichTextLabel = $HelpRequestPanel/Margin/VBox/Body
@onready var accept_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Accept
@onready var decline_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Decline
@onready var later_btn: Button = $HelpRequestPanel/Margin/VBox/Buttons/Later
@onready var beacon_label: Label = $BeaconLabel

var inventory_panel: PanelContainer
var inventory_list: VBoxContainer
var _active_request_id: String = ""
var _active_request_type: String = ""

func _ready() -> void:
	add_to_group("hud")

	if interaction_label:
		interaction_label.hide()
	if help_panel:
		help_panel.hide()
	if beacon_label:
		beacon_label.hide()

	accept_btn.pressed.connect(func(): _respond("accept"))
	decline_btn.pressed.connect(func(): _respond("decline"))
	later_btn.pressed.connect(func(): _respond("later"))

	_setup_inventory_ui()
	_connect_help_signals()
	_connect_robot_inventory()

func _connect_help_signals() -> void:
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if not help_mgr:
		return
	if not help_mgr.request_updated.is_connected(_on_help_request_updated):
		help_mgr.request_updated.connect(_on_help_request_updated)
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
	if rid != _active_request_id:
		return

	var status = str(request.get("status", ""))
	if status == "accepted":
		help_panel.hide()
	elif status == "cooldown":
		help_panel.hide()
	elif status == "pending":
		help_body.text = _build_help_text(request)

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
