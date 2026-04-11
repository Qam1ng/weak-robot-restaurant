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

static func generate_dialogue(request_type: String, context: Dictionary, escalation_count: int, payload: Dictionary) -> Dictionary:
	var scores := _score_all(context)
	var strategy := _pick_best(scores)
	var intent := _build_intent(request_type, strategy, context, escalation_count, payload)
	var utterance := _render_template(intent, payload)

	return {
		"strategy": strategy,
		"strategy_scores": scores,
		"dialogue_intent": intent,
		"utterance": utterance
	}

static func _score_all(context: Dictionary) -> Dictionary:
	var scores := {}
	for s in STRATEGIES:
		scores[s] = _score(s, context)
	return scores

static func _score(strategy: String, context: Dictionary) -> float:
	var robot: Dictionary = context.get("robot", {})
	var player: Dictionary = context.get("player", {})
	var personality: Dictionary = context.get("personality", {})
	var env: Dictionary = context.get("environment", {})
	var history: Dictionary = context.get("history", {})

	var urgency := float(env.get("urgency", 0.5))
	var busyness := float(env.get("busyness", 0.5))
	var player_task_load := float(player.get("task_load", 0.5))
	var acceptance_rate := float(history.get("acceptance_rate", 0.5))
	var annoyance := float(history.get("annoyance", 0.0))
	var battery_level := float(robot.get("battery_level", 100.0))
	var battery_mode := str(robot.get("battery_mode", "normal"))
	var affinity: Dictionary = personality.get("strategy_affinity", {})
	var personality_boost := float(affinity.get(strategy, 0.0))

	var battery_pressure := clampf((100.0 - battery_level) / 100.0, 0.0, 1.0)
	if battery_mode == "emergency":
		battery_pressure = 1.0
	elif battery_mode == "conserve":
		battery_pressure = maxf(battery_pressure, 0.6)

	match strategy:
		STRATEGY_SCARCITY:
			return 2.2 * urgency + 1.8 * battery_pressure - 1.2 * player_task_load + 0.9 * personality_boost
		STRATEGY_AUTHORITY:
			return 1.7 * urgency + 1.2 * busyness + 1.0 * battery_pressure - 1.0 * player_task_load + 0.9 * personality_boost
		STRATEGY_COMMITMENT:
			return 1.8 * acceptance_rate + 0.6 * urgency - 0.6 * annoyance - 0.4 * player_task_load + 0.9 * personality_boost
		STRATEGY_RECIPROCITY:
			return 1.2 * acceptance_rate + 0.8 * (1.0 - player_task_load) + 0.5 * busyness - 0.6 * annoyance - 0.5 * player_task_load + 0.9 * personality_boost
		STRATEGY_SOCIAL_PROOF:
			return 1.6 * busyness + 0.8 * urgency - 0.7 * player_task_load + 0.9 * personality_boost
		STRATEGY_LIKING:
			return 1.4 * annoyance + 0.8 * (1.0 - player_task_load) + 0.4 * acceptance_rate - 0.3 * player_task_load + 0.9 * personality_boost
		_:
			return 0.0

static func _pick_best(scores: Dictionary) -> String:
	var best_strategy := STRATEGY_SCARCITY
	var best_score := -INF
	for s in scores.keys():
		var v := float(scores[s])
		if v > best_score:
			best_score = v
			best_strategy = str(s)
	return best_strategy

static func _build_intent(request_type: String, strategy: String, context: Dictionary, escalation_count: int, payload: Dictionary) -> Dictionary:
	var urgency := float(context.get("environment", {}).get("urgency", 0.5))
	var urgency_level := "medium"
	if urgency >= 0.75:
		urgency_level = "high"
	elif urgency <= 0.35:
		urgency_level = "low"

	var evidence := []
	var slack_ms := int(context.get("environment", {}).get("slack_ms", 0))
	if slack_ms != 0:
		evidence.append("slack_ms:%d" % slack_ms)
	var battery_mode := str(context.get("robot", {}).get("battery_mode", "normal"))
	evidence.append("battery_mode:%s" % battery_mode)
	var player_active_tasks := int(context.get("player", {}).get("active_tasks", 0))
	var player_task_load := float(context.get("player", {}).get("task_load", 0.0))
	evidence.append("player_active_tasks:%d" % player_active_tasks)
	evidence.append("player_task_load:%.2f" % player_task_load)

	return {
		"request_type": request_type,
		"strategy": strategy,
		"urgency_level": urgency_level,
		"escalation_count": escalation_count,
		"politeness": "high" if escalation_count <= 1 else "medium",
		"evidence": evidence,
		"constraints": {
			"no_remote_acceptance": true,
			"response_options": ["accept", "decline", "later"]
		},
		"cta": _default_cta(request_type, payload)
	}

static func _render_template(intent: Dictionary, payload: Dictionary) -> String:
	var strategy := str(intent.get("strategy", STRATEGY_SCARCITY))
	var request_type := str(intent.get("request_type", "HANDOFF"))
	var escalation := int(intent.get("escalation_count", 0))
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

static func _default_cta(request_type: String, payload: Dictionary) -> String:
	return "Provide requested item: %s" % str(payload.get("item_needed", "item"))
