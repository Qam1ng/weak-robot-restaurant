# EpisodeLogger.gd - Singleton for collecting episode data
# Used for Causal Inference research
extends Node

# Episode state
var _current_episode: Dictionary = {}
var _episode_active: bool = false
var _episode_start_time: int = 0
var _episode_counter: int = 0
var _participant_id: String = ""
var _delegation_templates_logged := false
var _remote_failure_counter: int = 0
var _runtime_debug_counter: int = 0

const DEBUG_EVENT_TYPES := {
	"robot_task_assigned": true,
	"robot_step_changed": true,
	"navigation_start": true,
	"navigation_retry": true,
	"navigation_failed": true,
	"pickup_started": true,
	"pickup_failed": true,
	"delivery_started": true,
	"delivery_failed": true,
}

const DEBUG_EVENT_REASONS := {
	"": true,
	"navigation_retry_exhausted": true,
	"no_navigation_path": true,
	"stuck_retry": true,
	"missing_inventory": true,
	"inventory_full": true,
	"item_missing": true,
	"too_far_from_item": true,
	"delivery_state_invalid": true,
	"customer_cannot_receive_item": true,
	"customer_missing": true,
}

const DEBUG_ROBOT_STEPS := {
	"": true,
	"TAKE_ORDER": true,
	"PICKUP_FROM_KITCHEN": true,
	"DELIVER_AND_SERVE": true,
}

const DEBUG_DELEGATION_SCENARIOS := {
	"": true,
	"battery_pressure": true,
	"workload_overload": true,
	"deadline_pressure": true,
	"trial_tutorial": true,
}

# File paths
const DATA_DIR = "user://data/episodes/"
const CSV_FILE = "user://data/episodes_summary.csv"
const HELP_DIR = "user://data/help_requests/"
const HELP_JSONL_FILE = "user://data/help_requests/help_requests.jsonl"
const REPLAY_DIR = "user://data/replay/"
const REPLAY_JSONL_FILE = "user://data/replay/replay_events.jsonl"

var _session_id: String = ""
const API_LOG_URL := "https://us-central1-weak-robot-restaurant-web.cloudfunctions.net/apiLog"

signal episode_started(episode_id: String)
signal episode_ended(episode_data: Dictionary)

func _ready() -> void:
	_session_id = _generate_session_id()
	_participant_id = _session_id
	if _should_write_local_files():
		# Ensure data directory exists
		DirAccess.make_dir_recursive_absolute(DATA_DIR.replace("user://", OS.get_user_data_dir() + "/"))
		DirAccess.make_dir_recursive_absolute(HELP_DIR.replace("user://", OS.get_user_data_dir() + "/"))
		DirAccess.make_dir_recursive_absolute(REPLAY_DIR.replace("user://", OS.get_user_data_dir() + "/"))
		_ensure_csv_header()
		print("[EpisodeLogger] Ready. Data dir: ", ProjectSettings.globalize_path(DATA_DIR))
	else:
		print("[EpisodeLogger] Ready. Web mode uses remote logging only.")

func _ensure_csv_header() -> void:
	var csv_path = ProjectSettings.globalize_path(CSV_FILE)
	if not FileAccess.file_exists(csv_path):
		var file = FileAccess.open(csv_path, FileAccess.WRITE)
		if file:
			file.store_line("episode_id,timestamp,success,duration_ms,failure_reason")
			file.close()

# ==================== Public API ====================

func start_episode(_food_item: String, _customer_seat: String, _customer_pos: Vector2, _robot_pos: Vector2) -> String:
	if _episode_active:
		push_warning("[EpisodeLogger] Previous episode not ended, forcing end")
		end_episode(false, "interrupted_by_new_episode")
	
	_episode_counter += 1
	var timestamp = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var episode_id = "ep_%s_%03d" % [timestamp, _episode_counter]
	
	_episode_start_time = Time.get_ticks_msec()
	
	_current_episode = {
		"episode_id": episode_id,
		"timestamp_start": Time.get_datetime_string_from_system(),
		"timestamp_end": "",
		"duration_ms": 0,

		"outcome": {
			"success": false,
			"failure_reason": null
		}
	}
	
	_episode_active = true
	
	print("[EpisodeLogger] Started episode: ", episode_id)
	episode_started.emit(episode_id)
	return episode_id

func end_episode(success: bool, failure_reason: String = "") -> Dictionary:
	if not _episode_active:
		push_warning("[EpisodeLogger] No active episode to end")
		return {}
	
	var duration_ms = Time.get_ticks_msec() - _episode_start_time
	
	_current_episode["timestamp_end"] = Time.get_datetime_string_from_system()
	_current_episode["duration_ms"] = duration_ms
	_current_episode["outcome"]["success"] = success
	if success:
		_current_episode["outcome"]["failure_reason"] = ""
	else:
		_current_episode["outcome"]["failure_reason"] = failure_reason
	
	if _should_write_local_files():
		_save_json()
		_append_csv()
	_post_remote_log("episode_upsert", {
		"participant_id": _participant_id,
		"session_id": _session_id,
		"episode_id": _current_episode.get("episode_id", ""),
		"timestamp": _current_episode.get("timestamp_start", ""),
		"success": success,
		"failure_reason": failure_reason,
		"duration_ms": duration_ms
	})
	
	var result = _current_episode.duplicate(true)
	
	print("[EpisodeLogger] Ended episode: ", _current_episode["episode_id"], 
		  " | Success: ", success, 
		  " | Duration: ", duration_ms, "ms")
	
	episode_ended.emit(result)
	
	_episode_active = false
	_current_episode = {}
	
	return result

func is_active() -> bool:
	return _episode_active

func get_current_episode_id() -> String:
	if _episode_active:
		return _current_episode.get("episode_id", "")
	return ""

func get_participant_id() -> String:
	return _participant_id

func log_participant_profile(profile: Dictionary) -> void:
	if profile.is_empty():
		return
	var payload := {
		"participant_id": _participant_id,
		"session_id": _session_id,
		"nickname": str(profile.get("nickname", "")),
		"tipi_responses": profile.get("tipi_responses", {}),
		"tipi_scores": profile.get("tipi_scores", {}),
		"question_count": int(profile.get("question_count", 0))
	}
	_post_remote_log("participant_upsert", payload)

func log_game_run(run_outcome: String, final_score: int) -> void:
	var payload := {
		"run_id": _session_id,
		"participant_id": _participant_id,
		"session_id": _session_id,
		"run_outcome": run_outcome,
		"final_score": final_score
	}
	_post_remote_log("game_run_upsert", payload)

func log_api_failure(api_name: String, event_type: String, http_status: int, error_code: String, error_message: String, request_id: String = "", episode_id: String = "", client_timestamp_ms: int = -1) -> void:
	var failure_id := "fail_%s_%04d" % [_session_id, _remote_failure_counter]
	_remote_failure_counter += 1
	var payload := {
		"failure_id": failure_id,
		"session_id": _session_id,
		"episode_id": episode_id if episode_id != "" else get_current_episode_id(),
		"request_id": request_id,
		"api_name": api_name,
		"event_type": event_type,
		"http_status": http_status,
		"error_code": error_code,
		"error_message": error_message,
		"client_timestamp_ms": client_timestamp_ms if client_timestamp_ms >= 0 else _gameplay_now_ms()
	}
	_post_remote_log("api_failure_upsert", payload, false)

func log_runtime_debug_event(event_type: String, data: Dictionary = {}) -> void:
	var normalized_event_type := _normalize_debug_value(event_type, DEBUG_EVENT_TYPES)
	var normalized_reason := _normalize_debug_value(str(data.get("event_reason", data.get("reason", ""))), DEBUG_EVENT_REASONS)
	var normalized_step := _normalize_debug_value(str(data.get("robot_step", "")), DEBUG_ROBOT_STEPS)
	var normalized_scenario := _normalize_debug_value(str(data.get("delegation_scenario", "")), DEBUG_DELEGATION_SCENARIOS)
	var payload := {
		"debug_event_id": "dbg_%s_%05d" % [_session_id, _runtime_debug_counter],
		"session_id": _session_id,
		"episode_id": str(data.get("episode_id", get_current_episode_id())),
		"request_id": str(data.get("request_id", "")),
		"timestamp_ms": int(data.get("timestamp_ms", _gameplay_now_ms())),
		"event_type": normalized_event_type,
		"event_reason": normalized_reason,
		"robot_task_id": str(data.get("robot_task_id", "")),
		"robot_step": normalized_step,
		"delegation_scenario": normalized_scenario,
		"robot_x": float(data.get("robot_x", 0.0)),
		"robot_y": float(data.get("robot_y", 0.0)),
		"robot_target_x": data.get("robot_target_x", null),
		"robot_target_y": data.get("robot_target_y", null),
		"robot_battery_level": data.get("robot_battery_level", null),
		"robot_inventory_count": int(data.get("robot_inventory_count", 0)),
		"player_active_tasks": int(data.get("player_active_tasks", 0)),
		"has_navigation_path": bool(data.get("has_navigation_path", false)),
		"path_length": int(data.get("path_length", 0)),
		"moved_distance_px": data.get("moved_distance_px", null),
		"stuck_duration_ms": int(data.get("stuck_duration_ms", 0)),
		"total_stuck_time_ms": int(data.get("total_stuck_time_ms", 0)),
		"retry_count": int(data.get("retry_count", 0)),
	}
	_runtime_debug_counter += 1
	_post_remote_log("runtime_debug_event_upsert", payload)

func log_delegation_templates(templates: Array[Dictionary]) -> void:
	if _delegation_templates_logged:
		return
	for template in templates:
		if template.is_empty():
			continue
		_post_remote_log("template_upsert", {
			"template_id": str(template.get("template_id", "")),
			"template_group": str(template.get("template_group", "")),
			"strategy": str(template.get("strategy", "")),
			"template_text": str(template.get("template_text", ""))
		})
	_delegation_templates_logged = true

func log_help_request_event(request: Dictionary) -> void:
	if request.is_empty():
		return
	var payload: Dictionary = request.get("payload", {})
	var context: Dictionary = request.get("context_snapshot", {})
	var robot: Dictionary = context.get("robot", {})
	var player: Dictionary = context.get("player", {})
	var env: Dictionary = context.get("environment", {})
	var personality: Dictionary = context.get("personality", {})
	var scores: Dictionary = personality.get("tipi_scores", {})
	var record := {
		"participant_id": _participant_id,
		"session_id": _session_id,
		"nickname": str(request.get("nickname", "")),
		"episode_id": get_current_episode_id(),
		"request_id": str(request.get("id", "")),
		"delegation_scenario": str(request.get("delegation_scenario", "")),
		"request_index_in_session": int(request.get("request_index_in_session", 0)),
		"status": str(request.get("status", "")),
		"created_at_ms": int(request.get("created_at_ms", 0)),
		"task_id": str(payload.get("task_id", "")),
		"item_needed": str(payload.get("item_needed", "")),
		"reason": str(payload.get("reason", "")),
		"slack_ms": int(payload.get("slack_ms", 0)),
		"phase_name": str(env.get("phase_name", "")),
		"busyness": float(env.get("busyness", 0.0)),
		"urgency": float(env.get("urgency", 0.0)),
		"player_active_tasks": int(player.get("active_tasks", 0)),
		"battery_level": float(robot.get("battery_level", 0.0)),
		"trait_O": float(scores.get("O", 0.0)),
		"trait_C": float(scores.get("C", 0.0)),
		"trait_E": float(scores.get("E", 0.0)),
		"trait_A": float(scores.get("A", 0.0)),
		"trait_N": float(scores.get("N", 0.0)),
		"strategy": str(request.get("strategy", "")),
		"assignment_buckets": request.get("assignment_buckets", {}),
		"opener_template_id": str(request.get("opener_template_id", "")),
		"bridge_template_id": str(request.get("bridge_template_id", "")),
		"template_id": str(request.get("template_id", "")),
		"utterance": str(request.get("utterance", "")),
		"response": str(request.get("last_response", "")),
		"response_latency_ms": int(request.get("response_latency_ms", -1)),
		"resolution_path": str(request.get("resolution_path", "")),
		"task_completed": bool(request.get("task_completed", false)),
		"delivery_actor": str(request.get("delivery_actor", "")),
		"customer_timed_out": bool(request.get("customer_timed_out", false)),
		"score_delta": int(request.get("score_delta", 0))
	}
	if _should_write_local_files():
		_append_jsonl(HELP_JSONL_FILE, record)
	_post_remote_log("help_request_upsert", record)
	if _should_write_local_files() and _is_replay_logging_enabled():
		_append_jsonl(REPLAY_JSONL_FILE, record)

func log_replay_event(event_type: String, data: Dictionary = {}) -> void:
	if not _should_write_local_files() or not _is_replay_logging_enabled():
		return
	var record := {
		"kind": "replay_event",
		"event_type": event_type,
		"timestamp": Time.get_datetime_string_from_system(),
		"timestamp_ms": Time.get_ticks_msec(),
		"episode_id": get_current_episode_id(),
		"data": data
	}
	_append_jsonl(REPLAY_JSONL_FILE, record)

# ==================== File I/O ====================

func _save_json() -> void:
	var episode_id = _current_episode.get("episode_id", "unknown")
	var file_path = DATA_DIR + episode_id + ".json"
	var global_path = ProjectSettings.globalize_path(file_path)
	
	# Ensure directory exists
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("data/episodes")
	
	var file = FileAccess.open(global_path, FileAccess.WRITE)
	if file:
		var json_str = JSON.stringify(_current_episode, "\t")
		file.store_string(json_str)
		file.close()
		print("[EpisodeLogger] Saved JSON: ", global_path)
	else:
		push_error("[EpisodeLogger] Failed to save JSON: ", global_path)

func _append_csv() -> void:
	var csv_path = ProjectSettings.globalize_path(CSV_FILE)
	
	# Ensure directory exists
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("data")
	
	var file = FileAccess.open(csv_path, FileAccess.READ_WRITE)
	if not file:
		# Create new file with header
		file = FileAccess.open(csv_path, FileAccess.WRITE)
		if file:
			file.store_line("episode_id,timestamp,success,duration_ms,failure_reason")
	
	if file:
		file.seek_end()
		
		var ep = _current_episode
		var outcome = ep.get("outcome", {})
		var row = [
			ep.get("episode_id", ""),
			ep.get("timestamp_start", ""),
			str(outcome.get("success", false)).to_lower(),
			str(ep.get("duration_ms", 0)),
			str(outcome.get("failure_reason", ""))
		]
		
		file.store_line(",".join(row))
		file.close()
		print("[EpisodeLogger] Appended to CSV: ", csv_path)
	else:
		push_error("[EpisodeLogger] Failed to open CSV: ", csv_path)

func _append_jsonl(file_path: String, record: Dictionary) -> void:
	var global_path = ProjectSettings.globalize_path(file_path)
	var file = FileAccess.open(global_path, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(global_path, FileAccess.WRITE)
	if not file:
		push_error("[EpisodeLogger] Failed to open JSONL: ", global_path)
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))
	file.close()

func get_session_id() -> String:
	return _session_id

func reset_session() -> void:
	_episode_active = false
	_current_episode = {}
	_episode_start_time = 0
	_episode_counter = 0
	_session_id = _generate_session_id()
	_participant_id = _session_id
	_delegation_templates_logged = false
	_remote_failure_counter = 0
	_runtime_debug_counter = 0

func _generate_session_id() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "").replace(" ", "")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "sess_%s_%06d" % [stamp, rng.randi_range(0, 999999)]

func _post_remote_log(event_type: String, payload: Dictionary = {}, allow_failure_capture: bool = true) -> void:
	if not _should_post_remote_logs():
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_remote_log_completed.bind(http, event_type, payload, allow_failure_capture))
	var body := {
		"session_id": _session_id,
		"participant_id": _participant_id,
		"type": event_type,
		"platform": "web" if OS.has_feature("web") else OS.get_name().to_lower(),
		"build_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"data": payload
	}
	var err := http.request(API_LOG_URL, PackedStringArray([
		"Content-Type: application/json"
	]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		if is_instance_valid(http):
			http.queue_free()
		push_warning("[EpisodeLogger] Failed to queue remote log: %s" % event_type)
		if allow_failure_capture and event_type != "api_failure_upsert":
			log_api_failure(
				"apiLog",
				event_type,
				-1,
				"request_queue_error",
				"Failed to queue remote log request",
				str(payload.get("request_id", "")),
				str(payload.get("episode_id", "")),
				int(payload.get("timestamp_ms", _gameplay_now_ms()))
			)

func _on_remote_log_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, event_type: String, payload: Dictionary, allow_failure_capture: bool) -> void:
	if is_instance_valid(http):
		http.queue_free()
	if code < 200 or code >= 300:
		push_warning("[EpisodeLogger] Remote log failed (%s): %d" % [event_type, code])
		if allow_failure_capture and event_type != "api_failure_upsert":
			var err_text := body.get_string_from_utf8().strip_edges()
			log_api_failure(
				"apiLog",
				event_type,
				code,
				"http_error",
				err_text if err_text != "" else "Remote log returned non-2xx status",
				str(payload.get("request_id", "")),
				str(payload.get("episode_id", "")),
				int(payload.get("timestamp_ms", _gameplay_now_ms()))
			)

func _should_post_remote_logs() -> bool:
	return OS.has_feature("web")

func _should_write_local_files() -> bool:
	return not OS.has_feature("web")

func _gameplay_now_ms() -> int:
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.has_method("get_gameplay_time_ms"):
		return int(game_mgr.get_gameplay_time_ms())
	return Time.get_ticks_msec()

func _normalize_debug_value(raw_value: String, allowed: Dictionary) -> String:
	var value := raw_value.strip_edges()
	if allowed.has(value):
		return value
	return ""

func _experiment_config() -> Node:
	return get_node_or_null("/root/ExperimentConfig")

func _is_replay_logging_enabled() -> bool:
	var exp = _experiment_config()
	if exp and exp.has_method("is_replay_logging_enabled"):
		return bool(exp.is_replay_logging_enabled())
	return false

# ==================== Utility ====================

func get_data_directory() -> String:
	return ProjectSettings.globalize_path(DATA_DIR)

func get_csv_path() -> String:
	return ProjectSettings.globalize_path(CSV_FILE)
