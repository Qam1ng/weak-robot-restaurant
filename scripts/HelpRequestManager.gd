extends Node

signal request_created(request: Dictionary)
signal request_updated(request: Dictionary)
signal request_resolved(request: Dictionary)

const RESPONSE_ACCEPT := "accept"
const RESPONSE_DECLINE := "decline"

const TYPE_HANDOFF := "HANDOFF"
const API_ASSIGN_STRATEGY_URL := "https://us-central1-weak-robot-restaurant-web.cloudfunctions.net/apiAssignStrategy"

const STATUS_PENDING := "pending"
const STATUS_ACCEPTED := "accepted"
const STATUS_RESOLVED := "resolved"

const PERSUASION_ENGINE_PATH := "res://scripts/PersuasionEngine.gd"
const SESSION_STRATEGY_STATE_KEY := "weak_robot_formal_strategy_state"
const FORMAL_COVERAGE_STRATEGY_COUNT := 6

var _requests_by_id: Dictionary = {}
var _order: Array[String] = []
var _next_id: int = 1
var _request_index_in_session: int = 0
var _formal_session_active := false
var _formal_coverage_strategies: Array[String] = []

func _gameplay_now_ms() -> int:
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_gameplay_time_ms"):
		return int(game_mgr.get_gameplay_time_ms())
	return Time.get_ticks_msec()

func _persuasion_engine():
	return load(PERSUASION_ENGINE_PATH)

func reset_all() -> void:
	_requests_by_id.clear()
	_order.clear()
	_next_id = 1
	_request_index_in_session = 0
	_formal_session_active = false
	_formal_coverage_strategies.clear()
	_clear_persisted_formal_strategy_state()
	var engine = _persuasion_engine()
	if engine and engine.has_method("reset_assignment_state"):
		engine.reset_assignment_state()

func set_formal_session_active(active: bool) -> void:
	_formal_session_active = active
	if active:
		_load_persisted_formal_strategy_state()
		return
	_formal_coverage_strategies.clear()

func _is_formal_research_request(req: Dictionary) -> bool:
	if not _formal_session_active:
		return false
	var payload: Dictionary = req.get("payload", {})
	return str(payload.get("delegation_scenario", "")) != "trial_tutorial"

func _forced_coverage_strategy() -> String:
	if _formal_coverage_strategies.size() >= FORMAL_COVERAGE_STRATEGY_COUNT:
		return ""
	var engine = _persuasion_engine()
	if engine == null or not engine.has_method("pick_unseen_strategy"):
		return ""
	return str(engine.pick_unseen_strategy(_formal_coverage_strategies))

func _confirm_formal_coverage_strategy(req: Dictionary) -> bool:
	if not _is_formal_research_request(req):
		return false
	if str(req.get("assignment_mode", "")) != "session_coverage":
		return false
	if bool(req.get("session_coverage_consumed", false)):
		return false
	var strategy := str(req.get("strategy", ""))
	if strategy == "" or _formal_coverage_strategies.has(strategy):
		return false
	_formal_coverage_strategies.append(strategy)
	_persist_formal_strategy_state()
	return true

func _load_persisted_formal_strategy_state() -> void:
	_formal_coverage_strategies.clear()
	if not OS.has_feature("web"):
		return
	var value = JavaScriptBridge.eval("window.sessionStorage.getItem('%s') || '[]'" % SESSION_STRATEGY_STATE_KEY, true)
	var parsed: Variant = JSON.parse_string(str(value))
	if not (parsed is Array):
		return
	var engine = _persuasion_engine()
	var strategies: Array = engine.get("STRATEGIES") if engine else []
	for raw_strategy in parsed:
		var strategy := str(raw_strategy)
		if strategies.has(strategy) and not _formal_coverage_strategies.has(strategy):
			_formal_coverage_strategies.append(strategy)
			if _formal_coverage_strategies.size() >= FORMAL_COVERAGE_STRATEGY_COUNT:
				break

func _persist_formal_strategy_state() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.sessionStorage.setItem('%s', %s)" % [SESSION_STRATEGY_STATE_KEY, JSON.stringify(_formal_coverage_strategies)], true)

func _clear_persisted_formal_strategy_state() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.sessionStorage.removeItem('%s')" % SESSION_STRATEGY_STATE_KEY, true)

func _ready() -> void:
	var board = get_node_or_null("/root/TaskBoard")
	if board:
		if board.has_signal("task_completed") and not board.task_completed.is_connected(_on_task_completed):
			board.task_completed.connect(_on_task_completed)
		if board.has_signal("task_failed") and not board.task_failed.is_connected(_on_task_failed):
			board.task_failed.connect(_on_task_failed)
func create_request(robot: Node, payload: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	if robot == null or not is_instance_valid(robot):
		return {}

	var now_ms := _gameplay_now_ms()
	var request_id := "help_%06d" % _next_id
	_next_id += 1
	_request_index_in_session += 1

	var urgency := float(options.get("urgency", 0.5))
	var copied_payload := payload.duplicate(true)
	var delegation_scenario := str(copied_payload.get("delegation_scenario", "")).strip_edges()

	var req := {
		"id": request_id,
		"status": STATUS_PENDING,
		"robot_instance_id": robot.get_instance_id(),
		"payload": copied_payload,
		"created_at_ms": now_ms,
		"last_prompt_ms": 0,
		"urgency": urgency,
		"resolution_path": "",
		"context_snapshot": {},
		"strategy": "",
		"assignment_buckets": {},
		"system_notice": "",
		"nickname": "",
		"opener_template_id": "",
		"opener_text": "",
		"opener_reply_text": "",
		"bridge_template_id": "",
		"bridge_text": "",
		"bridge_reply_text": "",
		"utterance": "",
		"template_id": "",
		"last_response": "",
		"task_completed": false,
		"delivery_actor": "",
		"customer_timed_out": false,
		"score_delta": 0,
		"delegation_scenario": delegation_scenario,
		"request_index_in_session": _request_index_in_session,
		"assignment_pending": true
	}

	var context = _build_context(robot, req, options)
	req["context_snapshot"] = context
	req["nickname"] = str(context.get("personality", {}).get("nickname", "")).strip_edges()
	var engine = _persuasion_engine()
	if engine and engine.has_method("build_assignment_buckets"):
		req["assignment_buckets"] = engine.build_assignment_buckets(context)
	else:
		req["assignment_buckets"] = {}
	req["system_notice"] = _build_system_notice(payload)

	_requests_by_id[request_id] = req
	_order.append(request_id)
	_begin_strategy_assignment(request_id)
	return _copy(req)

func get_request(request_id: String) -> Dictionary:
	return _copy(_requests_by_id.get(request_id, {}))

func get_promptable_request_for_robot(robot: Node) -> Dictionary:
	if robot == null:
		return {}
	var robot_iid := robot.get_instance_id()
	var best: Dictionary = {}
	var best_score := -INF

	for request_id in _order:
		var req: Dictionary = _requests_by_id.get(request_id, {})
		if req.is_empty():
			continue
		if int(req.get("robot_instance_id", 0)) != robot_iid:
			continue
		var status := str(req.get("status", ""))
		if status != STATUS_PENDING:
			continue
		if bool(req.get("assignment_pending", false)):
			continue

		var urgency := float(req.get("urgency", 0.5))
		var score := urgency * 10.0
		if score > best_score:
			best_score = score
			best = req

	if best.is_empty():
		return {}
	return _copy(best)

func mark_prompted(request_id: String) -> void:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return
	if _confirm_formal_coverage_strategy(req):
		req["session_coverage_consumed"] = true
	req["last_prompt_ms"] = _gameplay_now_ms()
	_requests_by_id[request_id] = req
	_log_help_event(req)
	request_updated.emit(_copy(req))

func respond(request_id: String, response: String) -> Dictionary:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return {}
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return _copy(req)

	var now_ms := _gameplay_now_ms()
	var prompt_latency_ms := 0
	if int(req.get("last_prompt_ms", 0)) > 0:
		prompt_latency_ms = now_ms - int(req.get("last_prompt_ms", 0))
	req["response_latency_ms"] = prompt_latency_ms
	req["last_response"] = response
	match response:
		RESPONSE_ACCEPT:
			req["status"] = STATUS_ACCEPTED
		RESPONSE_DECLINE:
			req["status"] = STATUS_RESOLVED
			req["resolution_path"] = "declined"
		_:
			return _copy(req)

	_requests_by_id[request_id] = req
	var copied := _copy(req)
	print("[HelpRequest] Response ", response, " -> ", request_id, " status=", copied.get("status", ""))
	_log_help_event(req)
	request_updated.emit(copied)
	if str(req.get("status", "")) == STATUS_RESOLVED:
		request_resolved.emit(copied)
	return copied

func complete_request(request_id: String, resolution_path: String = "cooperative_execution") -> Dictionary:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return {}
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return _copy(req)

	req["status"] = STATUS_RESOLVED
	if str(req.get("last_response", "")) == "":
		req["last_response"] = RESPONSE_ACCEPT
	req["resolution_path"] = resolution_path
	_requests_by_id[request_id] = req

	var copied := _copy(req)
	print("[HelpRequest] Completed ", request_id, " path=", resolution_path)
	_log_help_event(req)
	request_updated.emit(copied)
	request_resolved.emit(copied)
	return copied

func cancel_request(request_id: String, resolution_path: String = "invalidated") -> Dictionary:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return {}
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return _copy(req)
	req["status"] = STATUS_RESOLVED
	req["resolution_path"] = resolution_path
	_requests_by_id[request_id] = req
	var copied := _copy(req)
	_log_help_event(req)
	request_updated.emit(copied)
	request_resolved.emit(copied)
	return copied

func _copy(req: Dictionary) -> Dictionary:
	if req.is_empty():
		return {}
	return req.duplicate(true)

func _begin_strategy_assignment(request_id: String) -> void:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return
	var engine = _persuasion_engine()
	if not _is_formal_research_request(req):
		# Trial prompts demonstrate the interface but must not affect experiment counters.
		_finalize_strategy_assignment(request_id, {
			"strategy": "",
			"buckets": req.get("assignment_buckets", {})
		})
		return
	var forced_strategy := _forced_coverage_strategy()
	req["forced_strategy"] = forced_strategy
	req["assignment_mode"] = "session_coverage" if forced_strategy != "" else "condition_weighted"
	_requests_by_id[request_id] = req
	if _should_use_backend_assignment():
		_request_remote_strategy_assignment(req)
		return
	var context: Dictionary = req.get("context_snapshot", {})
	var assignment: Dictionary = {}
	if engine and engine.has_method("assign_strategy_locally"):
		assignment = engine.assign_strategy_locally(context, forced_strategy)
	_finalize_strategy_assignment(request_id, assignment)

func _request_remote_strategy_assignment(req: Dictionary) -> void:
	var request_id := str(req.get("id", ""))
	if request_id == "":
		return
	var body := {
		"request_id": request_id,
		"assignment_buckets": req.get("assignment_buckets", {}),
		"forced_strategy": str(req.get("forced_strategy", ""))
	}
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_strategy_assignment_completed.bind(http, request_id))
	var err := http.request(API_ASSIGN_STRATEGY_URL, PackedStringArray([
		"Content-Type: application/json"
	]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		if is_instance_valid(http):
			http.queue_free()
		var logger = _episode_logger()
		if logger and logger.has_method("log_api_failure"):
			logger.log_api_failure(
				"apiAssignStrategy",
				"strategy_assignment",
				-1,
				"request_queue_error",
				"Failed to queue strategy assignment request.",
				request_id,
				"",
				_gameplay_now_ms()
			)
		var engine = _persuasion_engine()
		var fallback: Dictionary = {}
		if engine and engine.has_method("assign_strategy_locally"):
			fallback = engine.assign_strategy_locally(req.get("context_snapshot", {}), str(req.get("forced_strategy", "")))
		_finalize_strategy_assignment(request_id, fallback)

func _on_strategy_assignment_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, request_id: String) -> void:
	if is_instance_valid(http):
		http.queue_free()
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return
	if code < 200 or code >= 300:
		var logger = _episode_logger()
		if logger and logger.has_method("log_api_failure"):
			logger.log_api_failure(
				"apiAssignStrategy",
				"strategy_assignment",
				code,
				"http_error",
				"Strategy assignment request returned HTTP %d." % code,
				request_id,
				"",
				_gameplay_now_ms()
			)
		var engine = _persuasion_engine()
		var fallback: Dictionary = {}
		if engine and engine.has_method("assign_strategy_locally"):
			fallback = engine.assign_strategy_locally(req.get("context_snapshot", {}), str(req.get("forced_strategy", "")))
		_finalize_strategy_assignment(request_id, fallback)
		return
	var top: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (top is Dictionary):
		var logger = _episode_logger()
		if logger and logger.has_method("log_api_failure"):
			logger.log_api_failure(
				"apiAssignStrategy",
				"strategy_assignment",
				code,
				"parse_error",
				"Strategy assignment response was not valid JSON.",
				request_id,
				"",
				_gameplay_now_ms()
			)
		var engine = _persuasion_engine()
		var fallback_parse: Dictionary = {}
		if engine and engine.has_method("assign_strategy_locally"):
			fallback_parse = engine.assign_strategy_locally(req.get("context_snapshot", {}), str(req.get("forced_strategy", "")))
		_finalize_strategy_assignment(request_id, fallback_parse)
		return
	var assignment: Dictionary = {
		"strategy": str(top.get("strategy", "")),
		"buckets": top.get("assignment_buckets", {})
	}
	_finalize_strategy_assignment(request_id, assignment)

func _finalize_strategy_assignment(request_id: String, assignment: Dictionary) -> void:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return
	var strategy := str(assignment.get("strategy", "")).strip_edges()
	var engine = _persuasion_engine()
	var payload: Dictionary = req.get("payload", {})
	if strategy == "" and not bool(payload.get("trial_force_prompt", false)):
		strategy = str(engine.get("STRATEGY_AUTHORITY")) if engine else "authority"
	var buckets: Dictionary = assignment.get("buckets", {})
	if buckets.is_empty():
		if engine and engine.has_method("build_assignment_buckets"):
			buckets = engine.build_assignment_buckets(req.get("context_snapshot", {}))
	req["strategy"] = strategy
	req["assignment_buckets"] = buckets
	_refresh_request_surface(req)
	req["assignment_pending"] = false
	_requests_by_id[request_id] = req
	print("[HelpRequest] Created ", request_id)
	_log_help_event(req)
	var copied := _copy(req)
	request_created.emit(copied)

func _refresh_request_surface(req: Dictionary) -> void:
	var engine = _persuasion_engine()
	var authority_strategy := str(engine.get("STRATEGY_AUTHORITY")) if engine else "authority"
	var rendered := {}
	if engine and engine.has_method("render_request_dialogue"):
		rendered = engine.render_request_dialogue(
			str(req.get("strategy", authority_strategy)),
			req.get("payload", {}),
			str(req.get("nickname", ""))
		)
	req["opener_template_id"] = str(rendered.get("opener_template_id", ""))
	req["opener_text"] = str(rendered.get("opener_text", ""))
	req["opener_reply_text"] = str(rendered.get("opener_reply_text", ""))
	req["bridge_template_id"] = str(rendered.get("bridge_template_id", ""))
	req["bridge_text"] = str(rendered.get("bridge_text", ""))
	req["bridge_reply_text"] = str(rendered.get("bridge_reply_text", ""))
	req["template_id"] = str(rendered.get("template_id", ""))
	req["utterance"] = str(rendered.get("utterance", ""))

func _should_use_backend_assignment() -> bool:
	return OS.has_feature("web")

func _robot_from_request(req: Dictionary) -> Node:
	var iid := int(req.get("robot_instance_id", 0))
	if iid <= 0:
		return null
	var obj = instance_from_id(iid)
	if obj and is_instance_valid(obj):
		return obj
	return null

func _build_context(robot: Node, req: Dictionary, options: Dictionary) -> Dictionary:
	var robot_state := {
		"battery_level": float(robot.get("battery_level")),
		"battery_mode": str(robot.get("_battery_mode"))
	}
	if robot_state["battery_level"] == 0.0 and robot.get("battery_level") == null:
		robot_state["battery_level"] = 100.0
	if robot_state["battery_mode"] == "" or robot_state["battery_mode"] == "Null":
		robot_state["battery_mode"] = "normal"

	var player_state := _sample_player_state()
	var personality := _sample_personality_profile()

	var busyness := 0.5
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_busyness"):
		busyness = float(game_mgr.get_busyness())

	var payload: Dictionary = req.get("payload", {})
	var slack_ms := int(payload.get("slack_ms", 0))
	var urgency := float(options.get("urgency", 0.5))
	if slack_ms != 0:
		urgency = clampf(1.0 - (float(slack_ms) / 90000.0), 0.0, 1.0)

	return {
		"robot": robot_state,
		"player": player_state,
		"personality": personality,
		"environment": {
			"urgency": urgency,
			"busyness": busyness,
			"slack_ms": slack_ms,
			"phase_name": game_mgr.get_period() if game_mgr and game_mgr.has_method("get_period") else "unknown"
		}
	}

func _sample_player_state() -> Dictionary:
	var player_active_tasks := 0
	var board = get_node_or_null("/root/TaskBoard")
	if board and board.has_method("get_in_progress_tasks_for_assignee"):
		var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee("player")
		player_active_tasks = tasks.size()

	return {
		"active_tasks": player_active_tasks
	}

func _sample_personality_profile() -> Dictionary:
	var profile = get_node_or_null("/root/PlayerProfile")
	if profile and profile.has_method("get_profile"):
		return profile.get_profile()
	return {
		"tipi_responses": {},
		"tipi_scores": {},
		"question_count": 0
	}

func _episode_logger() -> Node:
	return get_node_or_null("/root/EpisodeLogger")

func _experiment_config() -> Node:
	return get_node_or_null("/root/ExperimentConfig")

func _log_help_event(req: Dictionary) -> void:
	var logger = _episode_logger()
	if logger == null or not logger.has_method("log_help_request_event"):
		return
	var exp = _experiment_config()
	if exp and exp.has_method("is_help_logging_enabled") and not bool(exp.is_help_logging_enabled()):
		return
	logger.log_help_request_event(req)

func _on_task_completed(task: Dictionary) -> void:
	_attach_task_outcome(task, true)

func _on_task_failed(task: Dictionary) -> void:
	_attach_task_outcome(task, false)

func _attach_task_outcome(task: Dictionary, completed: bool) -> void:
	if task.is_empty():
		return
	var task_id := str(task.get("id", ""))
	if task_id == "":
		return
	var request_id := _latest_request_id_for_task(task_id)
	if request_id == "":
		return
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return
	var payload: Dictionary = task.get("payload", {})
	var order_kind := str(payload.get("order_kind", "food"))
	var failure_reason := str(task.get("failure_reason", ""))
	req["task_completed"] = completed
	req["delivery_actor"] = str(task.get("assigned_to", ""))
	req["customer_timed_out"] = (not completed) and (failure_reason == "task_deadline_expired" or failure_reason == "customer_drink_timeout")
	req["score_delta"] = _score_delta_for_outcome(order_kind, completed)
	_requests_by_id[request_id] = req
	_log_help_event(req)
	request_updated.emit(_copy(req))

func _latest_request_id_for_task(task_id: String) -> String:
	for i in range(_order.size() - 1, -1, -1):
		var request_id := _order[i]
		var req: Dictionary = _requests_by_id.get(request_id, {})
		if req.is_empty():
			continue
		var payload: Dictionary = req.get("payload", {})
		if str(payload.get("task_id", "")) == task_id:
			return request_id
	return ""

func _score_delta_for_outcome(order_kind: String, completed: bool) -> int:
	if completed:
		return 1 if order_kind == "drink" else 2
	return -3 if order_kind == "drink" else -6

func _build_system_notice(payload: Dictionary) -> String:
	var reason := str(payload.get("reason", "")).strip_edges()
	var item := str(payload.get("item_needed", "item")).strip_edges()
	if item == "":
		item = "item"
	match reason:
		"deadline_critical":
			return "Priority order handling requires immediate handoff of %s." % item
		"battery_emergency":
			return "Battery critical. Delegation requested for %s." % item
		"robot_over_threshold_post_take_order":
			return "Task load threshold exceeded. Delegation requested for %s." % item
		_:
			return ""
