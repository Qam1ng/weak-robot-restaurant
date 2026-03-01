extends Node

const VARIANT_A := "A"
const VARIANT_B := "B"

const DEFAULTS := {
	"ab_enabled": true,
	"ab_seed": 17,
	"forced_variant": "",
	"control_variant": VARIANT_B,
	"replay_logging_enabled": true,
	"help_logging_enabled": true,
	"llm_utterance_enabled": true,
	"llm_model": "gpt-4o-mini",
	"llm_temperature": 0.4
}

var _cached: Dictionary = {}

func _ready() -> void:
	_cache_settings()
	print("[ExperimentConfig] Ready: ", _cached)

func is_help_logging_enabled() -> bool:
	return bool(_cached.get("help_logging_enabled", true))

func is_replay_logging_enabled() -> bool:
	return bool(_cached.get("replay_logging_enabled", true))

func get_snapshot() -> Dictionary:
	return _cached.duplicate(true)

func is_llm_utterance_enabled() -> bool:
	return bool(_cached.get("llm_utterance_enabled", true))

func get_llm_model() -> String:
	return str(_cached.get("llm_model", "gpt-4o-mini"))

func get_llm_temperature() -> float:
	return float(_cached.get("llm_temperature", 0.4))

func resolve_variant(request_id: String) -> String:
	var forced := str(_cached.get("forced_variant", "")).strip_edges()
	if forced == VARIANT_A or forced == VARIANT_B:
		return forced
	if not bool(_cached.get("ab_enabled", true)):
		return VARIANT_A
	var seed := int(_cached.get("ab_seed", 17))
	var value := hash("%s|%d" % [request_id, seed])
	if abs(value) % 2 == 0:
		return VARIANT_A
	return VARIANT_B

func apply_dialogue_variant(variant: String, request_type: String, persuasion: Dictionary, payload: Dictionary, escalation_count: int) -> Dictionary:
	var out := persuasion.duplicate(true)
	if variant != str(_cached.get("control_variant", VARIANT_B)):
		return out

	out["strategy"] = "control_neutral"
	out["strategy_scores"] = {}
	var intent: Dictionary = out.get("dialogue_intent", {})
	intent["strategy"] = "control_neutral"
	intent["variant"] = variant
	out["dialogue_intent"] = intent
	out["utterance"] = _neutral_utterance(request_type, payload, escalation_count)
	return out

func _neutral_utterance(request_type: String, payload: Dictionary, escalation_count: int) -> String:
	var prefix := ""
	if escalation_count >= 1:
		prefix = "Reminder: "
	var item := str(payload.get("item_needed", "item"))
	return prefix + "Please help with %s when you are available." % item

func _cache_settings() -> void:
	_cached = DEFAULTS.duplicate(true)
	_cached["ab_enabled"] = _get_setting("experiment/ab_enabled", DEFAULTS["ab_enabled"])
	_cached["ab_seed"] = int(_get_setting("experiment/ab_seed", DEFAULTS["ab_seed"]))
	_cached["forced_variant"] = str(_get_setting("experiment/forced_variant", DEFAULTS["forced_variant"]))
	_cached["control_variant"] = str(_get_setting("experiment/control_variant", DEFAULTS["control_variant"]))
	_cached["replay_logging_enabled"] = _get_setting("experiment/replay_logging_enabled", DEFAULTS["replay_logging_enabled"])
	_cached["help_logging_enabled"] = _get_setting("experiment/help_logging_enabled", DEFAULTS["help_logging_enabled"])
	_cached["llm_utterance_enabled"] = _get_setting("experiment/llm_utterance_enabled", DEFAULTS["llm_utterance_enabled"])
	_cached["llm_model"] = str(_get_setting("experiment/llm_model", DEFAULTS["llm_model"]))
	_cached["llm_temperature"] = float(_get_setting("experiment/llm_temperature", DEFAULTS["llm_temperature"]))

func _get_setting(key: String, fallback):
	if ProjectSettings.has_setting(key):
		return ProjectSettings.get_setting(key)
	return fallback
