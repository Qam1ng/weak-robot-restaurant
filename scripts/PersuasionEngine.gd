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

static var _assignment_counts: Dictionary = {}
static var _rng := RandomNumberGenerator.new()
static var _rng_seeded := false

static func reset_assignment_state() -> void:
	_assignment_counts.clear()

static func generate_dialogue(request_type: String, context: Dictionary, escalation_count: int, payload: Dictionary) -> Dictionary:
	var assignment := _assign_strategy(request_type, context)
	var strategy := str(assignment.get("strategy", STRATEGY_AUTHORITY))
	var message_context := _build_message_context(request_type, strategy, context, escalation_count)
	var utterance := _render_template(message_context, payload)

	return {
		"strategy": strategy,
		"assignment_method": assignment.get("method", "stratified_balanced_random"),
		"assignment_stratum": assignment.get("stratum", ""),
		"assignment_buckets": assignment.get("buckets", {}),
		"message_context": message_context,
		"utterance": utterance
	}

static func _assign_strategy(request_type: String, context: Dictionary) -> Dictionary:
	_ensure_rng_seeded()
	var buckets := _build_assignment_buckets(request_type, context)
	var stratum := _assignment_stratum_from_buckets(buckets)
	var counts: Dictionary = _assignment_counts.get(stratum, {})
	if counts.is_empty():
		for strategy in STRATEGIES:
			counts[strategy] = 0

	var min_count := INF
	var candidates: Array[String] = []
	for strategy in STRATEGIES:
		var count := int(counts.get(strategy, 0))
		if count < min_count:
			min_count = count
			candidates.clear()
			candidates.append(strategy)
		elif count == min_count:
			candidates.append(strategy)

	var chosen := candidates[_rng.randi_range(0, candidates.size() - 1)]
	counts[chosen] = int(counts.get(chosen, 0)) + 1
	_assignment_counts[stratum] = counts

	return {
		"strategy": chosen,
		"method": "stratified_balanced_random",
		"stratum": stratum,
		"buckets": buckets
	}

static func _build_assignment_buckets(request_type: String, context: Dictionary) -> Dictionary:
	var robot: Dictionary = context.get("robot", {})
	var player: Dictionary = context.get("player", {})
	var env: Dictionary = context.get("environment", {})

	var urgency_bucket := _urgency_bucket(float(env.get("urgency", 0.5)))
	var busyness_bucket := _busyness_bucket(float(env.get("busyness", 1.0)))
	var player_load_bucket := _player_load_bucket(float(player.get("task_load", 0.0)))
	var battery_mode := str(robot.get("battery_mode", "normal")).strip_edges().to_lower()
	if battery_mode == "":
		battery_mode = "normal"

	return {
		"request_type_bucket": request_type,
		"urgency_bucket": urgency_bucket,
		"busyness_bucket": busyness_bucket,
		"player_load_bucket": player_load_bucket,
		"battery_mode_bucket": battery_mode
	}

static func _assignment_stratum_from_buckets(buckets: Dictionary) -> String:
	return "%s|urgency:%s|busyness:%s|player_load:%s|battery:%s" % [
		str(buckets.get("request_type_bucket", "HANDOFF")),
		str(buckets.get("urgency_bucket", "medium")),
		str(buckets.get("busyness_bucket", "medium")),
		str(buckets.get("player_load_bucket", "medium")),
		str(buckets.get("battery_mode_bucket", "normal"))
	]

static func _build_message_context(request_type: String, strategy: String, context: Dictionary, escalation_count: int) -> Dictionary:
	var env: Dictionary = context.get("environment", {})
	var urgency := float(env.get("urgency", 0.5))
	var urgency_level := _urgency_bucket(urgency)

	return {
		"request_type": request_type,
		"strategy": strategy,
		"urgency_level": urgency_level,
		"escalation_count": escalation_count
	}

static func _render_template(message_context: Dictionary, payload: Dictionary) -> String:
	var strategy := str(message_context.get("strategy", STRATEGY_SCARCITY))
	var escalation := int(message_context.get("escalation_count", 0))
	var item := str(payload.get("item_needed", "item"))

	var intro := ""
	if escalation >= 2:
		intro = "This is my final request. "
	elif escalation == 1:
		intro = "Following up on my previous request. "

	match strategy:
		STRATEGY_AUTHORITY:
			return intro + "Please hand off %s right away." % item
		STRATEGY_SOCIAL_PROOF:
			return intro + "Please hand off %s now so we can keep service moving." % item
		STRATEGY_LIKING:
			return intro + "Could you please hand off %s? Your help really keeps things moving." % item
		STRATEGY_RECIPROCITY:
			return intro + "Please hand over %s now, and I can clear this table for you next." % item
		STRATEGY_COMMITMENT:
			return intro + "You have handled these handoffs well before; could you take %s again?" % item
		_:
			return intro + "Please hand off %s now, or this order may miss the service window." % item

static func _urgency_bucket(urgency: float) -> String:
	if urgency >= 0.75:
		return "high"
	if urgency <= 0.35:
		return "low"
	return "medium"

static func _busyness_bucket(busyness: float) -> String:
	if busyness >= 1.5:
		return "high"
	if busyness <= 1.05:
		return "low"
	return "medium"

static func _player_load_bucket(task_load: float) -> String:
	if task_load >= 0.67:
		return "high"
	if task_load <= 0.33:
		return "low"
	return "medium"

static func _ensure_rng_seeded() -> void:
	if _rng_seeded:
		return
	_rng.randomize()
	_rng_seeded = true
