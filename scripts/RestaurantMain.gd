extends Node2D

var all_locations: Dictionary = {}

func _ready() -> void:
	_init_item_display_names()
	_discover_all_locations()
	_force_collision_policy()
	_build_runtime_nav_floor_from_walls()
	_enable_tilemap_navigation_sources()

	var nav_region := get_node_or_null("Navigation2D") as NavigationRegion2D
	if nav_region:
		nav_region.enabled = false

	await get_tree().physics_frame
	await get_tree().physics_frame
	await _setup_navigation()
	_register_customer_spawner()

func _init_item_display_names() -> void:
	var item1 = get_node_or_null("InteractiveItems/Item1")
	if item1:
		item1.display_name = "hotdog"
	var item2 = get_node_or_null("InteractiveItems/Item2")
	if item2:
		item2.display_name = "pizza"
	var item4 = get_node_or_null("InteractiveItems/Item4")
	if item4:
		item4.display_name = "sandwich"

func _discover_all_locations() -> void:
	all_locations.clear()
	var markers_node = get_node_or_null("LocationMarkers")
	if markers_node:
		for child in markers_node.get_children():
			if child is Marker2D:
				all_locations[child.name] = child.global_position
	print("[Restaurant] Total locations: ", all_locations.keys())

func get_all_locations() -> Dictionary:
	return all_locations

func get_location(location_name: String) -> Vector2:
	return all_locations.get(location_name, Vector2.ZERO)

func _setup_navigation() -> void:
	var world_map: RID = get_world_2d().navigation_map
	await _wait_for_navigation_sync(world_map, 120)

func _wait_for_navigation_sync(nav_map: RID, max_physics_frames: int = 90) -> bool:
	for _i in range(max_physics_frames):
		if NavigationServer2D.map_get_iteration_id(nav_map) > 0:
			return true
		await get_tree().physics_frame
	return false

func _register_customer_spawner() -> void:
	var spawner = get_node_or_null("CustomerSpawner")
	if not spawner:
		return
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("register_customer_spawner"):
		game_manager.register_customer_spawner(spawner)

func _node_has_property(node: Object, prop_name: String) -> bool:
	for p in node.get_property_list():
		if str(p.get("name", "")) == prop_name:
			return true
	return false

func _enable_tilemap_navigation_sources() -> void:
	var enabled_count := 0
	var disabled_count := 0
	var tilemap_root := get_node_or_null("TileMap")
	if tilemap_root == null:
		return

	var stack: Array = [tilemap_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)

		if _node_has_property(n, "navigation_enabled"):
			var should_enable := (n is TileMapLayer) and String(n.name) == "__NavFloorRuntime"
			n.set("navigation_enabled", should_enable)
			if should_enable:
				enabled_count += 1
			else:
				disabled_count += 1
		if _node_has_property(n, "navigation_visibility_mode"):
			n.set("navigation_visibility_mode", 0)
		if _node_has_property(n, "navigation_layers"):
			n.set("navigation_layers", 1)

	print("[Restaurant][NavSource] enabled=", enabled_count, " disabled=", disabled_count)

func _build_runtime_nav_floor_from_walls() -> void:
	var tilemap_root := get_node_or_null("TileMap") as Node
	if tilemap_root == null:
		return

	var floor := tilemap_root.get_node_or_null("LayerFloor") as TileMapLayer
	var walls := tilemap_root.get_node_or_null("LayerWalls") as TileMapLayer
	if floor == null:
		return

	var old_runtime := tilemap_root.get_node_or_null("__NavFloorRuntime")
	if old_runtime:
		old_runtime.queue_free()

	var nav_floor := floor.duplicate() as TileMapLayer
	if nav_floor == null:
		return
	nav_floor.name = "__NavFloorRuntime"
	nav_floor.visible = false
	nav_floor.y_sort_enabled = false
	nav_floor.z_index = -100
	var removed := 0
	var blockers: Array[TileMapLayer] = []
	if walls:
		blockers.append(walls)
	var furniture_carpet := tilemap_root.get_node_or_null("LayerFurnitureCarpet") as TileMapLayer
	var furniture_bot := tilemap_root.get_node_or_null("LayerFurnitureCarpet/LayerFurnitureBot") as TileMapLayer
	var furniture_top := tilemap_root.get_node_or_null("LayerFurnitureCarpet/LayerFurnitureBot/LayerFurnitureTop") as TileMapLayer
	if furniture_carpet:
		blockers.append(furniture_carpet)
	if furniture_bot:
		blockers.append(furniture_bot)
	if furniture_top:
		blockers.append(furniture_top)

	var blocker_cells := {}
	for layer in blockers:
		for c in layer.get_used_cells():
			blocker_cells[c] = true

	for c in blocker_cells.keys():
		var cell := c as Vector2i
		if nav_floor.get_cell_source_id(cell) != -1:
			nav_floor.erase_cell(cell)
			removed += 1
	tilemap_root.add_child(nav_floor)
	print("[Restaurant][NavCarve] removed_blocker_cells=", removed, " blocker_layers=", blockers.size())

func _force_collision_policy() -> void:
	var tilemap_root := get_node_or_null("TileMap")
	if tilemap_root == null:
		return
	var nonwall_paths := [
		"LayerFloor",
		"LayerFurnitureCarpet",
		"LayerFurnitureCarpet/LayerFurnitureBot",
		"LayerFurnitureCarpet/LayerFurnitureBot/LayerFurnitureTop",
		"__NavFloorRuntime"
	]
	for p in nonwall_paths:
		var layer := tilemap_root.get_node_or_null(p)
		if layer and _node_has_property(layer, "collision_enabled"):
			layer.set("collision_enabled", false)
	var walls := tilemap_root.get_node_or_null("LayerWalls")
	if walls and _node_has_property(walls, "collision_enabled"):
		walls.set("collision_enabled", true)
