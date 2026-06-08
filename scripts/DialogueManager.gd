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

	var strategy := str(request.get("strategy", ""))
	var payload: Dictionary = request.get("payload", {})
	var item := str(payload.get("item_needed", "item"))
	var escalation: Dictionary = request.get("escalation", {})
	if escalation.is_empty():
		escalation = {}

	if _use_backend_api():
		var backend_body := {
			"kind": "help_utterance",
			"request_id": request_id,
			"model": _llm_model(),
			"temperature": _llm_temperature(),
			"strategy": strategy,
			"item": item
		}
		if not escalation.is_empty():
			backend_body["escalation"] = escalation
		_request_dialogue_via_backend(request_id, backend_body, false, "")
		return

	var system_prompt := _help_utterance_system_prompt()
	var user_prompt := _help_utterance_user_prompt(strategy, item, escalation)

	var local_body := {
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
	http.request_completed.connect(_on_request_completed.bind(http, request_id, ""))
	var err := http.request(OPENAI_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(local_body))
	if err != OK:
		http.queue_free()
		utterance_generated.emit(request_id, "", {
			"provider": "llm",
			"status": "request_error"
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
			"provider": "llm",
			"status": "http_error",
			"http_code": code
		})
		return

	var top = JSON.parse_string(body.get_string_from_utf8())
	if not (top is Dictionary):
		utterance_generated.emit(request_id, "", {
			"provider": "llm",
			"status": "parse_error"
		})
		return

	var choices: Array = top.get("choices", [])
	if choices.is_empty():
		utterance_generated.emit(request_id, "", {
			"provider": "llm",
			"status": "empty_choices"
		})
		return

	var message: Dictionary = choices[0].get("message", {})
	var content := str(message.get("content", "")).strip_edges()
	content = content.replace("\n", " ")
	if content == "":
		utterance_generated.emit(request_id, "", {
			"provider": "llm",
			"status": "empty_content"
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

func _help_utterance_system_prompt() -> String:
	return "Write one short in-game delegation line from robot to player. Keep it natural, concrete. No quotes. No options. The relevant fields are defined below:\nstrategy: one persuasion framing drawn from our six-strategy set, adapted from Cialdini's six principles of persuasion.\nitem: the handoff item; the player is being asked to take it over, not give it to the robot.\nescalation: the follow-up stage of the same request, represented by escalation.count and escalation.prefix. escalation.count indicates how many times the request has already been followed up, and higher escalation should sound more insistent. escalation.prefix provides the stage-specific wording, may be lightly rewritten, and should be prepended to the utterance as a prefix."

func _help_utterance_user_prompt(strategy: String, item: String, escalation: Dictionary) -> String:
	var lines := [
		"strategy: %s" % _help_strategy_label(strategy),
		"item: %s" % item
	]
	if not escalation.is_empty():
		lines.append("escalation.count: %d" % int(escalation.get("count", 0)))
		lines.append("escalation.prefix: %s" % str(escalation.get("prefix", "")))
	return "\n".join(lines)

func _help_strategy_label(strategy: String) -> String:
	match strategy:
		"authority":
			return "authority — a persuasion framing based on role-based coordination authority, expressed as a direct task-oriented request."
		"reciprocity":
			return "reciprocity — a persuasion framing based on returning help or favors, expressed by offering support in return for cooperation. For reciprocity, the promised payoff is real: if the player accepts, the robot will handle its next order faster. Reflect this promise naturally in the utterance."
		"liking":
			return "liking — a persuasion framing based on warmth and positive regard, expressed in an appreciative and friendly tone."
		"commitment":
			return "commitment — a persuasion framing based on consistency with prior actions, expressed by referring to earlier cooperation."
		"social_proof":
			return "social_proof — a persuasion framing based on shared group behavior, expressed by emphasizing ongoing team coordination."
		"scarcity":
			return "scarcity — a persuasion framing based on limited opportunity or time, expressed by emphasizing the risk of missing the service window."
		_:
			return strategy
