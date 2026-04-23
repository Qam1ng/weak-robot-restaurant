

extends Node
class_name CustomerSpawner


signal customer_spawned(customer: Node)
signal customer_left(customer: Node)



const CustomerScene = preload("res://scenes/Customer.tscn")


@export var absolute_max_customers: int = 5


const PERIOD_CONFIG = {
	"morning": {"max": 2, "interval_min": 30.0, "interval_max": 60.0, "batch_min": 1, "batch_max": 1},
	"lunch": {"max": 5, "interval_min": 15.0, "interval_max": 25.0, "batch_min": 1, "batch_max": 2},
	"afternoon": {"max": 2, "interval_min": 40.0, "interval_max": 80.0, "batch_min": 1, "batch_max": 1},
	"dinner": {"max": 5, "interval_min": 12.0, "interval_max": 20.0, "batch_min": 1, "batch_max": 2},
	"night": {"max": 0, "interval_min": 999.0, "interval_max": 999.0, "batch_min": 0, "batch_max": 0}
}


var _current_max_customers: int = 2


var active_customers: Array[Node] = []
var spawn_timer: Timer
var spawn_point: Vector2 = Vector2.ZERO
var time_manager: TimeManager = null
var _enabled: bool = true
var _force_first_spawned_customer_drink: bool = true

func _wait_seconds(seconds: float) -> bool:
	if seconds <= 0.0:
		return true
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = seconds
	add_child(timer)
	timer.start()
	await timer.timeout
	if is_instance_valid(timer):
		timer.queue_free()
	return is_inside_tree()


func _ready() -> void:

	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	

	call_deferred("_initialize")

func _initialize() -> void:

	var spawn_marker = _find_spawn_point()
	if spawn_marker:
		spawn_point = spawn_marker.global_position
		print("[CustomerSpawner] Spawn point set to CS1 at ", spawn_point)
	else:

		spawn_point = Vector2(-48, 333)
		print("[CustomerSpawner] Using default spawn point: ", spawn_point)
	

	_find_time_manager()
	

	if time_manager:
		var period_name = time_manager.get_period_name()
		var config = PERIOD_CONFIG.get(period_name, PERIOD_CONFIG["morning"])
		_current_max_customers = mini(config["max"], absolute_max_customers)
	else:
		_current_max_customers = 2
	

	print("[CustomerSpawner] Ready. Max customers for current period: %d (absolute max: %d)" % [_current_max_customers, absolute_max_customers])
	print("[CustomerSpawner] First customer will spawn in ~8 seconds...")
	spawn_timer.start(8.0)

func _find_spawn_point() -> Node2D:

	var markers = get_tree().get_nodes_in_group("spawn")
	for marker in markers:
		if marker.name == "CS1":
			return marker
	

	var root = get_tree().current_scene
	if root:
		var cs1 = root.find_child("CS1", true, false)
		if cs1:
			return cs1
	
	return null

func _find_time_manager() -> void:

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("get_time_manager"):
		time_manager = game_manager.get_time_manager()
	

	if not time_manager:
		time_manager = get_node_or_null("../TimeManager")
	
	if time_manager:
		time_manager.period_changed.connect(_on_period_changed)
		print("[CustomerSpawner] Connected to TimeManager")


func _get_current_config() -> Dictionary:
	if not time_manager:
		return PERIOD_CONFIG["morning"]
	var period_name = time_manager.get_period_name()
	return PERIOD_CONFIG.get(period_name, PERIOD_CONFIG["morning"])

func _schedule_next_spawn() -> void:
	if not _enabled:
		return
	

	if time_manager and not time_manager.is_open:

		print("[CustomerSpawner] Restaurant closed. Waiting...")
		spawn_timer.start(60.0)
		return
	

	var config = _get_current_config()
	var interval = randf_range(config["interval_min"], config["interval_max"])
	var period_name = time_manager.get_period_name() if time_manager else "unknown"
	
	print("[CustomerSpawner] Next spawn in %.1f seconds (%s, max: %d)" % [interval, period_name, _current_max_customers])
	spawn_timer.start(interval)

func _on_spawn_timer_timeout() -> void:

	if not _enabled:
		return
	
	if time_manager and not time_manager.is_open:
		_schedule_next_spawn()
		return
	

	_cleanup_inactive_customers()
	

	if active_customers.size() >= _current_max_customers:
		print("[CustomerSpawner] Max customers for this period reached (%d/%d), waiting..." % [active_customers.size(), _current_max_customers])
		_schedule_next_spawn()
		return
	

	var config = _get_current_config()
	

	var spawn_count = randi_range(config["batch_min"], config["batch_max"])
	

	var remaining_capacity = _current_max_customers - active_customers.size()
	spawn_count = mini(spawn_count, remaining_capacity)
	
	if spawn_count <= 0:
		_schedule_next_spawn()
		return
	

	for i in range(spawn_count):
		_spawn_single_customer(i * 1.0)
	

	_schedule_next_spawn()

func _spawn_single_customer(delay: float = 0.0) -> void:
	if delay > 0:
		if not await _wait_seconds(delay):
			return
	
	if not _enabled:
		return
	
	var customer = CustomerScene.instantiate()
	if "force_drink_order" in customer and _force_first_spawned_customer_drink:
		customer.force_drink_order = true
		_force_first_spawned_customer_drink = false
	

	if "spawn_path" in customer:
		customer.spawn_path = NodePath()
	

	if "start_delay_sec" in customer:
		customer.start_delay_sec = randf_range(0.5, 1.5)
	

	if customer.has_signal("customer_left"):
		customer.customer_left.connect(_on_customer_left)
	

	var restaurant = get_tree().current_scene
	restaurant.add_child(customer)
	

	var offset = Vector2(randf_range(-20, 20), randf_range(-10, 10))
	customer.global_position = spawn_point + offset
	
	print("[CustomerSpawner] Customer spawned at position: ", customer.global_position)
	

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


func _on_customer_left(customer: Node) -> void:
	if customer in active_customers:
		active_customers.erase(customer)
	customer_left.emit(customer)
	print("[CustomerSpawner] Customer left. Active: %d/%d" % [active_customers.size(), _current_max_customers])

func _on_period_changed(period_name: String, is_peak: bool) -> void:

	var config = PERIOD_CONFIG.get(period_name, PERIOD_CONFIG["morning"])
	_current_max_customers = mini(config["max"], absolute_max_customers)
	
	print("[CustomerSpawner] Period changed to %s (Peak: %s) - Max customers now: %d" % [period_name, is_peak, _current_max_customers])
	

	if time_manager and time_manager.is_open:
		if spawn_timer.is_stopped():
			_schedule_next_spawn()


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

func reset_first_spawn_drink_guarantee() -> void:
	_force_first_spawned_customer_drink = true

func get_active_customers() -> Array[Node]:
	_cleanup_inactive_customers()
	return active_customers


func force_spawn() -> Node:
	if active_customers.size() >= absolute_max_customers:
		print("[CustomerSpawner] Cannot force spawn - absolute max customers reached")
		return null
	
	_spawn_single_customer()
	return active_customers.back() if not active_customers.is_empty() else null


func clear_all_customers() -> void:
	for c in active_customers:
		if is_instance_valid(c):
			c.queue_free()
	active_customers.clear()
	reset_first_spawn_drink_guarantee()
	print("[CustomerSpawner] Cleared all customers")

func shutdown_immediately() -> void:
	_enabled = false
	if spawn_timer != null:
		spawn_timer.stop()
	var customers := get_tree().get_nodes_in_group("customer")
	for customer in customers:
		if is_instance_valid(customer):
			customer.free()
	active_customers.clear()
	reset_first_spawn_drink_guarantee()
