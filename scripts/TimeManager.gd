

extends Node
class_name TimeManager


signal time_changed(hour: int, minute: int)
signal period_changed(new_period: String, is_peak: bool)
signal day_changed(day: int)
signal run_day_completed(day: int)



@export var real_to_game_ratio: float = 2.0

# The full day remains 12 minutes while preserving more time for active service.
@export var morning_time_multiplier: float = 0.8
@export var lunch_time_multiplier: float = 0.8
@export var afternoon_time_multiplier: float = 0.75
@export var dinner_time_multiplier: float = 6.0 / 7.0
@export var night_time_multiplier: float = 7.0 / 3.0

@export var start_hour: int = 6

@export var start_minute: int = 0
@export var stop_after_single_day: bool = true


enum Period { MORNING, LUNCH, AFTERNOON, DINNER, NIGHT }

const PERIOD_NAMES = {
	Period.MORNING: "morning",
	Period.LUNCH: "lunch", 
	Period.AFTERNOON: "afternoon",
	Period.DINNER: "dinner",
	Period.NIGHT: "night"
}


const PERIOD_CONFIG = {
	Period.MORNING: [6, 10, false],
	Period.LUNCH: [10, 14, true],
	Period.AFTERNOON: [14, 17, false],
	Period.DINNER: [17, 23, true],
	Period.NIGHT: [23, 6, false]
}

const PERIOD_ORDER := [Period.MORNING, Period.LUNCH, Period.AFTERNOON, Period.DINNER, Period.NIGHT]


var current_hour: int = 8
var current_minute: int = 0
var current_day: int = 1
var current_period: Period = Period.MORNING
var is_peak_time: bool = false
var is_open: bool = true

var _accumulated_game_minutes: float = 0.0
var _paused: bool = false

func reset_runtime() -> void:
	current_day = 1
	current_hour = start_hour
	current_minute = start_minute
	current_period = Period.MORNING
	is_peak_time = false
	is_open = true
	_accumulated_game_minutes = 0.0
	_paused = false
	_update_period()
	time_changed.emit(current_hour, current_minute)


func _ready() -> void:
	current_hour = start_hour
	current_minute = start_minute
	_update_period()
	print("[TimeManager] Started at Day %d, %02d:%02d (%s)" % [current_day, current_hour, current_minute, get_period_name()])

func _process(delta: float) -> void:
	if _paused:
		return

	var minutes_per_second := _get_minutes_per_second()
	_accumulated_game_minutes += delta * minutes_per_second


	while _accumulated_game_minutes >= 1.0:
		_accumulated_game_minutes -= 1.0
		_advance_time(1)

func _get_minutes_per_second() -> float:
	return _get_minutes_per_second_for_period(current_period)

func _get_minutes_per_second_for_period(period: Period) -> float:
	var minutes_per_second := real_to_game_ratio
	match period:
		Period.MORNING:
			minutes_per_second *= morning_time_multiplier
		Period.LUNCH:
			minutes_per_second *= lunch_time_multiplier
		Period.AFTERNOON:
			minutes_per_second *= afternoon_time_multiplier
		Period.DINNER:
			minutes_per_second *= dinner_time_multiplier
		Period.NIGHT:
			minutes_per_second *= night_time_multiplier
		_:
			pass
	return maxf(0.01, minutes_per_second)

func get_formal_day_duration_seconds() -> float:
	var total_seconds := 0.0
	for period in PERIOD_ORDER:
		total_seconds += float(_get_period_duration_minutes(period)) / _get_minutes_per_second_for_period(period)
	return total_seconds

func get_formal_day_progress() -> float:
	var remaining_minutes := _elapsed_minutes_since_start()
	var elapsed_seconds := 0.0
	for period in PERIOD_ORDER:
		var period_minutes := _get_period_duration_minutes(period)
		var elapsed_in_period := mini(remaining_minutes, period_minutes)
		if elapsed_in_period > 0:
			elapsed_seconds += float(elapsed_in_period) / _get_minutes_per_second_for_period(period)
		remaining_minutes -= elapsed_in_period
		if remaining_minutes <= 0:
			break
	var total_seconds := get_formal_day_duration_seconds()
	return clampf(elapsed_seconds / maxf(total_seconds, 0.01), 0.0, 1.0)

func get_period_start_progress(period: Period) -> float:
	var elapsed_seconds := 0.0
	for ordered_period in PERIOD_ORDER:
		if ordered_period == period:
			break
		elapsed_seconds += float(_get_period_duration_minutes(ordered_period)) / _get_minutes_per_second_for_period(ordered_period)
	var total_seconds := get_formal_day_duration_seconds()
	return clampf(elapsed_seconds / maxf(total_seconds, 0.01), 0.0, 1.0)

func _elapsed_minutes_since_start() -> int:
	var now_minutes := current_hour * 60 + current_minute
	var start_minutes := start_hour * 60 + start_minute
	return posmod(now_minutes - start_minutes, 24 * 60)

func _get_period_duration_minutes(period: Period) -> int:
	var config: Array = PERIOD_CONFIG.get(period, [])
	if config.size() < 2:
		return 0
	var period_start_hour := int(config[0])
	var period_end_hour := int(config[1])
	if period_end_hour <= period_start_hour:
		period_end_hour += 24
	return (period_end_hour - period_start_hour) * 60


func _advance_time(minutes: int) -> void:
	current_minute += minutes

	while current_minute >= 60:
		current_minute -= 60
		current_hour += 1
		
		if current_hour >= 24:
			current_hour = 0

	if current_hour == start_hour and current_minute == start_minute:
		if stop_after_single_day:
			_paused = true
			_accumulated_game_minutes = 0.0
			run_day_completed.emit(current_day)
			print("[TimeManager] Run day completed: %d" % current_day)
			return
		current_day += 1
		day_changed.emit(current_day)
		print("[TimeManager] New day: %d" % current_day)

	time_changed.emit(current_hour, current_minute)
	_update_period()

func _update_period() -> void:
	var old_period = current_period
	var old_is_peak = is_peak_time


	for period in PERIOD_CONFIG:
		var config = PERIOD_CONFIG[period]
		var start_h = config[0]
		var end_h = config[1]
		

		if start_h > end_h:
			if current_hour >= start_h or current_hour < end_h:
				current_period = period
				is_peak_time = config[2]
				break
		else:
			if current_hour >= start_h and current_hour < end_h:
				current_period = period
				is_peak_time = config[2]
				break


	is_open = true


	if old_period != current_period or old_is_peak != is_peak_time:
		var period_name = get_period_name()
		period_changed.emit(period_name, is_peak_time)
		print("[TimeManager] Period changed to: %s (Peak: %s, Open: %s)" % [period_name, is_peak_time, is_open])


func get_period_name() -> String:
	return PERIOD_NAMES.get(current_period, "unknown")

func get_time_string() -> String:
	return "%02d:%02d" % [current_hour, current_minute]

func get_full_time_string() -> String:
	return "Day %d, %s" % [current_day, get_time_string()]

func pause() -> void:
	_paused = true
	print("[TimeManager] Paused")

func resume() -> void:
	_paused = false
	print("[TimeManager] Resumed")

func is_paused() -> bool:
	return _paused


func set_time(hour: int, minute: int = 0) -> void:
	current_hour = clampi(hour, 0, 23)
	current_minute = clampi(minute, 0, 59)
	_update_period()
	time_changed.emit(current_hour, current_minute)
	print("[TimeManager] Time set to: %s" % get_time_string())


func skip_to_next_period() -> void:
	var next_periods = {
		Period.MORNING: [10, 0],
		Period.LUNCH: [14, 0],
		Period.AFTERNOON: [17, 0],
		Period.DINNER: [23, 0],
		Period.NIGHT: [start_hour, start_minute]
	}

	var next = next_periods.get(current_period, [start_hour, start_minute])


	if current_period == Period.NIGHT and stop_after_single_day:
		_paused = true
		_accumulated_game_minutes = 0.0
		run_day_completed.emit(current_day)
		print("[TimeManager] Run day completed: %d" % current_day)
		return

	if current_period == Period.NIGHT:
		current_day += 1
		day_changed.emit(current_day)

	set_time(next[0], next[1])


func get_busyness() -> float:
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager == null:
		return 0.0
	var active_customers := 0.0
	if game_manager.has_method("get_active_customer_count"):
		active_customers = float(game_manager.get_active_customer_count())
	var customer_spawner = null
	if game_manager.has_method("get_customer_spawner"):
		customer_spawner = game_manager.get_customer_spawner()
	if customer_spawner == null:
		return 0.0
	var period_capacity := 1.0
	if customer_spawner.has_method("get_current_max_customers"):
		period_capacity = maxf(float(customer_spawner.get_current_max_customers()), 1.0)
	var spawn_interval_midpoint := 30.0
	if customer_spawner.has_method("get_spawn_interval_midpoint"):
		spawn_interval_midpoint = maxf(float(customer_spawner.get_spawn_interval_midpoint()), 1.0)
	var occupancy := active_customers / period_capacity
	var spawn_factor := 30.0 / spawn_interval_midpoint
	return clampf(occupancy * spawn_factor, 0.0, 1.0)
