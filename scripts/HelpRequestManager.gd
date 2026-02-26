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

var _requests_by_id: Dictionary = {}
var _order: Array[String] = []
var _next_id: int = 1
var _beacon_request_id: String = ""

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
		"beacon_position": beacon_pos
	}

	_requests_by_id[request_id] = req
	_order.append(request_id)
	_set_beacon_if_needed(req)
	print("[HelpRequest] Created ", request_id, " type=", request_type)

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
	req["last_prompt_ms"] = Time.get_ticks_msec()
	req["updated_at_ms"] = req["last_prompt_ms"]
	_requests_by_id[request_id] = req
	request_updated.emit(_copy(req))

func respond(request_id: String, response: String) -> Dictionary:
	var req: Dictionary = _requests_by_id.get(request_id, {})
	if req.is_empty():
		return {}
	if str(req.get("status", "")) == STATUS_RESOLVED:
		return _copy(req)

	var now_ms := Time.get_ticks_msec()
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
	var copied := _copy(req)
	print("[HelpRequest] Response ", response, " -> ", request_id, " status=", copied.get("status", ""))
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
	if str(req.get("final_response", "")) == "":
		req["final_response"] = RESPONSE_ACCEPT
	req["resolution_path"] = resolution_path
	req["updated_at_ms"] = Time.get_ticks_msec()
	_requests_by_id[request_id] = req

	_clear_beacon_if_matches(request_id)
	var copied := _copy(req)
	print("[HelpRequest] Completed ", request_id, " path=", resolution_path)
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
