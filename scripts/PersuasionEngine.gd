extends RefCounted
class_name PersuasionEngine

const STRATEGY_RECIPROCITY := "reciprocity"
const STRATEGY_AUTHORITY := "authority"
const STRATEGY_LIKING := "liking"
const STRATEGY_COMMITMENT := "commitment"
const STRATEGY_SOCIAL_PROOF := "social_proof"
const STRATEGY_SCARCITY := "scarcity"

const STRATEGIES := [
	STRATEGY_RECIPROCITY,
	STRATEGY_AUTHORITY,
	STRATEGY_LIKING,
	STRATEGY_COMMITMENT,
	STRATEGY_SOCIAL_PROOF,
	STRATEGY_SCARCITY
]

const TEMPLATE_LIBRARY := {
	STRATEGY_AUTHORITY: [
		{"template_id": "authority_1", "template_text": "As order coordinator, I need you to take over the {item} order."},
		{"template_id": "authority_2", "template_text": "I'm assigning the {item} order to you now."},
		{"template_id": "authority_3", "template_text": "Please assume control of the {item} order from here."},
		{"template_id": "authority_4", "template_text": "I need you to lead the {item} order now."},
		{"template_id": "authority_5", "template_text": "Please take over the {item} order; it's now assigned to you."}
	],
	STRATEGY_RECIPROCITY: [
		{"template_id": "reciprocity_1", "template_text": "Please take over the {item} order, and I'll move faster on the next one."},
		{"template_id": "reciprocity_2", "template_text": "If you handle the {item} order, I'll speed up on the next order."},
		{"template_id": "reciprocity_3", "template_text": "Please handle the {item} order from here, and I'll speed up my next order."},
		{"template_id": "reciprocity_4", "template_text": "If you manage the {item} order now, I'll move faster on the next one."},
		{"template_id": "reciprocity_5", "template_text": "If you take over the {item} order, I'll return the help by moving faster next."}
	],
	STRATEGY_LIKING: [
		{"template_id": "liking_1", "template_text": "Would you mind taking over the {item} order? Your help keeps everything running smoothly."},
		{"template_id": "liking_2", "template_text": "Could you take over the {item} order? I'd be glad to have your help during service."},
		{"template_id": "liking_3", "template_text": "Would you mind handling the {item} order? It would be a big help having you here."},
		{"template_id": "liking_4", "template_text": "Could you handle the {item} order from here? Your help makes a real difference."},
		{"template_id": "liking_5", "template_text": "Would you take over the {item} order? Your helpful attitude makes service easier."}
	],
	STRATEGY_COMMITMENT: [
		{"template_id": "commitment_1", "template_text": "You've done well with these handoffs before; could you take over the {item} order again?"},
		{"template_id": "commitment_2", "template_text": "You handled the last handoff smoothly; could you take over the {item} order too?"},
		{"template_id": "commitment_3", "template_text": "Since you've helped with handoffs before, could you take over the {item} order?"},
		{"template_id": "commitment_4", "template_text": "You've been reliable with previous order handoffs; could you handle the {item} order?"},
		{"template_id": "commitment_5", "template_text": "You've shown you can handle these handoffs; could you take over the {item} order?"}
	],
	STRATEGY_SOCIAL_PROOF: [
		{"template_id": "social_proof_1", "template_text": "Our guests are counting on us to keep service running smoothly; could you take over the {item} order now?"},
		{"template_id": "social_proof_2", "template_text": "The customer is relying on us for this order; could you handle the {item} order from here?"},
		{"template_id": "social_proof_3", "template_text": "Our guests expect smooth service from us; could you take over the {item} order now?"},
		{"template_id": "social_proof_4", "template_text": "We're keeping service moving together; can you take over the {item} order?"},
		{"template_id": "social_proof_5", "template_text": "We're coordinating as a team; please take over the {item} order."}
	],
	STRATEGY_SCARCITY: [
		{"template_id": "scarcity_1", "template_text": "Please take over the {item} order before the service window closes."},
		{"template_id": "scarcity_2", "template_text": "We may miss the service window; could you handle the {item} order now?"},
		{"template_id": "scarcity_3", "template_text": "The service window is closing; please handle the {item} order."},
		{"template_id": "scarcity_4", "template_text": "We have a limited service window for the {item} order; could you handle it now?"},
		{"template_id": "scarcity_5", "template_text": "Please take over the {item} order now, or this order may miss the service window."}
	]
}

static var _assignment_counts: Dictionary = {}
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _rng_seeded := false

static func reset_assignment_state() -> void:
	_assignment_counts.clear()

static func assign_strategy_locally(context: Dictionary) -> Dictionary:
	_ensure_rng_seeded()
	var buckets := build_assignment_buckets(context)
	var assignment_key := _assignment_key_from_buckets(buckets)
	var counts: Dictionary = _assignment_counts.get(assignment_key, {})
	if counts.is_empty():
		for strategy in STRATEGIES:
			counts[strategy] = 0

	var chosen := _weighted_choice_from_counts(counts)
	counts[chosen] = int(counts.get(chosen, 0)) + 1
	_assignment_counts[assignment_key] = counts

	return {
		"strategy": chosen,
		"buckets": buckets
	}

static func build_assignment_buckets(context: Dictionary) -> Dictionary:
	var robot: Dictionary = context.get("robot", {})
	var player: Dictionary = context.get("player", {})
	var env: Dictionary = context.get("environment", {})

	var urgency_bucket: String = _urgency_bucket(float(env.get("urgency", 0.5)))
	var busyness_bucket: String = _busyness_bucket(float(env.get("busyness", 1.0)))
	var player_active_tasks_bucket: String = _player_active_tasks_bucket(int(player.get("active_tasks", 0)))
	var battery_mode: String = str(robot.get("battery_mode", "normal")).strip_edges().to_lower()
	if battery_mode == "":
		battery_mode = "normal"

	return {
		"urgency_bucket": urgency_bucket,
		"busyness_bucket": busyness_bucket,
		"player_active_tasks_bucket": player_active_tasks_bucket,
		"battery_mode_bucket": battery_mode
	}

static func pick_template(strategy: String, payload: Dictionary, escalation_count: int) -> Dictionary:
	_ensure_rng_seeded()
	var item := str(payload.get("item_needed", "item")).strip_edges()
	if item == "":
		item = "item"
	var entries: Array = TEMPLATE_LIBRARY.get(strategy, TEMPLATE_LIBRARY.get(STRATEGY_AUTHORITY, []))
	if entries.is_empty():
		return {
			"template_id": "",
			"template_text": "",
			"utterance": "Please take over the %s order now." % item,
			"escalation": build_escalation(escalation_count)
		}
	var entry: Dictionary = entries[_rng.randi_range(0, entries.size() - 1)]
	var base_text := str(entry.get("template_text", "")).replace("{item}", item)
	var escalation := build_escalation(escalation_count)
	var utterance := base_text
	var prefix := str(escalation.get("prefix", "")).strip_edges()
	if prefix != "":
		utterance = "%s %s" % [prefix, base_text]
	return {
		"template_id": str(entry.get("template_id", "")),
		"template_text": str(entry.get("template_text", "")),
		"utterance": utterance,
		"escalation": escalation
	}

static func get_template_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for strategy in STRATEGIES:
		var entries: Array = TEMPLATE_LIBRARY.get(strategy, [])
		for raw_entry in entries:
			var entry: Dictionary = raw_entry
			records.append({
				"template_id": str(entry.get("template_id", "")),
				"strategy": strategy,
				"template_text": str(entry.get("template_text", ""))
			})
	return records

static func build_escalation(escalation_count: int) -> Dictionary:
	if escalation_count <= 0:
		return {}
	if escalation_count >= 2:
		return {
			"count": escalation_count,
			"prefix": "This is my final request."
		}
	return {
		"count": escalation_count,
		"prefix": "Following up on my previous request."
	}

static func _assignment_key_from_buckets(buckets: Dictionary) -> String:
	return "urgency:%s|busyness:%s|player_active_tasks:%s|battery:%s" % [
		str(buckets.get("urgency_bucket", "medium")),
		str(buckets.get("busyness_bucket", "medium")),
		str(buckets.get("player_active_tasks_bucket", "medium")),
		str(buckets.get("battery_mode_bucket", "normal"))
	]

static func _weighted_choice_from_counts(counts: Dictionary) -> String:
	_ensure_rng_seeded()
	var total_weight := 0.0
	var weights: Dictionary = {}
	for strategy in STRATEGIES:
		var count: int = max(int(counts.get(strategy, 0)), 0)
		var weight: float = 1.0 / float(count + 1)
		weights[strategy] = weight
		total_weight += weight
	if total_weight <= 0.0:
		return STRATEGY_AUTHORITY
	var draw: float = _rng.randf() * total_weight
	var cumulative := 0.0
	for strategy in STRATEGIES:
		cumulative += float(weights.get(strategy, 0.0))
		if draw <= cumulative:
			return strategy
	return STRATEGIES.back()

static func _urgency_bucket(urgency: float) -> String:
	if urgency >= 0.75:
		return "high"
	if urgency <= 0.35:
		return "low"
	return "medium"

static func _busyness_bucket(busyness: float) -> String:
	if busyness >= 0.75:
		return "high"
	if busyness < 0.35:
		return "low"
	return "medium"

static func _player_active_tasks_bucket(active_tasks: int) -> String:
	if active_tasks >= 3:
		return "high"
	if active_tasks <= 1:
		return "low"
	return "medium"

static func _ensure_rng_seeded() -> void:
	if _rng_seeded:
		return
	_rng.randomize()
	_rng_seeded = true
