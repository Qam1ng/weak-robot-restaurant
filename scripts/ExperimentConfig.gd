extends Node

const DEFAULTS := {
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

func _cache_settings() -> void:
	_cached = DEFAULTS.duplicate(true)
	_cached["replay_logging_enabled"] = _get_setting("experiment/replay_logging_enabled", DEFAULTS["replay_logging_enabled"])
	_cached["help_logging_enabled"] = _get_setting("experiment/help_logging_enabled", DEFAULTS["help_logging_enabled"])
	_cached["llm_utterance_enabled"] = _get_setting("experiment/llm_utterance_enabled", DEFAULTS["llm_utterance_enabled"])
	_cached["llm_model"] = str(_get_setting("experiment/llm_model", DEFAULTS["llm_model"]))
	_cached["llm_temperature"] = float(_get_setting("experiment/llm_temperature", DEFAULTS["llm_temperature"]))

func _get_setting(key: String, fallback):
	if ProjectSettings.has_setting(key):
		return ProjectSettings.get_setting(key)
	return fallback
