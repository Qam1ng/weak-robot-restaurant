extends Node2D

var all_locations: Dictionary = {}

func _ready() -> void:
	_init_item_display_names()
	_discover_all_locations()
	_force_collision_policy()
	_build_runtime_nav_floor_from_walls()
	_enable_tilemap_navigation_sources()
	_log_tilemap_layer_coverage()

	var nav_region := get_node_or_null("Navigation2D") as NavigationRegion2D
	if nav_region:
		nav_region.enabled = false

	await get_tree().physics_frame
	await get_tree().physics_frame
	await _setup_navigation()
	call_deferred("_run_stable_nav_probes")
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

func _run_stable_nav_probes() -> void:
	# NavigationServer map sync can lag startup by a few physics frames.
	# Probe after a short delay to avoid misleading (0,0) snapshots.
	await get_tree().create_timer(0.8).timeout
	await get_tree().physics_frame
	_log_nav_connectivity_probe()
	_log_nav_components()
	_log_floor_nav_strip_diagnostics()

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
	var patched := _patch_runtime_nav_missing_tiles(nav_floor)
	# Navigation is generated from floor, then carved by blockers so pathfinding avoids them.
	# This keeps navigation behavior consistent even if some visual props have collision disabled.
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

	# TEMP DEBUG: disable runtime carve entirely for A/B testing.
	# for c in blocker_cells.keys():
	# 	var cell := c as Vector2i
	# 	if nav_floor.get_cell_source_id(cell) != -1:
	# 		nav_floor.erase_cell(cell)
	# 		removed += 1
	tilemap_root.add_child(nav_floor)
	print("[Restaurant][NavCarve] removed_blocker_cells=", removed, " blocker_layers=", blockers.size())
	print("[Restaurant][NavPatch] patched_missing_nav_tiles=", patched)
	_log_transition_cut_audit(floor, walls, nav_floor)

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

func _global_to_cell(layer: TileMapLayer, global_pos: Vector2) -> Vector2i:
	var local_pos: Vector2 = layer.to_local(global_pos)
	return layer.local_to_map(local_pos)

func _log_transition_cut_audit(floor: TileMapLayer, walls: TileMapLayer, nav_floor: TileMapLayer) -> void:
	if walls == null:
		return
	# Audit likely transition columns (kitchen item X) to detect hidden wall cells
	# that carve a hard horizontal cut in runtime nav.
	var probe_names := ["hotdog", "pizza", "sandwich"]
	var y_top_cell := _global_to_cell(floor, Vector2(0.0, -360.0)).y
	var y_bottom_cell := _global_to_cell(floor, Vector2(0.0, 40.0)).y
	for name in probe_names:
		if not all_locations.has(name):
			continue
		var p: Vector2 = all_locations[name]
		var col_x := _global_to_cell(floor, p).x
		var carved_rows: Array[int] = []
		for y in range(min(y_top_cell, y_bottom_cell), max(y_top_cell, y_bottom_cell) + 1):
			var cell := Vector2i(col_x, y)
			var floor_has := floor.get_cell_source_id(cell) != -1
			if not floor_has:
				continue
			var nav_has := nav_floor.get_cell_source_id(cell) != -1
			var wall_has := walls.get_cell_source_id(cell) != -1
			if not nav_has and wall_has:
				carved_rows.append(y)
		if carved_rows.is_empty():
			print("[Restaurant][NavCutAudit] ", name, " x_cell=", col_x, " carved_rows=[]")
		else:
			var sample := carved_rows
			if sample.size() > 12:
				sample = sample.slice(0, 12)
			print("[Restaurant][NavCutAudit] ", name, " x_cell=", col_x, " carved_rows=", sample, " total=", carved_rows.size())

func _log_tilemap_layer_coverage() -> void:
	var tilemap_root := get_node_or_null("TileMap")
	if tilemap_root == null:
		return
	var stack: Array = [tilemap_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is TileMapLayer):
			continue
		var layer := n as TileMapLayer
		var used: Array[Vector2i] = layer.get_used_cells()
		var min_y := 999999
		var max_y := -999999
		for cell in used:
			if cell.y < min_y:
				min_y = cell.y
			if cell.y > max_y:
				max_y = cell.y
		var nav_enabled := false
		if _node_has_property(layer, "navigation_enabled"):
			nav_enabled = bool(layer.get("navigation_enabled"))
		var col_enabled := false
		if _node_has_property(layer, "collision_enabled"):
			col_enabled = bool(layer.get("collision_enabled"))
		if used.is_empty():
			print("[Restaurant][Layer] name=", layer.name, " used=0 nav_enabled=", nav_enabled, " collision_enabled=", col_enabled)
		else:
			print("[Restaurant][Layer] name=", layer.name, " used=", used.size(), " y_range=[", min_y, ",", max_y, "] nav_enabled=", nav_enabled, " collision_enabled=", col_enabled)

func _log_nav_connectivity_probe() -> void:
	var nav_map: RID = get_world_2d().navigation_map
	if not nav_map.is_valid():
		return
	if all_locations.is_empty():
		return
	if not all_locations.has("RG4"):
		return

	var from_pos: Vector2 = all_locations["RG4"]
	var from_nav := NavigationServer2D.map_get_closest_point(nav_map, from_pos)
	for item_key in ["hotdog", "pizza", "sandwich"]:
		if not all_locations.has(item_key):
			continue
		var to_pos: Vector2 = all_locations[item_key]
		var to_nav := NavigationServer2D.map_get_closest_point(nav_map, to_pos)
		var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from_nav, to_nav, true, 1)
		print("[Restaurant][NavProbe] from=RG4 to=", item_key, " path_points=", path.size(), " from_raw=", from_pos, " from_nav=", from_nav, " to_raw=", to_pos, " to_nav=", to_nav)

func _is_nav_reachable(nav_map: RID, a: Vector2, b: Vector2) -> bool:
	var a_nav := NavigationServer2D.map_get_closest_point(nav_map, a)
	var b_nav := NavigationServer2D.map_get_closest_point(nav_map, b)
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a_nav, b_nav, true, 1)
	return path.size() >= 2

func _log_nav_components() -> void:
	var nav_map: RID = get_world_2d().navigation_map
	if not nav_map.is_valid():
		return
	if all_locations.is_empty():
		return

	var keys: Array[String] = []
	for k in all_locations.keys():
		keys.append(String(k))
	keys.sort()

	var adj: Dictionary = {}
	for k in keys:
		adj[k] = []

	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a_key := keys[i]
			var b_key := keys[j]
			var a_pos: Vector2 = all_locations[a_key]
			var b_pos: Vector2 = all_locations[b_key]
			if _is_nav_reachable(nav_map, a_pos, b_pos):
				(adj[a_key] as Array).append(b_key)
				(adj[b_key] as Array).append(a_key)

	var visited: Dictionary = {}
	var components: Array[Array] = []
	for k in keys:
		if visited.get(k, false):
			continue
		var comp: Array = []
		var stack: Array = [k]
		visited[k] = true
		while not stack.is_empty():
			var cur: String = String(stack.pop_back())
			comp.append(cur)
			for nxt in adj[cur]:
				var nxt_key := String(nxt)
				if visited.get(nxt_key, false):
					continue
				visited[nxt_key] = true
				stack.append(nxt_key)
		comp.sort()
		components.append(comp)

	print("[Restaurant][NavComponents] count=", components.size())
	for idx in range(components.size()):
		print("  - comp#", idx + 1, " size=", components[idx].size(), " members=", components[idx])

	if components.size() <= 1:
		return

	var best_a := ""
	var best_b := ""
	var best_dist := INF
	for ci in range(components.size()):
		for cj in range(ci + 1, components.size()):
			for a in components[ci]:
				for b in components[cj]:
					var a_key := String(a)
					var b_key := String(b)
					var d := (all_locations[a_key] as Vector2).distance_to(all_locations[b_key] as Vector2)
					if d < best_dist:
						best_dist = d
						best_a = a_key
						best_b = b_key
	if best_a != "" and best_b != "":
		print("[Restaurant][NavCutHint] nearest_cross_component_pair=", best_a, "<->", best_b, " dist_px=", int(best_dist), " a=", all_locations[best_a], " b=", all_locations[best_b])

func _patch_runtime_nav_missing_tiles(nav_floor: TileMapLayer) -> int:
	var cells: Array[Vector2i] = nav_floor.get_used_cells()
	var patched: int = 0
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell: Vector2i in cells:
		if _tile_has_nav_polygon(nav_floor, cell):
			continue
		var replaced: bool = false
		for d: Vector2i in dirs:
			var ncell: Vector2i = cell + d
			var sid: int = nav_floor.get_cell_source_id(ncell)
			if sid == -1:
				continue
			if not _tile_has_nav_polygon(nav_floor, ncell):
				continue
			var coords: Vector2i = nav_floor.get_cell_atlas_coords(ncell)
			var alt: int = nav_floor.get_cell_alternative_tile(ncell)
			nav_floor.set_cell(cell, sid, coords, alt)
			patched += 1
			replaced = true
			break
		if not replaced:
			continue
	return patched

func _tile_has_nav_polygon(layer: TileMapLayer, cell: Vector2i) -> bool:
	var sid := layer.get_cell_source_id(cell)
	if sid == -1:
		return false
	var aset := layer.tile_set
	if aset == null:
		return false
	var src = aset.get_source(sid)
	if src == null:
		return false
	if not (src is TileSetAtlasSource):
		return false
	var atlas_src := src as TileSetAtlasSource
	var coords := layer.get_cell_atlas_coords(cell)
	var alt := layer.get_cell_alternative_tile(cell)
	var td = atlas_src.get_tile_data(coords, alt)
	if td == null:
		return false
	var nav_poly = td.get_navigation_polygon(0)
	return nav_poly != null and nav_poly.get_polygon_count() > 0

func _log_floor_nav_strip_diagnostics() -> void:
	var tilemap_root := get_node_or_null("TileMap")
	if tilemap_root == null:
		return
	var floor := tilemap_root.get_node_or_null("LayerFloor") as TileMapLayer
	if floor == null:
		return
	var runtime := tilemap_root.get_node_or_null("__NavFloorRuntime") as TileMapLayer
	if runtime == null:
		return
	var probe_names := ["hotdog", "pizza", "sandwich"]
	var y_top_cell := _global_to_cell(floor, Vector2(0.0, -360.0)).y
	var y_bottom_cell := _global_to_cell(floor, Vector2(0.0, 20.0)).y
	for name in probe_names:
		if not all_locations.has(name):
			continue
		var p: Vector2 = all_locations[name]
		var col_x := _global_to_cell(floor, p).x
		var missing_floor_nav: Array[int] = []
		var missing_runtime_tile: Array[int] = []
		var missing_tile_kinds := {}
		for y in range(min(y_top_cell, y_bottom_cell), max(y_top_cell, y_bottom_cell) + 1):
			var cell := Vector2i(col_x, y)
			var floor_sid := floor.get_cell_source_id(cell)
			if floor_sid == -1:
				continue
			var floor_has_nav := _tile_has_nav_polygon(floor, cell)
			if not floor_has_nav:
				missing_floor_nav.append(y)
				var coords := floor.get_cell_atlas_coords(cell)
				var alt := floor.get_cell_alternative_tile(cell)
				var key := str(floor_sid) + ":" + str(coords) + ":" + str(alt)
				missing_tile_kinds[key] = true
			var runtime_sid := runtime.get_cell_source_id(cell)
			if runtime_sid == -1:
				missing_runtime_tile.append(y)
		var mf := missing_floor_nav
		var mr := missing_runtime_tile
		if mf.size() > 10:
			mf = mf.slice(0, 10)
		if mr.size() > 10:
			mr = mr.slice(0, 10)
		print("[Restaurant][FloorNavStrip] ", name, " x_cell=", col_x, " missing_floor_nav_rows=", mf, " total=", missing_floor_nav.size(), " missing_runtime_rows=", mr, " total=", missing_runtime_tile.size(), " missing_tile_kinds=", missing_tile_kinds.keys())
