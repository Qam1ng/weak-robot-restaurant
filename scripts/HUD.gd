extends CanvasLayer

signal kitchen_pick_selected(item_name: String)

@onready var mbti_panel: PanelContainer = $MBTIPanel
@onready var mbti_progress: Label = $MBTIPanel/Margin/VBox/Progress
@onready var mbti_question: Label = $MBTIPanel/Margin/VBox/Question
@onready var mbti_option_a: Button = $MBTIPanel/Margin/VBox/Options/OptionA
@onready var mbti_option_b: Button = $MBTIPanel/Margin/VBox/Options/OptionB
@onready var mbti_result: Label = $MBTIPanel/Margin/VBox/Result
@onready var mbti_confirm: Button = $MBTIPanel/Margin/VBox/Confirm

var inventory_panel: PanelContainer
var inventory_list: VBoxContainer
var score_label: Label
var battery_label: Label
var robot_items_box: VBoxContainer
var robot_tasks_box: VBoxContainer
var player_items_box: VBoxContainer
var player_tasks_box: VBoxContainer
var customer_tab_buttons: HBoxContainer
var customer_live_btn: Button
var customer_history_btn: Button
var customer_items_box: VBoxContainer
var dialogue_panel: PanelContainer
var dialogue_title: Label
var dialogue_log: RichTextLabel
var player_dialogue_overlay: PanelContainer
var player_dialogue_overlay_label: RichTextLabel
var player_dialogue_info_stack: VBoxContainer
var player_dialogue_overlay_buttons: HBoxContainer
var player_dialogue_overlay_accept_btn: Button
var player_dialogue_overlay_decline_btn: Button
var player_dialogue_overlay_later_btn: Button
var _player_dialogue_overlay_tween: Tween
var _player_dialogue_info_cards: Array[Dictionary] = []
var _left_panel_width: float = 0.0
var _active_request_id: String = ""
var _active_request_type: String = ""
var _last_utterance_by_request: Dictionary = {}
var _auto_open_in_flight: Dictionary = {}
var _popup_mode: String = "none"
var _kitchen_pick_options: Array[String] = []
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
const POPUP_MODE_NONE := "none"
const POPUP_MODE_HELP := "help"
const POPUP_MODE_KITCHEN_PICK := "kitchen_pick"
const POPUP_MODE_GAME_OVER := "game_over"
const CUSTOMER_TAB_LIVE := "live"
const CUSTOMER_TAB_HISTORY := "history"
const LEFT_PANEL_GAP_Y := 16.0
const SIDE_PANEL_MARGIN := 20.0
const TOP_PANEL_Y := 60.0
const PLAYER_DIALOGUE_OVERLAY_Y := 84.0
const PLAYER_DIALOGUE_OVERLAY_WIDTH := 520.0
const PLAYER_DIALOGUE_OVERLAY_MIN_HEIGHT := 72.0
const PLAYER_DIALOGUE_OVERLAY_SHOW_SEC := 5.0
const PLAYER_DIALOGUE_STACK_GAP := 10.0
const PLAYER_DIALOGUE_MAX_STACK := 3
const DIALOGUE_PANEL_WIDTH := 340.0
var _customer_tab: String = CUSTOMER_TAB_LIVE
var _score: int = 0
var _success_count: int = 0
var _failed_count: int = 0
const SCORE_PER_SUCCESS := 2
const SCORE_PER_FAILURE := -6
const SCORE_PER_DRINK_SUCCESS := 1
const SCORE_PER_DRINK_FAILURE := -3
const SCORE_FAIL_THRESHOLD := -30
const MBTI_PANEL_BASE_SIZE := Vector2(720.0, 440.0)
const MBTI_PANEL_MARGIN := 24.0
const MBTI_PANEL_OFFSET_X := 23.0
var _score_game_over: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")

	if mbti_panel:
		mbti_panel.hide()

	mbti_option_a.pressed.connect(func(): _choose_mbti("A"))
	mbti_option_b.pressed.connect(func(): _choose_mbti("B"))
	mbti_confirm.pressed.connect(_finish_mbti_and_start)

	_setup_inventory_ui()
	_setup_dialogue_feed_ui()
	_setup_player_dialogue_overlay_ui()
	_set_gameplay_panels_visible(false)
	_connect_viewport_resize()
	_connect_help_signals()
	_connect_dialogue_feed_signals()
	_connect_robot_inventory()
	_connect_player_inventory()
	_connect_score_signals()
	call_deferred("_setup_mbti_survey")

func _connect_viewport_resize() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)
	_recenter_mbti_panel()

func _on_viewport_size_changed() -> void:
	_recenter_mbti_panel()
	_update_gameplay_panel_layout()

func _recenter_mbti_panel() -> void:
	if mbti_panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var view_size: Vector2 = vp.get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	var target_w := clampf(MBTI_PANEL_BASE_SIZE.x, 360.0, maxf(360.0, view_size.x - MBTI_PANEL_MARGIN * 2.0))
	var target_h := clampf(MBTI_PANEL_BASE_SIZE.y, 260.0, maxf(260.0, view_size.y - MBTI_PANEL_MARGIN * 2.0))
	mbti_panel.custom_minimum_size = Vector2(target_w, target_h)
	mbti_panel.size = Vector2(target_w, target_h)
	mbti_panel.position = (view_size - mbti_panel.size) * 0.5 + Vector2(MBTI_PANEL_OFFSET_X, 0.0)

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
	var inv = null
	if "inventory" in player and player.inventory != null:
		inv = player.inventory
	else:
		inv = player.get_node_or_null("Inventory")
	if inv:
		inv.inventory_changed.connect(_on_player_inventory_changed)
		_on_player_inventory_changed(inv.items)

func _setup_inventory_ui() -> void:
	inventory_panel = PanelContainer.new()
	inventory_panel.name = "InventoryPanel"
	add_child(inventory_panel)
	inventory_panel.position = Vector2(SIDE_PANEL_MARGIN, TOP_PANEL_Y)

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

	score_label = Label.new()
	score_label.text = "Score: 0"
	score_label.add_theme_color_override("font_color", Color(0.86, 0.96, 1.0, 1.0))
	inventory_list.add_child(score_label)

	var sep0 = HSeparator.new()
	inventory_list.add_child(sep0)

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

	var robot_task_title = Label.new()
	robot_task_title.text = "Assigned Tasks"
	robot_task_title.add_theme_color_override("font_color", Color(0.78, 0.94, 1.0, 1.0))
	inventory_list.add_child(robot_task_title)

	robot_tasks_box = VBoxContainer.new()
	inventory_list.add_child(robot_tasks_box)

	var sep = HSeparator.new()
	inventory_list.add_child(sep)

	var player_title = Label.new()
	player_title.text = "PLAYER"
	player_title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.74, 1.0))
	inventory_list.add_child(player_title)

	player_items_box = VBoxContainer.new()
	inventory_list.add_child(player_items_box)

	var player_task_title = Label.new()
	player_task_title.text = "Assigned Tasks"
	player_task_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.76, 1.0))
	inventory_list.add_child(player_task_title)

	player_tasks_box = VBoxContainer.new()
	inventory_list.add_child(player_tasks_box)

	var sep2 = HSeparator.new()
	inventory_list.add_child(sep2)

	var customer_title = Label.new()
	customer_title.text = "Customer Orders"
	customer_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.78, 1.0))
	inventory_list.add_child(customer_title)

	customer_tab_buttons = HBoxContainer.new()
	inventory_list.add_child(customer_tab_buttons)

	customer_live_btn = Button.new()
	customer_live_btn.text = "Live"
	customer_live_btn.toggle_mode = true
	customer_live_btn.button_pressed = true
	customer_live_btn.pressed.connect(func():
		_set_customer_tab(CUSTOMER_TAB_LIVE)
	)
	customer_tab_buttons.add_child(customer_live_btn)

	customer_history_btn = Button.new()
	customer_history_btn.text = "History"
	customer_history_btn.toggle_mode = true
	customer_history_btn.button_pressed = false
	customer_history_btn.pressed.connect(func():
		_set_customer_tab(CUSTOMER_TAB_HISTORY)
	)
	customer_tab_buttons.add_child(customer_history_btn)

	customer_items_box = VBoxContainer.new()
	inventory_list.add_child(customer_items_box)

	_left_panel_width = maxf(250.0, inventory_panel.get_combined_minimum_size().x + 26.0)
	inventory_panel.custom_minimum_size = Vector2(_left_panel_width, 0.0)

func _setup_dialogue_feed_ui() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.name = "DialogueFeedPanel"
	add_child(dialogue_panel)
	dialogue_panel.position = Vector2(SIDE_PANEL_MARGIN, TOP_PANEL_Y)
	dialogue_panel.custom_minimum_size = Vector2(maxf(DIALOGUE_PANEL_WIDTH, _left_panel_width), 210)

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
	dialogue_log.custom_minimum_size = Vector2(maxf(170.0, dialogue_panel.custom_minimum_size.x - 30.0), 160)
	dialogue_log.bbcode_enabled = false
	dialogue_log.scroll_active = true
	dialogue_log.fit_content = false
	vbox.add_child(dialogue_log)
	_update_gameplay_panel_layout()

func _setup_player_dialogue_overlay_ui() -> void:
	player_dialogue_info_stack = VBoxContainer.new()
	player_dialogue_info_stack.name = "PlayerDialogueInfoStack"
	player_dialogue_info_stack.visible = false
	player_dialogue_info_stack.add_theme_constant_override("separation", PLAYER_DIALOGUE_STACK_GAP)
	add_child(player_dialogue_info_stack)

	player_dialogue_overlay = PanelContainer.new()
	player_dialogue_overlay.name = "PlayerDialogueOverlay"
	player_dialogue_overlay.visible = false
	add_child(player_dialogue_overlay)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.84, 0.36, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	player_dialogue_overlay.add_theme_stylebox_override("panel", style)
	player_dialogue_overlay.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH, PLAYER_DIALOGUE_OVERLAY_MIN_HEIGHT)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	player_dialogue_overlay.add_child(vbox)

	player_dialogue_overlay_label = RichTextLabel.new()
	player_dialogue_overlay_label.bbcode_enabled = false
	player_dialogue_overlay_label.fit_content = true
	player_dialogue_overlay_label.scroll_active = false
	player_dialogue_overlay_label.selection_enabled = false
	player_dialogue_overlay_label.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH - 28.0, PLAYER_DIALOGUE_OVERLAY_MIN_HEIGHT - 20.0)
	vbox.add_child(player_dialogue_overlay_label)

	player_dialogue_overlay_buttons = HBoxContainer.new()
	player_dialogue_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	player_dialogue_overlay_buttons.visible = false
	vbox.add_child(player_dialogue_overlay_buttons)

	player_dialogue_overlay_accept_btn = Button.new()
	player_dialogue_overlay_accept_btn.text = "Accept"
	player_dialogue_overlay_accept_btn.pressed.connect(func(): _respond("accept"))
	player_dialogue_overlay_buttons.add_child(player_dialogue_overlay_accept_btn)

	player_dialogue_overlay_decline_btn = Button.new()
	player_dialogue_overlay_decline_btn.text = "Decline"
	player_dialogue_overlay_decline_btn.pressed.connect(func(): _respond("decline"))
	player_dialogue_overlay_buttons.add_child(player_dialogue_overlay_decline_btn)

	player_dialogue_overlay_later_btn = Button.new()
	player_dialogue_overlay_later_btn.text = "Later"
	player_dialogue_overlay_later_btn.pressed.connect(func(): _respond("later"))
	player_dialogue_overlay_buttons.add_child(player_dialogue_overlay_later_btn)

	_update_gameplay_panel_layout()

func _connect_score_signals() -> void:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null:
		return
	if board.has_signal("task_completed") and not board.task_completed.is_connected(_on_task_completed):
		board.task_completed.connect(_on_task_completed)
	if board.has_signal("task_failed") and not board.task_failed.is_connected(_on_task_failed):
		board.task_failed.connect(_on_task_failed)
	_refresh_score_label()

func _on_task_completed(task: Dictionary) -> void:
	_success_count += 1
	var payload: Dictionary = task.get("payload", {})
	var order_kind := str(payload.get("order_kind", "food"))
	if order_kind == "drink":
		_score += SCORE_PER_DRINK_SUCCESS
	else:
		_score += SCORE_PER_SUCCESS
	_refresh_score_label()
	_update_player_task_panel()
	_update_customer_panel()

func _on_task_failed(task: Dictionary) -> void:
	_failed_count += 1
	var payload: Dictionary = task.get("payload", {})
	var order_kind := str(payload.get("order_kind", "food"))
	if order_kind == "drink":
		_score += SCORE_PER_DRINK_FAILURE
	else:
		_score += SCORE_PER_FAILURE
	_refresh_score_label()
	_update_player_task_panel()
	_update_customer_panel()
	_check_score_game_over()

func _refresh_score_label() -> void:
	if score_label == null:
		return
	score_label.text = "Score: %d" % _score
	if _score < 0:
		score_label.add_theme_color_override("font_color", Color(1.0, 0.70, 0.70, 1.0))
	elif _score > 0:
		score_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78, 1.0))
	else:
		score_label.add_theme_color_override("font_color", Color(0.86, 0.96, 1.0, 1.0))

func _check_score_game_over() -> void:
	if _score_game_over:
		return
	if _score > SCORE_FAIL_THRESHOLD:
		return
	_score_game_over = true
	get_tree().paused = true
	_popup_mode = POPUP_MODE_GAME_OVER
	_active_request_id = ""
	_active_request_type = ""
	_show_player_dialogue_prompt(
		"Game Over",
		"Score reached %d (threshold %d).\nShift failed." % [_score, SCORE_FAIL_THRESHOLD],
		["Retry", "Quit"],
		false
	)

func _on_game_over_retry() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_game_over_quit() -> void:
	get_tree().quit()

func _connect_dialogue_feed_signals() -> void:
	var bubble_mgr = get_node_or_null("/root/BubbleManager")
	if bubble_mgr and bubble_mgr.has_signal("message_routed") and not bubble_mgr.message_routed.is_connected(_on_bubble_message):
		bubble_mgr.message_routed.connect(_on_bubble_message)

func _on_robot_inventory_changed(items: Array) -> void:
	if not robot_items_box:
		return

	for c in robot_items_box.get_children():
		c.queue_free()

	var holding = Label.new()
	holding.text = "Holding (%d/%d):" % [items.size(), _get_robot_capacity()]
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
	holding.text = "Holding (%d/%d):" % [items.size(), _get_player_capacity()]
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
	_update_robot_task_panel()
	_update_player_task_panel()
	_update_customer_panel()
	_update_gameplay_panel_layout()

func _update_gameplay_panel_layout() -> void:
	if inventory_panel == null or dialogue_panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var view_size := vp.get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	inventory_panel.position = Vector2(SIDE_PANEL_MARGIN, TOP_PANEL_Y)
	var dialogue_w := maxf(_left_panel_width, dialogue_panel.custom_minimum_size.x)
	dialogue_panel.position = Vector2(view_size.x - dialogue_w - SIDE_PANEL_MARGIN, TOP_PANEL_Y)
	dialogue_panel.custom_minimum_size.x = maxf(DIALOGUE_PANEL_WIDTH, _left_panel_width)
	if player_dialogue_overlay:
		var overlay_w := player_dialogue_overlay.custom_minimum_size.x
		player_dialogue_overlay.position = Vector2((view_size.x - overlay_w) * 0.5, PLAYER_DIALOGUE_OVERLAY_Y)
	if player_dialogue_info_stack:
		var stack_y := PLAYER_DIALOGUE_OVERLAY_Y
		if player_dialogue_overlay and player_dialogue_overlay.visible:
			var prompt_h := maxf(player_dialogue_overlay.size.y, player_dialogue_overlay.get_combined_minimum_size().y)
			stack_y += prompt_h + PLAYER_DIALOGUE_STACK_GAP
		player_dialogue_info_stack.position = Vector2((view_size.x - PLAYER_DIALOGUE_OVERLAY_WIDTH) * 0.5, stack_y)
		player_dialogue_info_stack.custom_minimum_size.x = PLAYER_DIALOGUE_OVERLAY_WIDTH

func _update_robot_task_panel() -> void:
	if robot_tasks_box == null:
		return
	for c in robot_tasks_box.get_children():
		c.queue_free()

	var board = get_node_or_null("/root/TaskBoard")
	var robots := get_tree().get_nodes_in_group("robot")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee") or robots.is_empty():
		var empty_fallback := Label.new()
		empty_fallback.text = "(None)"
		empty_fallback.add_theme_color_override("font_color", Color.GRAY)
		robot_tasks_box.add_child(empty_fallback)
		return

	var assignee := str(robots[0].name)
	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee(assignee)
	if tasks.is_empty():
		var empty := Label.new()
		empty.text = "(None)"
		empty.add_theme_color_override("font_color", Color.GRAY)
		robot_tasks_box.add_child(empty)
		return

	for task in tasks:
		var task_id := str(task.get("id", ""))
		var payload: Dictionary = task.get("payload", {})
		var item_label := _task_display_name(payload)
		var seat := _friendly_table_name(str(payload.get("seat", "-")))
		var step := "In Progress"
		if board.has_method("get_current_step_name"):
			step = _friendly_step_name(str(board.get_current_step_name(task_id)))
		var eta := "Waiting"
		var deadline_ms := int(task.get("deadline_ms", 0))
		if deadline_ms > 0:
			var remain_sec := int(ceili(float(deadline_ms - Time.get_ticks_msec()) / 1000.0))
			eta = str(maxi(remain_sec, 0)) + "s"
		var line := Label.new()
		line.text = "%s | %s | %s | %s" % [seat, item_label, step, eta]
		if eta == "0s":
			line.add_theme_color_override("font_color", Color(1.0, 0.52, 0.52, 1.0))
		robot_tasks_box.add_child(line)

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
	var mode_text := _friendly_battery_mode(mode)
	battery_label.text = "Battery: %d%% (%s)" % [clampi(level, 0, 100), mode_text]

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

	if _customer_tab == CUSTOMER_TAB_HISTORY:
		_update_customer_history_panel()
		return

	var customers := get_tree().get_nodes_in_group("customer")
	if customers.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(None)"
		empty_label.add_theme_color_override("font_color", Color.GRAY)
		customer_items_box.add_child(empty_label)
		return

	var board = get_node_or_null("/root/TaskBoard")
	var now_ms := Time.get_ticks_msec()
	var shown_count := 0
	for n in customers:
		if not (n is Node):
			continue
		var cnode := n as Node
		var state := "unknown"
		if cnode.has_method("get_state_name"):
			state = str(cnode.call("get_state_name"))

		var seat := ""
		if "current_seat" in cnode:
			seat = str(cnode.get("current_seat"))
		if seat == "":
			seat = "-"

		var open_tasks: Array[Dictionary] = []
		var ended_task_recently := false
		if board and board.has_method("get_open_tasks_for_customer"):
			open_tasks = board.get_open_tasks_for_customer(cnode.get_instance_id())
		if open_tasks.is_empty() and board and board.has_method("get_all_tasks"):
			for task in board.get_all_tasks():
				var payload: Dictionary = task.get("payload", {})
				if int(payload.get("customer_instance_id", 0)) != cnode.get_instance_id():
					continue
				var task_state := str(task.get("state", ""))
				if task_state == "completed" or task_state == "failed":
					ended_task_recently = true
					break

		if ended_task_recently and state != "EATING":
			continue

		var line := Label.new()
		var table_text := _friendly_table_name(seat)
		var food_task := _task_by_kind(open_tasks, "food")
		var drink_task := _task_by_kind(open_tasks, "drink")
		var display_state := _friendly_customer_state(state, _current_customer_step_name(food_task))
		if state == "WAITING_FOR_FOOD":
			var food_step := _current_customer_step_name(food_task)
			var drink_step := _current_customer_step_name(drink_task)
			if food_step == "TAKE_ORDER":
				display_state = "Waiting"
			elif not drink_task.is_empty() and drink_step == "TAKE_ORDER":
				display_state = "Waiting"
			elif not drink_task.is_empty():
				display_state = "Waiting"
		if state == "WAITING_FOR_FOOD":
			var parts: Array[String] = [table_text]
			if not food_task.is_empty():
				parts.append("%s %s" % [_compact_item_name(food_task.get("payload", {})), _countdown_text_from_task(food_task, now_ms)])
			if not drink_task.is_empty():
				parts.append("%s %s" % [_compact_item_name(drink_task.get("payload", {})), _countdown_text_from_task(drink_task, now_ms)])
			parts.append(_compact_customer_status(display_state))
			line.text = " | ".join(parts)
			if (not food_task.is_empty() and _countdown_text_from_task(food_task, now_ms) == "0s") or (not drink_task.is_empty() and _countdown_text_from_task(drink_task, now_ms) == "0s"):
				line.add_theme_color_override("font_color", Color(1.0, 0.52, 0.52, 1.0))
		else:
			var parts: Array[String] = [table_text]
			if not food_task.is_empty():
				parts.append(_compact_item_name(food_task.get("payload", {})))
			if not drink_task.is_empty():
				parts.append(_compact_item_name(drink_task.get("payload", {})))
			parts.append(_compact_customer_status(display_state))
			line.text = " | ".join(parts)
		customer_items_box.add_child(line)
		shown_count += 1

	if shown_count == 0:
		var empty_after_filter := Label.new()
		empty_after_filter.text = "(None)"
		empty_after_filter.add_theme_color_override("font_color", Color.GRAY)
		customer_items_box.add_child(empty_after_filter)

func _update_customer_history_panel() -> void:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_all_tasks"):
		var empty_fallback := Label.new()
		empty_fallback.text = "(No history)"
		empty_fallback.add_theme_color_override("font_color", Color.GRAY)
		customer_items_box.add_child(empty_fallback)
		return

	var tasks: Array[Dictionary] = board.get_all_tasks()
	var ended: Array[Dictionary] = []
	for task in tasks:
		var st := str(task.get("state", ""))
		if st == "completed" or st == "failed":
			ended.append(task)

	var summary := Label.new()
	summary.text = "Success %d | Failed %d" % [_success_count, _failed_count]
	summary.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0, 1.0))
	customer_items_box.add_child(summary)

	if ended.is_empty():
		var empty := Label.new()
		empty.text = "(No finished tasks)"
		empty.add_theme_color_override("font_color", Color.GRAY)
		customer_items_box.add_child(empty)
		return

	ended.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := maxi(int(a.get("completed_at_ms", 0)), int(a.get("failed_at_ms", 0)))
		var tb := maxi(int(b.get("completed_at_ms", 0)), int(b.get("failed_at_ms", 0)))
		return ta > tb
	)

	var show_count := mini(8, ended.size())
	for i in range(show_count):
		var task: Dictionary = ended[i]
		var payload: Dictionary = task.get("payload", {})
		var seat := _friendly_table_name(str(payload.get("seat", "-")))
		var item_label := _task_display_name(payload)
		var state := str(task.get("state", ""))
		var status_text := "Success"
		if state == "failed":
			status_text = "Failed"
		var score_delta_text := _history_score_delta_text(task)
		var line := Label.new()
		line.text = "%s | %s | %s | %s" % [seat, item_label, status_text, score_delta_text]
		if state == "failed":
			line.add_theme_color_override("font_color", Color(1.0, 0.56, 0.56, 1.0))
		else:
			line.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78, 1.0))
		customer_items_box.add_child(line)

func _set_customer_tab(tab: String) -> void:
	_customer_tab = tab
	if customer_live_btn:
		customer_live_btn.button_pressed = (_customer_tab == CUSTOMER_TAB_LIVE)
	if customer_history_btn:
		customer_history_btn.button_pressed = (_customer_tab == CUSTOMER_TAB_HISTORY)
	_update_customer_panel()

func _update_player_task_panel() -> void:
	if player_tasks_box == null:
		return
	for c in player_tasks_box.get_children():
		c.queue_free()

	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee"):
		var empty_fallback := Label.new()
		empty_fallback.text = "(None)"
		empty_fallback.add_theme_color_override("font_color", Color.GRAY)
		player_tasks_box.add_child(empty_fallback)
		return

	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee("player")
	if tasks.is_empty():
		var empty := Label.new()
		empty.text = "(None)"
		empty.add_theme_color_override("font_color", Color.GRAY)
		player_tasks_box.add_child(empty)
		return

	for task in tasks:
		var task_id := str(task.get("id", ""))
		var payload: Dictionary = task.get("payload", {})
		var item_label := _task_display_name(payload)
		var seat := _friendly_table_name(str(payload.get("seat", "-")))
		var step := "In Progress"
		if board.has_method("get_current_step_name"):
			step = _friendly_step_name(str(board.get_current_step_name(task_id)))
		var eta := "Waiting"
		var deadline_ms := int(task.get("deadline_ms", 0))
		if deadline_ms > 0:
			var remain_sec := int(ceili(float(deadline_ms - Time.get_ticks_msec()) / 1000.0))
			eta = str(maxi(remain_sec, 0)) + "s"
		var line := Label.new()
		line.text = "%s | %s | %s | %s" % [seat, item_label, step, eta]
		if eta == "0s":
			line.add_theme_color_override("font_color", Color(1.0, 0.52, 0.52, 1.0))
		player_tasks_box.add_child(line)

func _extract_food_from_request(request: String) -> String:
	var text := request.to_lower()
	var foods = ["pizza", "hotdog", "sandwich"]
	for f in foods:
		if f in text:
			return f
	return "order"

func _task_display_name(payload: Dictionary) -> String:
	var item := str(payload.get("display_item", "")).strip_edges()
	if item == "":
		item = str(payload.get("food_item", payload.get("drink_item", "order"))).strip_edges()
	return item.capitalize()

func _compact_item_name(payload: Dictionary) -> String:
	var item := str(payload.get("display_item", "")).strip_edges().to_lower()
	if item == "":
		item = str(payload.get("food_item", payload.get("drink_item", "order"))).strip_edges().to_lower()
	return item.capitalize()

func _history_score_delta_text(task: Dictionary) -> String:
	var payload: Dictionary = task.get("payload", {})
	var order_kind := str(payload.get("order_kind", "food"))
	var state := str(task.get("state", ""))
	var delta := 0
	if state == "completed":
		delta = SCORE_PER_DRINK_SUCCESS if order_kind == "drink" else SCORE_PER_SUCCESS
	elif state == "failed":
		delta = SCORE_PER_DRINK_FAILURE if order_kind == "drink" else SCORE_PER_FAILURE
	return ("%+d" % delta)

func _task_by_kind(tasks: Array[Dictionary], order_kind: String) -> Dictionary:
	for task in tasks:
		var payload: Dictionary = task.get("payload", {})
		if str(payload.get("order_kind", "food")) == order_kind:
			return task
	return {}

func _countdown_text_from_task(task: Dictionary, now_ms: int) -> String:
	var deadline_ms := int(task.get("deadline_ms", 0))
	if deadline_ms <= 0:
		return "Waiting"
	var remain_sec := int(ceili(float(deadline_ms - now_ms) / 1000.0))
	return str(maxi(remain_sec, 0)) + "s"

func _summarize_holding(items: Array) -> String:
	if items.is_empty():
		return "None"
	var names: Array[String] = []
	for item in items:
		names.append(str(item.get("name", "item")))
	return ", ".join(names)

func _friendly_customer_state(raw: String, step_name: String = "") -> String:
	match raw:
		"ENTERING":
			return "Entering"
		"WAITING_FOR_FOOD":
			return "Waiting"
		"EATING":
			return "Eating"
		"LEAVING":
			return "Leaving"
		"LEFT":
			return "Left"
		_:
			return "Unknown"

func _compact_customer_status(status: String) -> String:
	match status:
		"Entering":
			return "Entering"
		"Waiting":
			return "Waiting"
		"Eating":
			return "Eating"
		"Leaving":
			return "Leaving"
		"Left":
			return "Left"
		_:
			return status

func _friendly_table_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	if s.begins_with("seat"):
		var suffix := s.substr(4, s.length() - 4)
		if suffix != "":
			return "Table " + suffix
	if s == "" or s == "-":
		return "Table -"
	return raw

func _friendly_battery_mode(raw: String) -> String:
	match raw:
		"normal":
			return "Normal"
		"conserve":
			return "Low Power"
		"emergency":
			return "Critical"
		_:
			return "Normal"

func _friendly_step_name(raw: String) -> String:
	match raw:
		"TAKE_ORDER":
			return "Take Order"
		"PICKUP_FROM_KITCHEN":
			return "Pickup"
		"DELIVER_AND_SERVE":
			return "Deliver"
		_:
			return "In Progress"

func _current_customer_step_name(task: Dictionary) -> String:
	if task.is_empty():
		return ""
	var idx := int(task.get("current_step_index", 0))
	var steps: Array = task.get("steps", [])
	if idx < 0 or idx >= steps.size():
		return ""
	return str((steps[idx] as Dictionary).get("name", ""))

func _get_robot_capacity() -> int:
	var robots = get_tree().get_nodes_in_group("robot")
	if robots.is_empty():
		return 0
	var inv = robots[0].get_node_or_null("Inventory")
	if inv == null:
		return 0
	return int(inv.capacity)

func _get_player_capacity() -> int:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return 0
	var player = players[0]
	var inv = null
	if "inventory" in player and player.inventory != null:
		inv = player.inventory
	else:
		inv = player.get_node_or_null("Inventory")
	if inv == null:
		return 0
	return int(inv.capacity)

func show_help_request(request: Dictionary) -> void:
	if request.is_empty():
		return

	_popup_mode = POPUP_MODE_HELP
	_active_request_id = str(request.get("id", ""))
	_active_request_type = str(request.get("type", ""))
	_reset_help_buttons()
	_show_player_dialogue_prompt("Robot Request", _build_help_text(request), ["Accept", "Decline", "Later"], true)
	_maybe_show_help_bubble(request)

func _build_help_text(request: Dictionary) -> String:
	var utterance = str(request.get("utterance", ""))
	if utterance == "":
		utterance = "Can you help now?"
	return utterance + "\n\nChoose: Accept / Decline / Later"

func _respond(response: String) -> void:
	if _popup_mode == POPUP_MODE_KITCHEN_PICK:
		var idx := -1
		match response:
			"accept":
				idx = 0
			"decline":
				idx = 1
			"later":
				idx = 2
		if idx >= 0 and idx < _kitchen_pick_options.size():
			kitchen_pick_selected.emit(_kitchen_pick_options[idx])
		return

	if _popup_mode == POPUP_MODE_GAME_OVER:
		match response:
			"accept":
				_on_game_over_retry()
			"decline":
				_on_game_over_quit()
		return

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
			_hide_player_dialogue_overlay()
			_popup_mode = POPUP_MODE_NONE
	elif status == "cooldown":
		if rid == _active_request_id:
			_hide_player_dialogue_overlay()
			_popup_mode = POPUP_MODE_NONE
	elif status == "pending":
		if rid != _active_request_id:
			_auto_open_help_request(request)
		else:
			_show_player_dialogue_prompt("Robot Request", _build_help_text(request), ["Accept", "Decline", "Later"], true)
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
	_hide_player_dialogue_overlay()
	_popup_mode = POPUP_MODE_NONE
	_reset_help_buttons()

func show_kitchen_pick_popup(options: Array[String], title: String = "Kitchen Pickup") -> void:
	if options.size() < 3:
		return
	_popup_mode = POPUP_MODE_KITCHEN_PICK
	_kitchen_pick_options.clear()
	for i in range(3):
		_kitchen_pick_options.append(str(options[i]))
	_active_request_id = ""
	_active_request_type = ""
	_show_player_dialogue_prompt(
		title,
		"Take the item you need.\nTap an option to add +1.\nPress E to close.",
		[
			_kitchen_pick_options[0].capitalize(),
			_kitchen_pick_options[1].capitalize(),
			_kitchen_pick_options[2].capitalize()
		],
		true
	)

func hide_kitchen_pick_popup() -> void:
	if _popup_mode != POPUP_MODE_KITCHEN_PICK:
		return
	_hide_player_dialogue_overlay()
	_popup_mode = POPUP_MODE_NONE
	_kitchen_pick_options.clear()
	_reset_help_buttons()

func is_kitchen_pick_popup_visible() -> bool:
	return _popup_mode == POPUP_MODE_KITCHEN_PICK and player_dialogue_overlay != null and player_dialogue_overlay.visible

func is_help_request_popup_visible() -> bool:
	return _popup_mode == POPUP_MODE_HELP and player_dialogue_overlay != null and player_dialogue_overlay.visible

func show_quick_notice(text: String) -> void:
	_append_feed_line("Notice", text)

func _reset_help_buttons() -> void:
	if player_dialogue_overlay_accept_btn:
		player_dialogue_overlay_accept_btn.text = "Accept"
	if player_dialogue_overlay_decline_btn:
		player_dialogue_overlay_decline_btn.text = "Decline"
	if player_dialogue_overlay_later_btn:
		player_dialogue_overlay_later_btn.text = "Later"
	if player_dialogue_overlay_later_btn:
		player_dialogue_overlay_later_btn.visible = true

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
		_set_gameplay_panels_visible(true)
		return

	# Let player camera settle before pausing, to avoid post-survey camera jump.
	await _stabilize_player_camera_before_mbti()

	_mbti_index = 0
	for k in _mbti_scores.keys():
		_mbti_scores[k] = 0

	get_tree().paused = true
	_recenter_mbti_panel()
	mbti_panel.show()
	mbti_result.hide()
	mbti_confirm.hide()
	mbti_option_a.show()
	mbti_option_b.show()
	_refresh_mbti_question()

func _focus_player_camera_now() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player = players[0]
	if not (player is Node):
		return
	var cam = (player as Node).get_node_or_null("Camera2D")
	if cam == null or not (cam is Camera2D):
		return
	var camera := cam as Camera2D
	camera.make_current()
	camera.force_update_scroll()

func _stabilize_player_camera_before_mbti() -> void:
	# Wait for a few frames until player camera is current to avoid startup top-edge framing.
	for _i in range(6):
		_focus_player_camera_now()
		await get_tree().process_frame
		var cam := get_viewport().get_camera_2d()
		if cam != null:
			return
	await get_tree().physics_frame
	_focus_player_camera_now()
	await get_tree().process_frame

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
	_set_gameplay_panels_visible(true)

func _set_gameplay_panels_visible(visible: bool) -> void:
	if inventory_panel:
		inventory_panel.visible = visible
	if dialogue_panel:
		dialogue_panel.visible = visible
	if player_dialogue_overlay and not visible:
		player_dialogue_overlay.visible = false
	if player_dialogue_info_stack and not visible:
		player_dialogue_info_stack.visible = false

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
	if rid == _active_request_id and player_dialogue_overlay != null and player_dialogue_overlay.visible:
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
	var players := get_tree().get_nodes_in_group("player")
	var player := players[0] if not players.is_empty() else null
	if robot is Node2D:
		if player != null and player is Node2D and bubble_mgr.has_method("say_to"):
			bubble_mgr.say_to(robot, player, utterance, 2.8, Color(0.94, 0.98, 1.0, 1.0))
		else:
			bubble_mgr.say(robot, utterance, 2.8, Color(0.94, 0.98, 1.0, 1.0))

func _on_bubble_message(source: Node2D, recipient: Node2D, speaker: String, text: String, kind: String, recipient_kind: String) -> void:
	if kind == "system":
		return
	_append_feed_line(speaker, text)
	if _should_skip_player_overlay_message(source, recipient, kind, recipient_kind):
		return
	if _is_player_related_dialogue(source, recipient, kind, recipient_kind):
		_show_player_dialogue_overlay(speaker, text, kind)

func _append_feed_line(speaker: String, text: String) -> void:
	if dialogue_log == null:
		return
	var content := text.strip_edges()
	if content == "":
		return
	var line := "%s: %s\n" % [speaker, content]
	dialogue_log.push_color(FEED_COLOR_DIALOGUE)
	dialogue_log.add_text(line)
	dialogue_log.pop()
	var max_lines := 80
	if dialogue_log.get_line_count() > max_lines:
		dialogue_log.clear()
	dialogue_log.scroll_to_line(max(0, dialogue_log.get_line_count() - 1))

func _is_player_related_dialogue(source: Node2D, recipient: Node2D, kind: String, recipient_kind: String) -> bool:
	if recipient_kind == "player":
		return true
	if recipient != null and is_instance_valid(recipient) and recipient.is_in_group("player"):
		return true
	return false

func _should_skip_player_overlay_message(source: Node2D, recipient: Node2D, kind: String, recipient_kind: String) -> bool:
	if not _is_player_related_dialogue(source, recipient, kind, recipient_kind):
		return true
	if _popup_mode == POPUP_MODE_HELP and kind == "robot" and recipient_kind == "player":
		return true
	if _popup_mode == POPUP_MODE_KITCHEN_PICK or _popup_mode == POPUP_MODE_GAME_OVER:
		return true
	return false

func _show_player_dialogue_overlay(speaker: String, text: String, kind: String) -> void:
	if player_dialogue_info_stack == null:
		return
	var content := text.strip_edges()
	if content == "":
		return
	var speaker_color := Color(1.0, 0.92, 0.74, 1.0)
	if kind == "robot":
		speaker_color = Color(0.76, 0.95, 1.0, 1.0)
	elif kind == "customer":
		speaker_color = Color(1.0, 0.85, 0.78, 1.0)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH, PLAYER_DIALOGUE_OVERLAY_MIN_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.90)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = speaker_color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var label := RichTextLabel.new()
	label.bbcode_enabled = false
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH - 28.0, PLAYER_DIALOGUE_OVERLAY_MIN_HEIGHT - 20.0)
	card.add_child(label)
	label.push_color(speaker_color)
	label.add_text(speaker)
	label.pop()
	label.add_text(": %s" % content)

	player_dialogue_info_stack.add_child(card)
	player_dialogue_info_stack.visible = true
	_player_dialogue_info_cards.append({"node": card})
	_trim_player_dialogue_info_cards()
	_update_gameplay_panel_layout()

	card.modulate = Color(1, 1, 1, 1)
	card.scale = Vector2(0.95, 0.95)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(PLAYER_DIALOGUE_OVERLAY_SHOW_SEC)
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func():
		_remove_player_dialogue_info_card(card)
	)

func _show_player_dialogue_prompt(title: String, body: String, button_texts: Array[String] = [], show_third_button: bool = true) -> void:
	if player_dialogue_overlay == null or player_dialogue_overlay_label == null:
		return
	if _player_dialogue_overlay_tween and _player_dialogue_overlay_tween.is_valid():
		_player_dialogue_overlay_tween.kill()
	player_dialogue_overlay.visible = true
	player_dialogue_overlay.modulate = Color(1, 1, 1, 1)
	player_dialogue_overlay.scale = Vector2(1.0, 1.0)
	player_dialogue_overlay.position = Vector2(player_dialogue_overlay.position.x, PLAYER_DIALOGUE_OVERLAY_Y)
	player_dialogue_overlay_label.clear()
	player_dialogue_overlay_label.push_color(Color(1.0, 0.84, 0.36, 1.0))
	player_dialogue_overlay_label.add_text(title)
	player_dialogue_overlay_label.pop()
	player_dialogue_overlay_label.add_text("\n\n" + body)
	if player_dialogue_overlay_buttons:
		player_dialogue_overlay_buttons.visible = not button_texts.is_empty()
		if player_dialogue_overlay_accept_btn and button_texts.size() >= 1:
			player_dialogue_overlay_accept_btn.text = button_texts[0]
		if player_dialogue_overlay_decline_btn and button_texts.size() >= 2:
			player_dialogue_overlay_decline_btn.text = button_texts[1]
		if player_dialogue_overlay_later_btn:
			player_dialogue_overlay_later_btn.visible = show_third_button and button_texts.size() >= 3
			if button_texts.size() >= 3:
				player_dialogue_overlay_later_btn.text = button_texts[2]
	_trim_player_dialogue_info_cards()
	_update_gameplay_panel_layout()

func _hide_player_dialogue_overlay_buttons() -> void:
	if player_dialogue_overlay_buttons:
		player_dialogue_overlay_buttons.visible = false

func _hide_player_dialogue_overlay() -> void:
	if player_dialogue_overlay == null:
		return
	_hide_player_dialogue_overlay_buttons()
	player_dialogue_overlay.visible = false
	player_dialogue_overlay.modulate = Color(1, 1, 1, 1)
	player_dialogue_overlay.position = Vector2(player_dialogue_overlay.position.x, PLAYER_DIALOGUE_OVERLAY_Y)
	_update_gameplay_panel_layout()

func _trim_player_dialogue_info_cards() -> void:
	var allowed := PLAYER_DIALOGUE_MAX_STACK
	if player_dialogue_overlay and player_dialogue_overlay.visible:
		allowed -= 1
	allowed = maxi(allowed, 0)
	while _player_dialogue_info_cards.size() > allowed:
		var oldest: Dictionary = _player_dialogue_info_cards.pop_front()
		var node = oldest.get("node", null)
		if node != null and is_instance_valid(node):
			node.queue_free()

func _remove_player_dialogue_info_card(card: Control) -> void:
	for i in range(_player_dialogue_info_cards.size()):
		var entry: Dictionary = _player_dialogue_info_cards[i]
		if entry.get("node", null) == card:
			_player_dialogue_info_cards.remove_at(i)
			break
	if card != null and is_instance_valid(card):
		card.queue_free()
	if player_dialogue_info_stack and _player_dialogue_info_cards.is_empty():
		player_dialogue_info_stack.visible = false
	_update_gameplay_panel_layout()
