extends CanvasLayer

signal kitchen_pick_selected(item_name: String)

const TrialCustomerScene = preload("res://scenes/Customer.tscn")

@onready var survey_panel: PanelContainer = $SurveyPanel
@onready var survey_question_title: RichTextLabel = $SurveyPanel/Margin/VBox/QuestionTitle
@onready var survey_question: Label = $SurveyPanel/Margin/VBox/Question
@onready var survey_scale_title: RichTextLabel = $SurveyPanel/Margin/VBox/ScaleTitle
@onready var survey_scale_hint: Label = $SurveyPanel/Margin/VBox/ScaleHint
@onready var survey_scale_spacer: Control = $SurveyPanel/Margin/VBox/ScaleSpacer
@onready var survey_options: HBoxContainer = $SurveyPanel/Margin/VBox/Options
@onready var survey_result_group_spacer: Control = $SurveyPanel/Margin/VBox/ResultGroupSpacer
@onready var survey_result_group: VBoxContainer = $SurveyPanel/Margin/VBox/ResultGroup
@onready var survey_result_title: RichTextLabel = $SurveyPanel/Margin/VBox/ResultGroup/ResultTitle
@onready var survey_result: Label = $SurveyPanel/Margin/VBox/ResultGroup/Result
@onready var survey_result_spacer: Control = $SurveyPanel/Margin/VBox/ResultSpacer
@onready var survey_confirm: Button = $SurveyPanel/Margin/VBox/Confirm

var inventory_panel: PanelContainer
var inventory_list: VBoxContainer
var day_phase_label: Label
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
var customer_history_pager: HBoxContainer
var customer_history_prev_btn: Button
var customer_history_page_label: Label
var customer_history_next_btn: Button
var dialogue_panel: PanelContainer
var dialogue_list: VBoxContainer
var dialogue_log: RichTextLabel
var customer_panel: PanelContainer
var customer_panel_list: VBoxContainer
var tutorial_panel: PanelContainer
var tutorial_body: RichTextLabel
var tutorial_start_button: Button
var tutorial_close_button: Button
var tutorial_toggle_button: Button
var player_dialogue_overlay_backdrop: ColorRect
var player_dialogue_overlay: PanelContainer
var player_dialogue_overlay_label: RichTextLabel
var help_prompt_stack: VBoxContainer
var player_dialogue_info_stack: VBoxContainer
var player_dialogue_overlay_buttons: HBoxContainer
var player_dialogue_overlay_button_spacer: Control
var player_dialogue_overlay_accept_btn: Button
var player_dialogue_overlay_decline_btn: Button
var player_dialogue_overlay_later_btn: Button
var _player_dialogue_info_cards: Array[Dictionary] = []
var _help_prompt_cards: Array[Dictionary] = []
var _left_panel_width: float = 0.0
var _last_help_bubble_utterance_by_request: Dictionary = {}
var _shown_help_system_notice_by_request: Dictionary = {}
var _auto_open_in_flight: Dictionary = {}
var _popup_mode: String = "none"
var _kitchen_pick_options: Array[String] = []
var _tipi_questions: Array[Dictionary] = []
var _tipi_index: int = 0
var _tipi_responses := {}
var _survey_scale_buttons: Array[Button] = []
var _player_task_notice_player: AudioStreamPlayer
var _last_player_live_task_ids: Dictionary = {}
var _player_task_notice_initialized: bool = false
const FEED_COLOR_DIALOGUE := Color(0.84, 0.95, 1.0, 1.0)
const HANDOFF_PROMPT_DISTANCE := 120.0
const POPUP_MODE_NONE := "none"
const POPUP_MODE_KITCHEN_PICK := "kitchen_pick"
const POPUP_MODE_GAME_OVER := "game_over"
const POPUP_MODE_TRIAL_COMPLETE := "trial_complete"
const CUSTOMER_TAB_LIVE := "live"
const CUSTOMER_TAB_HISTORY := "history"
const SIDE_PANEL_MARGIN := 20.0
const GAMEPLAY_REFERENCE_HEIGHT := 720.0
const GAMEPLAY_TOP_OFFSET := -60.0
const GAMEPLAY_BAND_WIDTH := 760.0
const GAMEPLAY_SIDE_GAP := 24.0
const SYSTEM_PANEL_X_OFFSET := 40.0
const SYSTEM_PANEL_WIDTH_REDUCTION := 28.0
const PLAYER_DIALOGUE_OVERLAY_Y_OFFSET := 4.0
const PLAYER_DIALOGUE_OVERLAY_WIDTH := 520.0
const PLAYER_DIALOGUE_OVERLAY_SHOW_SEC := 3.0
const PLAYER_DIALOGUE_STACK_GAP := 10.0
const HELP_PROMPT_MAX_STACK := 2
const DIALOGUE_PANEL_WIDTH := 340.0
const TUTORIAL_PANEL_WIDTH := 620.0
const TUTORIAL_PANEL_MIN_HEIGHT := 420.0
const TUTORIAL_TOGGLE_SIZE := 44.0
const TUTORIAL_TEXT := "[b]Controls[/b]\nWASD / Arrow Keys: move\nE: interact (take orders, open the cabinet, deliver items)\n\n[b]Goal[/b]\nServe customers' drinks before the deadline\nRespond to robot handoff popups\n\n[b]Robot Handoffs[/b]\nThe robot may hand off tasks when it is overloaded, running out of time, charging, stuck, or carrying a full backpack.\n\n[b]Player Reminders[/b]\nCheck your assigned tasks\nNotice how the robot asks for help"
var _customer_tab: String = CUSTOMER_TAB_LIVE
var _score: int = 0
var _success_count: int = 0
var _failed_count: int = 0
const SCORE_PER_SUCCESS := 2
const SCORE_PER_FAILURE := -6
const SCORE_PER_DRINK_SUCCESS := 1
const SCORE_PER_DRINK_FAILURE := -3
const SCORE_FAIL_THRESHOLD := -30
const SURVEY_PANEL_BASE_SIZE := Vector2(580.0, 300.0)
const SURVEY_PANEL_MARGIN := 24.0
const SURVEY_PANEL_OFFSET_X := 20.0
const SURVEY_QUESTION_Y_OFFSET := -34.0
const SURVEY_RESULT_Y_OFFSET := -20.0
var _score_game_over: bool = false
var _tutorial_started: bool = false
var _customer_history_page: int = 0
var _pending_day_notice: int = 0
var _initial_day_notice_shown: bool = false
var _formal_session_started: bool = false
var _trial_session_active: bool = false
var _trial_step: String = ""
var _trial_customer: Node2D = null
var _trial_food_task_id: String = ""
var _trial_drink_task_id: String = ""
var _trial_handoff_customer: Node2D = null
var _trial_handoff_task_id: String = ""
var _trial_handoff_request_id: String = ""
var _trial_handoff_preloading: bool = false
var _trial_handoff_ready: bool = false
var _trial_handoff_activate_when_ready: bool = false
var _trial_timeout_timer: Timer = null
var _trial_guide_layer: Control = null
var _trial_guide_dim: ColorRect = null
var _trial_guide_dim_top: ColorRect = null
var _trial_guide_dim_bottom: ColorRect = null
var _trial_guide_dim_left: ColorRect = null
var _trial_guide_dim_right: ColorRect = null
var _trial_guide_focus: PanelContainer = null
var _trial_guide_arrow: TextureRect = null
var _trial_guide_arrow_direction: String = "→"
var _trial_guide_message_panel: PanelContainer = null
var _trial_guide_message_label: RichTextLabel = null
var _trial_guide_target: Dictionary = {}
const CUSTOMER_HISTORY_PAGE_SIZE := 5
const TRIAL_SESSION_MAX_SEC := 90.0
const TRIAL_GUIDE_FOCUS_BORDER := Color(1.0, 0.93, 0.62, 1.0)
const TRIAL_GUIDE_ARROW_TEXTURE := preload("res://assets/icons/orders/right-arrow.png")
const TRIAL_GUIDE_ARROW_SIZE := Vector2(24.0, 24.0)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")

	if survey_panel:
		survey_panel.hide()

	_setup_survey_scale_buttons()
	survey_confirm.pressed.connect(_finish_survey_and_start)

	_setup_inventory_ui()
	_setup_dialogue_feed_ui()
	_setup_customer_orders_ui()
	_setup_player_dialogue_overlay_ui()
	_setup_tutorial_ui()
	_setup_trial_guide_ui()
	_setup_player_task_notice_audio()
	_set_gameplay_panels_visible(false)
	_connect_viewport_resize()
	_connect_help_signals()
	_connect_dialogue_feed_signals()
	_connect_robot_inventory()
	_connect_player_inventory()
	_connect_task_signals()
	_connect_time_signals()
	call_deferred("_setup_tipi_survey")

func _connect_viewport_resize() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)
	_recenter_survey_panel()

func _on_viewport_size_changed() -> void:
	_recenter_survey_panel()
	_update_gameplay_panel_layout()

func _recenter_survey_panel() -> void:
	if survey_panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var view_size: Vector2 = vp.get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	var target_w := clampf(SURVEY_PANEL_BASE_SIZE.x, 360.0, maxf(360.0, view_size.x - SURVEY_PANEL_MARGIN * 2.0))
	var target_h := clampf(SURVEY_PANEL_BASE_SIZE.y, 260.0, maxf(260.0, view_size.y - SURVEY_PANEL_MARGIN * 2.0))
	survey_panel.custom_minimum_size = Vector2(target_w, target_h)
	survey_panel.size = Vector2(target_w, target_h)
	var survey_y_offset := SURVEY_QUESTION_Y_OFFSET
	if survey_result != null and survey_result.visible:
		survey_y_offset = SURVEY_RESULT_Y_OFFSET
	survey_panel.position = (view_size - survey_panel.size) * 0.5 + Vector2(SURVEY_PANEL_OFFSET_X, survey_y_offset)

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
	inventory_panel.position = Vector2(SIDE_PANEL_MARGIN, 0.0)
	inventory_panel.grow_vertical = Control.GROW_DIRECTION_END

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	inventory_panel.add_theme_stylebox_override("panel", style)
	inventory_panel.clip_contents = true

	inventory_list = VBoxContainer.new()
	inventory_panel.add_child(inventory_list)

	var title = Label.new()
	title.text = "SYSTEM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 1.0))
	inventory_list.add_child(title)

	day_phase_label = Label.new()
	day_phase_label.text = "Day 1 | Morning"
	day_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_phase_label.add_theme_color_override("font_color", Color(0.94, 0.94, 0.94, 1.0))
	inventory_list.add_child(day_phase_label)

	var sep0 = HSeparator.new()
	inventory_list.add_child(sep0)

	var player_title = Label.new()
	player_title.text = "PLAYER"
	player_title.add_theme_color_override("font_color", Color(0.76, 0.95, 1.0, 1.0))
	inventory_list.add_child(player_title)

	score_label = Label.new()
	score_label.text = "Score: 0"
	score_label.add_theme_color_override("font_color", Color(0.86, 0.96, 1.0, 1.0))
	inventory_list.add_child(score_label)

	player_items_box = VBoxContainer.new()
	inventory_list.add_child(player_items_box)

	var player_task_title = Label.new()
	player_task_title.text = "Assigned Tasks"
	player_task_title.add_theme_color_override("font_color", Color(0.78, 0.94, 1.0, 1.0))
	inventory_list.add_child(player_task_title)

	player_tasks_box = VBoxContainer.new()
	inventory_list.add_child(player_tasks_box)

	var sep = HSeparator.new()
	inventory_list.add_child(sep)

	var robot_title = Label.new()
	robot_title.text = "ROBOT"
	robot_title.add_theme_color_override("font_color", Color(0.76, 0.95, 1.0, 1.0))
	inventory_list.add_child(robot_title)

	battery_label = Label.new()
	battery_label.text = "Battery: --%"
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

	var measured_panel_w: float = maxf(216.0, inventory_panel.get_combined_minimum_size().x + 6.0)
	var base_panel_w: float = maxf(measured_panel_w, DIALOGUE_PANEL_WIDTH)
	_left_panel_width = maxf(200.0, base_panel_w - SYSTEM_PANEL_WIDTH_REDUCTION)
	inventory_panel.custom_minimum_size = Vector2(_left_panel_width, 0.0)

func _setup_dialogue_feed_ui() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.name = "DialogueFeedPanel"
	add_child(dialogue_panel)
	dialogue_panel.position = Vector2(SIDE_PANEL_MARGIN, 0.0)
	dialogue_panel.grow_vertical = Control.GROW_DIRECTION_END
	dialogue_panel.custom_minimum_size = Vector2(maxf(DIALOGUE_PANEL_WIDTH, _left_panel_width), 210)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	dialogue_panel.add_theme_stylebox_override("panel", style)
	dialogue_panel.clip_contents = true

	dialogue_list = VBoxContainer.new()
	dialogue_panel.add_child(dialogue_list)

	var dialogue_title := Label.new()
	dialogue_title.text = "DIALOGUE"
	dialogue_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_title.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 1.0))
	dialogue_list.add_child(dialogue_title)

	dialogue_log = RichTextLabel.new()
	dialogue_log.custom_minimum_size = Vector2(maxf(170.0, dialogue_panel.custom_minimum_size.x - 30.0), 160)
	dialogue_log.bbcode_enabled = false
	dialogue_log.scroll_active = true
	dialogue_log.fit_content = false
	dialogue_list.add_child(dialogue_log)
	_update_gameplay_panel_layout()

func _setup_customer_orders_ui() -> void:
	customer_panel = PanelContainer.new()
	customer_panel.name = "CustomerOrdersPanel"
	add_child(customer_panel)
	customer_panel.position = Vector2(SIDE_PANEL_MARGIN, 0.0)
	customer_panel.grow_vertical = Control.GROW_DIRECTION_END
	customer_panel.custom_minimum_size = Vector2(maxf(DIALOGUE_PANEL_WIDTH, _left_panel_width), 180)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	customer_panel.add_theme_stylebox_override("panel", style)
	customer_panel.clip_contents = true

	customer_panel_list = VBoxContainer.new()
	customer_panel.add_child(customer_panel_list)

	var customer_title = Label.new()
	customer_title.text = "Customer Orders"
	customer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	customer_title.add_theme_color_override("font_color", Color(0.76, 0.95, 1.0, 1.0))
	customer_panel_list.add_child(customer_title)

	customer_tab_buttons = HBoxContainer.new()
	customer_panel_list.add_child(customer_tab_buttons)

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
	customer_panel_list.add_child(customer_items_box)

	customer_history_pager = HBoxContainer.new()
	customer_history_pager.alignment = BoxContainer.ALIGNMENT_BEGIN
	customer_history_pager.add_theme_constant_override("separation", 8)
	customer_history_pager.visible = false
	customer_panel_list.add_child(customer_history_pager)

	customer_history_prev_btn = Button.new()
	customer_history_prev_btn.text = "Prev"
	customer_history_prev_btn.pressed.connect(func():
		_customer_history_page = maxi(_customer_history_page - 1, 0)
		_update_customer_panel()
	)
	customer_history_pager.add_child(customer_history_prev_btn)

	customer_history_page_label = Label.new()
	customer_history_page_label.text = "1/1"
	customer_history_pager.add_child(customer_history_page_label)

	customer_history_next_btn = Button.new()
	customer_history_next_btn.text = "Next"
	customer_history_next_btn.pressed.connect(func():
		_customer_history_page += 1
		_update_customer_panel()
	)
	customer_history_pager.add_child(customer_history_next_btn)

	_update_gameplay_panel_layout()

func _setup_player_dialogue_overlay_ui() -> void:
	help_prompt_stack = VBoxContainer.new()
	help_prompt_stack.name = "HelpPromptStack"
	help_prompt_stack.visible = false
	help_prompt_stack.add_theme_constant_override("separation", PLAYER_DIALOGUE_STACK_GAP)
	add_child(help_prompt_stack)

	player_dialogue_info_stack = VBoxContainer.new()
	player_dialogue_info_stack.name = "PlayerDialogueInfoStack"
	player_dialogue_info_stack.visible = false
	player_dialogue_info_stack.add_theme_constant_override("separation", PLAYER_DIALOGUE_STACK_GAP)
	add_child(player_dialogue_info_stack)

	player_dialogue_overlay_backdrop = ColorRect.new()
	player_dialogue_overlay_backdrop.name = "PlayerDialogueOverlayBackdrop"
	player_dialogue_overlay_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_dialogue_overlay_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_dialogue_overlay_backdrop.color = Color(0.02, 0.03, 0.05, 0.42)
	player_dialogue_overlay_backdrop.visible = false
	add_child(player_dialogue_overlay_backdrop)

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
	player_dialogue_overlay.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH, 0.0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	player_dialogue_overlay.add_child(vbox)

	player_dialogue_overlay_label = RichTextLabel.new()
	player_dialogue_overlay_label.bbcode_enabled = false
	player_dialogue_overlay_label.fit_content = true
	player_dialogue_overlay_label.scroll_active = false
	player_dialogue_overlay_label.selection_enabled = false
	player_dialogue_overlay_label.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH - 28.0, 0.0)
	vbox.add_child(player_dialogue_overlay_label)

	player_dialogue_overlay_button_spacer = Control.new()
	player_dialogue_overlay_button_spacer.custom_minimum_size = Vector2(0.0, 0.0)
	vbox.add_child(player_dialogue_overlay_button_spacer)

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

func _connect_task_signals() -> void:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null:
		return
	if board.has_signal("task_updated") and not board.task_updated.is_connected(_on_task_updated):
		board.task_updated.connect(_on_task_updated)
	if board.has_signal("task_created") and not board.task_created.is_connected(_on_task_created):
		board.task_created.connect(_on_task_created)
	if board.has_signal("task_completed") and not board.task_completed.is_connected(_on_task_completed):
		board.task_completed.connect(_on_task_completed)
	if board.has_signal("task_failed") and not board.task_failed.is_connected(_on_task_failed):
		board.task_failed.connect(_on_task_failed)
	_refresh_score_label()

func _connect_time_signals() -> void:
	var time_mgr = get_node_or_null("/root/GameManager/TimeManager")
	if time_mgr == null:
		return
	if time_mgr.has_signal("day_changed") and not time_mgr.day_changed.is_connected(_on_day_changed_notice):
		time_mgr.day_changed.connect(_on_day_changed_notice)
	if time_mgr.has_signal("time_changed") and not time_mgr.time_changed.is_connected(_refresh_day_phase_label):
		time_mgr.time_changed.connect(_refresh_day_phase_label)
	if time_mgr.has_signal("period_changed") and not time_mgr.period_changed.is_connected(_on_period_changed_label):
		time_mgr.period_changed.connect(_on_period_changed_label)
	call_deferred("_cache_initial_day_notice")
	call_deferred("_refresh_day_phase_label")

func _cache_initial_day_notice() -> void:
	var time_mgr = get_node_or_null("/root/GameManager/TimeManager")
	if time_mgr == null:
		return
	_pending_day_notice = int(time_mgr.get("current_day"))

func _refresh_day_phase_label(_hour: int = -1, _minute: int = -1) -> void:
	if day_phase_label == null:
		return
	if _trial_session_active or not _formal_session_started:
		day_phase_label.text = "Trial Session"
		return
	var time_mgr = get_node_or_null("/root/GameManager/TimeManager")
	if time_mgr == null:
		return
	var day := int(time_mgr.get("current_day"))
	var period := str(time_mgr.call("get_period_name")).capitalize()
	day_phase_label.text = "Day %d | %s" % [maxi(day, 1), period]

func _on_period_changed_label(_period_name: String, _is_peak: bool) -> void:
	_refresh_day_phase_label()

func _on_day_changed_notice(day: int) -> void:
	if day <= 0:
		return
	if not _formal_session_started:
		_pending_day_notice = day
		return
	_initial_day_notice_shown = true
	var message := "You have entered Day %d." % day
	if day == 1:
		message = "The formal session is starting. You have entered Day 1."
	_show_player_dialogue_overlay("System", message, "system")

func _on_task_created(task: Dictionary) -> void:
	var payload: Dictionary = task.get("payload", {})
	if _trial_session_active and _is_trial_customer_task(payload):
		var order_kind := str(payload.get("order_kind", "food"))
		if order_kind == "food" and _trial_step == "await_food_order":
			_trial_food_task_id = str(task.get("id", ""))
			_trial_step = "await_drink_order"
			call_deferred("_ensure_trial_drink_request")
		elif order_kind == "drink":
			_trial_drink_task_id = str(task.get("id", ""))
			_show_trial_guide_for_drink_request()
			_trial_step = "await_take_order"
	elif _trial_session_active and _trial_handoff_preloading and _is_trial_handoff_customer_task(payload):
		if str(payload.get("order_kind", "food")) == "food":
			_trial_handoff_task_id = str(task.get("id", ""))
			call_deferred("_prepare_trial_handoff_task", _trial_handoff_task_id)
	if str(payload.get("order_kind", "")) != "drink":
		return
	if str(task.get("assigned_to", "")).strip_edges() != "":
		return
	_play_new_order_notice()

func _on_task_updated(task: Dictionary) -> void:
	if not _trial_session_active:
		return
	if _trial_handoff_task_id != "" and str(task.get("id", "")) == _trial_handoff_task_id:
		var board_handoff = get_node_or_null("/root/TaskBoard")
		var step_name_handoff := ""
		if board_handoff and board_handoff.has_method("get_current_step_name"):
			step_name_handoff = str(board_handoff.get_current_step_name(_trial_handoff_task_id))
		var assignee_handoff := str(task.get("assigned_to", ""))
		if _trial_step == "await_handoff_accept" and assignee_handoff == "player" and step_name_handoff == "DELIVER_AND_SERVE":
			_trial_step = "await_handoff_delivery"
			call_deferred("_show_trial_guide_for_handoff_delivery")
		return
	if str(task.get("id", "")) != _trial_drink_task_id or _trial_drink_task_id == "":
		return
	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_current_step_name"):
		return
	var step_name := str(board.get_current_step_name(_trial_drink_task_id))
	var assignee := str(task.get("assigned_to", ""))
	if _trial_step == "await_take_order" and assignee == "player" and step_name == "PICKUP_FROM_KITCHEN":
		_trial_step = "await_pickup"
		_show_trial_guide_for_drink_pickup()
	elif (_trial_step == "await_pickup" or _trial_step == "await_delivery") and step_name == "DELIVER_AND_SERVE":
		_trial_step = "await_delivery"
		_show_trial_guide_for_drink_delivery()
		call_deferred("_ensure_trial_handoff_preload")

func _on_task_completed(task: Dictionary) -> void:
	if _trial_session_active:
		var completed_id := str(task.get("id", ""))
		if completed_id == _trial_food_task_id:
			var robot = _trial_robot()
			if robot != null and robot.has_method("set_trial_stationary_pause"):
				robot.call("set_trial_stationary_pause", true)
		elif completed_id == _trial_drink_task_id:
			_trial_step = "await_delegation"
			call_deferred("_activate_trial_handoff_request")
		elif _trial_handoff_task_id != "" and completed_id == _trial_handoff_task_id:
			call_deferred("_finish_trial_session", true)
		return
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
	if _trial_session_active:
		var failed_id := str(task.get("id", ""))
		if failed_id == _trial_drink_task_id or (_trial_handoff_task_id != "" and failed_id == _trial_handoff_task_id):
			call_deferred("_finish_trial_session", false)
		return
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
		score_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45, 1.0))

func _check_score_game_over() -> void:
	if _score_game_over:
		return
	if _score > SCORE_FAIL_THRESHOLD:
		return
	_score_game_over = true
	get_tree().paused = true
	_popup_mode = POPUP_MODE_GAME_OVER
	_show_player_dialogue_prompt(
		"Game Over",
		"Score reached %d (threshold %d).\nShift failed." % [_score, SCORE_FAIL_THRESHOLD],
		["Retry", "Quit"],
		false
	)

func _on_game_over_retry() -> void:
	get_tree().paused = false
	var board = get_node_or_null("/root/TaskBoard")
	if board and board.has_method("reset_all"):
		board.reset_all()
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr and help_mgr.has_method("reset_all"):
		help_mgr.reset_all()
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("reset_run"):
		game_mgr.reset_run()
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

	_clear_dynamic_children(robot_items_box)

	var holding = Label.new()
	holding.text = "Holding (%d/%d):" % [items.size(), _get_robot_capacity()]
	holding.add_theme_color_override("font_color", Color(0.80, 0.94, 1.0, 1.0))
	robot_items_box.add_child(holding)

	if items.is_empty():
		_add_blank_row(robot_items_box)
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

	_clear_dynamic_children(player_items_box)

	var holding = Label.new()
	holding.text = "Holding (%d/%d):" % [items.size(), _get_player_capacity()]
	holding.add_theme_color_override("font_color", Color(0.80, 0.94, 1.0, 1.0))
	player_items_box.add_child(holding)

	if items.is_empty():
		_add_blank_row(player_items_box)
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
	_update_trial_guide_overlay()

func _update_gameplay_panel_layout() -> void:
	if inventory_panel == null or dialogue_panel == null or customer_panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var view_size := vp.get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	var system_panel_w: float = maxf(_left_panel_width, inventory_panel.size.x)
	var dialogue_panel_w: float = maxf(DIALOGUE_PANEL_WIDTH, dialogue_panel.size.x)
	var center_x: float = view_size.x * 0.5
	var gameplay_top_y: float = maxf(0.0, (view_size.y - GAMEPLAY_REFERENCE_HEIGHT) * 0.5) + GAMEPLAY_TOP_OFFSET
	var system_x: float = maxf(
		SIDE_PANEL_MARGIN,
		center_x - GAMEPLAY_BAND_WIDTH * 0.5 - GAMEPLAY_SIDE_GAP - _left_panel_width + SYSTEM_PANEL_X_OFFSET
	)
	var dialogue_x: float = minf(
		view_size.x - SIDE_PANEL_MARGIN - dialogue_panel_w,
		center_x + GAMEPLAY_BAND_WIDTH * 0.5 + GAMEPLAY_SIDE_GAP
	)
	inventory_panel.position = Vector2(system_x, gameplay_top_y)
	dialogue_panel.position = Vector2(dialogue_x, gameplay_top_y)
	var system_panel_h: float = 20.0
	if inventory_list != null:
		system_panel_h += inventory_list.get_combined_minimum_size().y
	var dialogue_panel_h: float = 20.0
	if dialogue_list != null:
		dialogue_panel_h += dialogue_list.get_combined_minimum_size().y
	dialogue_panel_h = maxf(dialogue_panel_h, 210.0)
	var customer_panel_h: float = 20.0
	if customer_panel_list != null:
		customer_panel_h += customer_panel_list.get_combined_minimum_size().y
	customer_panel_h = maxf(customer_panel_h, 160.0)
	inventory_panel.custom_minimum_size.y = system_panel_h
	inventory_panel.size.y = system_panel_h
	dialogue_panel.custom_minimum_size.y = dialogue_panel_h
	dialogue_panel.size.y = dialogue_panel_h
	customer_panel.custom_minimum_size.x = dialogue_panel_w
	customer_panel.custom_minimum_size.y = customer_panel_h
	customer_panel.size = Vector2(dialogue_panel_w, customer_panel_h)
	customer_panel.position = Vector2(dialogue_x, dialogue_panel.position.y + dialogue_panel_h + 12.0)
	var centered_x: float = (view_size.x - PLAYER_DIALOGUE_OVERLAY_WIDTH) * 0.5
	var stack_origin_y: float = gameplay_top_y + PLAYER_DIALOGUE_OVERLAY_Y_OFFSET
	var stack_y: float = stack_origin_y
	if help_prompt_stack:
		help_prompt_stack.position = Vector2(centered_x, stack_origin_y)
		help_prompt_stack.custom_minimum_size.x = PLAYER_DIALOGUE_OVERLAY_WIDTH
		if help_prompt_stack.visible:
			var help_h := maxf(help_prompt_stack.size.y, help_prompt_stack.get_combined_minimum_size().y)
			stack_y += help_h + PLAYER_DIALOGUE_STACK_GAP
	if player_dialogue_overlay:
		var overlay_w := player_dialogue_overlay.custom_minimum_size.x
		player_dialogue_overlay.position = Vector2((view_size.x - overlay_w) * 0.5, stack_y)
		if player_dialogue_overlay.visible:
			var prompt_h := maxf(player_dialogue_overlay.size.y, player_dialogue_overlay.get_combined_minimum_size().y)
			stack_y += prompt_h + PLAYER_DIALOGUE_STACK_GAP
	if player_dialogue_info_stack:
		player_dialogue_info_stack.position = Vector2(centered_x, stack_y)
		player_dialogue_info_stack.custom_minimum_size.x = PLAYER_DIALOGUE_OVERLAY_WIDTH
	if tutorial_panel:
		tutorial_panel.custom_minimum_size = Vector2(TUTORIAL_PANEL_WIDTH, TUTORIAL_PANEL_MIN_HEIGHT)
		tutorial_panel.size = tutorial_panel.custom_minimum_size
		tutorial_panel.position = Vector2((view_size.x - tutorial_panel.size.x) * 0.5, maxf(56.0, (view_size.y - tutorial_panel.size.y) * 0.5))
	if tutorial_toggle_button:
		tutorial_toggle_button.size = Vector2(TUTORIAL_TOGGLE_SIZE, TUTORIAL_TOGGLE_SIZE)
		var panel_size := inventory_panel.size
		if panel_size.x <= 0.0 or panel_size.y <= 0.0:
			panel_size = inventory_panel.get_combined_minimum_size()
		tutorial_toggle_button.position = Vector2(
			inventory_panel.position.x + panel_size.x - TUTORIAL_TOGGLE_SIZE * 0.55 - 36.0,
			inventory_panel.position.y - TUTORIAL_TOGGLE_SIZE * 0.2 + 20.0
		)

func _update_robot_task_panel() -> void:
	if robot_tasks_box == null:
		return
	_clear_dynamic_children(robot_tasks_box)

	var board = get_node_or_null("/root/TaskBoard")
	var robots := get_tree().get_nodes_in_group("robot")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee") or robots.is_empty():
		_add_blank_row(robot_tasks_box)
		return

	var assignee := str(robots[0].name)
	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee(assignee)
	if tasks.is_empty():
		_add_blank_row(robot_tasks_box)
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
		battery_label.text = "Battery: --%"
		return
	var robot = robots[0]
	var level := int(round(float(robot.get("battery_level"))))
	var mode := str(robot.get("_battery_mode"))
	if mode == "" or mode == "Null":
		mode = "normal"
	battery_label.text = "Battery: %d%%" % clampi(level, 0, 100)

	if mode == "emergency":
		battery_label.add_theme_color_override("font_color", Color(1.0, 0.52, 0.52, 1.0))
	elif mode == "conserve":
		battery_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45, 1.0))
	else:
		battery_label.add_theme_color_override("font_color", Color(0.78, 1.0, 0.78, 1.0))

func _update_customer_panel() -> void:
	if customer_items_box == null:
		return

	_clear_dynamic_children(customer_items_box)

	if _customer_tab == CUSTOMER_TAB_HISTORY:
		if customer_history_pager:
			customer_history_pager.visible = true
		_update_customer_history_panel()
		return

	var customers := get_tree().get_nodes_in_group("customer")
	if customers.is_empty():
		if customer_history_pager:
			customer_history_pager.visible = false
		_add_blank_row(customer_items_box)
		return

	var board = get_node_or_null("/root/TaskBoard")
	var now_ms := Time.get_ticks_msec()
	var customer_lines: Array[Label] = []
	for n in customers:
		if not (n is Node):
			continue
		var cnode := n as Node

		var seat := ""
		if "current_seat" in cnode:
			seat = str(cnode.get("current_seat"))
		if seat == "":
			seat = "-"

		var open_tasks: Array[Dictionary] = []
		if board and board.has_method("get_open_tasks_for_customer"):
			open_tasks = board.get_open_tasks_for_customer(cnode.get_instance_id())
		if open_tasks.is_empty():
			continue

		var table_text := _friendly_table_name(seat)
		var food_task := _task_by_kind(open_tasks, "food")
		var drink_task := _task_by_kind(open_tasks, "drink")
		if not food_task.is_empty():
			var food_line := Label.new()
			var food_parts: Array[String] = [table_text]
			food_parts.append(_compact_item_name(food_task.get("payload", {})))
			food_parts.append(_countdown_text_from_task(food_task, now_ms))
			food_parts.append("Waiting")
			food_line.text = " | ".join(food_parts)
			if _countdown_text_from_task(food_task, now_ms) == "0s":
				food_line.add_theme_color_override("font_color", Color(1.0, 0.52, 0.52, 1.0))
			customer_lines.append(food_line)

		if not drink_task.is_empty():
			var drink_line := Label.new()
			var drink_parts: Array[String] = [table_text]
			drink_parts.append(_compact_item_name(drink_task.get("payload", {})))
			drink_parts.append(_countdown_text_from_task(drink_task, now_ms))
			drink_parts.append("Waiting")
			drink_line.text = " | ".join(drink_parts)
			if _countdown_text_from_task(drink_task, now_ms) == "0s":
				drink_line.add_theme_color_override("font_color", Color(1.0, 0.52, 0.52, 1.0))
			customer_lines.append(drink_line)

	if customer_lines.is_empty():
		if customer_history_pager:
			customer_history_pager.visible = false
		_add_blank_row(customer_items_box)
		return

	var total_pages := maxi(1, int(ceili(float(customer_lines.size()) / float(CUSTOMER_HISTORY_PAGE_SIZE))))
	_customer_history_page = clampi(_customer_history_page, 0, total_pages - 1)
	var start_index := _customer_history_page * CUSTOMER_HISTORY_PAGE_SIZE
	var end_index := mini(start_index + CUSTOMER_HISTORY_PAGE_SIZE, customer_lines.size())
	if customer_history_pager:
		customer_history_pager.visible = total_pages > 1
	if customer_history_prev_btn:
		customer_history_prev_btn.disabled = (_customer_history_page <= 0)
	if customer_history_next_btn:
		customer_history_next_btn.disabled = (_customer_history_page >= total_pages - 1)
	if customer_history_page_label:
		customer_history_page_label.text = "%d/%d" % [_customer_history_page + 1, total_pages]
	for i in range(customer_lines.size()):
		var line := customer_lines[i]
		if i >= start_index and i < end_index:
			customer_items_box.add_child(line)
		elif is_instance_valid(line):
			line.free()

func _update_customer_history_panel() -> void:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_all_tasks"):
		if customer_history_pager:
			customer_history_pager.visible = false
		_add_blank_row(customer_items_box)
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
		if customer_history_pager:
			customer_history_pager.visible = false
		_add_blank_row(customer_items_box)
		return

	ended.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := maxi(int(a.get("completed_at_ms", 0)), int(a.get("failed_at_ms", 0)))
		var tb := maxi(int(b.get("completed_at_ms", 0)), int(b.get("failed_at_ms", 0)))
		return ta > tb
	)

	var total_pages := maxi(1, int(ceili(float(ended.size()) / float(CUSTOMER_HISTORY_PAGE_SIZE))))
	_customer_history_page = clampi(_customer_history_page, 0, total_pages - 1)
	var start_index := _customer_history_page * CUSTOMER_HISTORY_PAGE_SIZE
	var end_index := mini(start_index + CUSTOMER_HISTORY_PAGE_SIZE, ended.size())
	if customer_history_pager:
		customer_history_pager.visible = total_pages > 1
	if customer_history_prev_btn:
		customer_history_prev_btn.disabled = (_customer_history_page <= 0)
	if customer_history_next_btn:
		customer_history_next_btn.disabled = (_customer_history_page >= total_pages - 1)
	if customer_history_page_label:
		customer_history_page_label.text = "%d/%d" % [_customer_history_page + 1, total_pages]

	for i in range(start_index, end_index):
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
	if _customer_tab != tab:
		_customer_history_page = 0
	_customer_tab = tab
	if customer_live_btn:
		customer_live_btn.button_pressed = (_customer_tab == CUSTOMER_TAB_LIVE)
	if customer_history_btn:
		customer_history_btn.button_pressed = (_customer_tab == CUSTOMER_TAB_HISTORY)
	_update_customer_panel()

func _update_player_task_panel() -> void:
	if player_tasks_box == null:
		return
	_clear_dynamic_children(player_tasks_box)

	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee"):
		_add_blank_row(player_tasks_box)
		return

	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee("player")
	_track_player_live_task_ids(tasks)
	if tasks.is_empty():
		_add_blank_row(player_tasks_box)
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

func _setup_player_task_notice_audio() -> void:
	_player_task_notice_player = AudioStreamPlayer.new()
	_player_task_notice_player.name = "PlayerTaskNotice"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.25
	_player_task_notice_player.stream = generator
	_player_task_notice_player.bus = &"Master"
	add_child(_player_task_notice_player)

func _add_blank_row(container: Container, min_height: float = 18.0) -> void:
	if container == null:
		return
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, min_height)
	container.add_child(spacer)

func _clear_dynamic_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.free()

func shutdown_immediately() -> void:
	_help_prompt_cards.clear()
	_player_dialogue_info_cards.clear()
	_last_help_bubble_utterance_by_request.clear()
	_shown_help_system_notice_by_request.clear()
	_auto_open_in_flight.clear()
	if robot_items_box:
		_clear_dynamic_children(robot_items_box)
	if robot_tasks_box:
		_clear_dynamic_children(robot_tasks_box)
	if player_items_box:
		_clear_dynamic_children(player_items_box)
	if player_tasks_box:
		_clear_dynamic_children(player_tasks_box)
	if customer_items_box:
		_clear_dynamic_children(customer_items_box)
	if survey_options:
		_clear_dynamic_children(survey_options)
	if help_prompt_stack:
		_clear_dynamic_children(help_prompt_stack)
	if player_dialogue_info_stack:
		_clear_dynamic_children(player_dialogue_info_stack)
	if dialogue_log:
		dialogue_log.clear()
	if player_dialogue_overlay_label:
		player_dialogue_overlay_label.clear()
	if tutorial_body:
		tutorial_body.clear()
	_hide_player_dialogue_overlay()

func _track_player_live_task_ids(tasks: Array[Dictionary]) -> void:
	var current_ids := {}
	for task in tasks:
		var task_id := str(task.get("id", "")).strip_edges()
		if task_id != "":
			current_ids[task_id] = true

	if not _player_task_notice_initialized:
		_last_player_live_task_ids = current_ids
		_player_task_notice_initialized = true
		return

	for task_id in current_ids.keys():
		if not _last_player_live_task_ids.has(task_id):
			_play_player_task_accept_notice()
			break

	_last_player_live_task_ids = current_ids

func _play_new_order_notice() -> void:
	_play_notice_tones([
		{"freq": 1046.5, "duration": 0.10, "amp": 0.18}
	])

func _play_player_task_accept_notice() -> void:
	_play_notice_tones([
		{"freq": 880.0, "duration": 0.08, "amp": 0.18},
		{"freq": 1174.7, "duration": 0.11, "amp": 0.20}
	])

func _play_notice_tones(tones: Array[Dictionary]) -> void:
	if _player_task_notice_player == null:
		return
	var stream := _player_task_notice_player.stream
	if stream == null or not (stream is AudioStreamGenerator):
		return

	_player_task_notice_player.stop()
	_player_task_notice_player.play()
	var playback = _player_task_notice_player.get_stream_playback()
	if playback == null or not (playback is AudioStreamGeneratorPlayback):
		return

	var generator := stream as AudioStreamGenerator
	var gen_playback := playback as AudioStreamGeneratorPlayback
	var mix_rate := float(generator.mix_rate)
	for tone in tones:
		var freq := float(tone.get("freq", 1046.5))
		var duration_sec := float(tone.get("duration", 0.10))
		var amplitude := float(tone.get("amp", 0.18))
		var frame_count := int(duration_sec * mix_rate)
		for i in range(frame_count):
			var t := float(i) / mix_rate
			var envelope := exp(-18.0 * t)
			var sample := sin(TAU * freq * t) * amplitude * envelope
			gen_playback.push_frame(Vector2(sample, sample))
		var gap_frames := int(0.035 * mix_rate)
		for _j in range(gap_frames):
			gen_playback.push_frame(Vector2.ZERO)

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

func _friendly_table_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	if s.begins_with("seat"):
		var suffix := s.substr(4, s.length() - 4)
		if suffix != "":
			return "Table " + suffix
	if s == "" or s == "-":
		return "Table -"
	return raw

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
	_maybe_append_help_system_notice(request)
	_show_or_update_help_request_card(request)
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

	if _popup_mode == POPUP_MODE_TRIAL_COMPLETE:
		if response == "accept":
			_popup_mode = POPUP_MODE_NONE
			if player_dialogue_overlay:
				player_dialogue_overlay.visible = false
			_begin_formal_session()
		return

func _on_help_request_updated(request: Dictionary) -> void:
	if request.is_empty():
		return
	var rid = str(request.get("id", ""))
	var payload: Dictionary = request.get("payload", {})
	if _trial_session_active and _trial_handoff_task_id != "" and str(payload.get("task_id", "")) == _trial_handoff_task_id:
		_trial_handoff_request_id = rid

	var status = str(request.get("status", ""))
	if status == "accepted":
		if _trial_session_active and rid == _trial_handoff_request_id and _trial_step == "await_handoff_accept":
			_trial_step = "await_handoff_delivery"
			call_deferred("_show_trial_guide_for_handoff_delivery")
		_remove_help_request_card(rid)
	elif status == "cooldown":
		_remove_help_request_card(rid)
	elif status == "pending":
		_maybe_append_help_system_notice(request)
		if _has_help_request_card(rid):
			_show_or_update_help_request_card(request)
		else:
			_auto_open_help_request(request)
		if _trial_session_active and rid == _trial_handoff_request_id and _trial_step == "await_handoff_accept":
			call_deferred("_show_trial_guide_for_handoff_accept")

func _on_help_request_created(request: Dictionary) -> void:
	if request.is_empty():
		return
	if str(request.get("status", "")) != "pending":
		return
	var payload: Dictionary = request.get("payload", {})
	if _trial_session_active and _trial_handoff_task_id != "" and str(payload.get("task_id", "")) == _trial_handoff_task_id:
		_trial_handoff_request_id = str(request.get("id", ""))
	_maybe_append_help_system_notice(request)
	_auto_open_help_request(request)
	if _trial_session_active and str(request.get("id", "")) == _trial_handoff_request_id:
		call_deferred("_show_trial_guide_for_handoff_accept")

func _on_help_request_resolved(request: Dictionary) -> void:
	if request.is_empty():
		return
	var rid = str(request.get("id", ""))
	if _trial_session_active and rid == _trial_handoff_request_id:
		_trial_handoff_request_id = ""
	_remove_help_request_card(rid)

func show_kitchen_pick_popup(options: Array[String], title: String = "Kitchen Pickup") -> void:
	if options.size() < 3:
		return
	if _trial_session_active and _trial_step == "await_pickup":
		_hide_trial_guide()
	if player_dialogue_overlay_backdrop:
		player_dialogue_overlay_backdrop.visible = true
	_popup_mode = POPUP_MODE_KITCHEN_PICK
	_kitchen_pick_options.clear()
	for i in range(3):
		_kitchen_pick_options.append(str(options[i]))
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
	if _trial_session_active and _trial_step == "await_pickup":
		call_deferred("_show_trial_guide_for_drink_pickup")

func is_kitchen_pick_popup_visible() -> bool:
	return _popup_mode == POPUP_MODE_KITCHEN_PICK and player_dialogue_overlay != null and player_dialogue_overlay.visible

func is_help_request_popup_visible() -> bool:
	return help_prompt_stack != null and help_prompt_stack.visible and not _help_prompt_cards.is_empty()

func show_quick_notice(text: String) -> void:
	_append_feed_line("System", text)

func show_kitchen_pick_feedback(item_name: String, success: bool) -> void:
	if _popup_mode != POPUP_MODE_KITCHEN_PICK:
		return
	var wanted := item_name.strip_edges().to_lower()
	if wanted == "":
		return
	var idx := _kitchen_pick_options.find(wanted)
	if idx < 0:
		return
	var button: Button = null
	match idx:
		0:
			button = player_dialogue_overlay_accept_btn
		1:
			button = player_dialogue_overlay_decline_btn
		2:
			button = player_dialogue_overlay_later_btn
	_flash_kitchen_pick_button(button, success)

func _reset_help_buttons() -> void:
	if player_dialogue_overlay_accept_btn:
		player_dialogue_overlay_accept_btn.text = "Accept"
	if player_dialogue_overlay_decline_btn:
		player_dialogue_overlay_decline_btn.text = "Decline"
	if player_dialogue_overlay_later_btn:
		player_dialogue_overlay_later_btn.text = "Later"
	if player_dialogue_overlay_later_btn:
		player_dialogue_overlay_later_btn.visible = true

func _flash_kitchen_pick_button(button: Button, success: bool) -> void:
	if button == null or not is_instance_valid(button):
		return
	var flash_token := int(button.get_meta("kitchen_flash_token", 0)) + 1
	button.set_meta("kitchen_flash_token", flash_token)
	var flash_style := StyleBoxFlat.new()
	flash_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	flash_style.border_width_left = 2
	flash_style.border_width_top = 2
	flash_style.border_width_right = 2
	flash_style.border_width_bottom = 2
	flash_style.border_color = Color(0.40, 0.86, 0.48, 1.0) if success else Color(0.92, 0.34, 0.34, 1.0)
	flash_style.corner_radius_top_left = 8
	flash_style.corner_radius_top_right = 8
	flash_style.corner_radius_bottom_left = 8
	flash_style.corner_radius_bottom_right = 8
	button.add_theme_stylebox_override("normal", flash_style)
	button.add_theme_stylebox_override("hover", flash_style)
	button.add_theme_stylebox_override("pressed", flash_style)
	button.add_theme_stylebox_override("focus", flash_style)
	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(Callable(self, "_clear_kitchen_pick_button_flash").bind(button.get_instance_id(), flash_token))

func _setup_survey_scale_buttons() -> void:
	if survey_options == null:
		return
	for child in survey_options.get_children():
		child.queue_free()
	_survey_scale_buttons.clear()
	for i in range(1, 8):
		var button := Button.new()
		button.custom_minimum_size = Vector2(64, 44)
		button.text = str(i)
		button.pressed.connect(_on_tipi_scale_pressed.bind(i))
		survey_options.add_child(button)
		_survey_scale_buttons.append(button)

func _on_tipi_scale_pressed(response_value: int) -> void:
	_choose_tipi(response_value)

func _setup_tipi_survey() -> void:
	_tipi_questions = [
		{"item": 1, "text": "I see myself as: Extraverted, enthusiastic."},
		{"item": 2, "text": "I see myself as: Critical, quarrelsome."},
		{"item": 3, "text": "I see myself as: Dependable, self-disciplined."},
		{"item": 4, "text": "I see myself as: Anxious, easily upset."},
		{"item": 5, "text": "I see myself as: Open to new experiences, complex."},
		{"item": 6, "text": "I see myself as: Reserved, quiet."},
		{"item": 7, "text": "I see myself as: Sympathetic, warm."},
		{"item": 8, "text": "I see myself as: Disorganized, careless."},
		{"item": 9, "text": "I see myself as: Calm, emotionally stable."},
		{"item": 10, "text": "I see myself as: Conventional, uncreative."},
	]

	var profile = get_node_or_null("/root/PlayerProfile")
	if profile and profile.has_method("has_tipi") and bool(profile.has_tipi()):
		_show_tutorial_before_game()
		return

	await _stabilize_player_camera_before_survey()

	_tipi_index = 0
	_tipi_responses.clear()

	get_tree().paused = true
	_recenter_survey_panel()
	survey_panel.show()
	if survey_result_group_spacer:
		survey_result_group_spacer.hide()
	if survey_result_group:
		survey_result_group.hide()
	if survey_result_spacer:
		survey_result_spacer.hide()
	survey_confirm.hide()
	if survey_question_title:
		survey_question_title.show()
	if survey_scale_title:
		survey_scale_title.show()
	if survey_scale_spacer:
		survey_scale_spacer.show()
	if survey_scale_hint:
		survey_scale_hint.show()
	for button in _survey_scale_buttons:
		button.show()
	_refresh_tipi_question()

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

func _stabilize_player_camera_before_survey() -> void:
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

func _refresh_tipi_question() -> void:
	if _tipi_index < 0 or _tipi_index >= _tipi_questions.size():
		return
	var q: Dictionary = _tipi_questions[_tipi_index]
	survey_question.custom_minimum_size = Vector2(SURVEY_PANEL_BASE_SIZE.x - 48.0, 48)
	survey_question.text = str(q.get("text", ""))
	if survey_question_title:
		survey_question_title.text = "[b]Questions[/b] (%d/%d)" % [_tipi_index + 1, _tipi_questions.size()]
	if survey_scale_title:
		survey_scale_title.text = "[b]Scale Guide[/b]"
	if survey_scale_hint:
		survey_scale_hint.text = "1 = disagree strongly\n4 = neutral\n7 = agree strongly"
	if survey_result_group_spacer:
		survey_result_group_spacer.hide()
	if survey_result_group:
		survey_result_group.hide()

func _choose_tipi(response_value: int) -> void:
	if _tipi_index < 0 or _tipi_index >= _tipi_questions.size():
		return
	var q: Dictionary = _tipi_questions[_tipi_index]
	var item_index := int(q.get("item", 0))
	if item_index > 0:
		_tipi_responses[item_index] = clampi(response_value, 1, 7)
	_tipi_index += 1

	if _tipi_index >= _tipi_questions.size():
		_show_tipi_result()
	else:
		_refresh_tipi_question()

func _show_tipi_result() -> void:
	var profile = get_node_or_null("/root/PlayerProfile")
	if profile and profile.has_method("set_tipi"):
		profile.set_tipi(_tipi_responses.duplicate(true), _tipi_questions.size())

	survey_question.custom_minimum_size = Vector2(SURVEY_PANEL_BASE_SIZE.x - 48.0, 24)
	survey_question.text = "Your responses have been recorded.\nThey will be taken into account in the robot delegation."
	if survey_question_title:
		survey_question_title.show()
		survey_question_title.text = "[b]Question Finished[/b]"
	if survey_scale_title:
		survey_scale_title.hide()
	if survey_scale_spacer:
		survey_scale_spacer.hide()
	if survey_scale_hint:
		survey_scale_hint.hide()
	if survey_result_group_spacer:
		survey_result_group_spacer.hide()
	if survey_result_group:
		survey_result_group.hide()
	if survey_result_spacer:
		survey_result_spacer.hide()
	for button in _survey_scale_buttons:
		button.hide()
	survey_confirm.text = "Start Tutorial"
	survey_confirm.show()
	_recenter_survey_panel()

func _finish_survey_and_start() -> void:
	survey_panel.hide()
	_start_game_from_tutorial()

func _setup_tutorial_ui() -> void:
	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "TutorialPanel"
	tutorial_panel.visible = false
	add_child(tutorial_panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	tutorial_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Tutorial"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	tutorial_body = RichTextLabel.new()
	tutorial_body.bbcode_enabled = true
	tutorial_body.fit_content = true
	tutorial_body.scroll_active = false
	tutorial_body.selection_enabled = false
	tutorial_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_body.custom_minimum_size = Vector2(TUTORIAL_PANEL_WIDTH - 48.0, 260.0)
	tutorial_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tutorial_body.text = TUTORIAL_TEXT
	vbox.add_child(tutorial_body)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(button_row)

	tutorial_start_button = Button.new()
	tutorial_start_button.text = "Start Game"
	tutorial_start_button.custom_minimum_size = Vector2(0, 52)
	tutorial_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_start_button.pressed.connect(_start_game_from_tutorial)
	button_row.add_child(tutorial_start_button)

	tutorial_close_button = Button.new()
	tutorial_close_button.text = "Close"
	tutorial_close_button.custom_minimum_size = Vector2(0, 52)
	tutorial_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_close_button.visible = false
	tutorial_close_button.pressed.connect(_close_tutorial_overlay)
	button_row.add_child(tutorial_close_button)

	tutorial_toggle_button = Button.new()
	tutorial_toggle_button.name = "TutorialToggle"
	tutorial_toggle_button.text = "?"
	tutorial_toggle_button.visible = false
	tutorial_toggle_button.custom_minimum_size = Vector2(TUTORIAL_TOGGLE_SIZE, TUTORIAL_TOGGLE_SIZE)
	tutorial_toggle_button.tooltip_text = "Tutorial"
	tutorial_toggle_button.add_theme_font_size_override("font_size", 22)
	tutorial_toggle_button.add_theme_color_override("font_color", Color(1.0, 0.97, 0.78, 1.0))
	var toggle_style := StyleBoxFlat.new()
	toggle_style.bg_color = Color(0.08, 0.08, 0.08, 0.92)
	toggle_style.corner_radius_top_left = 10
	toggle_style.corner_radius_top_right = 10
	toggle_style.corner_radius_bottom_right = 10
	toggle_style.corner_radius_bottom_left = 10
	toggle_style.border_width_left = 1
	toggle_style.border_width_top = 1
	toggle_style.border_width_right = 1
	toggle_style.border_width_bottom = 1
	toggle_style.border_color = Color(1.0, 0.97, 0.78, 0.35)
	tutorial_toggle_button.add_theme_stylebox_override("normal", toggle_style)
	var toggle_hover := toggle_style.duplicate() as StyleBoxFlat
	toggle_hover.bg_color = Color(0.16, 0.16, 0.16, 0.96)
	toggle_hover.border_color = Color(1.0, 0.97, 0.78, 0.6)
	tutorial_toggle_button.add_theme_stylebox_override("hover", toggle_hover)
	var toggle_pressed := toggle_style.duplicate() as StyleBoxFlat
	toggle_pressed.bg_color = Color(0.22, 0.22, 0.22, 0.98)
	tutorial_toggle_button.add_theme_stylebox_override("pressed", toggle_pressed)
	tutorial_toggle_button.pressed.connect(_open_tutorial_overlay)
	add_child(tutorial_toggle_button)

func _show_tutorial_before_game() -> void:
	get_tree().paused = true
	_set_gameplay_panels_visible(false)
	if tutorial_panel:
		tutorial_panel.show()
	if tutorial_start_button:
		tutorial_start_button.show()
	if tutorial_close_button:
		tutorial_close_button.hide()
	if tutorial_toggle_button:
		tutorial_toggle_button.hide()
	_update_gameplay_panel_layout()

func _start_game_from_tutorial() -> void:
	_tutorial_started = true
	if tutorial_panel:
		tutorial_panel.hide()
	if tutorial_toggle_button and _formal_session_started:
		tutorial_toggle_button.show()
	get_tree().paused = false
	_set_gameplay_panels_visible(true)
	_start_trial_session()

func _show_pending_day_notice() -> void:
	if _initial_day_notice_shown:
		return
	if _pending_day_notice <= 0:
		return
	_on_day_changed_notice(_pending_day_notice)

func _open_tutorial_overlay() -> void:
	if not _tutorial_started:
		return
	get_tree().paused = true
	if tutorial_panel:
		tutorial_panel.show()
	if tutorial_start_button:
		tutorial_start_button.hide()
	if tutorial_close_button:
		tutorial_close_button.show()
	if tutorial_toggle_button:
		tutorial_toggle_button.hide()
	_update_gameplay_panel_layout()

func _close_tutorial_overlay() -> void:
	if tutorial_panel:
		tutorial_panel.hide()
	if tutorial_close_button:
		tutorial_close_button.hide()
	if tutorial_toggle_button:
		tutorial_toggle_button.show()
	get_tree().paused = false

func _set_gameplay_panels_visible(visible: bool) -> void:
	if inventory_panel:
		inventory_panel.visible = visible
	if dialogue_panel:
		dialogue_panel.visible = visible
	if customer_panel:
		customer_panel.visible = visible
	if help_prompt_stack and not visible:
		help_prompt_stack.visible = false
	if player_dialogue_overlay and not visible:
		player_dialogue_overlay.visible = false
	if player_dialogue_info_stack and not visible:
		player_dialogue_info_stack.visible = false

func _setup_trial_guide_ui() -> void:
	_trial_timeout_timer = Timer.new()
	_trial_timeout_timer.one_shot = true
	_trial_timeout_timer.wait_time = TRIAL_SESSION_MAX_SEC
	_trial_timeout_timer.timeout.connect(_on_trial_timeout)
	add_child(_trial_timeout_timer)

	_trial_guide_layer = Control.new()
	_trial_guide_layer.name = "TrialGuideLayer"
	_trial_guide_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trial_guide_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_guide_layer.visible = false
	add_child(_trial_guide_layer)

	_trial_guide_dim = ColorRect.new()
	_trial_guide_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trial_guide_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_guide_dim.color = Color(0, 0, 0, 0)
	_trial_guide_layer.add_child(_trial_guide_dim)

	_trial_guide_dim_top = ColorRect.new()
	_trial_guide_dim_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_guide_dim_top.color = Color(0.02, 0.03, 0.05, 0.38)
	_trial_guide_dim.add_child(_trial_guide_dim_top)

	_trial_guide_dim_bottom = ColorRect.new()
	_trial_guide_dim_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_guide_dim_bottom.color = Color(0.02, 0.03, 0.05, 0.38)
	_trial_guide_dim.add_child(_trial_guide_dim_bottom)

	_trial_guide_dim_left = ColorRect.new()
	_trial_guide_dim_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_guide_dim_left.color = Color(0.02, 0.03, 0.05, 0.38)
	_trial_guide_dim.add_child(_trial_guide_dim_left)

	_trial_guide_dim_right = ColorRect.new()
	_trial_guide_dim_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_guide_dim_right.color = Color(0.02, 0.03, 0.05, 0.38)
	_trial_guide_dim.add_child(_trial_guide_dim_right)

	_trial_guide_focus = PanelContainer.new()
	_trial_guide_focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color(0, 0, 0, 0)
	focus_style.border_width_left = 3
	focus_style.border_width_top = 3
	focus_style.border_width_right = 3
	focus_style.border_width_bottom = 3
	focus_style.border_color = TRIAL_GUIDE_FOCUS_BORDER
	focus_style.corner_radius_top_left = 12
	focus_style.corner_radius_top_right = 12
	focus_style.corner_radius_bottom_left = 12
	focus_style.corner_radius_bottom_right = 12
	_trial_guide_focus.add_theme_stylebox_override("panel", focus_style)
	_trial_guide_layer.add_child(_trial_guide_focus)

	_trial_guide_arrow = TextureRect.new()
	_trial_guide_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_guide_arrow.texture = TRIAL_GUIDE_ARROW_TEXTURE
	_trial_guide_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_trial_guide_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_trial_guide_arrow.custom_minimum_size = TRIAL_GUIDE_ARROW_SIZE
	_trial_guide_arrow.size = TRIAL_GUIDE_ARROW_SIZE
	_trial_guide_arrow.pivot_offset = TRIAL_GUIDE_ARROW_SIZE * 0.5
	_trial_guide_layer.add_child(_trial_guide_arrow)

	_trial_guide_message_panel = PanelContainer.new()
	_trial_guide_message_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var message_style := StyleBoxFlat.new()
	message_style.bg_color = Color(0.08, 0.11, 0.16, 0.94)
	message_style.border_width_left = 2
	message_style.border_width_top = 2
	message_style.border_width_right = 2
	message_style.border_width_bottom = 2
	message_style.border_color = TRIAL_GUIDE_FOCUS_BORDER
	message_style.corner_radius_top_left = 12
	message_style.corner_radius_top_right = 12
	message_style.corner_radius_bottom_left = 12
	message_style.corner_radius_bottom_right = 12
	message_style.content_margin_left = 14
	message_style.content_margin_right = 14
	message_style.content_margin_top = 10
	message_style.content_margin_bottom = 10
	_trial_guide_message_panel.add_theme_stylebox_override("panel", message_style)
	_trial_guide_layer.add_child(_trial_guide_message_panel)

	_trial_guide_message_label = RichTextLabel.new()
	_trial_guide_message_label.bbcode_enabled = true
	_trial_guide_message_label.fit_content = true
	_trial_guide_message_label.scroll_active = false
	_trial_guide_message_label.selection_enabled = false
	_trial_guide_message_label.custom_minimum_size = Vector2(280.0, 0.0)
	_trial_guide_message_panel.add_child(_trial_guide_message_label)

func _trial_wait(seconds: float) -> bool:
	if seconds <= 0.0:
		return true
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = seconds
	add_child(timer)
	timer.start()
	await timer.timeout
	if is_instance_valid(timer):
		timer.queue_free()
	return is_inside_tree()

func _start_trial_session() -> void:
	if _trial_session_active or _formal_session_started:
		return
	_trial_session_active = true
	_trial_step = "intro"
	_trial_drink_task_id = ""
	_refresh_day_phase_label()
	_reset_trial_world_state()
	var time_mgr = get_node_or_null("/root/GameManager/TimeManager")
	if time_mgr and time_mgr.has_method("pause"):
		time_mgr.pause()
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_customer_spawner"):
		var spawner = game_mgr.get_customer_spawner()
		if spawner and spawner.has_method("disable"):
			spawner.disable()
	if tutorial_toggle_button:
		tutorial_toggle_button.hide()
	if _trial_timeout_timer:
		_trial_timeout_timer.start(TRIAL_SESSION_MAX_SEC)
	call_deferred("_run_trial_intro")

func _run_trial_intro() -> void:
	_hide_trial_guide()
	_show_player_dialogue_overlay("System", "Welcome to the restaurant.", "system")
	if not await _trial_wait(PLAYER_DIALOGUE_OVERLAY_SHOW_SEC + 0.1):
		return
	if not _trial_session_active:
		return
	_show_player_dialogue_overlay("System", "You are now entering the trial session.", "system")
	if not await _trial_wait(1.0):
		return
	if not _trial_session_active:
		return
	_spawn_trial_customer()
	_trial_step = "await_food_order"
	_show_trial_guide_for_customer_orders()

func _spawn_trial_customer() -> void:
	if _trial_customer != null and is_instance_valid(_trial_customer):
		return
	var customer = TrialCustomerScene.instantiate()
	customer.preset_food_item = "pizza"
	customer.preset_drink_item = "coffee"
	customer.start_delay_sec = 0.2
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return
	current_scene.add_child(customer)
	var spawn_marker = current_scene.find_child("CS1", true, false)
	if spawn_marker != null and spawn_marker is Node2D:
		customer.global_position = (spawn_marker as Node2D).global_position
	_trial_customer = customer as Node2D

func _ensure_trial_drink_request() -> void:
	if not await _trial_wait(2.5):
		return
	if not _trial_session_active or _trial_customer == null or not is_instance_valid(_trial_customer):
		return
	if _trial_drink_task_id != "":
		return
	if _trial_customer.has_method("on_food_order_taken"):
		_trial_customer.call("on_food_order_taken")

func _show_trial_guide_for_customer_orders() -> void:
	_show_trial_guide(
		"The robot will handle the food order first, and you will handle the drink order.",
		{"type": "control", "id": customer_panel.get_instance_id(), "prefer_below": true, "message_offset_y": -25.0},
		"→"
	)

func _show_trial_guide_for_drink_request() -> void:
	_show_trial_guide(
		"The customer is now requesting a drink. Walk to the customer and press [b]E[/b] to take the drink order.",
		{"type": "world_customer", "id": _trial_customer.get_instance_id(), "size": Vector2(104.0, 150.0), "offset": Vector2(0.0, -24.0)},
		"↓"
	)

func _show_trial_guide_for_drink_pickup() -> void:
	_show_trial_guide(
		"Next, go to the drink cabinet and press [b]E[/b]. Select the requested drink to pick it up.",
		_drink_cabinet_trial_target(),
		"↓"
	)

func _show_trial_guide_for_drink_delivery() -> void:
	_show_trial_guide(
		"Take the drink back to the customer and deliver it.",
		{"type": "world_customer", "id": _trial_customer.get_instance_id(), "size": Vector2(104.0, 150.0), "offset": Vector2(0.0, -24.0)},
		"↓"
	)

func _ensure_trial_handoff_preload() -> void:
	if not _trial_session_active:
		return
	if _trial_handoff_ready or _trial_handoff_preloading:
		return
	_trial_handoff_preloading = true
	_spawn_trial_handoff_customer()

func _spawn_trial_handoff_customer() -> void:
	if _trial_handoff_customer != null and is_instance_valid(_trial_handoff_customer):
		return
	var customer = TrialCustomerScene.instantiate()
	customer.preset_food_item = "sandwich"
	customer.preset_drink_item = ""
	customer.force_drink_order = false
	customer.start_delay_sec = 0.2
	var current_scene = get_tree().current_scene
	if current_scene == null:
		_trial_handoff_preloading = false
		return
	current_scene.add_child(customer)
	var spawn_marker = current_scene.find_child("CS1", true, false)
	if spawn_marker != null and spawn_marker is Node2D:
		customer.global_position = (spawn_marker as Node2D).global_position
	_trial_handoff_customer = customer as Node2D

func _prepare_trial_handoff_task(task_id: String) -> void:
	if not _trial_session_active or task_id == "":
		return
	var board = get_node_or_null("/root/TaskBoard")
	var robot = _trial_robot()
	if board == null or robot == null:
		call_deferred("_finish_trial_session", false)
		return
	var claimed: Dictionary = board.claim_task(task_id, str(robot.name)) if board.has_method("claim_task") else {}
	if claimed.is_empty():
		call_deferred("_finish_trial_session", false)
		return
	if not board.complete_current_step(task_id, "TAKE_ORDER"):
		call_deferred("_finish_trial_session", false)
		return
	var task_snapshot: Dictionary = board.get_task(task_id) if board.has_method("get_task") else {}
	var payload: Dictionary = task_snapshot.get("payload", {})
	var item_name := str(payload.get("food_item", "sandwich")).strip_edges().to_lower()
	var visual := _trial_item_visual(item_name)
	var robot_inventory = robot.get_node_or_null("Inventory")
	if robot_inventory == null:
		call_deferred("_finish_trial_session", false)
		return
	var added: bool = robot_inventory.add_item(
		item_name,
		visual.get("atlas", null),
		visual.get("region", Rect2i()),
		{"task_id": task_id, "orphaned_at_ms": 0}
	)
	if not added:
		call_deferred("_finish_trial_session", false)
		return
	if not board.complete_current_step(task_id, "PICKUP_FROM_KITCHEN"):
		call_deferred("_finish_trial_session", false)
		return
	var deliver_task: Dictionary = board.get_task(task_id) if board.has_method("get_task") else {}
	if robot.has_method("_activate_task_context"):
		robot.call("_activate_task_context", deliver_task)
	robot.set("_active_task_step", "DELIVER_AND_SERVE")
	_trial_handoff_preloading = false
	_trial_handoff_ready = true
	if _trial_handoff_activate_when_ready:
		call_deferred("_activate_trial_handoff_request")

func _activate_trial_handoff_request() -> void:
	if not _trial_session_active:
		return
	if _trial_handoff_request_id != "":
		return
	if not _trial_handoff_ready:
		_trial_handoff_activate_when_ready = true
		_ensure_trial_handoff_preload()
		return
	_trial_handoff_activate_when_ready = false
	if _trial_handoff_task_id == "":
		call_deferred("_finish_trial_session", false)
		return
	var board = get_node_or_null("/root/TaskBoard")
	var robot = _trial_robot()
	if board == null or robot == null:
		call_deferred("_finish_trial_session", false)
		return
	var task_snapshot: Dictionary = board.get_task(_trial_handoff_task_id) if board.has_method("get_task") else {}
	var payload: Dictionary = task_snapshot.get("payload", {})
	var item_name := str(payload.get("food_item", "sandwich")).strip_edges().to_lower()
	if not robot.has_method("start_trial_item_handoff"):
		call_deferred("_finish_trial_session", false)
		return
	robot.call("start_trial_item_handoff", _trial_handoff_task_id, item_name)
	_trial_step = "await_handoff_accept"

func _show_trial_guide_for_handoff_accept() -> void:
	var prompt_target := _trial_handoff_prompt_target()
	var accept_target := _trial_help_accept_target()
	if prompt_target.is_empty() or accept_target.is_empty():
		return
	_show_trial_guide(
		"",
		{"type": "control", "id": int(prompt_target.get("id", 0)), "arrow_target": accept_target, "hide_focus_border": true},
		"→"
	)

func _show_trial_guide_for_handoff_delivery() -> void:
	if _trial_handoff_customer == null or not is_instance_valid(_trial_handoff_customer):
		return
	_show_trial_guide(
		"The dish has also been handed to you, so you can deliver it directly to the customer.",
		{"type": "world_customer", "id": _trial_handoff_customer.get_instance_id(), "size": Vector2(104.0, 150.0), "offset": Vector2(0.0, -24.0)},
		"↓"
	)

func _finish_trial_session(success: bool) -> void:
	if not _trial_session_active:
		return
	_trial_session_active = false
	_trial_step = "complete"
	if _trial_timeout_timer:
		_trial_timeout_timer.stop()
	_hide_trial_guide()
	_reset_trial_world_state()
	_refresh_day_phase_label()
	call_deferred("_show_trial_completion_prompt", success)

func _on_trial_timeout() -> void:
	_finish_trial_session(false)

func _show_trial_completion_prompt(success: bool) -> void:
	if success:
		_popup_mode = POPUP_MODE_TRIAL_COMPLETE
		_show_player_dialogue_prompt(
			"System",
			"Congratulations. You have successfully completed the trial session. Are you ready to begin the formal session?\n",
			["Start Game"],
			false
		)
	else:
		_show_player_dialogue_overlay("System", "The trial session has ended. The formal session will start now.", "system")
		await _trial_wait(PLAYER_DIALOGUE_OVERLAY_SHOW_SEC + 0.1)
		_begin_formal_session()

func _begin_formal_session() -> void:
	_formal_session_started = true
	_initial_day_notice_shown = false
	_pending_day_notice = 1
	var robot = _trial_robot()
	if robot != null and robot.has_method("set_trial_stationary_pause"):
		robot.call("set_trial_stationary_pause", false)
	var time_mgr = get_node_or_null("/root/GameManager/TimeManager")
	if time_mgr and time_mgr.has_method("reset_runtime"):
		time_mgr.reset_runtime()
	if time_mgr and time_mgr.has_method("resume"):
		time_mgr.resume()
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_customer_spawner"):
		var spawner = game_mgr.get_customer_spawner()
		if spawner:
			if spawner.has_method("clear_all_customers"):
				spawner.clear_all_customers()
			if spawner.has_method("enable"):
				spawner.enable()
	if tutorial_toggle_button:
		tutorial_toggle_button.show()
	_refresh_day_phase_label()
	_show_pending_day_notice()

func _reset_trial_world_state() -> void:
	var board = get_node_or_null("/root/TaskBoard")
	if board and board.has_method("reset_all"):
		board.reset_all()
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr and help_mgr.has_method("reset_all"):
		help_mgr.reset_all()
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_customer_spawner"):
		var spawner = game_mgr.get_customer_spawner()
		if spawner and spawner.has_method("clear_all_customers"):
			spawner.clear_all_customers()
	if _trial_customer != null and is_instance_valid(_trial_customer):
		_trial_customer.queue_free()
	_trial_customer = null
	if _trial_handoff_customer != null and is_instance_valid(_trial_handoff_customer):
		_trial_handoff_customer.queue_free()
	_trial_handoff_customer = null
	_trial_food_task_id = ""
	_trial_drink_task_id = ""
	_trial_handoff_task_id = ""
	_trial_handoff_request_id = ""
	_clear_actor_inventory("player")
	_clear_actor_inventory("robot")
	var robot = _trial_robot()
	if robot != null:
		if robot.has_method("set_trial_stationary_pause"):
			robot.call("set_trial_stationary_pause", false)
		if robot.has_method("_clear_current_task_runtime"):
			robot.call("_clear_current_task_runtime")
		robot.set("_waiting_for_help", false)
		robot.set("_help_item_needed", "")
		robot.set("_active_help_request_id", "")
		robot.set("_active_help_request_type", "")
	_score = 0
	_success_count = 0
	_failed_count = 0
	_score_game_over = false
	_customer_history_page = 0
	_last_player_live_task_ids.clear()
	_refresh_score_label()
	if dialogue_log:
		dialogue_log.clear()
	_update_player_task_panel()
	_update_robot_task_panel()
	_update_customer_panel()

func _clear_actor_inventory(group_name: String) -> void:
	var actors = get_tree().get_nodes_in_group(group_name)
	if actors.is_empty():
		return
	var actor = actors[0]
	var inv = actor.get_node_or_null("Inventory")
	if inv == null or not (inv is Inventory):
		return
	var inventory_node := inv as Inventory
	inventory_node.items.clear()
	inventory_node.emit_signal("inventory_changed", inventory_node.items)

func _is_trial_customer_task(payload: Dictionary) -> bool:
	if _trial_customer == null or not is_instance_valid(_trial_customer):
		return false
	return int(payload.get("customer_instance_id", 0)) == _trial_customer.get_instance_id()

func _is_trial_handoff_customer_task(payload: Dictionary) -> bool:
	if _trial_handoff_customer == null or not is_instance_valid(_trial_handoff_customer):
		return false
	return int(payload.get("customer_instance_id", 0)) == _trial_handoff_customer.get_instance_id()

func _trial_robot() -> Node:
	var robots = get_tree().get_nodes_in_group("robot")
	if robots.is_empty():
		return null
	return robots[0]

func _trial_item_visual(item_name: String) -> Dictionary:
	var items_root = get_tree().get_root().find_child("InteractiveItems", true, false)
	if items_root == null:
		return {"atlas": null, "region": Rect2i()}
	for child in items_root.get_children():
		if not ("display_name" in child):
			continue
		if str(child.display_name).strip_edges().to_lower() != item_name.strip_edges().to_lower():
			continue
		var sprite := child.get_node_or_null("Sprite2D") as Sprite2D
		if sprite == null:
			break
		return {
			"atlas": sprite.texture,
			"region": Rect2i(sprite.region_rect.position, sprite.region_rect.size)
		}
	return {"atlas": null, "region": Rect2i()}

func _trial_help_accept_target() -> Dictionary:
	if _trial_handoff_request_id == "":
		return {}
	var idx := _find_help_request_card_index(_trial_handoff_request_id)
	if idx < 0:
		return {}
	var entry: Dictionary = _help_prompt_cards[idx]
	var accept_btn: Button = entry.get("accept_btn", null)
	if accept_btn == null or not is_instance_valid(accept_btn):
		return {}
	return {"type": "control", "id": accept_btn.get_instance_id()}

func _trial_handoff_prompt_target() -> Dictionary:
	if _trial_handoff_request_id == "":
		return {}
	var idx := _find_help_request_card_index(_trial_handoff_request_id)
	if idx < 0:
		return {}
	var entry: Dictionary = _help_prompt_cards[idx]
	var card: Control = entry.get("node", null)
	if card == null or not is_instance_valid(card):
		return {}
	return {"type": "control", "id": card.get_instance_id()}

func _show_trial_guide(text: String, target: Dictionary, arrow: String = "↓") -> void:
	if _trial_guide_layer == null or _trial_guide_message_label == null:
		return
	_trial_guide_target = target.duplicate(true)
	_trial_guide_layer.visible = true
	_trial_guide_message_label.clear()
	if text.strip_edges() == "":
		_trial_guide_message_panel.visible = false
	else:
		_trial_guide_message_panel.visible = true
		_trial_guide_message_label.append_text(text)
	_set_trial_guide_arrow_direction(arrow)
	_update_trial_guide_overlay()

func _set_trial_guide_arrow_direction(arrow: String) -> void:
	_trial_guide_arrow_direction = arrow

	if _trial_guide_arrow == null:
		return

	match arrow:
		"↓":
			_trial_guide_arrow.rotation_degrees = 90.0
		"←":
			_trial_guide_arrow.rotation_degrees = 180.0
		"↑":
			_trial_guide_arrow.rotation_degrees = -90.0
		_:
			_trial_guide_arrow.rotation_degrees = 0.0

func _hide_trial_guide() -> void:
	_trial_guide_target.clear()
	if _trial_guide_layer:
		_trial_guide_layer.visible = false

func _update_trial_guide_overlay() -> void:
	if _trial_guide_layer == null or not _trial_guide_layer.visible:
		return
	var rect := _resolve_trial_guide_target_rect(_trial_guide_target)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var focus_rect := rect.grow(8.0)
	var view_size := get_viewport().get_visible_rect().size
	var clipped_focus := Rect2(
		Vector2(clampf(focus_rect.position.x, 0.0, view_size.x), clampf(focus_rect.position.y, 0.0, view_size.y)),
		Vector2(
			clampf(focus_rect.end.x, 0.0, view_size.x) - clampf(focus_rect.position.x, 0.0, view_size.x),
			clampf(focus_rect.end.y, 0.0, view_size.y) - clampf(focus_rect.position.y, 0.0, view_size.y)
		)
	)
	if _trial_guide_dim_top:
		_trial_guide_dim_top.position = Vector2.ZERO
		_trial_guide_dim_top.size = Vector2(view_size.x, maxf(0.0, clipped_focus.position.y))
	if _trial_guide_dim_bottom:
		_trial_guide_dim_bottom.position = Vector2(0.0, clipped_focus.end.y)
		_trial_guide_dim_bottom.size = Vector2(view_size.x, maxf(0.0, view_size.y - clipped_focus.end.y))
	if _trial_guide_dim_left:
		_trial_guide_dim_left.position = Vector2(0.0, clipped_focus.position.y)
		_trial_guide_dim_left.size = Vector2(maxf(0.0, clipped_focus.position.x), maxf(0.0, clipped_focus.size.y))
	if _trial_guide_dim_right:
		_trial_guide_dim_right.position = Vector2(clipped_focus.end.x, clipped_focus.position.y)
		_trial_guide_dim_right.size = Vector2(maxf(0.0, view_size.x - clipped_focus.end.x), maxf(0.0, clipped_focus.size.y))
	_trial_guide_focus.visible = not bool(_trial_guide_target.get("hide_focus_border", false))
	_trial_guide_focus.position = focus_rect.position
	_trial_guide_focus.size = focus_rect.size
	var place_above := false
	if _trial_guide_message_panel.visible:
		var message_size := _trial_guide_message_panel.get_combined_minimum_size()
		_trial_guide_message_panel.size = message_size
		var message_x := clampf(focus_rect.get_center().x - message_size.x * 0.5, 24.0, maxf(24.0, view_size.x - message_size.x - 24.0))
		var prefer_below := bool(_trial_guide_target.get("prefer_below", false))
		place_above = focus_rect.position.y >= message_size.y + 70.0 and not prefer_below
		var message_y := focus_rect.position.y - message_size.y - 48.0 if place_above else focus_rect.position.y + focus_rect.size.y + 56.0
		message_y += float(_trial_guide_target.get("message_offset_y", 0.0))
		_trial_guide_message_panel.position = Vector2(message_x, message_y)
	var arrow_rect := focus_rect
	var arrow_target: Dictionary = _trial_guide_target.get("arrow_target", {})
	if not arrow_target.is_empty():
		var resolved_arrow_rect := _resolve_trial_guide_target_rect(arrow_target)
		if resolved_arrow_rect.size.x > 0.0 and resolved_arrow_rect.size.y > 0.0:
			arrow_rect = resolved_arrow_rect.grow(4.0)
	var arrow_size := TRIAL_GUIDE_ARROW_SIZE

	if _trial_guide_arrow_direction == "→":
		_trial_guide_arrow.position = Vector2(
			arrow_rect.position.x - arrow_size.x - 10.0,
			arrow_rect.get_center().y - arrow_size.y * 0.5 + 3.0
		)
	elif _trial_guide_arrow_direction == "←":
		_trial_guide_arrow.position = Vector2(
			arrow_rect.position.x + arrow_rect.size.x + 10.0,
			arrow_rect.get_center().y - arrow_size.y * 0.5 + 3.0
		)
	elif place_above:
		_trial_guide_arrow.position = Vector2(
			arrow_rect.get_center().x - arrow_size.x * 0.5,
			arrow_rect.position.y - arrow_size.y - 8.0
		)
	else:
		_trial_guide_arrow.position = Vector2(
			arrow_rect.get_center().x - arrow_size.x * 0.5,
			arrow_rect.position.y + arrow_rect.size.y + 8.0
		)
	var blink_t := float(Time.get_ticks_msec()) * 0.008
	var alpha := 0.55 + 0.45 * (0.5 + 0.5 * sin(blink_t))
	_trial_guide_arrow.modulate = Color(1.0, 1.0, 1.0, alpha)

func _resolve_trial_guide_target_rect(target: Dictionary = _trial_guide_target) -> Rect2:
	if target.is_empty():
		return Rect2()
	var target_type := str(target.get("type", ""))
	match target_type:
		"control":
			var control = instance_from_id(int(target.get("id", 0)))
			if control != null and control is Control:
				return (control as Control).get_global_rect()
		"world_customer":
			var node = instance_from_id(int(target.get("id", 0)))
			if node != null and node is Node2D:
				var size: Vector2 = target.get("size", Vector2(96.0, 132.0))
				var offset: Vector2 = target.get("offset", Vector2.ZERO)
				var screen := _world_to_screen((node as Node2D).global_position + offset)
				return Rect2(screen - size * 0.5, size)
		"world_rect":
			var center: Vector2 = target.get("center", Vector2.ZERO)
			var size: Vector2 = target.get("size", Vector2.ZERO)
			var offset: Vector2 = target.get("offset", Vector2.ZERO)
			var screen := _world_to_screen(center + offset)
			return Rect2(screen - size * 0.5, size)
	return Rect2()

func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

func _drink_cabinet_trial_target() -> Dictionary:
	return {"type": "world_rect", "center": Vector2(-208.0, -358.0), "size": Vector2(246.0, 130.0)}

func _player_holding_bar_trial_target() -> Dictionary:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return {"type": "world_rect", "center": Vector2.ZERO, "size": Vector2(160.0, 56.0)}
	var player = players[0]
	var bar_root = player.get_node_or_null("HoldingBar")
	if bar_root != null:
		var panel = bar_root.get_child(0) if bar_root.get_child_count() > 0 else null
		if panel != null and panel is Control:
			return {"type": "control", "id": (panel as Control).get_instance_id()}
	if player is Node2D:
		return {"type": "world_rect", "center": (player as Node2D).global_position + Vector2(0.0, -98.0), "size": Vector2(180.0, 56.0)}
	return {"type": "world_rect", "center": Vector2.ZERO, "size": Vector2(180.0, 56.0)}

func _auto_open_help_request(request: Dictionary) -> void:
	if survey_panel and survey_panel.visible:
		return
	if not _can_auto_open_request(request):
		return
	if _should_wait_for_help_utterance(request):
		return
	var rid := str(request.get("id", ""))
	if rid == "":
		return
	if bool(_auto_open_in_flight.get(rid, false)):
		return
	if _has_help_request_card(rid):
		return
	if _help_prompt_cards.size() >= HELP_PROMPT_MAX_STACK:
		return

	_auto_open_in_flight[rid] = true
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr and help_mgr.has_method("mark_prompted"):
		help_mgr.mark_prompted(rid)
		request = help_mgr.get_request(rid)
	show_help_request(request)
	_auto_open_in_flight.erase(rid)

func _should_wait_for_help_utterance(request: Dictionary) -> bool:
	if str(request.get("type", "")) != "HANDOFF":
		return false
	var payload: Dictionary = request.get("payload", {})
	if bool(payload.get("trial_force_prompt", false)):
		return false
	return bool(request.get("utterance_pending", false))

func _can_auto_open_request(request: Dictionary) -> bool:
	var req_type := str(request.get("type", ""))
	if req_type != "HANDOFF":
		return true
	var payload: Dictionary = request.get("payload", {})
	if bool(payload.get("trial_force_prompt", false)):
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
	var rid := str(request.get("id", "")).strip_edges()
	var utterance := str(request.get("utterance", "")).strip_edges()
	if utterance == "":
		return
	if rid != "":
		var previous := str(_last_help_bubble_utterance_by_request.get(rid, ""))
		if previous == utterance:
			return
		_last_help_bubble_utterance_by_request[rid] = utterance

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

func _maybe_append_help_system_notice(request: Dictionary) -> void:
	var rid := str(request.get("id", "")).strip_edges()
	var notice := str(request.get("system_notice", "")).strip_edges()
	if rid == "" or notice == "":
		return
	if bool(_shown_help_system_notice_by_request.get(rid, false)):
		return
	_shown_help_system_notice_by_request[rid] = true
	_append_feed_line("System", notice)

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
	var speaker_color := _dialogue_speaker_color(speaker)
	dialogue_log.push_color(speaker_color)
	dialogue_log.add_text("%s:" % speaker)
	dialogue_log.pop()
	dialogue_log.push_color(FEED_COLOR_DIALOGUE)
	dialogue_log.add_text(" %s\n" % content)
	dialogue_log.pop()
	var max_lines := 80
	if dialogue_log.get_line_count() > max_lines:
		dialogue_log.clear()
	dialogue_log.scroll_to_line(max(0, dialogue_log.get_line_count() - 1))

func _dialogue_speaker_color(speaker: String) -> Color:
	var key := speaker.strip_edges().to_lower()
	match key:
		"robot":
			return Color(0.58, 0.88, 1.0, 1.0)
		"customer":
			return Color(1.0, 0.64, 0.72, 1.0)
		"system":
			return Color(1.0, 0.84, 0.36, 1.0)
		"player", "you":
			return Color(0.40, 0.86, 0.48, 1.0)
	return FEED_COLOR_DIALOGUE

func _is_player_related_dialogue(source: Node2D, recipient: Node2D, kind: String, recipient_kind: String) -> bool:
	if recipient_kind == "player":
		return true
	if recipient != null and is_instance_valid(recipient) and recipient.is_in_group("player"):
		return true
	return false

func _should_skip_player_overlay_message(source: Node2D, recipient: Node2D, kind: String, recipient_kind: String) -> bool:
	if not _is_player_related_dialogue(source, recipient, kind, recipient_kind):
		return true
	if kind == "robot" and recipient_kind == "player":
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
	var system_popup_color := Color(1.0, 0.84, 0.36, 1.0)
	var speaker_color := Color(1.0, 0.92, 0.74, 1.0)
	if kind == "customer":
		speaker_color = Color(1.0, 0.64, 0.72, 1.0)
	elif kind == "system":
		speaker_color = system_popup_color

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH, 0.0)
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
	label.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH - 28.0, 0.0)
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
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(PLAYER_DIALOGUE_OVERLAY_SHOW_SEC)
	tween.tween_property(card, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(Callable(self, "_remove_player_dialogue_info_card_by_id").bind(card.get_instance_id()))

func _show_player_dialogue_prompt(title: String, body: String, button_texts: Array[String] = [], show_third_button: bool = true) -> void:
	if player_dialogue_overlay == null or player_dialogue_overlay_label == null:
		return
	player_dialogue_overlay.visible = true
	player_dialogue_overlay.modulate = Color(1, 1, 1, 1)
	player_dialogue_overlay.scale = Vector2(1.0, 1.0)
	player_dialogue_overlay_label.clear()
	player_dialogue_overlay_label.push_color(Color(1.0, 0.84, 0.36, 1.0))
	player_dialogue_overlay_label.add_text(title)
	player_dialogue_overlay_label.pop()
	player_dialogue_overlay_label.add_text("\n\n" + body)
	if player_dialogue_overlay_button_spacer:
		player_dialogue_overlay_button_spacer.custom_minimum_size = Vector2(0.0, 0.0)
	if player_dialogue_overlay_buttons:
		player_dialogue_overlay_buttons.visible = not button_texts.is_empty()
		if player_dialogue_overlay_accept_btn:
			player_dialogue_overlay_accept_btn.visible = button_texts.size() >= 1
			if button_texts.size() >= 1:
				player_dialogue_overlay_accept_btn.text = button_texts[0]
			player_dialogue_overlay_accept_btn.disabled = false
			player_dialogue_overlay_accept_btn.modulate = Color(1, 1, 1, 1)
		if player_dialogue_overlay_decline_btn:
			player_dialogue_overlay_decline_btn.visible = button_texts.size() >= 2
			if button_texts.size() >= 2:
				player_dialogue_overlay_decline_btn.text = button_texts[1]
				player_dialogue_overlay_decline_btn.disabled = false
				player_dialogue_overlay_decline_btn.modulate = Color(1, 1, 1, 1)
		if player_dialogue_overlay_later_btn:
			player_dialogue_overlay_later_btn.visible = show_third_button and button_texts.size() >= 3
			if button_texts.size() >= 3:
				player_dialogue_overlay_later_btn.text = button_texts[2]
				player_dialogue_overlay_later_btn.disabled = false
				player_dialogue_overlay_later_btn.modulate = Color(1, 1, 1, 1)
	_trim_player_dialogue_info_cards()
	_update_gameplay_panel_layout()

func _create_help_prompt_card(request: Dictionary) -> Dictionary:
	var rid := str(request.get("id", ""))
	var payload: Dictionary = request.get("payload", {})
	var trial_accept_only := bool(payload.get("trial_accept_only", false))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH, 0.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.58, 0.88, 1.0, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var label := RichTextLabel.new()
	label.bbcode_enabled = false
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.custom_minimum_size = Vector2(PLAYER_DIALOGUE_OVERLAY_WIDTH - 28.0, 0.0)
	vbox.add_child(label)
	label.push_color(Color(0.58, 0.88, 1.0, 1.0))
	label.add_text("Robot Request")
	label.pop()
	label.add_text("\n\n" + _build_help_text(request))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.pressed.connect(func():
		var help_mgr = get_node_or_null("/root/HelpRequestManager")
		if help_mgr:
			help_mgr.respond(rid, "accept")
	)
	buttons.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	if trial_accept_only:
		decline_btn.disabled = true
	else:
		decline_btn.pressed.connect(func():
			var help_mgr = get_node_or_null("/root/HelpRequestManager")
			if help_mgr:
				help_mgr.respond(rid, "decline")
		)
	buttons.add_child(decline_btn)

	var later_btn := Button.new()
	later_btn.text = "Later"
	if trial_accept_only:
		later_btn.disabled = true
	else:
		later_btn.pressed.connect(func():
			var help_mgr = get_node_or_null("/root/HelpRequestManager")
			if help_mgr:
				help_mgr.respond(rid, "later")
		)
	buttons.add_child(later_btn)

	return {
		"request_id": rid,
		"node": card,
		"label": label,
		"accept_btn": accept_btn
	}

func _find_help_request_card_index(request_id: String) -> int:
	for i in range(_help_prompt_cards.size()):
		if str(_help_prompt_cards[i].get("request_id", "")) == request_id:
			return i
	return -1

func _has_help_request_card(request_id: String) -> bool:
	return _find_help_request_card_index(request_id) >= 0

func _show_or_update_help_request_card(request: Dictionary) -> void:
	if help_prompt_stack == null:
		return
	var rid := str(request.get("id", ""))
	if rid == "":
		return
	var idx := _find_help_request_card_index(rid)
	if idx >= 0:
		var entry: Dictionary = _help_prompt_cards[idx]
		var label: RichTextLabel = entry.get("label", null)
		if label != null:
			label.clear()
			label.push_color(Color(1.0, 0.84, 0.36, 1.0))
			label.add_text("Robot Request")
			label.pop()
			label.add_text("\n\n" + _build_help_text(request))
		_help_prompt_cards[idx] = entry
	else:
		if _help_prompt_cards.size() >= HELP_PROMPT_MAX_STACK:
			return
		var created := _create_help_prompt_card(request)
		_help_prompt_cards.append(created)
		help_prompt_stack.add_child(created.get("node"))
	help_prompt_stack.visible = not _help_prompt_cards.is_empty()
	_update_gameplay_panel_layout()

func _remove_help_request_card(request_id: String) -> void:
	var idx := _find_help_request_card_index(request_id)
	if idx < 0:
		_last_help_bubble_utterance_by_request.erase(request_id)
		_shown_help_system_notice_by_request.erase(request_id)
		_fill_help_prompt_slots()
		return
	var entry: Dictionary = _help_prompt_cards[idx]
	_help_prompt_cards.remove_at(idx)
	var node: Control = entry.get("node", null)
	if node != null and is_instance_valid(node):
		node.queue_free()
	if help_prompt_stack:
		help_prompt_stack.visible = not _help_prompt_cards.is_empty()
	_last_help_bubble_utterance_by_request.erase(request_id)
	_shown_help_system_notice_by_request.erase(request_id)
	_update_gameplay_panel_layout()
	_fill_help_prompt_slots()

func _fill_help_prompt_slots() -> void:
	if help_prompt_stack == null or _help_prompt_cards.size() >= HELP_PROMPT_MAX_STACK:
		return
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr == null or not help_mgr.has_method("get_promptable_request_for_robot"):
		return
	var robots := get_tree().get_nodes_in_group("robot")
	for robot in robots:
		if _help_prompt_cards.size() >= HELP_PROMPT_MAX_STACK:
			break
		var request: Dictionary = help_mgr.get_promptable_request_for_robot(robot)
		if request.is_empty():
			continue
		var rid := str(request.get("id", ""))
		if rid == "" or _has_help_request_card(rid):
			continue
		_auto_open_help_request(request)

func _hide_player_dialogue_overlay_buttons() -> void:
	if player_dialogue_overlay_buttons:
		player_dialogue_overlay_buttons.visible = false

func _hide_player_dialogue_overlay() -> void:
	if player_dialogue_overlay == null:
		return
	_hide_player_dialogue_overlay_buttons()
	if player_dialogue_overlay_backdrop:
		player_dialogue_overlay_backdrop.visible = false
	player_dialogue_overlay.visible = false
	player_dialogue_overlay.modulate = Color(1, 1, 1, 1)
	_update_gameplay_panel_layout()

func _trim_player_dialogue_info_cards() -> void:
	for i in range(_player_dialogue_info_cards.size() - 1, -1, -1):
		var entry: Dictionary = _player_dialogue_info_cards[i]
		var node = entry.get("node", null)
		if node == null or not is_instance_valid(node):
			_player_dialogue_info_cards.remove_at(i)

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

func _remove_player_dialogue_info_card_by_id(card_instance_id: int) -> void:
	var card = instance_from_id(card_instance_id)
	if card == null or not (card is Control):
		return
	_remove_player_dialogue_info_card(card as Control)

func _clear_kitchen_pick_button_flash(button_instance_id: int, flash_token: int) -> void:
	var button = instance_from_id(button_instance_id)
	if button == null or not (button is Button):
		return
	var button_node := button as Button
	if int(button_node.get_meta("kitchen_flash_token", 0)) != flash_token:
		return
	button_node.remove_theme_stylebox_override("normal")
	button_node.remove_theme_stylebox_override("hover")
	button_node.remove_theme_stylebox_override("pressed")
	button_node.remove_theme_stylebox_override("focus")
