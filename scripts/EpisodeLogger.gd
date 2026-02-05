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

signal episode_started(episode_id: String)
signal episode_ended(episode_data: Dictionary)

func _ready() -> void:
	# Ensure data directory exists
	DirAccess.make_dir_recursive_absolute(DATA_DIR.replace("user://", OS.get_user_data_dir() + "/"))
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

# ==================== Utility ====================

func get_data_directory() -> String:
	return ProjectSettings.globalize_path(DATA_DIR)

func get_csv_path() -> String:
	return ProjectSettings.globalize_path(CSV_FILE)
