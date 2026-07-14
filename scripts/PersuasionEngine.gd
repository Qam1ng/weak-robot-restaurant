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
		{"template_id": "authority_1", "template_text": "The approved handoff procedure says I should pass this order to the player, so please take over the {item} order."},
		{"template_id": "authority_2", "template_text": "According to the restaurant's service rules, the player should handle this order next, so please take over the {item} order."},
		{"template_id": "authority_3", "template_text": "Restaurant policy says I should transfer this order to you, so please take over the {item} order."},
		{"template_id": "authority_4", "template_text": "The service guidelines say this order should be transferred to the player, so please take over the {item} order."},
		{"template_id": "authority_5", "template_text": "The manager's procedure says I should hand this order to you, so please take over the {item} order."}
	],
	STRATEGY_RECIPROCITY: [
		{"template_id": "reciprocity_1", "template_text": "I've been handling the more involved food orders to help your score, so please help me back and take over the {item} order."},
		{"template_id": "reciprocity_2", "template_text": "Since I usually take care of the more complicated food orders for your points, could you take over the {item} order?"},
		{"template_id": "reciprocity_3", "template_text": "Since I handle the more involved orders that add to your score, please return the help and take over the {item} order."},
		{"template_id": "reciprocity_4", "template_text": "I've been taking on the more involved food orders for your score, so please help me back and take over the {item} order."},
		{"template_id": "reciprocity_5", "template_text": "Since I've been doing the more complicated part to help you earn points, could you take over the {item} order?"}
	],
	STRATEGY_LIKING: [
		{"template_id": "liking_1", "template_text": "I like how smoothly you handle handoffs, so could you take over the {item} order?"},
		{"template_id": "liking_2", "template_text": "We work well together on orders, so please take over the {item} order."},
		{"template_id": "liking_3", "template_text": "You've been easy to coordinate with, so please take over the {item} order."},
		{"template_id": "liking_4", "template_text": "I like working with you on these orders, so could you take over the {item} order?"},
		{"template_id": "liking_5", "template_text": "You and I have kept the service running well together, so please take over the {item} order."}
	],
	STRATEGY_COMMITMENT: [
		{"template_id": "commitment_1", "template_text": "Since you already helped with a handoff earlier, please take over the {item} order."},
		{"template_id": "commitment_2", "template_text": "You stepped in for an order before, so please take over the {item} order this time."},
		{"template_id": "commitment_3", "template_text": "You've handled a similar order before, so please take over the {item} order."},
		{"template_id": "commitment_4", "template_text": "You've taken over orders when needed before, so could you take over the {item} order?"},
		{"template_id": "commitment_5", "template_text": "You helped with this kind of handoff earlier, so please take over the {item} order."}
	],
	STRATEGY_SOCIAL_PROOF: [
		{"template_id": "social_proof_1", "template_text": "Players in your role usually take over orders like this, so please take over the {item} order."},
		{"template_id": "social_proof_2", "template_text": "Most players handle this kind of handoff by stepping in, so please take over the {item} order."},
		{"template_id": "social_proof_3", "template_text": "In this situation, players usually step in and take over the order, so please take over the {item} order."},
		{"template_id": "social_proof_4", "template_text": "Other players have been taking over orders like this successfully, so please take over the {item} order."},
		{"template_id": "social_proof_5", "template_text": "Players facing this kind of order usually take it over, so please take over the {item} order."}
	],
	STRATEGY_SCARCITY: [
		{"template_id": "scarcity_1", "template_text": "This handoff is only open for a short time, so please take over the {item} order."},
		{"template_id": "scarcity_2", "template_text": "The window to take this order is closing, so please take over the {item} order."},
		{"template_id": "scarcity_3", "template_text": "This order may not stay available to complete, so please take over the {item} order."},
		{"template_id": "scarcity_4", "template_text": "The opportunity to complete this order is running out, so please take over the {item} order."},
		{"template_id": "scarcity_5", "template_text": "This order can only be handled for a limited time, so please take over the {item} order."}
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
	var battery_level := float(robot.get("battery_level", 100.0))
	var battery_mode_bucket := "normal"
	if battery_level <= 20.0:
		battery_mode_bucket = "emergency"
	elif battery_level <= 50.0:
		battery_mode_bucket = "conserve"

	return {
		"urgency_bucket": urgency_bucket,
		"busyness_bucket": busyness_bucket,
		"player_active_tasks_bucket": player_active_tasks_bucket,
		"battery_mode_bucket": battery_mode_bucket
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
