extends Node

signal request_created(request: Dictionary)
signal request_updated(request: Dictionary)
signal request_resolved(request: Dictionary)

const RESPONSE_ACCEPT := "accept"
const RESPONSE_DECLINE := "decline"
const RESPONSE_LATER := "later"

const TYPE_HANDOFF := "HANDOFF"
const API_ASSIGN_STRATEGY_URL := "https://us-central1-weak-robot-restaurant-web.cloudfunctions.net/apiAssignStrategy"

const STATUS_PENDING := "pending"
const STATUS_COOLDOWN := "cooldown"
const STATUS_ACCEPTED := "accepted"
const STATUS_RESOLVED := "resolved"

const PersuasionEngineScript = preload("res://scripts/PersuasionEngine.gd")

var _requests_by_id: Dictionary = {}
var _order: Array[String] = []
var _next_id: int = 1
var _interaction_model := {
	"total": 0,
	"accepted": 0,
	"declined": 0,
	"later": 0,
	"avg_latency_ms": 0.0,
	"acceptance_rate": 0.5
}

func reset_all() -> void:
	_requests_by_id.clear()
	_order.clear()
	_next_id = 1
	if PersuasionEngineScript.has_method("reset_assignment_state"):
		PersuasionEngineScript.reset_assignment_state()
	_interaction_model = {
		"total": 0,
		"accepted": 0,
		"declined": 0,
		"later": 0,
		"avg_latency_ms": 0.0,
		"acceptance_rate": 0.5
	}

func _ready() -> void:
	var dm = _dialogue_manager()
	if dm and dm.has_signal("utterance_generated") and not dm.utterance_generated.is_connected(_on_utterance_generated):
		dm.utterance_generated.connect(_on_utterance_generated)
	var board = get_node_or_null("/root/TaskBoard")
	if board:
		if board.has_signal("task_completed") and not board.task_completed.is_connected(_on_task_completed):
			board.task_completed.connect(_on_task_completed)
		if board.has_signal("task_failed") and not board.task_failed.is_connected(_on_task_failed):
			board.task_failed.connect(_on_task_failed)

func _process(_dt: float) -> void:
	var now_ms := Time.get_ticks_msec()
	for request_id in _order:
		var req: Dictionary = _requests_by_id.get(request_id, {})
		if req.is_empty():
			continue
		if str(req.get("status", "")) != STATUS_COOLDOWN:
			continue
		if now_ms < int(req.get("cooldown_until_ms", 0)):
			continue
		req["status"] = STATUS_PENDING
		req["updated_at_ms"] = now_ms
		_requests_by_id[request_id] = req
		_log_help_event("cooldown_expired", req)
		request_updated.emit(_copy(req))
func create_request(request_type: String, robot: Node, payload: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	if robot == null or not is_instance_valid(robot):
		return {}

	var now_ms := Time.get_ticks_msec()
	var request_id := "help_%06d" % _next_id
	_next_id += 1

	var max_escalation := int(options.get("max_escalation", 2))
	var cooldown_ms := int(options.get("cooldown_ms", 4000))
	var urgency := float(options.get("urgency", 0.5))

	var req := {
		"id": request_id,
		"type": request_type,
		"status": STATUS_PENDING,
		"robot_instance_id": robot.get_instance_id(),
		"payload": payload.duplicate(true),
		"created_at_ms": now_ms,
		"updated_at_ms": now_ms,
		"last_prompt_ms": 0,
		"cooldown_until_ms": 0,
		"cooldown_ms": cooldown_ms,
		"escalation_count": 0,
		"max_escalation": max_escalation,
		"urgency": urgency,
		"final_response": "",
		"resolution_path": "",
		"context_snapshot": {},
		"strategy": "",
		"assignment_method": "",
		"assignment_buckets": {},
		"system_notice": "",
		"utterance": "",
		"utterance_source": "template",
		"utterance_pending": false,
		"last_response": "",
		"task_completed": false,
		"task_failed": false,
		"delivery_actor": "",
		"customer_timed_out": false,
		"score_delta": 0,
		"experiment": {},
		"assignment_pending": true
	}

	var context = _build_context(robot, req, options)
	req["context_snapshot"] = context
	var exp = _experiment_config()
	var exp_snapshot := {}
	if exp and exp.has_method("get_snapshot"):
		exp_snapshot = exp.get_snapshot()
	req["experiment"] = exp_snapshot

	req["assignment_buckets"] = PersuasionEngineScript.build_assignment_buckets(request_type, context)
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
	var now_ms := Time.get_ticks_msec()
	var best: Dictionary = {}
	var best_score := -INF

	for request_id in _order:
		var req: Dictionary = _requests_by_id.get(request_id, {})
		if req.is_empty():
			continue
		if int(req.get("robot_instance_id", 0)) != robot_iid:
			continue
		var status := str(req.get("status", ""))
		if status != STATUS_PENDING and status != STATUS_COOLDOWN:
			continue
		if bool(req.get("assignment_pending", false)):
			continue
		if now_ms < int(req.get("cooldown_until_ms", 0)):
			continue

		var escalation := int(req.get("escalation_count", 0))
		var urgency := float(req.get("urgency", 0.5))
		var score := urgency * 10.0 + float(escalation)
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
	req["last_prompt_ms"] = Time.get_ticks_msec()
	req["updated_at_ms"] = req["last_prompt_ms"]
	_requests_by_id[request_id] = req
	_log_help_event("prompted", req)
	request_updated.emit(_copy(req))

func respond(request_id: String, response: String) -> Dictionary:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return {}
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return _copy(req)

	var now_ms := Time.get_ticks_msec()
	var prompt_latency_ms := 0
	if int(req.get("last_prompt_ms", 0)) > 0:
		prompt_latency_ms = now_ms - int(req.get("last_prompt_ms", 0))
	req["response_latency_ms"] = prompt_latency_ms
	req["last_response"] = response
	match response:
		RESPONSE_ACCEPT:
			req["status"] = STATUS_ACCEPTED
			req["final_response"] = RESPONSE_ACCEPT
			req["updated_at_ms"] = now_ms
		RESPONSE_DECLINE:
			req["status"] = STATUS_RESOLVED
			req["final_response"] = RESPONSE_DECLINE
			req["resolution_path"] = "declined"
			req["updated_at_ms"] = now_ms
		RESPONSE_LATER:
			var escalation := int(req.get("escalation_count", 0)) + 1
			req["escalation_count"] = escalation
			req["updated_at_ms"] = now_ms
			if escalation >= int(req.get("max_escalation", 2)):
				req["status"] = STATUS_RESOLVED
				req["final_response"] = RESPONSE_DECLINE
				req["resolution_path"] = "later_threshold_decline"
			else:
				req["status"] = STATUS_COOLDOWN
				req["cooldown_until_ms"] = now_ms + int(req.get("cooldown_ms", 4000))
		_:
			return _copy(req)

	_requests_by_id[request_id] = req
	_update_interaction_model(response, prompt_latency_ms)
	var copied := _copy(req)
	print("[HelpRequest] Response ", response, " -> ", request_id, " status=", copied.get("status", ""))
	_log_help_event("responded", req, {"response": response})
	request_updated.emit(copied)
	if str(req.get("status", "")) == STATUS_RESOLVED:
		_log_help_event("resolved", req)
		request_resolved.emit(copied)
	return copied

func complete_request(request_id: String, resolution_path: String = "cooperative_execution") -> Dictionary:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return {}
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return _copy(req)

	req["status"] = STATUS_RESOLVED
	if str(req.get("final_response", "")) == "":
		req["final_response"] = RESPONSE_ACCEPT
	req["resolution_path"] = resolution_path
	req["updated_at_ms"] = Time.get_ticks_msec()
	_requests_by_id[request_id] = req
	_update_interaction_model(RESPONSE_ACCEPT, int(req.get("response_latency_ms", 0)))

	var copied := _copy(req)
	print("[HelpRequest] Completed ", request_id, " path=", resolution_path)
	_log_help_event("completed", req)
	_log_help_event("resolved", req)
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
	req["updated_at_ms"] = Time.get_ticks_msec()
	_requests_by_id[request_id] = req
	var copied := _copy(req)
	_log_help_event("canceled", req)
	_log_help_event("resolved", req)
	request_updated.emit(copied)
	request_resolved.emit(copied)
	return copied

func requeue_request(request_id: String, cooldown_ms: int = 1500, resolution_note: String = "retry_later") -> Dictionary:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return {}
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return _copy(req)
	var now_ms := Time.get_ticks_msec()
	req["status"] = STATUS_COOLDOWN
	req["updated_at_ms"] = now_ms
	req["cooldown_until_ms"] = now_ms + maxi(cooldown_ms, 0)
	req["resolution_path"] = resolution_note
	req["final_response"] = ""
	req["last_response"] = ""
	req["response_latency_ms"] = 0
	_requests_by_id[request_id] = req
	var copied := _copy(req)
	_log_help_event("requeued", req, {"resolution_note": resolution_note})
	request_updated.emit(copied)
	return copied


func _copy(req: Dictionary) -> Dictionary:
	if req.is_empty():
		return {}
	return req.duplicate(true)

func _begin_strategy_assignment(request_id: String) -> void:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return
	if _should_use_backend_assignment():
		_request_remote_strategy_assignment(req)
		return
	var request_type := str(req.get("type", TYPE_HANDOFF))
	var context: Dictionary = req.get("context_snapshot", {})
	var assignment := PersuasionEngineScript.assign_strategy_locally(request_type, context)
	_finalize_strategy_assignment(request_id, assignment)

func _request_remote_strategy_assignment(req: Dictionary) -> void:
	var request_id := str(req.get("id", ""))
	if request_id == "":
		return
	var body := {
		"request_id": request_id,
		"request_type": str(req.get("type", TYPE_HANDOFF)),
		"assignment_buckets": req.get("assignment_buckets", {})
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
		var fallback := PersuasionEngineScript.assign_strategy_locally(
			str(req.get("type", TYPE_HANDOFF)),
			req.get("context_snapshot", {})
		)
		_finalize_strategy_assignment(request_id, fallback)

func _on_strategy_assignment_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, request_id: String) -> void:
	if is_instance_valid(http):
		http.queue_free()
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return
	if code < 200 or code >= 300:
		var fallback := PersuasionEngineScript.assign_strategy_locally(
			str(req.get("type", TYPE_HANDOFF)),
			req.get("context_snapshot", {})
		)
		_finalize_strategy_assignment(request_id, fallback)
		return
	var top = JSON.parse_string(body.get_string_from_utf8())
	if not (top is Dictionary):
		var fallback_parse := PersuasionEngineScript.assign_strategy_locally(
			str(req.get("type", TYPE_HANDOFF)),
			req.get("context_snapshot", {})
		)
		_finalize_strategy_assignment(request_id, fallback_parse)
		return
	var assignment := {
		"strategy": str(top.get("strategy", "")),
		"method": str(top.get("assignment_method", "")),
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
	if strategy == "":
		strategy = PersuasionEngineScript.STRATEGY_AUTHORITY
	var method := str(assignment.get("method", "")).strip_edges()
	if method == "":
		method = "session_local_stratified_weighted_random"
	var buckets: Dictionary = assignment.get("buckets", {})
	if buckets.is_empty():
		buckets = PersuasionEngineScript.build_assignment_buckets(
			str(req.get("type", TYPE_HANDOFF)),
			req.get("context_snapshot", {})
		)
	req["strategy"] = strategy
	req["assignment_method"] = method
	req["assignment_buckets"] = buckets
	req["utterance"] = PersuasionEngineScript.render_template(
		str(req.get("type", TYPE_HANDOFF)),
		strategy,
		req.get("context_snapshot", {}),
		int(req.get("escalation_count", 0)),
		req.get("payload", {})
	)
	req["utterance_source"] = "template"
	req["assignment_pending"] = false
	req["updated_at_ms"] = Time.get_ticks_msec()
	if _should_request_help_utterance(req):
		req["utterance_pending"] = true
	else:
		req["utterance_pending"] = false
	_requests_by_id[request_id] = req
	print("[HelpRequest] Created ", request_id, " type=", str(req.get("type", "")))
	_log_help_event("created", req)
	if bool(req.get("utterance_pending", false)):
		_request_utterance_realization(req)
	var copied := _copy(req)
	request_created.emit(copied)

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
		},
		"history": {
			"acceptance_rate": float(_interaction_model.get("acceptance_rate", 0.5)),
			"avg_latency_ms": float(_interaction_model.get("avg_latency_ms", 0.0))
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

func _update_interaction_model(response: String, latency_ms: int) -> void:
	_interaction_model["total"] = int(_interaction_model.get("total", 0)) + 1
	if response == RESPONSE_ACCEPT:
		_interaction_model["accepted"] = int(_interaction_model.get("accepted", 0)) + 1
	elif response == RESPONSE_DECLINE:
		_interaction_model["declined"] = int(_interaction_model.get("declined", 0)) + 1
	elif response == RESPONSE_LATER:
		_interaction_model["later"] = int(_interaction_model.get("later", 0)) + 1

	var total := maxf(float(_interaction_model["total"]), 1.0)
	_interaction_model["acceptance_rate"] = float(_interaction_model.get("accepted", 0)) / total

	var old_avg := float(_interaction_model.get("avg_latency_ms", 0.0))
	_interaction_model["avg_latency_ms"] = ((old_avg * (total - 1.0)) + float(latency_ms)) / total

func _episode_logger() -> Node:
	return get_node_or_null("/root/EpisodeLogger")

func _experiment_config() -> Node:
	return get_node_or_null("/root/ExperimentConfig")

func _dialogue_manager() -> Node:
	return get_node_or_null("/root/DialogueManager")

func _log_help_event(event_type: String, req: Dictionary, extra: Dictionary = {}) -> void:
	var logger = _episode_logger()
	if logger == null or not logger.has_method("log_help_request_event"):
		return
	var exp = _experiment_config()
	if exp and exp.has_method("is_help_logging_enabled") and not bool(exp.is_help_logging_enabled()):
		return
	logger.log_help_request_event(event_type, req, extra)

func _should_request_help_utterance(req: Dictionary) -> bool:
	if req.is_empty():
		return false
	var dm = _dialogue_manager()
	if dm == null:
		return false
	if dm.has_method("_is_llm_enabled") and not bool(dm._is_llm_enabled()):
		return false
	if dm.has_method("has_api_key") and not bool(dm.has_api_key()):
		return false
	return dm.has_method("realize_help_utterance")

func _request_utterance_realization(req: Dictionary) -> void:
	if req.is_empty():
		return
	var dm = _dialogue_manager()
	if dm == null or not dm.has_method("realize_help_utterance"):
		return
	dm.realize_help_utterance(req)

func _on_utterance_generated(request_id: String, utterance: String, meta: Dictionary) -> void:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return
	if int(req.get("last_prompt_ms", 0)) > 0:
		req["utterance_pending"] = false
		_requests_by_id[request_id] = req
		_log_help_event("utterance_ignored_after_prompt", req, meta)
		return
	req["utterance_pending"] = false
	if utterance != "":
		req["utterance"] = utterance
		req["utterance_source"] = str(meta.get("provider", "llm"))
		req["updated_at_ms"] = Time.get_ticks_msec()
		_requests_by_id[request_id] = req
		_log_help_event("utterance_realized", req, meta)
		request_updated.emit(_copy(req))
		return
	req["updated_at_ms"] = Time.get_ticks_msec()
	_requests_by_id[request_id] = req
	_log_help_event("utterance_realization_failed", req, meta)
	request_updated.emit(_copy(req))

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
	req["task_failed"] = not completed
	req["delivery_actor"] = str(task.get("assigned_to", ""))
	req["customer_timed_out"] = (not completed) and (failure_reason == "task_deadline_expired" or failure_reason == "customer_drink_timeout")
	req["score_delta"] = _score_delta_for_outcome(order_kind, completed)
	req["updated_at_ms"] = Time.get_ticks_msec()
	_requests_by_id[request_id] = req
	_log_help_event("task_outcome_attached", req, {
		"task_id": task_id,
		"completed": completed
	})
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
		"inventory_full_blocked_pickup":
			return "Inventory full. Delegation requested for %s." % item
		"robot_stuck_or_pick_fail":
			return "Pickup blocked. Delegation requested for %s." % item
		_:
			return ""
