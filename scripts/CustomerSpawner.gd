# CustomerSpawner.gd - 顾客生成系统
# 根据时间段和繁忙程度动态生成顾客
extends Node
class_name CustomerSpawner

# ==================== 信号 ====================
signal customer_spawned(customer: Node)
signal customer_left(customer: Node)

# ==================== 配置 ====================
## 顾客场景
const CustomerScene = preload("res://scenes/Customer.tscn")

## 绝对最大顾客数（座位数）
@export var absolute_max_customers: int = 5

## 各时段配置 {max_customers, spawn_interval_min, spawn_interval_max, batch_min, batch_max}
const PERIOD_CONFIG = {
	"morning": {"max": 2, "interval_min": 30.0, "interval_max": 60.0, "batch_min": 1, "batch_max": 1},
	"lunch": {"max": 5, "interval_min": 15.0, "interval_max": 25.0, "batch_min": 1, "batch_max": 2},
	"afternoon": {"max": 2, "interval_min": 40.0, "interval_max": 80.0, "batch_min": 1, "batch_max": 1},
	"dinner": {"max": 5, "interval_min": 12.0, "interval_max": 20.0, "batch_min": 1, "batch_max": 2},
	"night": {"max": 0, "interval_min": 999.0, "interval_max": 999.0, "batch_min": 0, "batch_max": 0}
}

# 当前时段的动态最大顾客数
var _current_max_customers: int = 2

# ==================== 状态 ====================
var active_customers: Array[Node] = []
var spawn_timer: Timer
var spawn_point: Vector2 = Vector2.ZERO
var time_manager: TimeManager = null
var _enabled: bool = true

# ==================== 生命周期 ====================
func _ready() -> void:
	# 创建生成定时器
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	
	# 延迟初始化，等待其他节点准备好
	call_deferred("_initialize")

func _initialize() -> void:
	# 找到 spawn 点 (CS1 - Customer Spawn 1)
	var spawn_marker = _find_spawn_point()
	if spawn_marker:
		spawn_point = spawn_marker.global_position
		print("[CustomerSpawner] Spawn point set to CS1 at ", spawn_point)
	else:
		# 使用默认位置（场景中的 Customer 初始位置附近）
		spawn_point = Vector2(-48, 333)
		print("[CustomerSpawner] Using default spawn point: ", spawn_point)
	
	# 查找 TimeManager
	_find_time_manager()
	
	# 初始化当前时段的最大顾客数
	if time_manager:
		var period_name = time_manager.get_period_name()
		var config = PERIOD_CONFIG.get(period_name, PERIOD_CONFIG["morning"])
		_current_max_customers = mini(config["max"], absolute_max_customers)
	else:
		_current_max_customers = 2  # 默认值
	
	# 启动第一次生成 - 首次等待较短时间(8秒)以便快速测试
	print("[CustomerSpawner] Ready. Max customers for current period: %d (absolute max: %d)" % [_current_max_customers, absolute_max_customers])
	print("[CustomerSpawner] First customer will spawn in ~8 seconds...")
	spawn_timer.start(8.0)  # 首次8秒后生成

func _find_spawn_point() -> Node2D:
	# 尝试在 LocationMarkers 中找到 CS1
	var markers = get_tree().get_nodes_in_group("spawn")
	for marker in markers:
		if marker.name == "CS1":
			return marker
	
	# 备选：直接搜索
	var root = get_tree().current_scene
	if root:
		var cs1 = root.find_child("CS1", true, false)
		if cs1:
			return cs1
	
	return null

func _find_time_manager() -> void:
	# 尝试从 GameManager 获取
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("get_time_manager"):
		time_manager = game_manager.get_time_manager()
	
	# 或者直接在场景中查找
	if not time_manager:
		time_manager = get_node_or_null("../TimeManager")
	
	if time_manager:
		time_manager.period_changed.connect(_on_period_changed)
		print("[CustomerSpawner] Connected to TimeManager")

# ==================== 生成逻辑 ====================
func _get_current_config() -> Dictionary:
	if not time_manager:
		return PERIOD_CONFIG["morning"]
	var period_name = time_manager.get_period_name()
	return PERIOD_CONFIG.get(period_name, PERIOD_CONFIG["morning"])

func _schedule_next_spawn() -> void:
	if not _enabled:
		return
	
	# 检查是否营业时间
	if time_manager and not time_manager.is_open:
		# 关店期间，每分钟检查一次
		print("[CustomerSpawner] Restaurant closed. Waiting...")
		spawn_timer.start(60.0)
		return
	
	# 根据时间段获取配置
	var config = _get_current_config()
	var interval = randf_range(config["interval_min"], config["interval_max"])
	var period_name = time_manager.get_period_name() if time_manager else "unknown"
	
	print("[CustomerSpawner] Next spawn in %.1f seconds (%s, max: %d)" % [interval, period_name, _current_max_customers])
	spawn_timer.start(interval)

func _on_spawn_timer_timeout() -> void:
	# 检查是否可以生成
	if not _enabled:
		return
	
	if time_manager and not time_manager.is_open:
		_schedule_next_spawn()
		return
	
	# 清理已离开的顾客
	_cleanup_inactive_customers()
	
	# 检查顾客数量限制（使用动态最大值）
	if active_customers.size() >= _current_max_customers:
		print("[CustomerSpawner] Max customers for this period reached (%d/%d), waiting..." % [active_customers.size(), _current_max_customers])
		_schedule_next_spawn()
		return
	
	# 根据时段获取配置
	var config = _get_current_config()
	
	# 确定要生成的顾客数量
	var spawn_count = randi_range(config["batch_min"], config["batch_max"])
	
	# 不超过剩余容量
	var remaining_capacity = _current_max_customers - active_customers.size()
	spawn_count = mini(spawn_count, remaining_capacity)
	
	if spawn_count <= 0:
		_schedule_next_spawn()
		return
	
	# 生成顾客
	for i in range(spawn_count):
		_spawn_single_customer(i * 1.0)  # 间隔1秒生成，更自然
	
	# 安排下一次生成
	_schedule_next_spawn()

func _spawn_single_customer(delay: float = 0.0) -> void:
	if delay > 0:
		await get_tree().create_timer(delay).timeout
	
	if not _enabled:
		return
	
	var customer = CustomerScene.instantiate()
	
	# 重置 spawn_path，因为我们直接设置位置
	if "spawn_path" in customer:
		customer.spawn_path = NodePath()
	
	# 设置较短的延迟（因为是动态生成的）
	if "start_delay_sec" in customer:
		customer.start_delay_sec = randf_range(0.5, 1.5)
	
	# 连接顾客离开信号
	if customer.has_signal("customer_left"):
		customer.customer_left.connect(_on_customer_left)
	
	# 先添加到场景，然后设置位置
	var restaurant = get_tree().current_scene
	restaurant.add_child(customer)
	
	# 设置生成位置（稍微随机偏移避免重叠）- 必须在 add_child 之后
	var offset = Vector2(randf_range(-20, 20), randf_range(-10, 10))
	customer.global_position = spawn_point + offset
	
	print("[CustomerSpawner] Customer spawned at position: ", customer.global_position)
	
	# 记录
	active_customers.append(customer)
	customer_spawned.emit(customer)
	
	var period_name = time_manager.get_period_name() if time_manager else "unknown"
	print("[CustomerSpawner] Spawned customer. Active: %d/%d (Period: %s)" % [active_customers.size(), _current_max_customers, period_name])

func _cleanup_inactive_customers() -> void:
	var valid_customers: Array[Node] = []
	for c in active_customers:
		if is_instance_valid(c) and c.is_inside_tree():
			valid_customers.append(c)
	active_customers = valid_customers

# ==================== 事件处理 ====================
func _on_customer_left(customer: Node) -> void:
	if customer in active_customers:
		active_customers.erase(customer)
	customer_left.emit(customer)
	print("[CustomerSpawner] Customer left. Active: %d/%d" % [active_customers.size(), _current_max_customers])

func _on_period_changed(period_name: String, is_peak: bool) -> void:
	# 更新当前时段的最大顾客数
	var config = PERIOD_CONFIG.get(period_name, PERIOD_CONFIG["morning"])
	_current_max_customers = mini(config["max"], absolute_max_customers)
	
	print("[CustomerSpawner] Period changed to %s (Peak: %s) - Max customers now: %d" % [period_name, is_peak, _current_max_customers])
	
	# 如果刚开店，立即尝试生成
	if time_manager and time_manager.is_open:
		if spawn_timer.is_stopped():
			_schedule_next_spawn()

# ==================== 公共 API ====================
func enable() -> void:
	_enabled = true
	_schedule_next_spawn()
	print("[CustomerSpawner] Enabled")

func disable() -> void:
	_enabled = false
	spawn_timer.stop()
	print("[CustomerSpawner] Disabled")

func get_customer_count() -> int:
	_cleanup_inactive_customers()
	return active_customers.size()

func get_active_customers() -> Array[Node]:
	_cleanup_inactive_customers()
	return active_customers

## 强制立即生成一个顾客（用于测试）
func force_spawn() -> Node:
	if active_customers.size() >= absolute_max_customers:
		print("[CustomerSpawner] Cannot force spawn - absolute max customers reached")
		return null
	
	_spawn_single_customer()
	return active_customers.back() if not active_customers.is_empty() else null

## 清除所有顾客（用于重置）
func clear_all_customers() -> void:
	for c in active_customers:
		if is_instance_valid(c):
			c.queue_free()
	active_customers.clear()
	print("[CustomerSpawner] Cleared all customers")
