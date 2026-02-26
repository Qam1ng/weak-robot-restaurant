extends Node

signal request_created(request: Dictionary)
signal request_updated(request: Dictionary)
signal request_resolved(request: Dictionary)
signal beacon_changed(active: bool, position: Vector2, request_id: String)

const RESPONSE_ACCEPT := "accept"
const RESPONSE_DECLINE := "decline"
const RESPONSE_LATER := "later"

const TYPE_HANDOFF := "HANDOFF"
const TYPE_OPEN_DOOR := "OPEN_DOOR"

const STATUS_PENDING := "pending"
const STATUS_COOLDOWN := "cooldown"
const STATUS_ACCEPTED := "accepted"
const STATUS_RESOLVED := "resolved"

const PersuasionEngineScript = preload("res://scripts/PersuasionEngine.gd")

var _requests_by_id: Dictionary = {}
var _order: Array[String] = []
var _next_id: int = 1
var _beacon_request_id: String = ""
var _interaction_model := {
	"total": 0,
	"accepted": 0,
	"declined": 0,
	"later": 0,
	"avg_latency_ms": 0.0,
	"annoyance": 0.0,
	"acceptance_rate": 0.5
}

func create_request(request_type: String, robot: Node, payload: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	if robot == null or not is_instance_valid(robot):
		return {}

	var now_ms := Time.get_ticks_msec()
	var request_id := "help_%06d" % _next_id
	_next_id += 1

	var max_escalation := int(options.get("max_escalation", 2))
	var cooldown_ms := int(options.get("cooldown_ms", 4000))
	var urgency := float(options.get("urgency", 0.5))
	var require_beacon := bool(options.get("require_beacon", request_type == TYPE_OPEN_DOOR))
	var beacon_pos: Vector2 = payload.get("door_position", Vector2.ZERO)

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
		"require_beacon": require_beacon,
		"beacon_position": beacon_pos,
		"context_snapshot": {},
		"strategy": "",
		"strategy_scores": {},
		"dialogue_intent": {},
		"utterance": "",
		"last_response": "",
		"experiment": {}
	}

	var context = _build_context(robot, req, options)
	req["context_snapshot"] = context
	var exp = _experiment_config()
	var variant := "A"
	if exp and exp.has_method("resolve_variant"):
		variant = str(exp.resolve_variant(request_id))
	var exp_snapshot := {}
	if exp and exp.has_method("get_snapshot"):
		exp_snapshot = exp.get_snapshot()
	exp_snapshot["assigned_variant"] = variant
	req["experiment"] = exp_snapshot

	var persuasion = PersuasionEngineScript.generate_dialogue(request_type, context, int(req["escalation_count"]), payload)
	if exp and exp.has_method("apply_dialogue_variant"):
		persuasion = exp.apply_dialogue_variant(variant, request_type, persuasion, payload, int(req["escalation_count"]))
	req["strategy"] = persuasion.get("strategy", "")
	req["strategy_scores"] = persuasion.get("strategy_scores", {})
	req["dialogue_intent"] = persuasion.get("dialogue_intent", {})
	req["utterance"] = persuasion.get("utterance", "")

	_requests_by_id[request_id] = req
	_order.append(request_id)
	_set_beacon_if_needed(req)
	print("[HelpRequest] Created ", request_id, " type=", request_type)
	_log_help_event("created", req)

	var copied := _copy(req)
	request_created.emit(copied)
	return copied

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
	var robot = _robot_from_request(req)
	if robot:
		var context = _build_context(robot, req, {})
		req["context_snapshot"] = context
		var persuasion = PersuasionEngineScript.generate_dialogue(
			str(req.get("type", TYPE_HANDOFF)),
			context,
			int(req.get("escalation_count", 0)),
			req.get("payload", {})
		)
		var exp = _experiment_config()
		if exp and exp.has_method("apply_dialogue_variant"):
			var variant := str(req.get("experiment", {}).get("assigned_variant", "A"))
			persuasion = exp.apply_dialogue_variant(
				variant,
				str(req.get("type", TYPE_HANDOFF)),
				persuasion,
				req.get("payload", {}),
				int(req.get("escalation_count", 0))
			)
		req["strategy"] = persuasion.get("strategy", "")
		req["strategy_scores"] = persuasion.get("strategy_scores", {})
		req["dialogue_intent"] = persuasion.get("dialogue_intent", {})
		req["utterance"] = persuasion.get("utterance", "")

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
			_clear_beacon_if_matches(request_id)
		RESPONSE_LATER:
			var escalation := int(req.get("escalation_count", 0)) + 1
			req["escalation_count"] = escalation
			req["updated_at_ms"] = now_ms
			if escalation >= int(req.get("max_escalation", 2)):
				req["status"] = STATUS_RESOLVED
				req["final_response"] = RESPONSE_DECLINE
				req["resolution_path"] = "later_threshold_decline"
				_clear_beacon_if_matches(request_id)
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

	_clear_beacon_if_matches(request_id)
	var copied := _copy(req)
	print("[HelpRequest] Completed ", request_id, " path=", resolution_path)
	_log_help_event("completed", req)
	_log_help_event("resolved", req)
	request_updated.emit(copied)
	request_resolved.emit(copied)
	return copied

func is_beacon_active() -> bool:
	return _beacon_request_id != ""

func get_beacon_position() -> Vector2:
	if _beacon_request_id == "":
		return Vector2.ZERO
	var req: Dictionary = _requests_by_id.get(_beacon_request_id, {})
	if req.is_empty():
		return Vector2.ZERO
	return req.get("beacon_position", Vector2.ZERO)

func _set_beacon_if_needed(req: Dictionary) -> void:
	if not bool(req.get("require_beacon", false)):
		return
	_beacon_request_id = str(req.get("id", ""))
	beacon_changed.emit(true, req.get("beacon_position", Vector2.ZERO), _beacon_request_id)

func _clear_beacon_if_matches(request_id: String) -> void:
	if _beacon_request_id != request_id:
		return
	_beacon_request_id = ""
	beacon_changed.emit(false, Vector2.ZERO, "")

func _copy(req: Dictionary) -> Dictionary:
	if req.is_empty():
		return {}
	return req.duplicate(true)

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
		"battery_mode": str(robot.get("_battery_mode")),
		"waiting_for_help": bool(robot.get("_waiting_for_help")),
		"active_step": str(robot.get("_active_task_step"))
	}
	if robot_state["battery_level"] == 0.0 and robot.get("battery_level") == null:
		robot_state["battery_level"] = 100.0
	if robot_state["battery_mode"] == "" or robot_state["battery_mode"] == "Null":
		robot_state["battery_mode"] = "normal"

	var player_state := _sample_player_state()

	var busyness := 0.5
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_busyness"):
		busyness = float(game_mgr.get_busyness())

	var payload: Dictionary = req.get("payload", {})
	var door_blocked := bool(options.get("door_blocked", req.get("type", "") == TYPE_OPEN_DOOR))
	var slack_ms := int(payload.get("slack_ms", 0))
	var urgency := float(options.get("urgency", 0.5))
	if slack_ms != 0:
		urgency = clampf(1.0 - (float(slack_ms) / 90000.0), 0.0, 1.0)

	return {
		"robot": robot_state,
		"player": player_state,
		"environment": {
			"urgency": urgency,
			"busyness": busyness,
			"door_blocked": door_blocked,
			"slack_ms": slack_ms
		},
		"history": {
			"acceptance_rate": float(_interaction_model.get("acceptance_rate", 0.5)),
			"avg_latency_ms": float(_interaction_model.get("avg_latency_ms", 0.0)),
			"annoyance": float(_interaction_model.get("annoyance", 0.0))
		}
	}

func _sample_player_state() -> Dictionary:
	var load := 0.5
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var player = players[0]
		var inv = player.get_node_or_null("Inventory")
		if inv:
			var cap := maxf(float(inv.capacity), 1.0)
			load = clampf(float(inv.items.size()) / cap, 0.0, 1.0)

	return {
		"load": load
	}

func _update_interaction_model(response: String, latency_ms: int) -> void:
	_interaction_model["total"] = int(_interaction_model.get("total", 0)) + 1
	if response == RESPONSE_ACCEPT:
		_interaction_model["accepted"] = int(_interaction_model.get("accepted", 0)) + 1
		_interaction_model["annoyance"] = maxf(0.0, float(_interaction_model.get("annoyance", 0.0)) - 0.12)
	elif response == RESPONSE_DECLINE:
		_interaction_model["declined"] = int(_interaction_model.get("declined", 0)) + 1
		_interaction_model["annoyance"] = minf(1.0, float(_interaction_model.get("annoyance", 0.0)) + 0.18)
	elif response == RESPONSE_LATER:
		_interaction_model["later"] = int(_interaction_model.get("later", 0)) + 1
		_interaction_model["annoyance"] = minf(1.0, float(_interaction_model.get("annoyance", 0.0)) + 0.08)

	var total := maxf(float(_interaction_model["total"]), 1.0)
	_interaction_model["acceptance_rate"] = float(_interaction_model.get("accepted", 0)) / total

	var old_avg := float(_interaction_model.get("avg_latency_ms", 0.0))
	_interaction_model["avg_latency_ms"] = ((old_avg * (total - 1.0)) + float(latency_ms)) / total

func _episode_logger() -> Node:
	return get_node_or_null("/root/EpisodeLogger")

func _experiment_config() -> Node:
	return get_node_or_null("/root/ExperimentConfig")

func _log_help_event(event_type: String, req: Dictionary, extra: Dictionary = {}) -> void:
	var logger = _episode_logger()
	if logger == null or not logger.has_method("log_help_request_event"):
		return
	var exp = _experiment_config()
	if exp and exp.has_method("is_help_logging_enabled") and not bool(exp.is_help_logging_enabled()):
		return
	logger.log_help_request_event(event_type, req, extra)
