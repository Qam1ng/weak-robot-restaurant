# EpisodeLogger.gd - Singleton for collecting episode data
# Used for Causal Inference research
extends Node

# Episode state
var _current_episode: Dictionary = {}
var _episode_active: bool = false
var _episode_start_time: int = 0
var _episode_counter: int = 0

# Metrics tracking
var _start_position: Vector2 = Vector2.ZERO
var _total_distance: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

# File paths
const DATA_DIR = "user://data/episodes/"
const CSV_FILE = "user://data/episodes_summary.csv"
const HELP_DIR = "user://data/help_requests/"
const HELP_JSONL_FILE = "user://data/help_requests/help_requests.jsonl"
const REPLAY_DIR = "user://data/replay/"
const REPLAY_JSONL_FILE = "user://data/replay/replay_events.jsonl"

var _help_event_seq: int = 0
var _session_id: String = ""
const API_LOG_URL := "/api/log"

signal episode_started(episode_id: String)
signal episode_ended(episode_data: Dictionary)

func _ready() -> void:
	_session_id = _generate_session_id()
	# Ensure data directory exists
	DirAccess.make_dir_recursive_absolute(DATA_DIR.replace("user://", OS.get_user_data_dir() + "/"))
	DirAccess.make_dir_recursive_absolute(HELP_DIR.replace("user://", OS.get_user_data_dir() + "/"))
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR.replace("user://", OS.get_user_data_dir() + "/"))
	_ensure_csv_header()
	print("[EpisodeLogger] Ready. Data dir: ", ProjectSettings.globalize_path(DATA_DIR))

func _ensure_csv_header() -> void:
	var csv_path = ProjectSettings.globalize_path(CSV_FILE)
	if not FileAccess.file_exists(csv_path):
		var file = FileAccess.open(csv_path, FileAccess.WRITE)
		if file:
			file.store_line("episode_id,timestamp,food_item,customer_seat,success,player_helped,help_item,duration_ms,stuck_count,stuck_total_ms,evasion_count,action_count,total_distance,failure_reason")
			file.close()

# ==================== Public API ====================

func start_episode(food_item: String, customer_seat: String, customer_pos: Vector2, robot_pos: Vector2) -> String:
	if _episode_active:
		push_warning("[EpisodeLogger] Previous episode not ended, forcing end")
		end_episode(false, "interrupted_by_new_episode")
	
	_episode_counter += 1
	var timestamp = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var episode_id = "ep_%s_%03d" % [timestamp, _episode_counter]
	
	_episode_start_time = Time.get_ticks_msec()
	_start_position = robot_pos
	_last_position = robot_pos
	_total_distance = 0.0
	
	_current_episode = {
		"episode_id": episode_id,
		"timestamp_start": Time.get_datetime_string_from_system(),
		"timestamp_end": "",
		"duration_ms": 0,
		
		"task": {
			"food_item": food_item,
			"customer_seat": customer_seat,
			"customer_position": {"x": customer_pos.x, "y": customer_pos.y}
		},
		
		"outcome": {
			"success": false,
			"failure_reason": null,
			"player_helped": false,
			"help_item": null
		},
		
		"metrics": {
			"total_distance": 0.0,
			"stuck_count": 0,
			"stuck_total_ms": 0,
			"evasion_count": 0,
			"action_count": 0
		},
		
		"events": [],
		
		"path_data": {
			"waypoints": [
				{"x": robot_pos.x, "y": robot_pos.y, "timestamp_ms": 0}
			]
		}
	}
	
	_episode_active = true
	
	log_event("episode_start", {
		"food_item": food_item,
		"customer_seat": customer_seat
	})
	_post_remote_log("episode_started", {
		"episode_id": episode_id,
		"food_item": food_item,
		"customer_seat": customer_seat
	})
	
	print("[EpisodeLogger] Started episode: ", episode_id)
	episode_started.emit(episode_id)
	return episode_id

func log_event(event_type: String, data: Dictionary = {}) -> void:
	if not _episode_active:
		return
	
	var timestamp_ms = Time.get_ticks_msec() - _episode_start_time
	
	var event = {
		"timestamp_ms": timestamp_ms,
		"type": event_type,
		"data": data
	}
	
	_current_episode["events"].append(event)
	
	# Update metrics based on event type
	match event_type:
		"action_start":
			_current_episode["metrics"]["action_count"] += 1
		"obstacle_stuck":
			_current_episode["metrics"]["stuck_count"] += 1
			if data.has("duration_ms"):
				_current_episode["metrics"]["stuck_total_ms"] += data["duration_ms"]
		"evasion":
			_current_episode["metrics"]["evasion_count"] += 1
		"player_help":
			_current_episode["outcome"]["player_helped"] = true
			if data.has("item_given"):
				_current_episode["outcome"]["help_item"] = data["item_given"]

func log_position(pos: Vector2) -> void:
	if not _episode_active:
		return
	
	# Calculate distance traveled
	var dist = _last_position.distance_to(pos)
	if dist > 5.0:  # Only log significant movement
		_total_distance += dist
		_last_position = pos
		
		var timestamp_ms = Time.get_ticks_msec() - _episode_start_time
		_current_episode["path_data"]["waypoints"].append({
			"x": pos.x,
			"y": pos.y,
			"timestamp_ms": timestamp_ms
		})

func end_episode(success: bool, failure_reason: String = "") -> Dictionary:
	if not _episode_active:
		push_warning("[EpisodeLogger] No active episode to end")
		return {}
	
	var duration_ms = Time.get_ticks_msec() - _episode_start_time
	
	_current_episode["timestamp_end"] = Time.get_datetime_string_from_system()
	_current_episode["duration_ms"] = duration_ms
	_current_episode["outcome"]["success"] = success
	_current_episode["outcome"]["failure_reason"] = failure_reason if not success else ""
	_current_episode["metrics"]["total_distance"] = _total_distance
	
	log_event("episode_end", {
		"success": success,
		"failure_reason": failure_reason
	})
	
	# Save to files
	_save_json()
	_append_csv()
	_post_remote_log("episode_ended", {
		"episode_id": _current_episode.get("episode_id", ""),
		"success": success,
		"failure_reason": failure_reason,
		"duration_ms": duration_ms,
		"player_helped": bool(_current_episode.get("outcome", {}).get("player_helped", false))
	})
	
	var result = _current_episode.duplicate(true)
	
	print("[EpisodeLogger] Ended episode: ", _current_episode["episode_id"], 
		  " | Success: ", success, 
		  " | Duration: ", duration_ms, "ms",
		  " | Player helped: ", _current_episode["outcome"]["player_helped"])
	
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

func log_help_request_event(event_type: String, request: Dictionary, extra: Dictionary = {}) -> void:
	if request.is_empty():
		return
	var exp = _experiment_config()
	var exp_snapshot := {}
	if exp and exp.has_method("get_snapshot"):
		exp_snapshot = exp.get_snapshot()
	var record := {
		"kind": "help_request",
		"event_type": event_type,
		"event_seq": _help_event_seq + 1,
		"timestamp": Time.get_datetime_string_from_system(),
		"timestamp_ms": Time.get_ticks_msec(),
		"episode_id": get_current_episode_id(),
		"request_id": str(request.get("id", "")),
		"request_type": str(request.get("type", "")),
		"status": str(request.get("status", "")),
		"context_snapshot": request.get("context_snapshot", {}),
		"strategy": str(request.get("strategy", "")),
		"strategy_scores": request.get("strategy_scores", {}),
		"dialogue_intent": request.get("dialogue_intent", {}),
		"utterance": str(request.get("utterance", "")),
		"response": str(request.get("last_response", "")),
		"response_latency_ms": int(request.get("response_latency_ms", -1)),
		"escalation_count": int(request.get("escalation_count", 0)),
		"max_escalation": int(request.get("max_escalation", 0)),
		"final_response": str(request.get("final_response", "")),
		"final_path": str(request.get("resolution_path", "")),
		"payload": request.get("payload", {}),
		"robot_instance_id": int(request.get("robot_instance_id", 0)),
		"experiment": request.get("experiment", exp_snapshot),
		"extra": extra
	}
	_help_event_seq += 1
	_append_jsonl(HELP_JSONL_FILE, record)
	_post_remote_log("help_request_" + event_type, {
		"request_id": record.get("request_id", ""),
		"request_type": record.get("request_type", ""),
		"status": record.get("status", ""),
		"strategy": record.get("strategy", ""),
		"response": record.get("response", ""),
		"final_response": record.get("final_response", ""),
		"resolution_path": record.get("final_path", ""),
		"payload": record.get("payload", {}),
		"extra": extra
	})
	if _is_replay_logging_enabled():
		_append_jsonl(REPLAY_JSONL_FILE, record)

func log_replay_event(event_type: String, data: Dictionary = {}) -> void:
	if not _is_replay_logging_enabled():
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
			file.store_line("episode_id,timestamp,food_item,customer_seat,success,player_helped,help_item,duration_ms,stuck_count,stuck_total_ms,evasion_count,action_count,total_distance,failure_reason")
	
	if file:
		file.seek_end()
		
		var ep = _current_episode
		var outcome = ep.get("outcome", {})
		var metrics = ep.get("metrics", {})
		var task = ep.get("task", {})
		
		var row = [
			ep.get("episode_id", ""),
			ep.get("timestamp_start", ""),
			task.get("food_item", ""),
			task.get("customer_seat", ""),
			str(outcome.get("success", false)).to_lower(),
			str(outcome.get("player_helped", false)).to_lower(),
			str(outcome.get("help_item", "")),
			str(ep.get("duration_ms", 0)),
			str(metrics.get("stuck_count", 0)),
			str(metrics.get("stuck_total_ms", 0)),
			str(metrics.get("evasion_count", 0)),
			str(metrics.get("action_count", 0)),
			str(snapped(metrics.get("total_distance", 0.0), 0.1)),
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

func _generate_session_id() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "").replace(" ", "")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "sess_%s_%06d" % [stamp, rng.randi_range(0, 999999)]

func _post_remote_log(event_type: String, payload: Dictionary = {}) -> void:
	if not _should_post_remote_logs():
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_remote_log_completed.bind(http, event_type))
	var body := {
		"session_id": _session_id,
		"type": event_type,
		"ts": Time.get_ticks_msec(),
		"platform": "web" if OS.has_feature("web") else OS.get_name().to_lower(),
		"build_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"user_agent": "",
		"payload": payload
	}
	var err := http.request(API_LOG_URL, PackedStringArray([
		"Content-Type: application/json"
	]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		if is_instance_valid(http):
			http.queue_free()
		push_warning("[EpisodeLogger] Failed to queue remote log: %s" % event_type)

func _on_remote_log_completed(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, event_type: String) -> void:
	if is_instance_valid(http):
		http.queue_free()
	if code < 200 or code >= 300:
		push_warning("[EpisodeLogger] Remote log failed (%s): %d" % [event_type, code])

func _should_post_remote_logs() -> bool:
	return OS.has_feature("web")

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
