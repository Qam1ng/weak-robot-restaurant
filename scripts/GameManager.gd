

extends Node


signal game_state_changed(new_state: String)
signal restaurant_opened()
signal restaurant_closed()


enum GameState { RUNNING, PAUSED, CLOSED }

var current_state: GameState = GameState.RUNNING


var time_manager: TimeManager = null
var customer_spawner: CustomerSpawner = null


var total_customers_served: int = 0
var total_episodes_completed: int = 0
var current_day_customers: int = 0

func reset_run() -> void:
	current_state = GameState.RUNNING
	total_customers_served = 0
	total_episodes_completed = 0
	current_day_customers = 0
	customer_spawner = null
	if time_manager and time_manager.has_method("reset_runtime"):
		time_manager.reset_runtime()


func _ready() -> void:
	print("[GameManager] Initializing...")
	

	time_manager = TimeManager.new()
	time_manager.name = "TimeManager"
	add_child(time_manager)
	

	time_manager.period_changed.connect(_on_period_changed)
	time_manager.day_changed.connect(_on_day_changed)
	time_manager.time_changed.connect(_on_time_changed)
	
	print("[GameManager] Ready. Time: %s" % time_manager.get_full_time_string())

func _input(event: InputEvent) -> void:

	if event.is_action_pressed("ui_cancel"):  # ESC
		toggle_pause()
	

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:

				if customer_spawner:
					customer_spawner.force_spawn()
			KEY_F2:

				if time_manager:
					time_manager.skip_to_next_period()
			KEY_F3:

				print_status()


func get_time_manager() -> TimeManager:
	return time_manager

func get_customer_spawner() -> CustomerSpawner:
	return customer_spawner

func register_customer_spawner(spawner: CustomerSpawner) -> void:
	customer_spawner = spawner
	customer_spawner.customer_spawned.connect(_on_customer_spawned)
	customer_spawner.customer_left.connect(_on_customer_left)
	print("[GameManager] CustomerSpawner registered")


func toggle_pause() -> void:
	if current_state == GameState.PAUSED:
		resume_game()
	elif current_state == GameState.RUNNING:
		pause_game()

func pause_game() -> void:
	if current_state == GameState.PAUSED:
		return
	
	current_state = GameState.PAUSED
	
	if time_manager:
		time_manager.pause()
	if customer_spawner:
		customer_spawner.disable()
	

	# get_tree().paused = true
	
	game_state_changed.emit("paused")
	print("[GameManager] Game PAUSED")

func resume_game() -> void:
	if current_state == GameState.RUNNING:
		return
	
	current_state = GameState.RUNNING
	
	if time_manager:
		time_manager.resume()
	if customer_spawner:
		customer_spawner.enable()
	
	# get_tree().paused = false
	
	game_state_changed.emit("running")
	print("[GameManager] Game RESUMED")

func is_paused() -> bool:
	return current_state == GameState.PAUSED

func is_open() -> bool:
	if time_manager:
		return time_manager.is_open
	return true


func _on_period_changed(period_name: String, is_peak: bool) -> void:
	print("[GameManager] Period: %s (Peak: %s)" % [period_name, is_peak])
	

	if time_manager:
		if time_manager.is_open:
			restaurant_opened.emit()
		else:
			restaurant_closed.emit()
			print("[GameManager] Restaurant CLOSED for the night")

func _on_day_changed(day: int) -> void:
	print("[GameManager] === DAY %d ===" % day)
	print("[GameManager] Yesterday served: %d customers" % current_day_customers)
	current_day_customers = 0

func _on_time_changed(_hour: int, _minute: int) -> void:

	pass

func _on_customer_spawned(_customer: Node) -> void:
	current_day_customers += 1

func _on_customer_left(_customer: Node) -> void:
	total_customers_served += 1


func on_episode_completed(success: bool) -> void:
	total_episodes_completed += 1
	if success:
		print("[GameManager] Episode completed successfully! Total: %d" % total_episodes_completed)
	else:
		print("[GameManager] Episode failed. Total: %d" % total_episodes_completed)


func get_game_time() -> String:
	if time_manager:
		return time_manager.get_full_time_string()
	return "Unknown"

func get_period() -> String:
	if time_manager:
		return time_manager.get_period_name()
	return "unknown"

func is_peak_time() -> bool:
	if time_manager:
		return time_manager.is_peak_time
	return false

func get_busyness() -> float:
	if time_manager:
		return time_manager.get_busyness()
	return 0.5

func get_active_customer_count() -> int:
	if customer_spawner:
		return customer_spawner.get_customer_count()
	return 0

func print_status() -> void:
	print("====== GAME STATUS ======")
	print("State: %s" % GameState.keys()[current_state])
	print("Time: %s" % get_game_time())
	print("Period: %s (Peak: %s)" % [get_period(), is_peak_time()])
	print("Restaurant Open: %s" % is_open())
	print("Active Customers: %d" % get_active_customer_count())
	print("Today's Customers: %d" % current_day_customers)
	print("Total Served: %d" % total_customers_served)
	print("Total Episodes: %d" % total_episodes_completed)
	print("=========================")
