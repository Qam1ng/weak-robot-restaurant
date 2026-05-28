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

static func assign_strategy_locally(request_type: String, context: Dictionary) -> Dictionary:
	_ensure_rng_seeded()
	var buckets := build_assignment_buckets(request_type, context)
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
		"method": "session_local_stratified_weighted_random",
		"buckets": buckets
	}

static func build_assignment_buckets(request_type: String, context: Dictionary) -> Dictionary:
	_ = request_type
	var robot: Dictionary = context.get("robot", {})
	var player: Dictionary = context.get("player", {})
	var env: Dictionary = context.get("environment", {})

	var urgency_bucket := _urgency_bucket(float(env.get("urgency", 0.5)))
	var busyness_bucket := _busyness_bucket(float(env.get("busyness", 1.0)))
	var player_active_tasks_bucket := _player_active_tasks_bucket(int(player.get("active_tasks", 0)))
	var battery_mode := str(robot.get("battery_mode", "normal")).strip_edges().to_lower()
	if battery_mode == "":
		battery_mode = "normal"

	return {
		"urgency_bucket": urgency_bucket,
		"busyness_bucket": busyness_bucket,
		"player_active_tasks_bucket": player_active_tasks_bucket,
		"battery_mode_bucket": battery_mode
	}

static func _assignment_key_from_buckets(buckets: Dictionary) -> String:
	return "urgency:%s|busyness:%s|player_active_tasks:%s|battery:%s" % [
		str(buckets.get("urgency_bucket", "medium")),
		str(buckets.get("busyness_bucket", "medium")),
		str(buckets.get("player_active_tasks_bucket", "medium")),
		str(buckets.get("battery_mode_bucket", "normal"))
	]

static func render_template(request_type: String, strategy: String, context: Dictionary, escalation_count: int, payload: Dictionary) -> String:
	var env: Dictionary = context.get("environment", {})
	var urgency := float(env.get("urgency", 0.5))
	var urgency_level := _urgency_bucket(urgency)
	var item := str(payload.get("item_needed", "item"))

	var intro := ""
	if escalation_count >= 2:
		intro = "This is my final request. "
	elif escalation_count == 1:
		intro = "Following up on my previous request. "

	match strategy:
		STRATEGY_AUTHORITY:
			return intro + ("Please hand off %s right away." % item if urgency_level == "high" else "Please hand off %s now." % item)
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

static func _weighted_choice_from_counts(counts: Dictionary) -> String:
	_ensure_rng_seeded()
	var total_weight := 0.0
	var weights := {}
	for strategy in STRATEGIES:
		var count := max(int(counts.get(strategy, 0)), 0)
		var weight := 1.0 / float(count + 1)
		weights[strategy] = weight
		total_weight += weight
	if total_weight <= 0.0:
		return STRATEGY_AUTHORITY
	var draw := _rng.randf() * total_weight
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
	if busyness >= 1.5:
		return "high"
	if busyness <= 1.05:
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
