extends CanvasLayer

signal kitchen_pick_selected(item_name: String)
signal inventory_delete_requested(item_uid: int)

const TrialCustomerScene = preload("res://scenes/Customer.tscn")
const Character1SpriteFrames = preload("res://resources/player_avatars/character_1/character_1_sprite_frames.tres")
const Character2SpriteFrames = preload("res://resources/player_avatars/character_2/character_2_sprite_frames.tres")
const Character3SpriteFrames = preload("res://resources/player_avatars/character_3/character_3_sprite_frames.tres")
const Character4SpriteFrames = preload("res://resources/player_avatars/character_4/character_4_sprite_frames.tres")
const CHARACTER_SPRITE_FRAMES := {
	"character_1": Character1SpriteFrames,
	"character_2": Character2SpriteFrames,
	"character_3": Character3SpriteFrames,
	"character_4": Character4SpriteFrames,
}
const CHARACTER_IDS: Array[String] = ["character_1", "character_2", "character_3", "character_4"]

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
var inventory_portal_panel: PanelContainer
var inventory_portal_list: VBoxContainer
var _inventory_delete_buttons: Array[Button] = []
var _inventory_delete_keyboard_focus_index: int = -1
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
var session_progress_panel: PanelContainer
var session_progress_bar: ProgressBar
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
var player_dialogue_overlay_third_btn: Button
var _player_dialogue_info_cards: Array[Dictionary] = []
var _help_prompt_cards: Array[Dictionary] = []
var _delegation_pause_active: bool = false
var _left_panel_width: float = 0.0
var _last_help_bubble_utterance_by_request: Dictionary = {}
var _shown_help_system_notice_by_request: Dictionary = {}
var _auto_open_in_flight: Dictionary = {}
var _popup_mode: String = "none"
var _kitchen_pick_options: Array[String] = []
var _tipi_questions: Array[Dictionary] = []
var _tipi_index: int = 0
var _tipi_responses := {}
var _survey_nickname_input: LineEdit
var _survey_mode: String = "nickname"
var _survey_scale_buttons: Array[Button] = []
var _tipi_keyboard_focus_index: int = -1
var _character_selection_grid: GridContainer
var _character_selection_buttons: Dictionary = {}
var _selected_character_id: String = ""
var _character_focus_index: int = 0
var _overlay_keyboard_focus_index: int = -1
var _help_keyboard_focus_index: int = -1
var _gameplay_panel_keyboard_focus_index: int = -1
var _gameplay_panel_focus_tween: Tween = null
var _gameplay_panel_focus_token: int = 0
var _player_task_notice_player: AudioStreamPlayer
var _delegation_voice_player: AudioStreamPlayer
var _delegation_voice_request_id: String = ""
var _last_player_live_task_ids: Dictionary = {}
var _player_task_notice_initialized: bool = false
var _tutorial_toggle_flash_tween: Tween = null
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
const GAMEPLAY_VERTICAL_SHIFT := 30.0
const GAMEPLAY_TOP_OFFSET := -30.0 + GAMEPLAY_VERTICAL_SHIFT
const GAMEPLAY_BAND_WIDTH := 760.0
const GAMEPLAY_SIDE_GAP := 24.0
const SESSION_PROGRESS_PANEL_WIDTH := 560.0
const SESSION_PROGRESS_PANEL_HEIGHT := 62.0
const SESSION_PROGRESS_BAR_WIDTH := 520.0
const SESSION_PROGRESS_TOP_MARGIN := 8.0 + GAMEPLAY_VERTICAL_SHIFT
const SESSION_PROGRESS_TRIAL_SHARE := 0.10
const SESSION_PROGRESS_FORMAL_MINUTES := 18.0 * 60.0
const SYSTEM_PANEL_X_OFFSET := 40.0
const SYSTEM_PANEL_WIDTH_REDUCTION := 28.0
const PLAYER_DIALOGUE_OVERLAY_Y_OFFSET := 4.0
const PLAYER_DIALOGUE_OVERLAY_WIDTH := 520.0
const PLAYER_DIALOGUE_OVERLAY_SHOW_SEC := 3.0
const PLAYER_DIALOGUE_STACK_GAP := 10.0
const HELP_PROMPT_MAX_STACK := 2
const HELP_PROMPT_WIDTH_RATIO := 0.95
const HELP_PROMPT_X_OFFSET := 24.0
const HELP_PROMPT_BODY_FONT_SIZE := 24
const HELP_PROMPT_TITLE_FONT_SIZE := 32
const HELP_PROMPT_BUTTON_FONT_SIZE := 22
const HELP_PROMPT_BUTTON_HEIGHT := 60.0
const TRIAL_GUIDE_BODY_FONT_SIZE := 20
const TRIAL_GUIDE_MESSAGE_MIN_WIDTH := 320.0
const HELP_DIALOGUE_STAGE_OPENER := 0
const HELP_DIALOGUE_STAGE_BRIDGE := 1
const HELP_DIALOGUE_STAGE_DELEGATION := 2
const DIALOGUE_PANEL_WIDTH := 340.0
const TUTORIAL_PANEL_WIDTH := 620.0
const TUTORIAL_PANEL_MIN_HEIGHT := 420.0
const TUTORIAL_TOGGLE_SIZE := 44.0
const TUTORIAL_TEXT := "[b]Controls[/b]\nWASD / Arrow Keys: move\nE: interact (take orders, pick up items, deliver items)\nI: inventory (delete items)\nTab: focus interface buttons\nEnter: confirm the focused button\n\n[b]Goal[/b]\nServe customers' drinks before the deadline\nRespond to robot handoff popups\n\n[b]Win and Loss[/b]\nReach the end of Day 1 with a score of 0 or higher to win\nFinish Day 1 below 0 to lose\nReach -30 at any time and the game ends immediately\n\n[b]Robot Handoffs[/b]\nThe robot may ask you to take over an order when it is overloaded, running out of time, or low on battery.\n\n[b]Player Reminders[/b]\nCheck your assigned tasks\nNotice how the robot asks for help"
var _customer_tab: String = CUSTOMER_TAB_LIVE
var _score: int = 0
var _success_count: int = 0
var _failed_count: int = 0
const SCORE_PER_SUCCESS := 2
const SCORE_PER_FAILURE := -6
const SCORE_PER_DRINK_SUCCESS := 1
const SCORE_PER_DRINK_FAILURE := -3
const SCORE_FAIL_THRESHOLD := -30
const SCORE_WIN_THRESHOLD := 0
const SURVEY_PANEL_BASE_SIZE := Vector2(580.0, 300.0)
const SURVEY_PANEL_RESULT_HEIGHT := 220.0
const SURVEY_PANEL_CHARACTER_HEIGHT := 500.0
const SURVEY_PANEL_MARGIN := 24.0
const SURVEY_PANEL_OFFSET_X := 20.0
const SURVEY_QUESTION_Y_OFFSET := -34.0
const SURVEY_RESULT_Y_OFFSET := -20.0
const SURVEY_MODE_NICKNAME := "nickname"
const SURVEY_MODE_CHARACTER := "character"
const SURVEY_MODE_TIPI := "tipi"
const SURVEY_MODE_RESULT := "result"
var _score_game_over: bool = false
var _run_end_active: bool = false
var _game_run_logged: bool = false
var _embedded_completion_sent: bool = false
var _tutorial_started: bool = false
var _customer_history_page: int = 0
var _pending_day_notice: int = 0
var _initial_day_notice_shown: bool = false
var _formal_session_started: bool = false
var _participant_profile_logged: bool = false
var _trial_session_active: bool = false
var _trial_step: String = ""
var _trial_customer: Node2D = null
var _trial_food_task_id: String = ""
var _trial_drink_task_id: String = ""
var _trial_handoff_task_id: String = ""
var _trial_handoff_request_id: String = ""
var _trial_delete_item_uid: int = 0
var _trial_delete_item_name: String = ""
var _trial_drink_pickup_area_confirmed: bool = false
var _session_progress: float = 0.0
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
var _trial_guide_message_box: VBoxContainer = null
var _trial_guide_message_label: RichTextLabel = null
var _trial_guide_continue_button: Button = null
var _trial_guide_continue_callback: Callable = Callable()
var _trial_guide_target: Dictionary = {}
var _player_inventory_holding_label: Label = null
var _player_inventory_item_labels_by_name: Dictionary = {}
const CUSTOMER_HISTORY_PAGE_SIZE := 5
const TRIAL_SESSION_MAX_SEC := 210.0
const TRIAL_FOOD_TASK_WINDOW_MS := 180_000
const TRIAL_DRINK_TASK_WINDOW_MS := 90_000
const TRIAL_GUIDE_FOCUS_BORDER := Color(1.0, 0.93, 0.62, 1.0)
const TRIAL_GUIDE_ARROW_TEXTURE := preload("res://assets/icons/orders/right-arrow.png")
const TRIAL_GUIDE_ARROW_SIZE := Vector2(24.0, 24.0)
const UI_BTN_NEUTRAL_BG := Color(0.18, 0.21, 0.27, 0.96)
const UI_BTN_NEUTRAL_HOVER_BG := Color(0.25, 0.29, 0.36, 0.98)
const UI_BTN_NEUTRAL_PRESSED_BG := Color(0.13, 0.16, 0.21, 0.98)
const UI_BTN_PRIMARY_BG := Color(0.74, 0.58, 0.20, 0.98)
const UI_BTN_PRIMARY_HOVER_BG := Color(0.84, 0.67, 0.25, 1.0)
const UI_BTN_PRIMARY_PRESSED_BG := Color(0.58, 0.44, 0.14, 1.0)
const UI_BTN_DANGER_BG := Color(0.72, 0.22, 0.22, 1.0)
const UI_BTN_DANGER_HOVER_BG := Color(0.84, 0.29, 0.29, 1.0)
const UI_BTN_DANGER_PRESSED_BG := Color(0.56, 0.15, 0.15, 1.0)
const UI_BTN_TAB_BG := Color(0.11, 0.13, 0.17, 0.98)
const UI_BTN_TAB_HOVER_BG := Color(0.20, 0.23, 0.29, 1.0)
const UI_BTN_TAB_PRESSED_BG := Color(0.30, 0.35, 0.42, 1.0)
const UI_BTN_TEXT_LIGHT := Color(0.96, 0.97, 0.99, 1.0)
const UI_BTN_TEXT_DARK := Color(0.10, 0.08, 0.04, 1.0)
const UI_BTN_BORDER := Color(0.92, 0.96, 1.0, 0.22)
const UI_BTN_FOCUS_BORDER := Color(1.0, 0.88, 0.50, 0.95)
const GAMEPLAY_PANEL_FOCUS_TTL_SEC := 1.2

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")

	if survey_panel:
		survey_panel.hide()

	_setup_survey_scale_buttons()
	survey_confirm.pressed.connect(_finish_survey_and_start)
	_apply_button_theme(survey_confirm, "primary")

	_setup_inventory_ui()
	_setup_inventory_portal_ui()
	_setup_dialogue_feed_ui()
	_setup_customer_orders_ui()
	_setup_session_progress_ui()
	_setup_player_dialogue_overlay_ui()
	_setup_tutorial_ui()
	_setup_survey_input_ui()
	_setup_character_selection_ui()
	_setup_trial_guide_ui()
	_setup_player_task_notice_audio()
	_setup_delegation_voice_audio()
	_set_gameplay_panels_visible(false)
	_connect_viewport_resize()
	_connect_help_signals()
	_connect_dialogue_feed_signals()
	_connect_robot_inventory()
	_connect_player_inventory()
	_connect_task_signals()
	_connect_time_signals()
	call_deferred("_setup_tipi_survey")

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return
	if (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER) and tutorial_panel != null and tutorial_panel.visible and tutorial_start_button != null and tutorial_start_button.visible and not tutorial_start_button.disabled:
		tutorial_start_button.emit_signal("pressed")
		get_viewport().set_input_as_handled()
		return
	if _survey_mode == SURVEY_MODE_NICKNAME:
		if (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER) and _survey_nickname_input != null and _survey_nickname_input.visible:
			_finish_survey_and_start()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
		return
	if _survey_mode == SURVEY_MODE_CHARACTER:
		if _handle_character_selection_key(key_event):
			get_viewport().set_input_as_handled()
		return
	if _survey_mode == SURVEY_MODE_TIPI:
		if _handle_tipi_keyboard_key(key_event):
			get_viewport().set_input_as_handled()
		return
	if _survey_mode == SURVEY_MODE_RESULT:
		if (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER) and survey_panel != null and survey_panel.visible and survey_confirm != null and survey_confirm.visible and not survey_confirm.disabled:
			_finish_survey_and_start()
			get_viewport().set_input_as_handled()
			return
	if (key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER) and tutorial_panel != null and tutorial_panel.visible and tutorial_close_button != null and tutorial_close_button.visible and not tutorial_close_button.disabled:
		_close_tutorial_overlay()
		get_viewport().set_input_as_handled()
		return
	if is_inventory_portal_visible():
		if _handle_inventory_delete_keyboard_key(key_event):
			get_viewport().set_input_as_handled()
		return
	if (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER) and _trial_guide_continue_button != null and _trial_guide_continue_button.visible and not _trial_guide_continue_button.disabled:
		_on_trial_guide_continue_pressed()
		get_viewport().set_input_as_handled()
		return
	if _popup_mode != POPUP_MODE_NONE and player_dialogue_overlay != null and player_dialogue_overlay.visible:
		if _handle_overlay_keyboard_key(key_event):
			get_viewport().set_input_as_handled()
		return
	if not _help_prompt_cards.is_empty():
		if _handle_help_prompt_keyboard_key(key_event):
			get_viewport().set_input_as_handled()
			return
	if _tutorial_started and (tutorial_panel == null or not tutorial_panel.visible):
		if _handle_gameplay_panel_keyboard_key(key_event):
			get_viewport().set_input_as_handled()
			return

func _handle_character_selection_key(key_event: InputEventKey) -> bool:
	var keycode := key_event.keycode
	var next_index := _character_focus_index
	match keycode:
		KEY_LEFT:
			if _character_focus_index % 2 == 1:
				next_index -= 1
		KEY_RIGHT:
			if _character_focus_index % 2 == 0:
				next_index += 1
		KEY_UP:
			if _character_focus_index >= 2:
				next_index -= 2
		KEY_DOWN:
			if _character_focus_index < CHARACTER_IDS.size() - 2:
				next_index += 2
		KEY_TAB:
			var step := -1 if key_event.shift_pressed else 1
			next_index = posmod(_character_focus_index + step, CHARACTER_IDS.size())
		KEY_ENTER, KEY_KP_ENTER:
			_finish_survey_and_start()
			return true
		_:
			return false
	if next_index != _character_focus_index:
		_on_character_selected(CHARACTER_IDS[next_index])
		_focus_character_option(next_index)
	return true

func _handle_tipi_keyboard_key(key_event: InputEventKey) -> bool:
	if key_event.keycode == KEY_TAB:
		var step := -1 if key_event.shift_pressed else 1
		if _tipi_keyboard_focus_index < 0:
			_tipi_keyboard_focus_index = _survey_scale_buttons.size() - 1 if step < 0 else 0
		else:
			_tipi_keyboard_focus_index = posmod(_tipi_keyboard_focus_index + step, _survey_scale_buttons.size())
		_survey_scale_buttons[_tipi_keyboard_focus_index].grab_focus()
		return true
	var keycode := key_event.keycode
	var result := _update_choice_focus(keycode, _survey_scale_buttons, _tipi_keyboard_focus_index)
	if not bool(result.get("handled", false)):
		return false
	_tipi_keyboard_focus_index = int(result.get("focus_index", -1))
	if bool(result.get("activate", false)) and _tipi_keyboard_focus_index >= 0:
		_choose_tipi(_tipi_keyboard_focus_index + 1)
	return true

func _handle_overlay_keyboard_key(key_event: InputEventKey) -> bool:
	var buttons := _visible_overlay_choice_buttons()
	var result := _update_tab_choice_focus(key_event, buttons, _overlay_keyboard_focus_index)
	if not bool(result.get("handled", false)):
		return false
	_overlay_keyboard_focus_index = int(result.get("focus_index", -1))
	if bool(result.get("activate", false)) and _overlay_keyboard_focus_index >= 0:
		buttons[_overlay_keyboard_focus_index].emit_signal("pressed")
	return true

func _handle_help_prompt_keyboard_key(key_event: InputEventKey) -> bool:
	var buttons := _visible_help_prompt_choice_buttons()
	var result := _update_tab_choice_focus(key_event, buttons, _help_keyboard_focus_index)
	if not bool(result.get("handled", false)):
		return false
	_help_keyboard_focus_index = int(result.get("focus_index", -1))
	if bool(result.get("activate", false)) and _help_keyboard_focus_index >= 0:
		buttons[_help_keyboard_focus_index].emit_signal("pressed")
	return true

func _handle_inventory_delete_keyboard_key(key_event: InputEventKey) -> bool:
	if _inventory_delete_buttons.is_empty():
		return false
	var keycode := key_event.keycode
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		if _inventory_delete_keyboard_focus_index < 0 or _inventory_delete_keyboard_focus_index >= _inventory_delete_buttons.size():
			return false
		_inventory_delete_buttons[_inventory_delete_keyboard_focus_index].emit_signal("pressed")
		return true
	var result := _update_tab_choice_focus(key_event, _inventory_delete_buttons, _inventory_delete_keyboard_focus_index)
	if not bool(result.get("handled", false)):
		return false
	_inventory_delete_keyboard_focus_index = int(result.get("focus_index", -1))
	return true

func _reset_inventory_delete_keyboard_focus() -> void:
	_inventory_delete_keyboard_focus_index = -1
	_clear_choice_focus(_inventory_delete_buttons)

func _handle_gameplay_panel_keyboard_key(key_event: InputEventKey) -> bool:
	var buttons := _gameplay_panel_keyboard_buttons()
	if buttons.is_empty():
		return false
	if key_event.keycode == KEY_TAB:
		var step := -1 if key_event.shift_pressed else 1
		var next_index := _gameplay_panel_keyboard_focus_index + step
		if _gameplay_panel_keyboard_focus_index < 0:
			next_index = buttons.size() - 1 if key_event.shift_pressed else 0
		if next_index < 0 or next_index >= buttons.size():
			_reset_gameplay_panel_keyboard_focus()
			return true
		_set_gameplay_panel_keyboard_focus(next_index, buttons)
		return true
	if (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER) and _gameplay_panel_keyboard_focus_index >= 0 and _gameplay_panel_keyboard_focus_index < buttons.size():
		var button := buttons[_gameplay_panel_keyboard_focus_index]
		_reset_gameplay_panel_keyboard_focus()
		button.emit_signal("pressed")
		return true
	return false

func _gameplay_panel_keyboard_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for button in [tutorial_toggle_button, customer_live_btn, customer_history_btn]:
		if button != null and button.visible and not button.disabled:
			buttons.append(button)
	return buttons

func _reset_gameplay_panel_keyboard_focus() -> void:
	_gameplay_panel_focus_token += 1
	if _gameplay_panel_focus_tween != null:
		_gameplay_panel_focus_tween.kill()
		_gameplay_panel_focus_tween = null
	_gameplay_panel_keyboard_focus_index = -1
	_clear_choice_focus(_gameplay_panel_keyboard_buttons())

func _set_gameplay_panel_keyboard_focus(index: int, buttons: Array[Button]) -> void:
	if index < 0 or index >= buttons.size():
		return
	_gameplay_panel_focus_token += 1
	if _gameplay_panel_focus_tween != null:
		_gameplay_panel_focus_tween.kill()
	_gameplay_panel_keyboard_focus_index = index
	buttons[index].grab_focus()
	var token := _gameplay_panel_focus_token
	_gameplay_panel_focus_tween = create_tween()
	_gameplay_panel_focus_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_gameplay_panel_focus_tween.tween_interval(GAMEPLAY_PANEL_FOCUS_TTL_SEC)
	_gameplay_panel_focus_tween.tween_callback(func() -> void:
		if token == _gameplay_panel_focus_token:
			_gameplay_panel_focus_tween = null
			_gameplay_panel_keyboard_focus_index = -1
			_clear_choice_focus(_gameplay_panel_keyboard_buttons())
	)

func _update_choice_focus(keycode: Key, buttons: Array[Button], current_index: int) -> Dictionary:
	if buttons.is_empty():
		return {"handled": false}
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		if buttons.size() == 1:
			return {"handled": true, "focus_index": 0, "activate": true}
		return {
			"handled": current_index >= 0 and current_index < buttons.size(),
			"focus_index": current_index,
			"activate": true,
		}
	var next_index := current_index
	match keycode:
		KEY_LEFT, KEY_UP:
			next_index = buttons.size() - 1 if current_index < 0 else max(current_index - 1, 0)
		KEY_RIGHT, KEY_DOWN:
			next_index = 0 if current_index < 0 else min(current_index + 1, buttons.size() - 1)
		_:
			return {"handled": false}
	if next_index != current_index:
		buttons[next_index].grab_focus()
	return {"handled": true, "focus_index": next_index, "activate": false}

func _update_tab_choice_focus(key_event: InputEventKey, buttons: Array[Button], current_index: int) -> Dictionary:
	if buttons.is_empty():
		return {"handled": false}
	var keycode := key_event.keycode
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		if buttons.size() == 1:
			return {"handled": true, "focus_index": 0, "activate": true}
		return {
			"handled": current_index >= 0 and current_index < buttons.size(),
			"focus_index": current_index,
			"activate": true,
		}
	if keycode != KEY_TAB:
		return {"handled": false}
	var next_index := current_index
	if current_index < 0:
		next_index = buttons.size() - 1 if key_event.shift_pressed else 0
	else:
		next_index += -1 if key_event.shift_pressed else 1
	if next_index < 0 or next_index >= buttons.size():
		_clear_choice_focus(buttons)
		return {"handled": true, "focus_index": -1, "activate": false}
	buttons[next_index].grab_focus()
	return {"handled": true, "focus_index": next_index, "activate": false}

func _visible_overlay_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for button in _all_overlay_choice_buttons():
		if button != null and button.visible and not button.disabled:
			buttons.append(button)
	return buttons

func _all_overlay_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for button in [player_dialogue_overlay_accept_btn, player_dialogue_overlay_decline_btn, player_dialogue_overlay_third_btn]:
		if button != null:
			buttons.append(button)
	return buttons

func _visible_help_prompt_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for button in _all_help_prompt_choice_buttons():
		if button.visible and not button.disabled:
			buttons.append(button)
	return buttons

func _all_help_prompt_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for entry in _help_prompt_cards:
		for button_key in ["accept_btn", "decline_btn"]:
			var button: Button = entry.get(button_key, null)
			if button != null:
				buttons.append(button)
	return buttons

func _clear_choice_focus(buttons: Array[Button]) -> void:
	for button in buttons:
		if button != null and button.has_focus():
			button.release_focus()

func _reset_help_prompt_keyboard_focus() -> void:
	_help_keyboard_focus_index = -1
	_clear_choice_focus(_all_help_prompt_choice_buttons())

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

func _setup_session_progress_ui() -> void:
	session_progress_panel = PanelContainer.new()
	session_progress_panel.name = "SessionProgressPanel"
	session_progress_panel.visible = false
	session_progress_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(session_progress_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.09, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.74, 0.58, 0.20, 0.62)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_right = 9
	style.corner_radius_bottom_left = 9
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	session_progress_panel.add_theme_stylebox_override("panel", style)
	session_progress_panel.custom_minimum_size = Vector2(SESSION_PROGRESS_PANEL_WIDTH, SESSION_PROGRESS_PANEL_HEIGHT)

	var content := Control.new()
	content.custom_minimum_size = Vector2(SESSION_PROGRESS_BAR_WIDTH, 44.0)
	session_progress_panel.add_child(content)

	session_progress_bar = ProgressBar.new()
	session_progress_bar.show_percentage = false
	session_progress_bar.min_value = 0.0
	session_progress_bar.max_value = 100.0
	session_progress_bar.custom_minimum_size = Vector2(SESSION_PROGRESS_BAR_WIDTH, 8.0)
	session_progress_bar.position = Vector2(0.0, 27.0)
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.13, 0.16, 0.21, 0.95)
	track_style.corner_radius_top_left = 4
	track_style.corner_radius_top_right = 4
	track_style.corner_radius_bottom_right = 4
	track_style.corner_radius_bottom_left = 4
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.74, 0.58, 0.20, 0.98)
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_right = 4
	fill_style.corner_radius_bottom_left = 4
	session_progress_bar.add_theme_stylebox_override("background", track_style)
	session_progress_bar.add_theme_stylebox_override("fill", fill_style)
	content.add_child(session_progress_bar)
	_add_session_progress_anchors(content)
	_set_session_progress(0.0)

func _add_session_progress_anchors(container: Control) -> void:
	var anchors := [
		{"label": "Trial", "progress": 0.0},
		{"label": "Morning", "progress": 0.10},
		{"label": "Lunch", "progress": 0.30},
		{"label": "Afternoon", "progress": 0.50},
		{"label": "Dinner", "progress": 0.65},
		{"label": "Night", "progress": 0.95},
	]
	for anchor in anchors:
		var progress := float(anchor.get("progress", 0.0))
		var x := progress * SESSION_PROGRESS_BAR_WIDTH
		var tick := ColorRect.new()
		tick.color = Color(0.76, 0.95, 1.0, 0.50)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.position = Vector2(roundf(x), 24.0)
		tick.size = Vector2(1.0, 14.0)
		container.add_child(tick)

		var label := Label.new()
		label.text = str(anchor.get("label", ""))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.76, 0.95, 1.0, 0.88))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label_width := minf(72.0, SESSION_PROGRESS_BAR_WIDTH - x)
		label.position = Vector2(roundf(x), 0.0)
		label.size = Vector2(label_width, 18.0)
		container.add_child(label)

func _set_session_progress(value: float) -> void:
	_session_progress = clampf(value, 0.0, 1.0)
	if session_progress_bar:
		session_progress_bar.value = _session_progress * 100.0

func _refresh_formal_session_progress() -> void:
	if not _formal_session_started:
		return
	var time_mgr = get_node_or_null("/root/GameManager/TimeManager")
	if time_mgr == null:
		return
	var clock_minutes := int(time_mgr.get("current_hour")) * 60 + int(time_mgr.get("current_minute"))
	var elapsed_minutes := float(clock_minutes - 6 * 60)
	if clock_minutes < 6 * 60:
		elapsed_minutes += 24.0 * 60.0
	var day_progress := clampf(elapsed_minutes / SESSION_PROGRESS_FORMAL_MINUTES, 0.0, 1.0)
	_set_session_progress(SESSION_PROGRESS_TRIAL_SHARE + (1.0 - SESSION_PROGRESS_TRIAL_SHARE) * day_progress)

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
	var panel_base_h := SURVEY_PANEL_BASE_SIZE.y
	if _survey_mode == SURVEY_MODE_RESULT:
		panel_base_h = SURVEY_PANEL_RESULT_HEIGHT
	elif _survey_mode == SURVEY_MODE_CHARACTER:
		panel_base_h = SURVEY_PANEL_CHARACTER_HEIGHT
	var target_h := clampf(panel_base_h, 220.0, maxf(220.0, view_size.y - SURVEY_PANEL_MARGIN * 2.0))
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

func _make_button_style(bg: Color, border: Color, radius: int = 10, border_width: int = 1, pad_x: int = 14, pad_y: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style

func _apply_button_theme(button: Button, variant: String = "neutral") -> void:
	if button == null:
		return
	var normal_bg := UI_BTN_NEUTRAL_BG
	var hover_bg := UI_BTN_NEUTRAL_HOVER_BG
	var pressed_bg := UI_BTN_NEUTRAL_PRESSED_BG
	var font_color := UI_BTN_TEXT_LIGHT
	var border_color := UI_BTN_BORDER
	var radius := 10
	var border_width := 1
	var pad_x := 14
	var pad_y := 8
	match variant:
		"primary":
			normal_bg = UI_BTN_PRIMARY_BG
			hover_bg = UI_BTN_PRIMARY_HOVER_BG
			pressed_bg = UI_BTN_PRIMARY_PRESSED_BG
			font_color = UI_BTN_TEXT_DARK
			border_color = Color(1.0, 0.94, 0.72, 0.55)
		"danger":
			normal_bg = Color(0.66, 0.22, 0.22, 1.0)
			hover_bg = Color(0.76, 0.28, 0.28, 1.0)
			pressed_bg = Color(0.52, 0.16, 0.16, 1.0)
			font_color = Color(1.0, 0.97, 0.97, 1.0)
			border_color = Color(1.0, 0.82, 0.82, 0.22)
			radius = 7
			pad_x = 8
			pad_y = 4
		"tab":
			normal_bg = UI_BTN_TAB_BG
			hover_bg = UI_BTN_TAB_HOVER_BG
			pressed_bg = UI_BTN_TAB_PRESSED_BG
			font_color = UI_BTN_TEXT_LIGHT
			border_color = Color(0.76, 0.95, 1.0, 0.24)
			radius = 7
			pad_x = 12
			pad_y = 6
	var normal_style := _make_button_style(normal_bg, border_color, radius, border_width, pad_x, pad_y)
	var hover_style := _make_button_style(hover_bg, border_color.lerp(UI_BTN_FOCUS_BORDER, 0.35), radius, border_width, pad_x, pad_y)
	var pressed_style := _make_button_style(pressed_bg, border_color.lerp(UI_BTN_FOCUS_BORDER, 0.18), radius, border_width, pad_x, pad_y)
	var focus_style := _make_button_style(hover_bg, UI_BTN_FOCUS_BORDER, radius, max(border_width, 2), pad_x, pad_y)
	var disabled_style := _make_button_style(normal_bg.darkened(0.18), border_color * Color(1.0, 1.0, 1.0, 0.55), radius, border_width, pad_x, pad_y)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_color_override("font_focus_color", font_color)
	button.add_theme_color_override("font_disabled_color", font_color * Color(1.0, 1.0, 1.0, 0.58))

func _apply_nickname_input_theme(line_edit: LineEdit) -> void:
	if line_edit == null:
		return
	var border := Color(0.90, 0.76, 0.34, 0.75)
	var bg := Color(0.09, 0.10, 0.14, 0.96)
	var normal_style := _make_button_style(bg, border, 10, 1, 14, 10)
	var hover_style := _make_button_style(bg, border, 10, 1, 14, 10)
	var focus_style := _make_button_style(bg, border, 10, 1, 14, 10)
	var read_only_style := _make_button_style(bg, border * Color(1.0, 1.0, 1.0, 0.65), 10, 1, 14, 10)
	line_edit.add_theme_stylebox_override("normal", normal_style)
	line_edit.add_theme_stylebox_override("hover", hover_style)
	line_edit.add_theme_stylebox_override("focus", focus_style)
	line_edit.add_theme_stylebox_override("read_only", read_only_style)
	line_edit.add_theme_color_override("font_color", UI_BTN_TEXT_LIGHT)
	line_edit.add_theme_color_override("font_placeholder_color", Color(0.78, 0.71, 0.55, 0.72))
	line_edit.add_theme_color_override("caret_color", Color(1.0, 0.90, 0.58, 1.0))
	line_edit.add_theme_color_override("selection_color", Color(0.36, 0.51, 0.82, 0.65))

func _apply_default_overlay_button_themes() -> void:
	if player_dialogue_overlay_accept_btn:
		_apply_button_theme(player_dialogue_overlay_accept_btn, "primary")
	if player_dialogue_overlay_decline_btn:
		_apply_button_theme(player_dialogue_overlay_decline_btn, "neutral")
	if player_dialogue_overlay_third_btn:
		_apply_button_theme(player_dialogue_overlay_third_btn, "neutral")

func _apply_kitchen_pick_button_themes() -> void:
	if player_dialogue_overlay_accept_btn:
		_apply_button_theme(player_dialogue_overlay_accept_btn, "neutral")
	if player_dialogue_overlay_decline_btn:
		_apply_button_theme(player_dialogue_overlay_decline_btn, "neutral")
	if player_dialogue_overlay_third_btn:
		_apply_button_theme(player_dialogue_overlay_third_btn, "neutral")

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

func _setup_inventory_portal_ui() -> void:
	inventory_portal_panel = PanelContainer.new()
	inventory_portal_panel.name = "InventoryPortalPanel"
	inventory_portal_panel.visible = false
	add_child(inventory_portal_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.94)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.38, 0.82, 0.92, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	inventory_portal_panel.add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	inventory_portal_panel.add_child(root)

	var title := Label.new()
	title.text = "Inventory Portal"
	title.add_theme_color_override("font_color", Color(0.90, 0.97, 1.0, 1.0))
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Press I or Esc to close."
	hint.add_theme_color_override("font_color", Color(0.75, 0.83, 0.90, 0.95))
	root.add_child(hint)

	inventory_portal_list = VBoxContainer.new()
	inventory_portal_list.add_theme_constant_override("separation", 6)
	root.add_child(inventory_portal_list)

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
	_apply_button_theme(customer_live_btn, "tab")
	customer_tab_buttons.add_child(customer_live_btn)

	customer_history_btn = Button.new()
	customer_history_btn.text = "History"
	customer_history_btn.toggle_mode = true
	customer_history_btn.button_pressed = false
	customer_history_btn.pressed.connect(func():
		_set_customer_tab(CUSTOMER_TAB_HISTORY)
	)
	_apply_button_theme(customer_history_btn, "tab")
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
	_apply_button_theme(customer_history_prev_btn, "tab")
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
	_apply_button_theme(customer_history_next_btn, "tab")
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

	player_dialogue_overlay_third_btn = Button.new()
	player_dialogue_overlay_third_btn.text = ""
	player_dialogue_overlay_third_btn.pressed.connect(func(): _respond("third"))
	player_dialogue_overlay_buttons.add_child(player_dialogue_overlay_third_btn)
	_apply_default_overlay_button_themes()

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
	if time_mgr.has_signal("run_day_completed") and not time_mgr.run_day_completed.is_connected(_on_run_day_completed_notice):
		time_mgr.run_day_completed.connect(_on_run_day_completed_notice)
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
	_refresh_formal_session_progress()

func _on_period_changed_label(_period_name: String, _is_peak: bool) -> void:
	_refresh_day_phase_label()

func _on_day_changed_notice(day: int) -> void:
	if day <= 0:
		return
	if not _formal_session_started:
		_pending_day_notice = day
		return
	if day > 1:
		return
	_initial_day_notice_shown = true
	var message := "You have entered Day %d." % day
	if day == 1:
		message = "The formal session is starting. You have entered Day 1."
	_show_player_dialogue_overlay("System", message, "system")

func _on_run_day_completed_notice(day: int) -> void:
	if day <= 0 or not _formal_session_started:
		return
	_set_session_progress(1.0)
	if _score >= SCORE_WIN_THRESHOLD:
		_log_game_run_once("win")
		_show_run_end_prompt(
			"You Win",
			"Great work! You made it through Day %d with a score of %d." % [day, _score]
		)
	else:
		_log_game_run_once("end_of_day_loss")
		_show_run_end_prompt(
			"Game Over",
			"So close. Day %d is over, and you finished with %d, just short of making it through." % [day, _score]
		)

func _on_task_created(task: Dictionary) -> void:
	var payload: Dictionary = task.get("payload", {})
	if _trial_session_active and _is_trial_customer_task(payload):
		var order_kind := str(payload.get("order_kind", "food"))
		if order_kind == "food" and _trial_step == "await_food_order":
			_trial_food_task_id = str(task.get("id", ""))
			_trial_step = "await_robot_ready"
		elif order_kind == "drink":
			_trial_drink_task_id = str(task.get("id", ""))
			_show_trial_guide_for_drink_request()
			_trial_step = "await_take_order"
	if str(payload.get("order_kind", "")) != "drink":
		return
	if str(task.get("assigned_to", "")).strip_edges() != "":
		return
	_play_new_order_notice()

func _on_task_updated(task: Dictionary) -> void:
	if not _trial_session_active:
		return
	if str(task.get("id", "")) == _trial_food_task_id and _trial_food_task_id != "":
		var board_food = get_node_or_null("/root/TaskBoard")
		var step_name_food := ""
		if board_food and board_food.has_method("get_current_step_name"):
			step_name_food = str(board_food.get_current_step_name(_trial_food_task_id))
		var assignee_food := str(task.get("assigned_to", ""))
		if _trial_handoff_task_id == "" and assignee_food != "" and step_name_food == "PICKUP_FROM_KITCHEN":
			_trial_handoff_task_id = _trial_food_task_id
			var robot_food = _trial_robot()
			if robot_food != null and robot_food.has_method("arm_trial_item_handoff"):
				robot_food.call("arm_trial_item_handoff", _trial_food_task_id)
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

func _on_task_completed(task: Dictionary) -> void:
	if _trial_session_active:
		var completed_id := str(task.get("id", ""))
		if completed_id == _trial_drink_task_id:
			call_deferred("_begin_trial_delete_demo")
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
	_log_game_run_once("score_threshold_loss")
	_show_run_end_prompt(
		"Game Over",
		"Unfortunately, the restaurant fell too far behind. Your score reached %d." % _score
	)

func _log_game_run_once(run_outcome: String) -> void:
	if _game_run_logged or not _formal_session_started:
		return
	var logger = get_node_or_null("/root/EpisodeLogger")
	if logger and logger.has_method("log_game_run"):
		logger.log_game_run(run_outcome, _score)
		_game_run_logged = true

func _show_run_end_prompt(title: String, body: String) -> void:
	if _run_end_active:
		return
	_run_end_active = true
	_set_global_pause(true)
	_popup_mode = POPUP_MODE_GAME_OVER
	var end_action := "Continue" if _is_embedded_web_session() else "Play Again"
	_show_player_dialogue_prompt(title, body, [end_action], false)

func _is_embedded_web_session() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("Boolean(window.WeakRobotRestaurantEmbed && window.WeakRobotRestaurantEmbed.isEmbedded)", true))

func _complete_embedded_web_session() -> void:
	if _embedded_completion_sent:
		return
	_embedded_completion_sent = true
	JavaScriptBridge.eval("window.WeakRobotRestaurantEmbed && window.WeakRobotRestaurantEmbed.complete()", true)
	if player_dialogue_overlay_accept_btn:
		player_dialogue_overlay_accept_btn.disabled = true
		player_dialogue_overlay_accept_btn.text = "Returning..."

func _on_game_over_play_again() -> void:
	_set_global_pause(false)
	_run_end_active = false
	_score_game_over = false
	_embedded_completion_sent = false
	_popup_mode = POPUP_MODE_NONE
	var logger = get_node_or_null("/root/EpisodeLogger")
	if logger and logger.has_method("reset_session"):
		logger.reset_session()
		if logger.has_method("log_delegation_templates"):
			var engine = load("res://scripts/PersuasionEngine.gd")
			if engine and engine.has_method("get_template_records"):
				logger.log_delegation_templates(engine.get_template_records())
	var profile = get_node_or_null("/root/PlayerProfile")
	if profile and profile.has_method("reset_profile"):
		profile.reset_profile()
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
	_player_inventory_holding_label = null
	_player_inventory_item_labels_by_name.clear()

	var holding = Label.new()
	holding.text = "Holding (%d/%d):" % [items.size(), _get_player_capacity()]
	holding.add_theme_color_override("font_color", Color(0.80, 0.94, 1.0, 1.0))
	player_items_box.add_child(holding)
	_player_inventory_holding_label = holding

	if items.is_empty():
		_add_blank_row(player_items_box)
	else:
		for i in range(items.size()):
			var item = items[i]
			var l = Label.new()
			var n = item.get("name", "Unknown")
			l.text = "[%d] %s" % [i + 1, n]
			player_items_box.add_child(l)
			_player_inventory_item_labels_by_name[str(n).strip_edges().to_lower()] = l
	_refresh_inventory_portal(items)
	if _trial_session_active and _trial_step == "await_delete_confirm" and _trial_delete_item_uid > 0 and not _inventory_contains_uid(items, _trial_delete_item_uid):
		_trial_delete_item_uid = 0
		_trial_delete_item_name = ""
		hide_inventory_portal()
		_hide_trial_guide()
		_trial_step = "await_delegation"
		call_deferred("_activate_trial_handoff_request")

func _refresh_inventory_portal(items: Array) -> void:
	if inventory_portal_list == null:
		return
	_reset_inventory_delete_keyboard_focus()
	_inventory_delete_buttons.clear()
	_clear_dynamic_children(inventory_portal_list)
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No items in inventory."
		empty.add_theme_color_override("font_color", Color(0.78, 0.84, 0.90, 0.9))
		inventory_portal_list.add_child(empty)
		return
	for raw_item in items:
		var item: Dictionary = raw_item
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 4)
		var label := Label.new()
		label.text = str(item.get("name", "Unknown")).capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var delete_btn := Button.new()
		delete_btn.text = "Delete"
		delete_btn.custom_minimum_size = Vector2(44.0, 0.0)
		_apply_button_theme(delete_btn, "danger")
		delete_btn.set_meta("inventory_item_uid", int(item.get("uid", 0)))
		delete_btn.pressed.connect(_on_inventory_portal_delete_pressed.bind(int(item.get("uid", 0))), CONNECT_DEFERRED)
		row.add_child(delete_btn)
		_inventory_delete_buttons.append(delete_btn)
		inventory_portal_list.add_child(row)

func _on_inventory_portal_delete_pressed(item_uid: int) -> void:
	if item_uid <= 0:
		return
	inventory_delete_requested.emit(item_uid)

func toggle_inventory_portal() -> void:
	if inventory_portal_panel == null:
		return
	if inventory_portal_panel.visible:
		hide_inventory_portal()
	else:
		show_inventory_portal()

func show_inventory_portal() -> void:
	if inventory_portal_panel == null:
		return
	inventory_portal_panel.visible = true
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var player = players[0]
		var inv = null
		if "inventory" in player and player.inventory != null:
			inv = player.inventory
		else:
			inv = player.get_node_or_null("Inventory")
		if inv != null:
			_refresh_inventory_portal(inv.items)
	_update_gameplay_panel_layout()
	if _trial_session_active and _trial_step == "await_delete_open":
		_trial_step = "await_delete_confirm"
		call_deferred("_show_trial_guide_for_delete_confirm")

func hide_inventory_portal() -> void:
	if inventory_portal_panel == null:
		return
	_reset_inventory_delete_keyboard_focus()
	inventory_portal_panel.visible = false
	if _trial_session_active and _trial_step == "await_delete_confirm" and _trial_has_delete_item():
		_trial_step = "await_delete_open"
		call_deferred("_show_trial_guide_for_delete_open")

func is_inventory_portal_visible() -> bool:
	return inventory_portal_panel != null and inventory_portal_panel.visible

func _process(_dt: float) -> void:
	_update_battery_label()
	_update_robot_task_panel()
	_update_player_task_panel()
	_update_customer_panel()
	_update_gameplay_panel_layout()
	_update_trial_guide_overlay()

func _get_ui_now_ms() -> int:
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_gameplay_time_ms"):
		return int(game_mgr.get_gameplay_time_ms())
	return Time.get_ticks_msec()

func _set_global_pause(paused: bool) -> void:
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("set_gameplay_paused"):
		game_mgr.set_gameplay_paused(paused)
	get_tree().paused = paused

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
	if session_progress_panel:
		var progress_size := Vector2(SESSION_PROGRESS_PANEL_WIDTH, SESSION_PROGRESS_PANEL_HEIGHT)
		session_progress_panel.size = progress_size
		session_progress_panel.position = Vector2(
			center_x - progress_size.x * 0.5,
			SESSION_PROGRESS_TOP_MARGIN
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
	var stack_origin_y: float = maxf(
		SESSION_PROGRESS_TOP_MARGIN + SESSION_PROGRESS_PANEL_HEIGHT + 16.0,
		gameplay_top_y + PLAYER_DIALOGUE_OVERLAY_Y_OFFSET
	)
	var stack_y: float = stack_origin_y
	if help_prompt_stack:
		var help_prompt_width := GAMEPLAY_BAND_WIDTH * HELP_PROMPT_WIDTH_RATIO
		help_prompt_stack.custom_minimum_size.x = help_prompt_width
		if help_prompt_stack.visible:
			var help_h := maxf(help_prompt_stack.size.y, help_prompt_stack.get_combined_minimum_size().y)
			var help_x := center_x - help_prompt_width * 0.5 + HELP_PROMPT_X_OFFSET
			var help_y := maxf(SESSION_PROGRESS_TOP_MARGIN + SESSION_PROGRESS_PANEL_HEIGHT + 16.0, (view_size.y - help_h) * 0.44)
			help_prompt_stack.position = Vector2(help_x, help_y)
			stack_y += help_h + PLAYER_DIALOGUE_STACK_GAP
		else:
			help_prompt_stack.position = Vector2(center_x - help_prompt_width * 0.5 + HELP_PROMPT_X_OFFSET, stack_origin_y)
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
	if inventory_portal_panel:
		var portal_size := inventory_portal_panel.get_combined_minimum_size()
		portal_size.x = maxf(192.0, portal_size.x)
		portal_size.y = maxf(160.0, portal_size.y)
		inventory_portal_panel.custom_minimum_size = portal_size
		inventory_portal_panel.size = portal_size
		var portal_pos := Vector2(
			(view_size.x - portal_size.x) * 0.5,
			maxf(72.0, gameplay_top_y + 40.0)
		)
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty() and players[0] is Node2D:
			var player_screen := _world_to_screen((players[0] as Node2D).global_position + Vector2(0.0, -118.0))
			portal_pos = Vector2(
				player_screen.x - portal_size.x * 0.5,
				player_screen.y - portal_size.y - 14.0
			)
		portal_pos.x = clampf(portal_pos.x, 12.0, maxf(12.0, view_size.x - portal_size.x - 12.0))
		portal_pos.y = clampf(portal_pos.y, 12.0, maxf(12.0, view_size.y - portal_size.y - 12.0))
		inventory_portal_panel.position = portal_pos
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
			var remain_sec := int(ceili(float(deadline_ms - _get_ui_now_ms()) / 1000.0))
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
	var clamped_level := clampi(level, 0, 100)
	if mode == "emergency" and clamped_level <= 0:
		battery_label.text = "Battery: Low"
	else:
		battery_label.text = "Battery: %d%%" % clamped_level

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
	var now_ms := _get_ui_now_ms()
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
			var remain_sec := int(ceili(float(deadline_ms - _get_ui_now_ms()) / 1000.0))
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

func _setup_delegation_voice_audio() -> void:
	_delegation_voice_player = AudioStreamPlayer.new()
	_delegation_voice_player.name = "DelegationVoice"
	_delegation_voice_player.bus = &"Master"
	add_child(_delegation_voice_player)

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
		child.queue_free()

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
		help_prompt_stack.visible = false
	_update_delegation_pause_state()
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

func _build_help_text(request: Dictionary, dialogue_stage: int = HELP_DIALOGUE_STAGE_DELEGATION) -> String:
	match dialogue_stage:
		HELP_DIALOGUE_STAGE_OPENER:
			var opener := str(request.get("opener_text", "")).strip_edges()
			if opener != "":
				return opener
		HELP_DIALOGUE_STAGE_BRIDGE:
			var bridge := str(request.get("bridge_text", "")).strip_edges()
			if bridge != "":
				return bridge
	var utterance := str(request.get("utterance", "")).strip_edges()
	if utterance == "":
		utterance = "Can you help now?"
	return utterance

func _help_stage_reply_text(request: Dictionary, dialogue_stage: int) -> String:
	match dialogue_stage:
		HELP_DIALOGUE_STAGE_OPENER:
			return str(request.get("opener_reply_text", "Sure, what do you need?"))
		HELP_DIALOGUE_STAGE_BRIDGE:
			return str(request.get("bridge_reply_text", "Alright, tell me what it is."))
		_:
			return "Accept"

func _respond(response: String) -> void:
	if _popup_mode == POPUP_MODE_KITCHEN_PICK:
		var idx := -1
		match response:
			"accept":
				idx = 0
			"decline":
				idx = 1
			"third":
				idx = 2
		if idx >= 0 and idx < _kitchen_pick_options.size():
			kitchen_pick_selected.emit(_kitchen_pick_options[idx])
		return

	if _popup_mode == POPUP_MODE_GAME_OVER:
		if response == "accept":
			if _is_embedded_web_session():
				_complete_embedded_web_session()
			else:
				_on_game_over_play_again()
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
			_hide_trial_guide()
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
		"Choose an item to add +1 to your inventory.\nPress E, I, or Esc, or leave the kitchen to close.",
		[
			_kitchen_pick_options[0].capitalize(),
			_kitchen_pick_options[1].capitalize(),
			_kitchen_pick_options[2].capitalize()
		],
		true
	)
	_apply_kitchen_pick_button_themes()

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
			button = player_dialogue_overlay_third_btn
	_flash_kitchen_pick_button(button, success)

func _reset_help_buttons() -> void:
	if player_dialogue_overlay_accept_btn:
		player_dialogue_overlay_accept_btn.text = "Accept"
	if player_dialogue_overlay_decline_btn:
		player_dialogue_overlay_decline_btn.text = "Decline"
	if player_dialogue_overlay_third_btn:
		player_dialogue_overlay_third_btn.text = ""
	if player_dialogue_overlay_third_btn:
		player_dialogue_overlay_third_btn.visible = false
	_apply_default_overlay_button_themes()

func _flash_kitchen_pick_button(button: Button, success: bool) -> void:
	if button == null or not is_instance_valid(button):
		return
	var flash_token := int(button.get_meta("kitchen_flash_token", 0)) + 1
	button.set_meta("kitchen_flash_token", flash_token)
	var border := Color(0.40, 0.86, 0.48, 1.0) if success else Color(0.92, 0.34, 0.34, 1.0)
	var flash_normal := _make_button_style(UI_BTN_NEUTRAL_BG, border, 10, 2, 14, 8)
	var flash_hover := _make_button_style(UI_BTN_NEUTRAL_HOVER_BG, border, 10, 2, 14, 8)
	var flash_pressed := _make_button_style(UI_BTN_NEUTRAL_PRESSED_BG, border, 10, 2, 14, 8)
	button.add_theme_stylebox_override("normal", flash_normal)
	button.add_theme_stylebox_override("hover", flash_hover)
	button.add_theme_stylebox_override("pressed", flash_pressed)
	button.add_theme_stylebox_override("focus", flash_hover)
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
		_apply_button_theme(button, "neutral")
		survey_options.add_child(button)
		_survey_scale_buttons.append(button)

func _setup_survey_input_ui() -> void:
	if survey_options == null:
		return
	_survey_nickname_input = LineEdit.new()
	_survey_nickname_input.placeholder_text = "Enter your name"
	_survey_nickname_input.max_length = 20
	_survey_nickname_input.custom_minimum_size = Vector2(0, 44)
	_survey_nickname_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_survey_nickname_input.visible = false
	_apply_nickname_input_theme(_survey_nickname_input)
	_survey_nickname_input.text_submitted.connect(func(_text: String) -> void:
		if survey_confirm and survey_confirm.visible:
			_finish_survey_and_start()
	)
	survey_options.add_child(_survey_nickname_input)

func _setup_character_selection_ui() -> void:
	if survey_options == null:
		return
	_character_selection_grid = GridContainer.new()
	_character_selection_grid.columns = 2
	_character_selection_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_character_selection_grid.add_theme_constant_override("h_separation", 10)
	_character_selection_grid.add_theme_constant_override("v_separation", 10)
	_character_selection_grid.hide()
	survey_options.add_child(_character_selection_grid)
	for character_id in CHARACTER_IDS:
		var button := _make_character_selection_button(character_id)
		_character_selection_grid.add_child(button)
		_character_selection_buttons[character_id] = button

func _make_character_selection_button(character_id: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(210.0, 120.0)
	button.pressed.connect(_on_character_selected.bind(character_id))
	_apply_character_selection_button_theme(button, false)

	var portrait := TextureRect.new()
	portrait.texture = _character_idle_texture(character_id)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	portrait.offset_left = -40.0
	portrait.offset_top = -60.0
	portrait.offset_right = 40.0
	portrait.offset_bottom = 40.0
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(portrait)
	return button

func _character_idle_texture(character_id: String) -> Texture2D:
	var sprite_frames = CHARACTER_SPRITE_FRAMES.get(character_id)
	if sprite_frames is SpriteFrames:
		return (sprite_frames as SpriteFrames).get_frame_texture(&"idle_down", 0)
	return null

func _apply_character_selection_button_theme(button: Button, selected: bool) -> void:
	if not selected:
		_apply_button_theme(button, "neutral")
		return
	var normal := _make_button_style(UI_BTN_NEUTRAL_BG, UI_BTN_FOCUS_BORDER, 10, 3, 8, 6)
	var hover := _make_button_style(UI_BTN_NEUTRAL_HOVER_BG, UI_BTN_FOCUS_BORDER, 10, 3, 8, 6)
	var pressed := _make_button_style(UI_BTN_NEUTRAL_PRESSED_BG, UI_BTN_FOCUS_BORDER, 10, 3, 8, 6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", UI_BTN_TEXT_LIGHT)
	button.add_theme_color_override("font_hover_color", UI_BTN_TEXT_LIGHT)
	button.add_theme_color_override("font_pressed_color", UI_BTN_TEXT_LIGHT)
	button.add_theme_color_override("font_focus_color", UI_BTN_TEXT_LIGHT)

func _on_character_selected(character_id: String) -> void:
	if not CHARACTER_SPRITE_FRAMES.has(character_id):
		return
	_character_focus_index = CHARACTER_IDS.find(character_id)
	_selected_character_id = character_id
	var profile = get_node_or_null("/root/PlayerProfile")
	if profile and profile.has_method("set_character"):
		profile.set_character(character_id)
	_apply_character_to_player(character_id)
	for id in _character_selection_buttons:
		var button = _character_selection_buttons[id]
		if button is Button:
			_apply_character_selection_button_theme(button as Button, str(id) == character_id)
	if survey_confirm:
		survey_confirm.disabled = false

func _apply_character_to_player(character_id: String) -> void:
	var sprite_frames = CHARACTER_SPRITE_FRAMES.get(character_id)
	if not (sprite_frames is SpriteFrames):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player = players[0]
	if player is Node and player.has_method("set_character_sprite_frames"):
		player.call("set_character_sprite_frames", sprite_frames)

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
	if profile and profile.has_method("has_tipi") and bool(profile.has_tipi()) and profile.has_method("has_nickname") and bool(profile.has_nickname()) and profile.has_method("has_character") and bool(profile.has_character()):
		if profile.has_method("get_character"):
			_apply_character_to_player(str(profile.get_character()))
		_show_tutorial_before_game()
		return

	await _stabilize_player_camera_before_survey()

	_set_global_pause(true)
	_recenter_survey_panel()
	survey_panel.show()
	_show_nickname_prompt()

func _show_nickname_prompt() -> void:
	_survey_mode = SURVEY_MODE_NICKNAME
	survey_options.alignment = BoxContainer.ALIGNMENT_BEGIN
	var profile = get_node_or_null("/root/PlayerProfile")
	var current_nickname := ""
	if profile and profile.has_method("get_profile"):
		current_nickname = str(profile.get_profile().get("nickname", ""))
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
		survey_scale_title.hide()
	if survey_scale_spacer:
		survey_scale_spacer.hide()
	if survey_scale_hint:
		survey_scale_hint.hide()
	for button in _survey_scale_buttons:
		button.hide()
	if _survey_nickname_input:
		_survey_nickname_input.text = current_nickname
		_survey_nickname_input.show()
		_survey_nickname_input.editable = true
		_survey_nickname_input.call_deferred("grab_focus")
	if _character_selection_grid:
		_character_selection_grid.hide()
	survey_question.custom_minimum_size = Vector2(SURVEY_PANEL_BASE_SIZE.x - 48.0, 36)
	survey_question.text = "What should we call you in the restaurant?"
	if survey_question_title:
		survey_question_title.text = "[b]Nickname[/b]"
	if survey_scale_title:
		survey_scale_title.hide()
	if survey_scale_spacer:
		survey_scale_spacer.hide()
	if survey_scale_hint:
		survey_scale_hint.text = ""
	survey_confirm.text = "Continue"
	survey_confirm.disabled = false
	survey_confirm.show()
	_recenter_survey_panel()

func _show_character_selection() -> void:
	_survey_mode = SURVEY_MODE_CHARACTER
	survey_options.alignment = BoxContainer.ALIGNMENT_CENTER
	_character_focus_index = 0
	if _survey_nickname_input:
		_survey_nickname_input.hide()
	for button in _survey_scale_buttons:
		button.hide()
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
	if survey_question_title:
		survey_question_title.show()
		survey_question_title.text = "[b]Your Character[/b]"
	survey_question.custom_minimum_size = Vector2(SURVEY_PANEL_BASE_SIZE.x - 48.0, 28.0)
	survey_question.text = "Pick the character you want to play."
	if _character_selection_grid:
		_character_selection_grid.show()
	survey_confirm.text = "Continue"
	_on_character_selected(CHARACTER_IDS[0])
	survey_confirm.show()
	_recenter_survey_panel()
	call_deferred("_focus_character_option", 0)

func _focus_character_option(index: int) -> void:
	if index < 0 or index >= CHARACTER_IDS.size():
		return
	var button = _character_selection_buttons.get(CHARACTER_IDS[index])
	if not (button is Button):
		return
	_character_focus_index = index
	(button as Button).grab_focus()

func _begin_tipi_questions() -> void:
	_survey_mode = SURVEY_MODE_TIPI
	_tipi_keyboard_focus_index = -1
	_clear_choice_focus(_survey_scale_buttons)
	survey_options.alignment = BoxContainer.ALIGNMENT_CENTER
	if _survey_nickname_input:
		_survey_nickname_input.hide()
	if _character_selection_grid:
		_character_selection_grid.hide()
	_tipi_index = 0
	_tipi_responses.clear()
	if survey_result_group_spacer:
		survey_result_group_spacer.hide()
	if survey_result_group:
		survey_result_group.hide()
	if survey_result_spacer:
		survey_result_spacer.hide()
	survey_confirm.hide()
	survey_confirm.disabled = false
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
	if _survey_mode != SURVEY_MODE_TIPI:
		return
	if _tipi_index < 0 or _tipi_index >= _tipi_questions.size():
		return
	var q: Dictionary = _tipi_questions[_tipi_index]
	var item_index := int(q.get("item", 0))
	if item_index > 0:
		_tipi_responses[item_index] = clampi(response_value, 1, 7)
	_tipi_keyboard_focus_index = -1
	_clear_choice_focus(_survey_scale_buttons)
	_tipi_index += 1

	if _tipi_index >= _tipi_questions.size():
		_show_tipi_result()
	else:
		_refresh_tipi_question()

func _show_tipi_result() -> void:
	_survey_mode = SURVEY_MODE_RESULT
	var profile = get_node_or_null("/root/PlayerProfile")
	if profile and profile.has_method("set_tipi"):
		profile.set_tipi(_tipi_responses.duplicate(true), _tipi_questions.size())
	if _survey_nickname_input:
		_survey_nickname_input.hide()

	survey_question.custom_minimum_size = Vector2(SURVEY_PANEL_BASE_SIZE.x - 48.0, 24)
	survey_question.text = "Your responses have been recorded."
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
	survey_confirm.text = "Open Tutorial"
	survey_confirm.disabled = false
	survey_confirm.show()
	_recenter_survey_panel()

func _finish_survey_and_start() -> void:
	if _survey_mode == SURVEY_MODE_NICKNAME:
		var nickname := _normalized_nickname(_survey_nickname_input.text if _survey_nickname_input else "")
		if nickname == "":
			if survey_question:
				survey_question.text = "Please enter a nickname using letters, numbers, hyphens, or underscores."
			if _survey_nickname_input:
				_survey_nickname_input.grab_focus()
			return
		if _survey_nickname_input:
			_survey_nickname_input.text = nickname
		var profile = get_node_or_null("/root/PlayerProfile")
		if profile and profile.has_method("set_nickname"):
			profile.set_nickname(nickname)
		_show_character_selection()
		return
	if _survey_mode == SURVEY_MODE_CHARACTER:
		if _selected_character_id == "":
			return
		_begin_tipi_questions()
		return
	survey_panel.hide()
	_show_tutorial_before_game()

func _normalized_nickname(raw_value: String) -> String:
	var trimmed := raw_value.strip_edges()
	if trimmed == "":
		return ""
	var result := ""
	for i in range(trimmed.length()):
		var ch := trimmed.substr(i, 1)
		var code := ch.unicode_at(0)
		var is_upper := code >= 65 and code <= 90
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if is_upper or is_lower or is_digit or ch == "_" or ch == "-":
			result += ch
	return result.left(20)

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
	tutorial_start_button.text = "Start Trial Session"
	tutorial_start_button.custom_minimum_size = Vector2(0, 52)
	tutorial_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_start_button.pressed.connect(_start_game_from_tutorial)
	_apply_button_theme(tutorial_start_button, "primary")
	button_row.add_child(tutorial_start_button)

	tutorial_close_button = Button.new()
	tutorial_close_button.text = "Close"
	tutorial_close_button.custom_minimum_size = Vector2(0, 52)
	tutorial_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_close_button.visible = false
	tutorial_close_button.pressed.connect(_close_tutorial_overlay)
	_apply_button_theme(tutorial_close_button, "neutral")
	button_row.add_child(tutorial_close_button)

	tutorial_toggle_button = Button.new()
	tutorial_toggle_button.name = "TutorialToggle"
	tutorial_toggle_button.text = "?"
	tutorial_toggle_button.visible = false
	tutorial_toggle_button.custom_minimum_size = Vector2(TUTORIAL_TOGGLE_SIZE, TUTORIAL_TOGGLE_SIZE)
	tutorial_toggle_button.tooltip_text = "Tutorial"
	tutorial_toggle_button.add_theme_font_size_override("font_size", 22)
	_apply_button_theme(tutorial_toggle_button, "tab")
	tutorial_toggle_button.pressed.connect(_open_tutorial_overlay)
	add_child(tutorial_toggle_button)

func _show_tutorial_before_game() -> void:
	_set_global_pause(true)
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
	await _dismiss_tutorial_overlay(true)
	_clear_player_input_state()
	_set_global_pause(false)
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
	_set_global_pause(true)
	if tutorial_panel:
		tutorial_panel.show()
	if tutorial_start_button:
		tutorial_start_button.hide()
	if tutorial_close_button:
		tutorial_close_button.text = "Close"
		tutorial_close_button.show()
	if tutorial_toggle_button:
		tutorial_toggle_button.hide()
	_update_gameplay_panel_layout()

func _close_tutorial_overlay() -> void:
	await _dismiss_tutorial_overlay(false)
	_clear_player_input_state()
	_set_global_pause(false)

func _dismiss_tutorial_overlay(start_trial: bool) -> void:
	if tutorial_start_button:
		tutorial_start_button.disabled = true
	if tutorial_close_button:
		tutorial_close_button.disabled = true
	if tutorial_close_button:
		tutorial_close_button.hide()
	if tutorial_toggle_button and not start_trial:
		tutorial_toggle_button.show()
	var tween: Tween = null
	if tutorial_panel:
		tutorial_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		tutorial_panel.scale = Vector2.ONE
		tween = create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(tutorial_panel, "modulate:a", 0.0, 0.32)
	if tween:
		await tween.finished
	if tutorial_panel:
		tutorial_panel.hide()
		tutorial_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		tutorial_panel.scale = Vector2.ONE
	if start_trial:
		_set_gameplay_panels_visible(true)
		_update_gameplay_panel_layout()
		await get_tree().process_frame
		if tutorial_toggle_button:
			tutorial_toggle_button.show()
		await _spotlight_tutorial_toggle()
	if tutorial_start_button:
		tutorial_start_button.disabled = false
		tutorial_start_button.text = "Start Trial Session"
		tutorial_start_button.visible = start_trial
	if tutorial_close_button:
		tutorial_close_button.disabled = false
		tutorial_close_button.visible = false

func _flash_tutorial_toggle() -> void:
	if tutorial_toggle_button == null:
		return
	if _tutorial_toggle_flash_tween:
		_tutorial_toggle_flash_tween.kill()
	tutorial_toggle_button.scale = Vector2.ONE
	tutorial_toggle_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_tutorial_toggle_flash_tween = create_tween()
	_tutorial_toggle_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tutorial_toggle_flash_tween.set_trans(Tween.TRANS_SINE)
	_tutorial_toggle_flash_tween.set_ease(Tween.EASE_OUT)
	_tutorial_toggle_flash_tween.tween_property(tutorial_toggle_button, "scale", Vector2(1.24, 1.24), 0.28)
	_tutorial_toggle_flash_tween.parallel().tween_property(tutorial_toggle_button, "modulate", Color(1.2, 1.16, 0.86, 1.0), 0.28)
	_tutorial_toggle_flash_tween.set_ease(Tween.EASE_IN_OUT)
	_tutorial_toggle_flash_tween.tween_property(tutorial_toggle_button, "scale", Vector2.ONE, 0.42)
	_tutorial_toggle_flash_tween.parallel().tween_property(tutorial_toggle_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.42)
	_tutorial_toggle_flash_tween.finished.connect(func() -> void:
		_tutorial_toggle_flash_tween = null
	)

func _clear_player_input_state() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right", "interact", "ui_cancel"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	Input.flush_buffered_events()

func _set_trial_player_input_locked(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("player"):
		if player and player.has_method("set_input_locked"):
			player.call("set_input_locked", locked)
	if not locked:
		_clear_player_input_state()

func _spotlight_tutorial_toggle() -> void:
	if tutorial_toggle_button == null or not tutorial_toggle_button.visible:
		return
	_show_trial_guide(
		"",
		{
			"type": "control",
			"id": tutorial_toggle_button.get_instance_id()
		},
		""
	)
	_flash_tutorial_toggle()
	var timer := get_tree().create_timer(0.72, true, false, true)
	await timer.timeout
	_hide_trial_guide()

func _set_gameplay_panels_visible(visible: bool) -> void:
	if inventory_panel:
		inventory_panel.visible = visible
	if dialogue_panel:
		dialogue_panel.visible = visible
	if customer_panel:
		customer_panel.visible = visible
	if session_progress_panel:
		session_progress_panel.visible = visible
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
	_trial_guide_message_panel.mouse_filter = Control.MOUSE_FILTER_STOP
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
	message_style.content_margin_left = 18
	message_style.content_margin_right = 18
	message_style.content_margin_top = 12
	message_style.content_margin_bottom = 12
	_trial_guide_message_panel.add_theme_stylebox_override("panel", message_style)
	_trial_guide_layer.add_child(_trial_guide_message_panel)

	_trial_guide_message_label = RichTextLabel.new()
	_trial_guide_message_label.bbcode_enabled = true
	_trial_guide_message_label.fit_content = true
	_trial_guide_message_label.scroll_active = false
	_trial_guide_message_label.selection_enabled = false
	_trial_guide_message_label.add_theme_font_size_override("normal_font_size", TRIAL_GUIDE_BODY_FONT_SIZE)
	_trial_guide_message_label.custom_minimum_size = Vector2(TRIAL_GUIDE_MESSAGE_MIN_WIDTH, 0.0)
	_trial_guide_message_box = VBoxContainer.new()
	_trial_guide_message_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_guide_message_box.add_theme_constant_override("separation", 12)
	_trial_guide_message_panel.add_child(_trial_guide_message_box)
	_trial_guide_message_box.add_child(_trial_guide_message_label)

	var button_row := HBoxContainer.new()
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_trial_guide_message_box.add_child(button_row)

	_trial_guide_continue_button = Button.new()
	_trial_guide_continue_button.custom_minimum_size = Vector2(132.0, 40.0)
	_trial_guide_continue_button.add_theme_font_size_override("font_size", 18)
	_trial_guide_continue_button.pressed.connect(_on_trial_guide_continue_pressed)
	_apply_button_theme(_trial_guide_continue_button, "neutral")
	button_row.add_child(_trial_guide_continue_button)

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
	_set_session_progress(0.0)
	_trial_step = "intro"
	_trial_drink_task_id = ""
	_connect_trial_robot_signals()
	_refresh_day_phase_label()
	_reset_trial_world_state()
	_set_trial_player_input_locked(true)
	var time_mgr = get_node_or_null("/root/GameManager/TimeManager")
	if time_mgr and time_mgr.has_method("pause"):
		time_mgr.pause()
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_customer_spawner"):
		var spawner = game_mgr.get_customer_spawner()
		if spawner and spawner.has_method("disable"):
			spawner.disable()
	call_deferred("_run_trial_intro")

func _run_trial_intro() -> void:
	_hide_trial_guide()
	_show_player_dialogue_overlay("System", "Welcome to the restaurant.", "system")
	if not await _trial_wait(PLAYER_DIALOGUE_OVERLAY_SHOW_SEC + 0.1):
		return
	if not _trial_session_active:
		return
	_show_player_dialogue_overlay("System", "You are now entering the trial session.", "system")
	if not await _trial_wait(PLAYER_DIALOGUE_OVERLAY_SHOW_SEC + 0.1):
		return
	if not _trial_session_active:
		return
	_trial_step = "static_system_panel"
	_show_trial_guide_for_system_panel()

func _show_trial_guide_for_system_panel() -> void:
	if not _trial_session_active or _trial_step != "static_system_panel":
		return
	_show_trial_guide(
		"This panel keeps track of the current service period, score, items being held, and tasks assigned to you and the robot.",
		{"type": "control", "id": inventory_panel.get_instance_id()},
		"→",
		"Next",
		Callable(self, "_show_trial_guide_for_dialogue_panel")
	)

func _show_trial_guide_for_dialogue_panel() -> void:
	if not _trial_session_active or _trial_step != "static_system_panel":
		return
	_trial_step = "static_dialogue_panel"
	_show_trial_guide(
		"This panel records what customers, you, and the robot say during service.",
		{"type": "control", "id": dialogue_panel.get_instance_id()},
		"←",
		"Next",
		Callable(self, "_show_trial_guide_for_customer_orders")
	)

func _show_trial_guide_for_customer_orders() -> void:
	if not _trial_session_active or _trial_step != "static_dialogue_panel":
		return
	_trial_step = "static_order_history"
	_set_customer_tab(CUSTOMER_TAB_HISTORY)
	_show_trial_guide(
		"History keeps a record of completed and failed orders, including their score changes.",
		{"type": "control", "id": customer_panel.get_instance_id(), "prefer_below": true, "message_offset_y": -25.0},
		"←",
		"Next",
		Callable(self, "_show_trial_guide_for_live_orders")
	)

func _show_trial_guide_for_live_orders() -> void:
	if not _trial_session_active or _trial_step != "static_order_history":
		return
	_trial_step = "static_customer_orders"
	_set_customer_tab(CUSTOMER_TAB_LIVE)
	_show_trial_guide(
		"Live shows all active orders. In this trial, the robot handles food orders and you handle drink orders; assigned tasks appear in the System Panel.",
		{"type": "control", "id": customer_panel.get_instance_id(), "prefer_below": true, "message_offset_y": -25.0},
		"←",
		"Next",
		Callable(self, "_begin_trial_order_demo")
	)

func _begin_trial_order_demo() -> void:
	if not _trial_session_active or _trial_step != "static_customer_orders":
		return
	_hide_trial_guide()
	_set_session_progress(0.02)
	_spawn_trial_customer()
	_trial_step = "await_food_order"
	if _trial_timeout_timer:
		_trial_timeout_timer.start(TRIAL_SESSION_MAX_SEC)

func _spawn_trial_customer() -> void:
	if _trial_customer != null and is_instance_valid(_trial_customer):
		return
	var customer = TrialCustomerScene.instantiate()
	customer.preset_food_item = "pizza"
	customer.preset_drink_item = "coffee"
	customer.defer_drink_order_until_released = true
	customer.food_task_window_ms = TRIAL_FOOD_TASK_WINDOW_MS
	customer.drink_task_window_ms = TRIAL_DRINK_TASK_WINDOW_MS
	customer.start_delay_sec = 0.2
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return
	current_scene.add_child(customer)
	var spawn_marker = current_scene.find_child("CS1", true, false)
	if spawn_marker != null and spawn_marker is Node2D:
		customer.global_position = (spawn_marker as Node2D).global_position
	_trial_customer = customer as Node2D

func _show_trial_guide_for_drink_request() -> void:
	_show_trial_guide(
		"The customer is now requesting a drink. Walk to the customer and press [b]E[/b] to take the drink order.",
		{"type": "world_customer", "id": _trial_customer.get_instance_id(), "size": Vector2(104.0, 150.0), "offset": Vector2(0.0, -24.0), "message_min_width": 340.0},
		"↓"
	)

func _on_trial_handoff_wait_ready(task_id: String) -> void:
	if not _trial_session_active or _trial_step != "await_robot_ready" or task_id != _trial_food_task_id:
		return
	var robot = _trial_robot()
	if robot == null or not (robot is Node2D):
		return
	_set_session_progress(0.05)
	_show_trial_guide(
		"The robot has picked up the food. Next, you will handle the customer's drink order.",
		{"type": "world_rect", "center": (robot as Node2D).global_position, "size": Vector2(96.0, 128.0), "offset": Vector2(0.0, -20.0)},
		"↓",
		"Next",
		Callable(self, "_begin_trial_drink_demo")
	)

func _begin_trial_drink_demo() -> void:
	if not _trial_session_active or _trial_step != "await_robot_ready":
		return
	if _trial_customer == null or not is_instance_valid(_trial_customer):
		call_deferred("_finish_trial_session", false)
		return
	_hide_trial_guide()
	_set_session_progress(0.06)
	_trial_step = "await_drink_order"
	_set_trial_player_input_locked(false)
	if _trial_customer.has_method("release_deferred_drink_order"):
		_trial_customer.call("release_deferred_drink_order")

func _show_trial_guide_for_drink_pickup() -> void:
	if _trial_drink_pickup_area_confirmed:
		_show_trial_guide_for_drink_pickup_action()
		return
	_show_trial_guide(
		"Here's the pickup area: drinks are on the left, and food is on the right. You may use the food counter later if the robot asks for your help.",
		_pickup_area_trial_target(),
		"↓",
		"Got it.",
		Callable(self, "_show_trial_guide_for_drink_pickup_action")
	)

func _show_trial_guide_for_drink_pickup_action() -> void:
	if not _trial_session_active or _trial_step != "await_pickup":
		return
	_trial_drink_pickup_area_confirmed = true
	_show_trial_guide(
		"Now go to the drink cabinet on the left and press [b]E[/b]. Select the requested drink to pick it up.",
		_drink_cabinet_trial_target(),
		"↓"
	)

func _show_trial_guide_for_drink_delivery() -> void:
	_show_trial_guide(
		"Take the drink back to the customer and deliver it.",
		{
			"type": "world_customer",
			"id": _trial_customer.get_instance_id(),
			"size": Vector2(104.0, 150.0),
			"offset": Vector2(0.0, -24.0),
			"message_min_width": 220.0
		},
		"↓"
	)

func _begin_trial_delete_demo() -> void:
	if not _trial_session_active:
		return
	_set_session_progress(0.075)
	_trial_step = "await_delete_open"
	hide_inventory_portal()
	_clear_actor_inventory("player")
	var inv := _trial_player_inventory()
	if inv == null:
		call_deferred("_finish_trial_session", false)
		return
	_trial_delete_item_name = "hotdog"
	var added := inv.add_item(_trial_delete_item_name, null, Rect2i(), {
		"item_owner": "trial",
		"tutorial_cleanup": true
	})
	if not added or inv.items.is_empty():
		call_deferred("_finish_trial_session", false)
		return
	var last_item: Dictionary = inv.items.back()
	_trial_delete_item_uid = int(last_item.get("uid", 0))
	_show_trial_guide_for_delete_open()

func _show_trial_guide_for_delete_open() -> void:
	var inventory_target := _trial_player_inventory_lines_target()
	var hotdog_target := _trial_player_inventory_item_target(_trial_delete_item_name)
	if inventory_target.is_empty() or hotdog_target.is_empty():
		return
	_show_trial_guide(
		"You picked up an extra %s by mistake. Press [b]I[/b] to open the inventory portal." % _trial_delete_item_name,
		{
			"type": "control_group",
			"ids": inventory_target.get("ids", []),
			"message_side": "right",
			"arrow_target": hotdog_target
		},
		"→"
	)

func _show_trial_guide_for_delete_confirm() -> void:
	var delete_target := _trial_inventory_delete_button_target()
	if delete_target.is_empty() or inventory_portal_panel == null:
		return
	_show_trial_guide(
		"Delete the extra %s from your inventory, then continue." % _trial_delete_item_name,
		{
			"type": "control",
			"id": inventory_portal_panel.get_instance_id(),
			"hide_focus_border": true,
			"arrow_target": delete_target
		},
		"→"
	)

func _activate_trial_handoff_request() -> void:
	if not _trial_session_active:
		return
	if _trial_handoff_request_id != "":
		return
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
	if not robot.has_method("start_trial_task_handoff"):
		call_deferred("_finish_trial_session", false)
		return
	robot.call("start_trial_task_handoff", _trial_handoff_task_id, item_name)
	_set_session_progress(0.09)
	_trial_step = "await_handoff_accept"

func _show_trial_guide_for_handoff_accept() -> void:
	var prompt_target := _trial_handoff_prompt_target()
	var accept_target := _trial_help_accept_target()
	if prompt_target.is_empty() or accept_target.is_empty():
		return
	_show_trial_guide(
		"",
		{
			"type": "control",
			"id": int(prompt_target.get("id", 0)),
			"arrow_target": accept_target,
			"hide_focus_border": true,
			"message_min_width": 500.0,
			"message_offset_y": -20.0
		},
		"→"
	)

func _show_trial_guide_for_handoff_delivery() -> void:
	if _trial_customer == null or not is_instance_valid(_trial_customer):
		return
	_show_trial_guide(
		"The robot has handed the food to you. Now deliver it to the same customer.",
		{"type": "world_customer", "id": _trial_customer.get_instance_id(), "size": Vector2(104.0, 150.0), "offset": Vector2(0.0, -24.0)},
		"↓"
	)

func _finish_trial_session(success: bool) -> void:
	if not _trial_session_active:
		return
	_trial_session_active = false
	_set_session_progress(SESSION_PROGRESS_TRIAL_SHARE)
	_trial_step = "complete"
	if _trial_timeout_timer:
		_trial_timeout_timer.stop()
	_hide_trial_guide()
	_reset_trial_world_state()
	var robot = _trial_robot()
	if robot != null and robot.has_method("snap_to_trial_wait_marker_and_pause"):
		robot.call("snap_to_trial_wait_marker_and_pause")
	_refresh_day_phase_label()
	call_deferred("_show_trial_completion_prompt", success)

func _on_trial_timeout() -> void:
	_finish_trial_session(false)

func _show_trial_completion_prompt(success: bool) -> void:
	_popup_mode = POPUP_MODE_TRIAL_COMPLETE
	var body := "Congratulations. You have successfully completed the trial session. Are you ready to begin the formal session?\n" if success else "The trial session has ended. In the formal session, keep an eye on order timers and complete tasks before they expire."
	_show_player_dialogue_prompt(
		"System",
		body,
		["Start Game"],
		false
	)

func _begin_formal_session() -> void:
	_set_trial_player_input_locked(false)
	_log_participant_profile_for_formal_session()
	_formal_session_started = true
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr and help_mgr.has_method("set_formal_session_active"):
		help_mgr.set_formal_session_active(true)
	_initial_day_notice_shown = false
	_pending_day_notice = 1
	_run_end_active = false
	_score_game_over = false
	_game_run_logged = false
	_embedded_completion_sent = false
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

func _log_participant_profile_for_formal_session() -> void:
	if _participant_profile_logged:
		return
	var profile = get_node_or_null("/root/PlayerProfile")
	var logger = get_node_or_null("/root/EpisodeLogger")
	if profile == null or logger == null:
		return
	if not profile.has_method("get_profile") or not logger.has_method("log_participant_profile"):
		return
	logger.log_participant_profile(profile.get_profile())
	_participant_profile_logged = true

func _reset_trial_world_state() -> void:
	_clear_trial_ui_state()
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
	_trial_food_task_id = ""
	_trial_drink_task_id = ""
	_trial_handoff_task_id = ""
	_trial_handoff_request_id = ""
	_trial_delete_item_uid = 0
	_trial_delete_item_name = ""
	_trial_drink_pickup_area_confirmed = false
	_clear_actor_inventory("player")
	_clear_actor_inventory("robot")
	var robot = _trial_robot()
	if robot != null:
		if robot.has_method("set_trial_stationary_pause"):
			robot.call("set_trial_stationary_pause", false)
		if robot.has_method("_clear_current_task_runtime"):
			robot.call("_clear_current_task_runtime")
		robot.set("_waiting_for_help", false)
		robot.set("_active_help_request_id", "")
	_score = 0
	_success_count = 0
	_failed_count = 0
	_score_game_over = false
	_run_end_active = false
	_game_run_logged = false
	_customer_history_page = 0
	_last_player_live_task_ids.clear()
	_refresh_score_label()
	if dialogue_log:
		dialogue_log.clear()
	_update_player_task_panel()
	_update_robot_task_panel()
	_update_customer_panel()

func _clear_trial_ui_state() -> void:
	_popup_mode = POPUP_MODE_NONE
	_kitchen_pick_options.clear()
	_hide_trial_guide()
	hide_inventory_portal()
	_help_prompt_cards.clear()
	_last_help_bubble_utterance_by_request.clear()
	_shown_help_system_notice_by_request.clear()
	_auto_open_in_flight.clear()
	if help_prompt_stack:
		_clear_dynamic_children(help_prompt_stack)
		help_prompt_stack.visible = false
	_update_delegation_pause_state()
	_hide_player_dialogue_overlay()

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

func _trial_robot() -> Node:
	var robots = get_tree().get_nodes_in_group("robot")
	if robots.is_empty():
		return null
	return robots[0]

func _connect_trial_robot_signals() -> void:
	var robot = _trial_robot()
	if robot == null or not robot.has_signal("trial_handoff_wait_ready"):
		return
	if not robot.is_connected("trial_handoff_wait_ready", Callable(self, "_on_trial_handoff_wait_ready")):
		robot.connect("trial_handoff_wait_ready", Callable(self, "_on_trial_handoff_wait_ready"))

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
	if int(entry.get("dialogue_stage", HELP_DIALOGUE_STAGE_OPENER)) < HELP_DIALOGUE_STAGE_DELEGATION:
		return {}
	var accept_btn: Button = entry.get("accept_btn", null)
	if accept_btn == null or not is_instance_valid(accept_btn):
		return {}
	return {"type": "control", "id": accept_btn.get_instance_id()}

func _trial_inventory_delete_button_target() -> Dictionary:
	if inventory_portal_list == null or _trial_delete_item_uid <= 0:
		return {}
	for row in inventory_portal_list.get_children():
		if not (row is HBoxContainer):
			continue
		for child in row.get_children():
			if not (child is Button):
				continue
			var button := child as Button
			if int(button.get_meta("inventory_item_uid", 0)) == _trial_delete_item_uid:
				return {"type": "control", "id": button.get_instance_id()}
	return {}

func _trial_player_inventory_lines_target() -> Dictionary:
	if _player_inventory_holding_label == null or not is_instance_valid(_player_inventory_holding_label):
		return {}
	var item_target := _trial_player_inventory_item_target(_trial_delete_item_name)
	if item_target.is_empty():
		return {}
	return {
		"type": "control_group",
		"ids": [
			_player_inventory_holding_label.get_instance_id(),
			int(item_target.get("id", 0))
		]
	}

func _trial_player_inventory_item_target(item_name: String) -> Dictionary:
	var key := item_name.strip_edges().to_lower()
	if key == "":
		return {}
	var label: Label = _player_inventory_item_labels_by_name.get(key, null)
	if label == null or not is_instance_valid(label):
		return {}
	return {"type": "control", "id": label.get_instance_id()}

func _trial_player_inventory() -> Inventory:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var player = players[0]
	var inv = null
	if "inventory" in player and player.inventory != null:
		inv = player.inventory
	else:
		inv = player.get_node_or_null("Inventory")
	if inv != null and inv is Inventory:
		return inv as Inventory
	return null

func _trial_has_delete_item() -> bool:
	var inv := _trial_player_inventory()
	if inv == null:
		return false
	return _inventory_contains_uid(inv.items, _trial_delete_item_uid)

func _inventory_contains_uid(items: Array, item_uid: int) -> bool:
	if item_uid <= 0:
		return false
	for raw_item in items:
		var item: Dictionary = raw_item
		if int(item.get("uid", 0)) == item_uid:
			return true
	return false

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

func _show_trial_guide(text: String, target: Dictionary, arrow: String = "↓", continue_text: String = "", continue_callback: Callable = Callable()) -> void:
	if _trial_guide_layer == null or _trial_guide_message_label == null:
		return
	_trial_guide_target = target.duplicate(true)
	_trial_guide_continue_callback = continue_callback
	_trial_guide_layer.visible = true
	_trial_guide_message_label.clear()
	if text.strip_edges() == "":
		_trial_guide_message_panel.visible = false
	else:
		_trial_guide_message_panel.visible = true
		_trial_guide_message_label.append_text(text)
	if _trial_guide_continue_button:
		_trial_guide_continue_button.text = continue_text
		_trial_guide_continue_button.visible = not continue_text.strip_edges().is_empty() and continue_callback.is_valid()
	if _trial_guide_arrow:
		_trial_guide_arrow.visible = arrow.strip_edges() != ""
	if arrow.strip_edges() != "":
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
	_trial_guide_continue_callback = Callable()
	if _trial_guide_continue_button:
		_trial_guide_continue_button.visible = false
	if _trial_guide_layer:
		_trial_guide_layer.visible = false

func _on_trial_guide_continue_pressed() -> void:
	if not _trial_guide_continue_callback.is_valid():
		return
	var callback := _trial_guide_continue_callback
	_trial_guide_continue_callback = Callable()
	callback.call()

func _update_trial_guide_overlay() -> void:
	if _trial_guide_layer == null or not _trial_guide_layer.visible:
		return
	var rect := _resolve_trial_guide_target_rect(_trial_guide_target)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var hide_focus_border := bool(_trial_guide_target.get("hide_focus_border", false))
	rect.position = rect.position.round()
	rect.size = rect.size.round()
	var focus_rect := rect if hide_focus_border else rect.grow(8.0)
	focus_rect.position = focus_rect.position.round()
	focus_rect.size = focus_rect.size.round()
	var view_size := get_viewport().get_visible_rect().size
	var clipped_focus := Rect2(
		Vector2(clampf(focus_rect.position.x, 0.0, view_size.x), clampf(focus_rect.position.y, 0.0, view_size.y)),
		Vector2(
			clampf(focus_rect.end.x, 0.0, view_size.x) - clampf(focus_rect.position.x, 0.0, view_size.x),
			clampf(focus_rect.end.y, 0.0, view_size.y) - clampf(focus_rect.position.y, 0.0, view_size.y)
		)
	)
	clipped_focus.position = clipped_focus.position.round()
	clipped_focus.size = clipped_focus.size.round()
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
	_trial_guide_focus.visible = not hide_focus_border
	_trial_guide_focus.position = focus_rect.position
	_trial_guide_focus.size = focus_rect.size
	var place_above := false
	if _trial_guide_message_panel.visible:
		var message_min_width := float(_trial_guide_target.get("message_min_width", TRIAL_GUIDE_MESSAGE_MIN_WIDTH))
		_trial_guide_message_label.custom_minimum_size = Vector2(message_min_width, 0.0)
		var message_size := _trial_guide_message_panel.get_combined_minimum_size()
		_trial_guide_message_panel.size = message_size
		var message_side := str(_trial_guide_target.get("message_side", ""))
		var message_x := clampf(focus_rect.get_center().x - message_size.x * 0.5, 24.0, maxf(24.0, view_size.x - message_size.x - 24.0))
		var message_y := focus_rect.position.y + focus_rect.size.y + 56.0
		if message_side == "right":
			var right_x := focus_rect.end.x + 32.0
			var fits_right := right_x + message_size.x <= view_size.x - 24.0
			if fits_right:
				message_x = right_x
				message_y = clampf(
					focus_rect.get_center().y - message_size.y * 0.5,
					24.0,
					maxf(24.0, view_size.y - message_size.y - 24.0)
				)
			else:
				message_y = focus_rect.position.y + focus_rect.size.y + 56.0
		else:
			var prefer_below := bool(_trial_guide_target.get("prefer_below", false))
			place_above = focus_rect.position.y >= message_size.y + 70.0 and not prefer_below
			message_y = focus_rect.position.y - message_size.y - 48.0 if place_above else focus_rect.position.y + focus_rect.size.y + 56.0
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
		"control_group":
			var ids: Array = target.get("ids", [])
			var union_rect := Rect2()
			var found := false
			for raw_id in ids:
				var control_obj = instance_from_id(int(raw_id))
				if control_obj == null or not (control_obj is Control):
					continue
				var control_rect := (control_obj as Control).get_global_rect()
				if not found:
					union_rect = control_rect
					found = true
				else:
					union_rect = union_rect.merge(control_rect)
			if found:
				return union_rect
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
	return {"type": "world_rect", "center": Vector2(-325.0, -358.0), "size": Vector2(72.0, 128.0)}

func _pickup_area_trial_target() -> Dictionary:
	return {"type": "world_rect", "center": Vector2(-208.0, -358.0), "size": Vector2(246.0, 130.0), "message_min_width": 290.0}

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

func _can_auto_open_request(request: Dictionary) -> bool:
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
	if not _help_prompt_cards.is_empty():
		return true
	if _delegation_pause_active:
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
		if player_dialogue_overlay_third_btn:
			player_dialogue_overlay_third_btn.visible = show_third_button and button_texts.size() >= 3
			if button_texts.size() >= 3:
				player_dialogue_overlay_third_btn.text = button_texts[2]
				player_dialogue_overlay_third_btn.disabled = false
				player_dialogue_overlay_third_btn.modulate = Color(1, 1, 1, 1)
	_overlay_keyboard_focus_index = -1
	_clear_choice_focus(_all_overlay_choice_buttons())
	_trim_player_dialogue_info_cards()
	_update_gameplay_panel_layout()

func _create_help_prompt_card(request: Dictionary) -> Dictionary:
	var rid := str(request.get("id", ""))
	var payload: Dictionary = request.get("payload", {})
	var trial_accept_only := bool(payload.get("trial_accept_only", false))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(GAMEPLAY_BAND_WIDTH * HELP_PROMPT_WIDTH_RATIO, 0.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.92)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.58, 0.88, 1.0, 1.0)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_right = 18
	style.corner_radius_bottom_left = 18
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	card.add_child(vbox)

	var title_label := Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", HELP_PROMPT_TITLE_FONT_SIZE)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.36, 1.0))
	title_label.text = "Robot Request"
	vbox.add_child(title_label)

	var label := RichTextLabel.new()
	label.bbcode_enabled = false
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("normal_font_size", HELP_PROMPT_BODY_FONT_SIZE)
	label.custom_minimum_size = Vector2(card.custom_minimum_size.x - 48.0, 0.0)
	vbox.add_child(label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)

	var primary_btn := Button.new()
	primary_btn.custom_minimum_size = Vector2(160.0, HELP_PROMPT_BUTTON_HEIGHT)
	primary_btn.add_theme_font_size_override("font_size", HELP_PROMPT_BUTTON_FONT_SIZE)
	primary_btn.pressed.connect(func():
		_on_help_request_primary_pressed(rid)
	)
	_apply_button_theme(primary_btn, "neutral")
	buttons.add_child(primary_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	decline_btn.custom_minimum_size = Vector2(160.0, HELP_PROMPT_BUTTON_HEIGHT)
	decline_btn.add_theme_font_size_override("font_size", HELP_PROMPT_BUTTON_FONT_SIZE)
	decline_btn.pressed.connect(func():
		_submit_help_request_response(rid, "decline")
	)
	_apply_button_theme(decline_btn, "neutral")
	buttons.add_child(decline_btn)

	var entry := {
		"request_id": rid,
		"request": request.duplicate(true),
		"node": card,
		"title_label": title_label,
		"label": label,
		"accept_btn": primary_btn,
		"decline_btn": decline_btn,
		"dialogue_stage": HELP_DIALOGUE_STAGE_OPENER,
		"trial_accept_only": trial_accept_only
	}
	_apply_help_request_card_state(entry, request)
	return entry

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
		entry["request"] = request.duplicate(true)
		_apply_help_request_card_state(entry, request)
		_help_prompt_cards[idx] = entry
	else:
		if _help_prompt_cards.size() >= HELP_PROMPT_MAX_STACK:
			return
		var created := _create_help_prompt_card(request)
		_help_prompt_cards.append(created)
		help_prompt_stack.add_child(created.get("node"))
		_play_delegation_stage_voice(request, HELP_DIALOGUE_STAGE_OPENER)
	help_prompt_stack.visible = not _help_prompt_cards.is_empty()
	_reset_help_prompt_keyboard_focus()
	_update_delegation_pause_state()
	_update_gameplay_panel_layout()

func _apply_help_request_card_state(entry: Dictionary, request: Dictionary) -> void:
	var stage := int(entry.get("dialogue_stage", HELP_DIALOGUE_STAGE_OPENER))
	var label: RichTextLabel = entry.get("label", null)
	var title_label: Label = entry.get("title_label", null)
	if title_label != null:
		title_label.text = "Robot Request"
	if label != null:
		label.clear()
		label.add_text(_build_help_text(request, stage))
	var primary_btn: Button = entry.get("accept_btn", null)
	var decline_btn: Button = entry.get("decline_btn", null)
	var trial_accept_only := bool(entry.get("trial_accept_only", false))
	if primary_btn != null:
		primary_btn.visible = true
		primary_btn.text = _help_stage_reply_text(request, stage)
		primary_btn.disabled = false
	if decline_btn != null:
		decline_btn.visible = stage == HELP_DIALOGUE_STAGE_DELEGATION
		decline_btn.disabled = trial_accept_only

func _on_help_request_primary_pressed(request_id: String) -> void:
	var idx := _find_help_request_card_index(request_id)
	if idx < 0:
		return
	var entry: Dictionary = _help_prompt_cards[idx]
	var stage := int(entry.get("dialogue_stage", HELP_DIALOGUE_STAGE_OPENER))
	if stage >= HELP_DIALOGUE_STAGE_DELEGATION:
		_submit_help_request_response(request_id, "accept")
		return
	stage += 1
	entry["dialogue_stage"] = stage
	var request: Dictionary = entry.get("request", {})
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr != null and help_mgr.has_method("get_request"):
		var refreshed: Dictionary = help_mgr.get_request(request_id)
		if not refreshed.is_empty():
			request = refreshed
			entry["request"] = refreshed.duplicate(true)
	_apply_help_request_card_state(entry, request)
	_help_prompt_cards[idx] = entry
	_play_delegation_stage_voice(request, stage)
	_reset_help_prompt_keyboard_focus()
	if _trial_session_active and request_id == _trial_handoff_request_id and _trial_step == "await_handoff_accept" and stage >= HELP_DIALOGUE_STAGE_DELEGATION:
		call_deferred("_show_trial_guide_for_handoff_accept")

func _submit_help_request_response(request_id: String, response: String) -> void:
	var help_mgr = get_node_or_null("/root/HelpRequestManager")
	if help_mgr and help_mgr.has_method("respond"):
		help_mgr.respond(request_id, response)

func _remove_help_request_card(request_id: String) -> void:
	var idx := _find_help_request_card_index(request_id)
	if idx < 0:
		_last_help_bubble_utterance_by_request.erase(request_id)
		_shown_help_system_notice_by_request.erase(request_id)
		_update_delegation_pause_state()
		_fill_help_prompt_slots()
		return
	var entry: Dictionary = _help_prompt_cards[idx]
	_help_prompt_cards.remove_at(idx)
	_stop_delegation_voice_for_request(request_id)
	var node: Control = entry.get("node", null)
	if node != null and is_instance_valid(node):
		node.queue_free()
	if help_prompt_stack:
		help_prompt_stack.visible = not _help_prompt_cards.is_empty()
	_reset_help_prompt_keyboard_focus()
	_last_help_bubble_utterance_by_request.erase(request_id)
	_shown_help_system_notice_by_request.erase(request_id)
	_update_delegation_pause_state()
	_update_gameplay_panel_layout()
	_fill_help_prompt_slots()

func _play_delegation_stage_voice(request: Dictionary, dialogue_stage: int) -> void:
	if _delegation_voice_player == null:
		return
	var template_id := ""
	var category := ""
	var item_suffix := ""
	match dialogue_stage:
		HELP_DIALOGUE_STAGE_OPENER:
			template_id = str(request.get("opener_template_id", ""))
			category = "opener"
		HELP_DIALOGUE_STAGE_BRIDGE:
			template_id = str(request.get("bridge_template_id", ""))
			category = "bridge"
		_:
			template_id = str(request.get("template_id", ""))
			category = "trial" if template_id.begins_with("trial_") else "strategy"
			var payload: Dictionary = request.get("payload", {})
			var item_name := str(payload.get("item_needed", "")).strip_edges().to_lower()
			if item_name not in ["pizza", "hotdog", "sandwich"]:
				push_warning("[DelegationVoice] No audio variant for item: %s" % item_name)
				return
			item_suffix = "_" + item_name
	if template_id == "":
		return
	var path := "res://assets/audio/delegation/%s/%s%s.mp3" % [category, template_id, item_suffix]
	if not ResourceLoader.exists(path):
		push_warning("[DelegationVoice] Missing audio asset: %s" % path)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("[DelegationVoice] Could not load audio asset: %s" % path)
		return
	_delegation_voice_player.stop()
	_delegation_voice_player.stream = stream
	_delegation_voice_request_id = str(request.get("id", ""))
	_delegation_voice_player.play()

func _stop_delegation_voice_for_request(request_id: String) -> void:
	if _delegation_voice_player == null or _delegation_voice_request_id != request_id:
		return
	_delegation_voice_player.stop()
	_delegation_voice_request_id = ""

func _update_delegation_pause_state() -> void:
	var should_pause := not _help_prompt_cards.is_empty()
	if should_pause == _delegation_pause_active:
		return
	_delegation_pause_active = should_pause
	if should_pause:
		if _popup_mode == POPUP_MODE_KITCHEN_PICK:
			hide_kitchen_pick_popup()
		hide_inventory_portal()
		for entry in _player_dialogue_info_cards:
			var node: Control = entry.get("node", null)
			if node != null and is_instance_valid(node):
				node.queue_free()
		_player_dialogue_info_cards.clear()
		if player_dialogue_info_stack:
			player_dialogue_info_stack.visible = false
	_set_global_pause(should_pause)

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
	_overlay_keyboard_focus_index = -1
	_clear_choice_focus(_all_overlay_choice_buttons())
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
	if _popup_mode == POPUP_MODE_KITCHEN_PICK:
		_apply_kitchen_pick_button_themes()
	else:
		_apply_default_overlay_button_themes()
