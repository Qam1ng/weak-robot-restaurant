# TimeManager.gd - 游戏内时间系统
# 管理游戏时间流逝、时间段划分、高峰/低谷期
extends Node
class_name TimeManager

# ==================== 信号 ====================
signal time_changed(hour: int, minute: int)
signal period_changed(new_period: String, is_peak: bool)
signal day_changed(day: int)

# ==================== 时间配置 ====================
## 现实1秒 = 游戏内多少分钟
@export var real_to_game_ratio: float = 1.0
## 游戏开始时的小时 (0-23)
@export var start_hour: int = 8
## 游戏开始时的分钟 (0-59)
@export var start_minute: int = 0

# ==================== 时间段定义 ====================
enum Period { MORNING, LUNCH, AFTERNOON, DINNER, NIGHT }

const PERIOD_NAMES = {
	Period.MORNING: "morning",
	Period.LUNCH: "lunch", 
	Period.AFTERNOON: "afternoon",
	Period.DINNER: "dinner",
	Period.NIGHT: "night"
}

# 时间段范围 [开始小时, 结束小时, 是否高峰期]
const PERIOD_CONFIG = {
	Period.MORNING: [6, 11, false],    # 6:00 - 11:00 普通
	Period.LUNCH: [11, 14, true],      # 11:00 - 14:00 午餐高峰
	Period.AFTERNOON: [14, 17, false], # 14:00 - 17:00 普通
	Period.DINNER: [17, 21, true],     # 17:00 - 21:00 晚餐高峰
	Period.NIGHT: [21, 6, false]       # 21:00 - 6:00 关店/夜间
}

# ==================== 状态 ====================
var current_hour: int = 8
var current_minute: int = 0
var current_day: int = 1
var current_period: Period = Period.MORNING
var is_peak_time: bool = false
var is_open: bool = true  # 餐厅是否营业

var _accumulated_time: float = 0.0
var _paused: bool = false

# ==================== 生命周期 ====================
func _ready() -> void:
	current_hour = start_hour
	current_minute = start_minute
	_update_period()
	print("[TimeManager] Started at Day %d, %02d:%02d (%s)" % [current_day, current_hour, current_minute, get_period_name()])

func _process(delta: float) -> void:
	if _paused:
		return
	
	_accumulated_time += delta
	
	# 每现实1秒增加 real_to_game_ratio 分钟
	while _accumulated_time >= 1.0:
		_accumulated_time -= 1.0
		_advance_time(int(real_to_game_ratio))

# ==================== 时间推进 ====================
func _advance_time(minutes: int) -> void:
	current_minute += minutes
	
	while current_minute >= 60:
		current_minute -= 60
		current_hour += 1
		
		if current_hour >= 24:
			current_hour = 0
			current_day += 1
			day_changed.emit(current_day)
			print("[TimeManager] New day: %d" % current_day)
	
	time_changed.emit(current_hour, current_minute)
	_update_period()

func _update_period() -> void:
	var old_period = current_period
	var old_is_peak = is_peak_time
	
	# 确定当前时间段
	for period in PERIOD_CONFIG:
		var config = PERIOD_CONFIG[period]
		var start_h = config[0]
		var end_h = config[1]
		
		# 处理跨午夜的情况 (NIGHT: 21-6)
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
	
	# 更新营业状态
	is_open = current_period != Period.NIGHT
	
	# 如果时间段变化，发出信号
	if old_period != current_period or old_is_peak != is_peak_time:
		var period_name = get_period_name()
		period_changed.emit(period_name, is_peak_time)
		print("[TimeManager] Period changed to: %s (Peak: %s, Open: %s)" % [period_name, is_peak_time, is_open])

# ==================== 公共 API ====================
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

## 设置时间（用于调试或快进）
func set_time(hour: int, minute: int = 0) -> void:
	current_hour = clampi(hour, 0, 23)
	current_minute = clampi(minute, 0, 59)
	_update_period()
	time_changed.emit(current_hour, current_minute)
	print("[TimeManager] Time set to: %s" % get_time_string())

## 快进到下一个时间段
func skip_to_next_period() -> void:
	var next_periods = {
		Period.MORNING: [11, 0],
		Period.LUNCH: [14, 0],
		Period.AFTERNOON: [17, 0],
		Period.DINNER: [21, 0],
		Period.NIGHT: [6, 0]
	}
	
	var next = next_periods.get(current_period, [8, 0])
	
	# 如果跳到第二天早上
	if current_period == Period.NIGHT:
		current_day += 1
		day_changed.emit(current_day)
	
	set_time(next[0], next[1])

## 获取当前繁忙程度 (0.0 - 1.0)
func get_busyness() -> float:
	match current_period:
		Period.LUNCH, Period.DINNER:
			return 1.0  # 高峰期
		Period.MORNING, Period.AFTERNOON:
			return 0.5  # 普通时段
		Period.NIGHT:
			return 0.0  # 关店
	return 0.5
