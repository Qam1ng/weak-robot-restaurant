# HumanServer.gd (Godot 4.x)
extends CharacterBody2D

@export var speed: float = 180.0
@export var interact_radius: float = 48.0
@export var player_max_active_tasks: int = 3  # Soft threshold only; does not hard-block delegation

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

const InventoryScript = preload("res://scripts/Inventory.gd")
var inventory: Inventory

var last_dir: Vector2 = Vector2.DOWN
const FOOD_PICK_OPTIONS: Array[String] = ["pizza", "hotdog", "sandwich"]
const DRINK_PICK_OPTIONS: Array[String] = ["cola", "tea", "coffee"]
const PICKUP_STATION_RADIUS := 72.0
const PLAYER_ITEM_TTL_MS := 120_000
const HOLDING_BAR_ICON_PATHS := {
	"pizza": "res://assets/icons/orders/pizza.png",
	"hotdog": "res://assets/icons/orders/hotdog.png",
	"sandwich": "res://assets/icons/orders/sandwich.png",
	"coffee": "res://assets/icons/orders/coffee.png",
	"tea": "res://assets/icons/orders/tea.png",
	"cola": "res://assets/icons/orders/cola.png",
}
var _active_pick_station_kind: String = ""
var _holding_bar_root: Node2D = null
var _holding_bar_panel: PanelContainer = null
var _holding_bar_icons: HBoxContainer = null
var _holding_bar_textures: Dictionary = {}

func _ready() -> void:
	add_to_group("player")

	var cam := get_node_or_null("Camera2D")
	if cam and cam is Camera2D:
		var camera := cam as Camera2D
		camera.process_mode = Node.PROCESS_MODE_ALWAYS
		camera.make_current()
		camera.force_update_scroll()
		call_deferred("_ensure_camera_current")
	
	var existing_inv := get_node_or_null("Inventory")
	if existing_inv and existing_inv is Inventory:
		inventory = existing_inv as Inventory
	else:
		inventory = InventoryScript.new()
		inventory.name = "Inventory"
		add_child(inventory)
	inventory.capacity = 3

	_connect_hud_signals()
	_setup_holding_bar()
	if not inventory.inventory_changed.is_connected(_on_inventory_changed):
		inventory.inventory_changed.connect(_on_inventory_changed)
	_refresh_holding_bar(inventory.items)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_holding_bar_resources()

func _ensure_camera_current() -> void:
	var cam := get_node_or_null("Camera2D")
	if cam and cam is Camera2D:
		var camera := cam as Camera2D
		camera.make_current()
		camera.force_update_scroll()

func _physics_process(_dt: float) -> void:
	var vx: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vy: float = Input.get_action_strength("move_down")  - Input.get_action_strength("move_up")
	var v: Vector2 = Vector2(vx, vy)

	if v.length() > 0.0:
		velocity = v.normalized() * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	_update_animation(v)
	_auto_close_kitchen_pick_popup_if_left_zone()
	_expire_stale_inventory_items()

func _update_animation(input_dir: Vector2) -> void:
	var moving: bool = input_dir.length() > 0.0
	if moving:
		last_dir = input_dir

	var dir_name := ""
	if abs(last_dir.x) > abs(last_dir.y):
		if last_dir.x > 0.0:
			dir_name = "right"
		else:
			dir_name = "left"
	else:
		if last_dir.y > 0.0:
			dir_name = "down"
		else:
			dir_name = "up"

	var anim_name := ""
	if moving:
		anim_name = "walk_" + dir_name
	else:
		anim_name = "idle_" + dir_name

	if anim.animation != anim_name:
		anim.play(anim_name)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var hud := _get_hud()
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			if hud and hud.has_method("is_kitchen_pick_popup_visible") and bool(hud.call("is_kitchen_pick_popup_visible")):
				hud.call("hide_kitchen_pick_popup")
				_active_pick_station_kind = ""
				return
			if hud and hud.has_method("is_inventory_portal_visible") and bool(hud.call("is_inventory_portal_visible")):
				hud.call("hide_inventory_portal")
				return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_I:
			if hud and hud.has_method("toggle_inventory_portal"):
				hud.call("toggle_inventory_portal")
			return
	if event.is_action_pressed("interact"):
		if _handle_kitchen_pick_interact():
			return
		if _try_progress_player_delivery_interact():
			return
		# E key is reserved for world interactions (door/items) only.
		get_tree().call_group("interaction", "on_player_interact", self)

func _handle_kitchen_pick_interact() -> bool:
	# Kitchen zone only.
	if global_position.y >= -150.0:
		return false
	var hud := _get_hud()
	if hud == null:
		return false
	if hud.has_method("is_help_request_popup_visible") and bool(hud.call("is_help_request_popup_visible")):
		return false
	var station_kind := _nearest_pickup_station_kind()
	if station_kind == "":
		return false
	if hud.has_method("is_kitchen_pick_popup_visible") and bool(hud.call("is_kitchen_pick_popup_visible")):
		hud.call("hide_kitchen_pick_popup")
		_active_pick_station_kind = ""
		return true
	_active_pick_station_kind = station_kind
	if station_kind == "drink":
		hud.call("show_kitchen_pick_popup", DRINK_PICK_OPTIONS, "Drink Cabinet")
	else:
		hud.call("show_kitchen_pick_popup", FOOD_PICK_OPTIONS, "Food Cabinet")
	return true

func _auto_close_kitchen_pick_popup_if_left_zone() -> void:
	var hud := _get_hud()
	if hud == null:
		return
	var current_station_kind := _nearest_pickup_station_kind()
	var should_close := global_position.y >= -150.0 or current_station_kind == "" or (_active_pick_station_kind != "" and current_station_kind != _active_pick_station_kind)
	if should_close and hud.has_method("is_kitchen_pick_popup_visible") and bool(hud.call("is_kitchen_pick_popup_visible")):
		hud.call("hide_kitchen_pick_popup")
		_active_pick_station_kind = ""

func _try_progress_player_delivery_interact() -> bool:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee"):
		return false
	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee("player")
	if tasks.is_empty():
		return false

	return false

func _connect_hud_signals() -> void:
	await get_tree().process_frame
	var hud := _get_hud()
	if hud == null:
		return
	if hud.has_signal("kitchen_pick_selected") and not hud.kitchen_pick_selected.is_connected(_on_kitchen_pick_selected):
		hud.kitchen_pick_selected.connect(_on_kitchen_pick_selected)
	if hud.has_signal("inventory_delete_requested") and not hud.inventory_delete_requested.is_connected(_on_inventory_delete_requested):
		hud.inventory_delete_requested.connect(_on_inventory_delete_requested)

func _get_hud() -> Node:
	var huds := get_tree().get_nodes_in_group("hud")
	if huds.is_empty():
		return null
	return huds[0]

func _on_kitchen_pick_selected(item_name: String) -> void:
	var wanted := item_name.strip_edges().to_lower()
	if wanted == "":
		return
	var hud := _get_hud()
	if inventory == null or inventory.is_full():
		if hud and hud.has_method("show_kitchen_pick_feedback"):
			hud.call("show_kitchen_pick_feedback", wanted, false)
		_notify_player("Bag full. Cannot pick more.")
		return
	_complete_one_matching_pickup_step(wanted, _active_pick_station_kind)
	inventory.add_item(wanted, null, Rect2i(), _player_item_meta(wanted))
	if hud and hud.has_method("show_kitchen_pick_feedback"):
		hud.call("show_kitchen_pick_feedback", wanted, true)
	_notify_player("Picked: " + wanted.capitalize())

func _on_inventory_delete_requested(item_uid: int) -> void:
	if inventory == null or item_uid <= 0:
		return
	for i in range(inventory.items.size()):
		var entry: Dictionary = inventory.items[i]
		if int(entry.get("uid", 0)) != item_uid:
			continue
		var removed := inventory.remove_at(i)
		var item_name := str(removed.get("name", "item")).capitalize()
		_notify_player("Deleted: " + item_name)
		return

func _complete_one_matching_pickup_step(item_name: String, station_kind: String) -> bool:
	var board = get_node_or_null("/root/TaskBoard")
	if board == null or not board.has_method("get_in_progress_tasks_for_assignee"):
		return false
	var tasks: Array[Dictionary] = board.get_in_progress_tasks_for_assignee("player")
	for task in tasks:
		var task_id := str(task.get("id", ""))
		var step_name := str(board.get_current_step_name(task_id))
		var payload: Dictionary = task.get("payload", {})
		var order_kind := str(payload.get("order_kind", "food"))
		var wanted_item := str(payload.get("display_item", "")).strip_edges().to_lower()
		if wanted_item == "":
			wanted_item = str(payload.get("food_item", payload.get("drink_item", ""))).strip_edges().to_lower()
		if step_name != "PICKUP_FROM_KITCHEN":
			continue
		if station_kind != "" and order_kind != station_kind:
			continue
		if wanted_item != item_name:
			continue
		board.complete_current_step(task_id, "PICKUP_FROM_KITCHEN")
		return true
	return false

func _notify_player(text: String) -> void:
	var hud := _get_hud()
	if hud and hud.has_method("show_quick_notice"):
		hud.call("show_quick_notice", text)

func _setup_holding_bar() -> void:
	if _holding_bar_root != null:
		return
	_holding_bar_root = Node2D.new()
	_holding_bar_root.name = "HoldingBar"
	_holding_bar_root.position = Vector2(0.0, -98.0)
	_holding_bar_root.z_as_relative = false
	_holding_bar_root.z_index = 42
	add_child(_holding_bar_root)

	_holding_bar_panel = PanelContainer.new()
	_holding_bar_panel.visible = false
	_holding_bar_root.add_child(_holding_bar_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.40, 0.86, 0.48, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_holding_bar_panel.add_theme_stylebox_override("panel", style)

	_holding_bar_icons = HBoxContainer.new()
	_holding_bar_icons.add_theme_constant_override("separation", 8)
	_holding_bar_panel.add_child(_holding_bar_icons)

func _on_inventory_changed(items: Array) -> void:
	_refresh_holding_bar(items)

func _refresh_holding_bar(items: Array) -> void:
	if _holding_bar_panel == null or _holding_bar_icons == null:
		return
	for child in _holding_bar_icons.get_children():
		_holding_bar_icons.remove_child(child)
		child.free()
	if items.is_empty():
		_holding_bar_panel.visible = false
		return
	for raw_item in items:
		var item: Dictionary = raw_item
		var icon_texture := _holding_bar_texture_for(str(item.get("name", "")))
		if icon_texture == null:
			continue
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(24, 24)
		icon.size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = icon_texture
		_holding_bar_icons.add_child(icon)
	var visible_count := _holding_bar_icons.get_child_count()
	if visible_count == 0:
		_holding_bar_panel.visible = false
		return
	var bar_size := _holding_bar_panel.get_combined_minimum_size()
	_holding_bar_panel.size = bar_size
	_holding_bar_panel.position = Vector2(-bar_size.x * 0.5, -bar_size.y * 0.5)
	_holding_bar_panel.visible = true

func _holding_bar_texture_for(item_name: String) -> Texture2D:
	var key := item_name.strip_edges().to_lower()
	if _holding_bar_textures.has(key):
		return _holding_bar_textures.get(key, null)
	var path := str(HOLDING_BAR_ICON_PATHS.get(key, "")).strip_edges()
	if path == "":
		return null
	var loaded := load(path)
	if loaded == null or not (loaded is Texture2D):
		push_warning("[HumanServer] Failed to load holding bar icon: %s" % path)
		return null
	var texture := loaded as Texture2D
	_holding_bar_textures[key] = texture
	return texture

func _cleanup_holding_bar_resources() -> void:
	if _holding_bar_icons != null and is_instance_valid(_holding_bar_icons):
		for child in _holding_bar_icons.get_children():
			if child is TextureRect:
				(child as TextureRect).texture = null
	_holding_bar_textures.clear()
	if _holding_bar_root != null and is_instance_valid(_holding_bar_root):
		if _holding_bar_root.get_parent() != null:
			_holding_bar_root.get_parent().remove_child(_holding_bar_root)
		_holding_bar_root.free()
	_holding_bar_icons = null
	_holding_bar_panel = null
	_holding_bar_root = null

func _player_item_meta(item_name: String, extra: Dictionary = {}) -> Dictionary:
	var now_ms := Time.get_ticks_msec()
	var meta := {
		"item_owner": "player",
		"item_name": item_name,
		"picked_up_at_ms": now_ms,
		"expires_at_ms": now_ms + PLAYER_ITEM_TTL_MS
	}
	for key in extra.keys():
		meta[key] = extra[key]
	return meta

func _expire_stale_inventory_items() -> void:
	if inventory == null or inventory.items.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	var kept: Array = []
	var expired_names: Array[String] = []
	for raw_entry in inventory.items:
		var entry: Dictionary = raw_entry
		var expires_at_ms := int(entry.get("expires_at_ms", 0))
		if expires_at_ms > 0 and now_ms >= expires_at_ms:
			expired_names.append(str(entry.get("name", "item")).capitalize())
			continue
		kept.append(entry)
	if expired_names.is_empty():
		return
	inventory.items = kept
	inventory.emit_signal("inventory_changed", inventory.items)
	if expired_names.size() == 1:
		_notify_player("%s expired in your bag." % expired_names[0])
	else:
		_notify_player("%d items expired in your bag." % expired_names.size())

func _nearest_pickup_station_kind() -> String:
	var nearest_kind := ""
	var nearest_dist := PICKUP_STATION_RADIUS
	for node in get_tree().get_nodes_in_group("food_pickup_station"):
		if not (node is Node2D):
			continue
		var d := global_position.distance_to(_pickup_station_world_position(node as Node2D))
		if d <= nearest_dist:
			nearest_dist = d
			nearest_kind = "food"
	for node in get_tree().get_nodes_in_group("drink_pickup_station"):
		if not (node is Node2D):
			continue
		var d := global_position.distance_to(_pickup_station_world_position(node as Node2D))
		if d <= nearest_dist:
			nearest_dist = d
			nearest_kind = "drink"
	return nearest_kind

func _pickup_station_world_position(station: Node2D) -> Vector2:
	var sprite := station.get_node_or_null("Sprite2D")
	if sprite != null and sprite is Node2D:
		return (sprite as Node2D).global_position
	return station.global_position
