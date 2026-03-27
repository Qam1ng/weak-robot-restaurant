extends Node

signal task_created(task: Dictionary)
signal task_updated(task: Dictionary)
signal task_completed(task: Dictionary)
signal task_failed(task: Dictionary)

const TASK_FULFILL_ORDER := "FULFILL_ORDER"
const TASK_DRINK_ORDER := "DRINK_ORDER"
const STATE_UNASSIGNED := "unassigned"
const STATE_IN_PROGRESS := "in_progress"
const STATE_COMPLETED := "completed"
const STATE_FAILED := "failed"

const STEP_TAKE_ORDER := "TAKE_ORDER"
const STEP_PICKUP_FROM_KITCHEN := "PICKUP_FROM_KITCHEN"
const STEP_DELIVER_AND_SERVE := "DELIVER_AND_SERVE"
const SERVE_WINDOW_MS := 90_000
const DRINK_WINDOW_MS := 60_000

var _tasks_by_id: Dictionary = {}
var _task_order: Array[String] = []
var _next_id: int = 1

func create_fulfill_order(customer: Node) -> Dictionary:
	if not is_instance_valid(customer):
		return {}

	var request_text := ""
	var seat := ""
	if "request_text" in customer:
		request_text = str(customer.request_text)
	if "current_seat" in customer:
		seat = str(customer.current_seat)

	var task_id := _new_task_id()
	var now_ms := Time.get_ticks_msec()
	var food_item := _extract_food_from_request(request_text)
	var steps := [
		{"name": STEP_TAKE_ORDER, "state": "pending"},
		{"name": STEP_PICKUP_FROM_KITCHEN, "state": "pending"},
		{"name": STEP_DELIVER_AND_SERVE, "state": "pending"}
	]

	var task := {
		"id": task_id,
		"type": TASK_FULFILL_ORDER,
		"state": STATE_UNASSIGNED,
		"created_at_ms": now_ms,
		"deadline_ms": now_ms + SERVE_WINDOW_MS,
		"claimed_at_ms": 0,
		"completed_at_ms": 0,
		"assigned_to": "",
		"current_step_index": 0,
		"steps": steps,
		"payload": {
			"order_kind": "food",
			"request_text": request_text,
			"food_item": food_item,
			"display_item": food_item,
			"seat": seat,
			"customer_instance_id": customer.get_instance_id(),
			"serve_deadline_ms": now_ms + SERVE_WINDOW_MS
		}
	}

	_tasks_by_id[task_id] = task
	_task_order.append(task_id)

	var copied := _copy_task(task)
	task_created.emit(copied)
	_emit_taskbus_event("post_customer_request", copied)
	return copied

func create_drink_order(customer: Node, drink_item: String, assignee: String = "player") -> Dictionary:
	if not is_instance_valid(customer):
		return {}
	var item_name := drink_item.strip_edges().to_lower()
	if item_name == "":
		return {}
	var seat := ""
	if "current_seat" in customer:
		seat = str(customer.current_seat)
	var task_id := _new_task_id()
	var now_ms := Time.get_ticks_msec()
	var steps := [
		{"name": STEP_TAKE_ORDER, "state": "pending"},
		{"name": STEP_PICKUP_FROM_KITCHEN, "state": "pending"},
		{"name": STEP_DELIVER_AND_SERVE, "state": "pending"}
	]
	var initial_state := STATE_UNASSIGNED if assignee == "" else STATE_IN_PROGRESS
	var claimed_at_ms := 0 if assignee == "" else now_ms
	var task := {
		"id": task_id,
		"type": TASK_DRINK_ORDER,
		"state": initial_state,
		"created_at_ms": now_ms,
		"deadline_ms": now_ms + DRINK_WINDOW_MS,
		"claimed_at_ms": claimed_at_ms,
		"completed_at_ms": 0,
		"assigned_to": assignee,
		"current_step_index": 0,
		"steps": steps,
		"payload": {
			"order_kind": "drink",
			"request_text": "Can I also get a %s?" % item_name,
			"drink_item": item_name,
			"display_item": item_name,
			"seat": seat,
			"customer_instance_id": customer.get_instance_id(),
			"serve_deadline_ms": now_ms + DRINK_WINDOW_MS
		}
	}
	_tasks_by_id[task_id] = task
	_task_order.append(task_id)
	var copied := _copy_task(task)
	task_created.emit(copied)
	task_updated.emit(copied)
	return copied

func get_next_unassigned_task(task_type: String = "") -> Dictionary:
	for task_id in _task_order:
		var task = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		if task.get("state", "") != STATE_UNASSIGNED:
			continue
		if task_type != "" and task.get("type", "") != task_type:
			continue
		return _copy_task(task)
	return {}

func get_best_unassigned_task(task_type: String = "", constraints: Dictionary = {}) -> Dictionary:
	for task_id in _task_order:
		var task = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		if task.get("state", "") != STATE_UNASSIGNED:
			continue
		if task_type != "" and task.get("type", "") != task_type:
			continue
		# FIFO: return the earliest created unassigned task.
		return _copy_task(task)
	return {}

func claim_task(task_id: String, assignee: String) -> Dictionary:
	var task = _tasks_by_id.get(task_id, {})
	if task.is_empty():
		return {}
	if task.get("state", "") != STATE_UNASSIGNED:
		return {}

	task["state"] = STATE_IN_PROGRESS
	task["assigned_to"] = assignee
	task["claimed_at_ms"] = Time.get_ticks_msec()
	_tasks_by_id[task_id] = task

	var copied := _copy_task(task)
	task_updated.emit(copied)
	_emit_taskbus_event("post_robot_claimed", copied)
	return copied

func get_task(task_id: String) -> Dictionary:
	var task = _tasks_by_id.get(task_id, {})
	return _copy_task(task)

func get_current_step_name(task_id: String) -> String:
	var task = _tasks_by_id.get(task_id, {})
	if task.is_empty():
		return ""
	var idx: int = int(task.get("current_step_index", 0))
	var steps: Array = task.get("steps", [])
	if idx < 0 or idx >= steps.size():
		return ""
	return str(steps[idx].get("name", ""))

func complete_current_step(task_id: String, expected_step_name: String = "") -> bool:
	var task = _tasks_by_id.get(task_id, {})
	if task.is_empty():
		return false
	if task.get("state", "") != STATE_IN_PROGRESS:
		return false

	var idx: int = int(task.get("current_step_index", 0))
	var steps: Array = task.get("steps", [])
	if idx < 0 or idx >= steps.size():
		return false

	var step: Dictionary = steps[idx]
	var actual_step_name := str(step.get("name", ""))
	if expected_step_name != "" and actual_step_name != expected_step_name:
		return false

	step["state"] = "completed"
	steps[idx] = step
	task["steps"] = steps
	task["current_step_index"] = idx + 1
	if int(task["current_step_index"]) >= steps.size():
		task["state"] = STATE_COMPLETED
		task["completed_at_ms"] = Time.get_ticks_msec()

	_tasks_by_id[task_id] = task
	var copied := _copy_task(task)
	task_updated.emit(copied)

	if task.get("state", "") == STATE_COMPLETED:
		task_completed.emit(copied)

	return true

func reassign_task(task_id: String, assignee: String) -> Dictionary:
	var task = _tasks_by_id.get(task_id, {})
	if task.is_empty():
		return {}
	if str(task.get("state", "")) != STATE_IN_PROGRESS:
		return {}
	task["assigned_to"] = assignee
	task["reassigned_at_ms"] = Time.get_ticks_msec()
	_tasks_by_id[task_id] = task
	var copied := _copy_task(task)
	task_updated.emit(copied)
	return copied

func get_in_progress_tasks_for_assignee(assignee: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		if str(task.get("state", "")) != STATE_IN_PROGRESS:
			continue
		if str(task.get("assigned_to", "")) != assignee:
			continue
		out.append(_copy_task(task))
	return out

func get_in_progress_task_for_customer(customer_instance_id: int, assignee: String = "") -> Dictionary:
	if customer_instance_id <= 0:
		return {}
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		if str(task.get("state", "")) != STATE_IN_PROGRESS:
			continue
		if assignee != "" and str(task.get("assigned_to", "")) != assignee:
			continue
		var payload: Dictionary = task.get("payload", {})
		if int(payload.get("customer_instance_id", 0)) == customer_instance_id:
			return _copy_task(task)
	return {}

func get_open_task_for_customer(customer_instance_id: int) -> Dictionary:
	if customer_instance_id <= 0:
		return {}
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		var state := str(task.get("state", ""))
		if state == STATE_COMPLETED or state == STATE_FAILED:
			continue
		var payload: Dictionary = task.get("payload", {})
		if int(payload.get("customer_instance_id", 0)) == customer_instance_id:
			return _copy_task(task)
	return {}

func get_open_tasks_for_customer(customer_instance_id: int, task_type: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if customer_instance_id <= 0:
		return out
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		if task_type != "" and str(task.get("type", "")) != task_type:
			continue
		var state := str(task.get("state", ""))
		if state == STATE_COMPLETED or state == STATE_FAILED:
			continue
		var payload: Dictionary = task.get("payload", {})
		if int(payload.get("customer_instance_id", 0)) != customer_instance_id:
			continue
		out.append(_copy_task(task))
	return out

func get_in_progress_tasks_for_customer(customer_instance_id: int, assignee: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if customer_instance_id <= 0:
		return out
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		if str(task.get("state", "")) != STATE_IN_PROGRESS:
			continue
		if assignee != "" and str(task.get("assigned_to", "")) != assignee:
			continue
		var payload: Dictionary = task.get("payload", {})
		if int(payload.get("customer_instance_id", 0)) != customer_instance_id:
			continue
		out.append(_copy_task(task))
	return out

func get_best_handoff_candidate_for_player() -> Dictionary:
	var best: Dictionary = {}
	var best_slack := INF
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		if str(task.get("state", "")) != STATE_UNASSIGNED:
			continue
		var step_name := get_current_step_name(str(task.get("id", "")))
		if step_name != STEP_TAKE_ORDER:
			continue
		var slack := _compute_slack_ms(task, Time.get_ticks_msec())
		if slack < best_slack:
			best_slack = slack
			best = task
	if best.is_empty():
		return {}
	return _copy_task(best)

func is_task_completed(task_id: String) -> bool:
	var task = _tasks_by_id.get(task_id, {})
	if task.is_empty():
		return false
	return task.get("state", "") == STATE_COMPLETED

func get_task_slack_ms(task_id: String) -> int:
	var task = _tasks_by_id.get(task_id, {})
	if task.is_empty():
		return 0
	return _compute_slack_ms(task, Time.get_ticks_msec())

func get_open_task_count() -> int:
	var count := 0
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		var state := str(task.get("state", ""))
		if state == STATE_COMPLETED or state == STATE_FAILED:
			continue
		count += 1
	return count

func get_all_tasks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		out.append(_copy_task(task))
	return out

func complete_task(task_id: String) -> bool:
	var task = _tasks_by_id.get(task_id, {})
	if task.is_empty():
		return false

	var steps: Array = task.get("steps", [])
	for i in range(steps.size()):
		var step: Dictionary = steps[i]
		step["state"] = "completed"
		steps[i] = step
	task["steps"] = steps
	task["current_step_index"] = steps.size()
	task["state"] = STATE_COMPLETED
	task["completed_at_ms"] = Time.get_ticks_msec()
	_tasks_by_id[task_id] = task

	var copied := _copy_task(task)
	task_updated.emit(copied)
	task_completed.emit(copied)
	return true

func fail_task(task_id: String, reason: String = "unknown_failure") -> bool:
	var task = _tasks_by_id.get(task_id, {})
	if task.is_empty():
		return false
	var state := str(task.get("state", ""))
	if state == STATE_COMPLETED or state == STATE_FAILED:
		return false

	task["state"] = STATE_FAILED
	task["failed_at_ms"] = Time.get_ticks_msec()
	task["failure_reason"] = reason
	_tasks_by_id[task_id] = task

	var copied := _copy_task(task)
	task_updated.emit(copied)
	task_failed.emit(copied)
	_log_task_failure(copied)
	return true

func fail_task_by_customer(customer_instance_id: int, reason: String = "customer_left") -> bool:
	if customer_instance_id <= 0:
		return false
	var changed := false
	for task_id in _task_order:
		var task: Dictionary = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		var payload: Dictionary = task.get("payload", {})
		if int(payload.get("customer_instance_id", 0)) != customer_instance_id:
			continue
		var state := str(task.get("state", ""))
		if state == STATE_COMPLETED or state == STATE_FAILED:
			continue
		if fail_task(task_id, reason):
			changed = true
	return changed

func _new_task_id() -> String:
	var id := "task_%06d" % _next_id
	_next_id += 1
	return id

func _extract_food_from_request(request: String) -> String:
	var request_lower = request.to_lower()
	var foods = ["pizza", "hotdog", "sandwich"]
	for food in foods:
		if food in request_lower:
			return food
	return "unknown"

func _emit_taskbus_event(method_name: String, task: Dictionary) -> void:
	var task_bus = get_node_or_null("/root/TaskBus")
	if task_bus and task_bus.has_method(method_name):
		task_bus.call(method_name, task)

func _copy_task(task: Dictionary) -> Dictionary:
	if task.is_empty():
		return {}
	return task.duplicate(true)

func _compute_slack_ms(task: Dictionary, now_ms: int) -> int:
	var deadline_ms := int(task.get("deadline_ms", 0))
	if deadline_ms <= 0:
		# No active timer yet (before TAKE_ORDER); treat as low urgency.
		return 2_000_000_000
	return deadline_ms - now_ms

func _log_task_failure(task: Dictionary) -> void:
	var logger = get_node_or_null("/root/EpisodeLogger")
	if logger == null:
		return
	if logger.has_method("log_replay_event"):
		logger.log_replay_event("task_failed", {
			"task_id": str(task.get("id", "")),
			"reason": str(task.get("failure_reason", "")),
			"state": str(task.get("state", "")),
			"payload": task.get("payload", {})
		})
	if logger.has_method("log_event"):
		logger.log_event("task_failed", {
			"task_id": str(task.get("id", "")),
			"reason": str(task.get("failure_reason", ""))
		})
