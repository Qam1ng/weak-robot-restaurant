extends Node

signal task_created(task: Dictionary)
signal task_updated(task: Dictionary)
signal task_completed(task: Dictionary)

const TASK_FULFILL_ORDER := "FULFILL_ORDER"
const STATE_UNASSIGNED := "unassigned"
const STATE_IN_PROGRESS := "in_progress"
const STATE_COMPLETED := "completed"

const STEP_TAKE_ORDER := "TAKE_ORDER"
const STEP_PICKUP_FROM_KITCHEN := "PICKUP_FROM_KITCHEN"
const STEP_DELIVER_AND_SERVE := "DELIVER_AND_SERVE"

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
	var deadline_ms := now_ms + 90_000
	if customer.has_method("get_task_deadline_ms"):
		deadline_ms = int(customer.get_task_deadline_ms())
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
		"deadline_ms": deadline_ms,
		"claimed_at_ms": 0,
		"completed_at_ms": 0,
		"assigned_to": "",
		"current_step_index": 0,
		"steps": steps,
		"payload": {
			"request_text": request_text,
			"food_item": food_item,
			"seat": seat,
			"customer_instance_id": customer.get_instance_id()
		}
	}

	_tasks_by_id[task_id] = task
	_task_order.append(task_id)

	var copied := _copy_task(task)
	task_created.emit(copied)
	_emit_taskbus_event("post_customer_request", copied)
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
	var now_ms := Time.get_ticks_msec()
	var urgency_weight := float(constraints.get("deadline_urgency_weight", 1.0))
	var best_score := INF
	var best_task: Dictionary = {}

	for task_id in _task_order:
		var task = _tasks_by_id.get(task_id, {})
		if task.is_empty():
			continue
		if task.get("state", "") != STATE_UNASSIGNED:
			continue
		if task_type != "" and task.get("type", "") != task_type:
			continue

		var slack_ms := _compute_slack_ms(task, now_ms)
		var score := float(slack_ms) * urgency_weight
		if score < best_score:
			best_score = score
			best_task = task

	if best_task.is_empty():
		return {}
	return _copy_task(best_task)

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

func _new_task_id() -> String:
	var id := "task_%06d" % _next_id
	_next_id += 1
	return id

func _extract_food_from_request(request: String) -> String:
	var request_lower = request.to_lower()
	var foods = ["pizza", "hotdog", "skewers", "sandwich"]
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
	var deadline_ms := int(task.get("deadline_ms", now_ms))
	return deadline_ms - now_ms
