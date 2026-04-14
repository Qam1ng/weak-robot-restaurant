extends Node

signal utterance_generated(request_id: String, utterance: String, meta: Dictionary)
signal directed_utterance_generated(request_id: String, utterance: String, meta: Dictionary)

const OPENAI_URL := "https://api.openai.com/v1/chat/completions"
const API_DIALOGUE_URL := "https://us-central1-weak-robot-restaurant-web.cloudfunctions.net/apiDialogue"
const DEFAULT_MODEL := "gpt-4o-mini"
const KEY_FILE_PATH := "res://secrets/openai_api_key.txt"

var _api_key: String = ""

func _ready() -> void:
	_api_key = _load_api_key()
	if _use_backend_api():
		print("[DialogueManager] Ready. Using backend dialogue API.")
	elif _api_key == "":
		push_warning("[DialogueManager] OpenAI API key not found. Using template utterances.")
	else:
		print("[DialogueManager] Ready with API key from local secret source.")

func has_api_key() -> bool:
	return _use_backend_api() or _api_key != ""

func realize_help_utterance(request: Dictionary) -> void:
	if request.is_empty():
		return
	if not _is_llm_enabled():
		return
	if not has_api_key():
		return

	var request_id := str(request.get("id", ""))
	if request_id == "":
		return

	var intent: Dictionary = request.get("dialogue_intent", {})
	var strategy := str(request.get("strategy", ""))
	var fallback := str(request.get("utterance", ""))
	if fallback == "":
		fallback = "Can you help now?"

	var payload: Dictionary = request.get("payload", {})
	var context: Dictionary = request.get("context_snapshot", {})
	var personality_hint := _format_personality_hint(context.get("personality", {}))
	var request_type := str(request.get("type", "HANDOFF"))
	var urgency := str(intent.get("urgency_level", "medium"))
	var escalation := int(request.get("escalation_count", 0))
	var item := str(payload.get("item_needed", "item"))

	if _use_backend_api():
		_request_dialogue_via_backend(request_id, {
			"kind": "help_utterance",
			"request_id": request_id,
			"fallback": fallback,
			"model": _llm_model(),
			"temperature": _llm_temperature(),
			"strategy": strategy,
			"urgency": urgency,
			"escalation": escalation,
			"personality_hint": personality_hint,
			"item": item,
			"request_type": request_type
		}, false, fallback)
		return

	var system_prompt := "Write one short in-game delegation line from robot to player. Keep it natural, concrete, polite, and under 18 words. No quotes. No options."
	var user_prompt := "request_type=%s strategy=%s urgency=%s escalation=%d personality=%s item=%s fallback=%s" % [
		request_type,
		strategy,
		urgency,
		escalation,
		personality_hint,
		item,
		fallback
	]

	var body := {
		"model": _llm_model(),
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt}
		],
		"temperature": _llm_temperature(),
		"max_tokens": 60
	}
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _api_key
	])

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(http, request_id, fallback))
	var err := http.request(OPENAI_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		utterance_generated.emit(request_id, "", {
			"provider": "fallback",
			"status": "request_error",
			"fallback": fallback
		})

func realize_directed_utterance(request: Dictionary) -> void:
	if request.is_empty():
		return

	var request_id := str(request.get("id", "")).strip_edges()
	if request_id == "":
		return

	var fallback := str(request.get("fallback", "")).strip_edges()
	if fallback == "":
		fallback = "Okay."

	if not _is_llm_enabled() or not has_api_key():
		directed_utterance_generated.emit(request_id, fallback, {
			"provider": "fallback",
			"status": "disabled_or_missing_key",
			"fallback": fallback
		})
		return

	var source_role := str(request.get("source_role", "player")).strip_edges()
	var recipient_role := str(request.get("recipient_role", "robot")).strip_edges()
	var intent_type := str(request.get("intent_type", "directed_reply")).strip_edges()
	var item_name := str(request.get("item_name", "")).strip_edges()
	var context_note := str(request.get("context_note", "")).strip_edges()

	if _use_backend_api():
		_request_dialogue_via_backend(request_id, {
			"kind": "directed_utterance",
			"request_id": request_id,
			"fallback": fallback,
			"model": _llm_model(),
			"temperature": _llm_temperature(),
			"source_role": source_role,
			"recipient_role": recipient_role,
			"intent_type": intent_type,
			"item_name": item_name,
			"context_note": context_note
		}, true, fallback)
		return

	var system_prompt := "Write one short in-game line of direct speech. Keep it natural, concrete, polite, and under 18 words. No quotes. No stage directions."
	var user_prompt := "speaker=%s recipient=%s intent=%s item=%s context=%s fallback=%s" % [
		source_role,
		recipient_role,
		intent_type,
		item_name,
		context_note,
		fallback
	]

	var body := {
		"model": _llm_model(),
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt}
		],
		"temperature": _llm_temperature(),
		"max_tokens": 60
	}
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _api_key
	])

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_directed_request_completed.bind(http, request_id, fallback))
	var err := http.request(OPENAI_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		directed_utterance_generated.emit(request_id, fallback, {
			"provider": "fallback",
			"status": "request_error",
			"fallback": fallback
		})

func _on_request_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, request_id: String, fallback: String) -> void:
	if is_instance_valid(http):
		http.queue_free()

	if code < 200 or code >= 300:
		utterance_generated.emit(request_id, "", {
			"provider": "fallback",
			"status": "http_error",
			"http_code": code,
			"fallback": fallback
		})
		return

	var top = JSON.parse_string(body.get_string_from_utf8())
	if not (top is Dictionary):
		utterance_generated.emit(request_id, "", {
			"provider": "fallback",
			"status": "parse_error",
			"fallback": fallback
		})
		return

	var choices: Array = top.get("choices", [])
	if choices.is_empty():
		utterance_generated.emit(request_id, "", {
			"provider": "fallback",
			"status": "empty_choices",
			"fallback": fallback
		})
		return

	var message: Dictionary = choices[0].get("message", {})
	var content := str(message.get("content", "")).strip_edges()
	content = content.replace("\n", " ")
	if content == "":
		utterance_generated.emit(request_id, "", {
			"provider": "fallback",
			"status": "empty_content",
			"fallback": fallback
		})
		return

	utterance_generated.emit(request_id, content, {
		"provider": "openai",
		"status": "ok",
		"model": _llm_model()
	})

func _on_directed_request_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, request_id: String, fallback: String) -> void:
	if is_instance_valid(http):
		http.queue_free()

	if code < 200 or code >= 300:
		directed_utterance_generated.emit(request_id, fallback, {
			"provider": "fallback",
			"status": "http_error",
			"http_code": code,
			"fallback": fallback
		})
		return

	var top = JSON.parse_string(body.get_string_from_utf8())
	if not (top is Dictionary):
		directed_utterance_generated.emit(request_id, fallback, {
			"provider": "fallback",
			"status": "parse_error",
			"fallback": fallback
		})
		return

	var choices: Array = top.get("choices", [])
	if choices.is_empty():
		directed_utterance_generated.emit(request_id, fallback, {
			"provider": "fallback",
			"status": "empty_choices",
			"fallback": fallback
		})
		return

	var message: Dictionary = choices[0].get("message", {})
	var content := str(message.get("content", "")).strip_edges()
	content = content.replace("\n", " ")
	if content == "":
		directed_utterance_generated.emit(request_id, fallback, {
			"provider": "fallback",
			"status": "empty_content",
			"fallback": fallback
		})
		return

	directed_utterance_generated.emit(request_id, content, {
		"provider": "openai",
		"status": "ok",
		"model": _llm_model()
	})

func _request_dialogue_via_backend(request_id: String, body: Dictionary, directed: bool, fallback: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_backend_dialogue_completed.bind(http, request_id, directed, fallback))
	var err := http.request(API_DIALOGUE_URL, PackedStringArray([
		"Content-Type: application/json"
	]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		if is_instance_valid(http):
			http.queue_free()
		_emit_dialogue_fallback(request_id, directed, "request_error", fallback)

func _on_backend_dialogue_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, request_id: String, directed: bool, fallback: String) -> void:
	if is_instance_valid(http):
		http.queue_free()

	if code < 200 or code >= 300:
		_emit_dialogue_fallback(request_id, directed, "http_error", fallback, code)
		return

	var top = JSON.parse_string(body.get_string_from_utf8())
	if not (top is Dictionary):
		_emit_dialogue_fallback(request_id, directed, "parse_error", fallback)
		return

	var utterance := str(top.get("utterance", "")).strip_edges()
	var meta: Dictionary = top.get("meta", {})
	if utterance == "":
		_emit_dialogue_fallback(request_id, directed, str(meta.get("status", "empty_content")), fallback)
		return
	if directed:
		directed_utterance_generated.emit(request_id, utterance, meta)
	else:
		utterance_generated.emit(request_id, utterance, meta)

func _emit_dialogue_fallback(request_id: String, directed: bool, status: String, fallback: String, http_code: int = -1) -> void:
	var meta := {
		"provider": "fallback",
		"status": status,
		"fallback": fallback
	}
	if http_code >= 0:
		meta["http_code"] = http_code
	if directed:
		directed_utterance_generated.emit(request_id, fallback, meta)
	else:
		utterance_generated.emit(request_id, fallback, meta)

func _load_api_key() -> String:
	var env_key := OS.get_environment("OPENAI_API_KEY").strip_edges()
	if env_key != "":
		return env_key

	var path := ProjectSettings.globalize_path(KEY_FILE_PATH)
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()

func _experiment_config() -> Node:
	return get_node_or_null("/root/ExperimentConfig")

func _is_llm_enabled() -> bool:
	var exp = _experiment_config()
	if exp and exp.has_method("is_llm_utterance_enabled"):
		return bool(exp.is_llm_utterance_enabled())
	return true

func _use_backend_api() -> bool:
	return OS.has_feature("web")

func _llm_model() -> String:
	var exp = _experiment_config()
	if exp and exp.has_method("get_llm_model"):
		return str(exp.get_llm_model())
	return DEFAULT_MODEL

func _llm_temperature() -> float:
	var exp = _experiment_config()
	if exp and exp.has_method("get_llm_temperature"):
		return float(exp.get_llm_temperature())
	return 0.4

func _format_personality_hint(personality: Dictionary) -> String:
	var tipi_scores: Dictionary = personality.get("tipi_scores", {})
	if tipi_scores.is_empty():
		return ""
	return "O=%.1f C=%.1f E=%.1f A=%.1f N=%.1f" % [
		float(tipi_scores.get("O", 4.0)),
		float(tipi_scores.get("C", 4.0)),
		float(tipi_scores.get("E", 4.0)),
		float(tipi_scores.get("A", 4.0)),
		float(tipi_scores.get("N", 4.0)),
	]
