extends Node2D

# Global location data - accessible by all characters
var all_locations: Dictionary = {}

func _ready():
	# 0. Initialize Item Names
	var item1 = get_node_or_null("InteractiveItems/Item1")
	if item1:
		item1.display_name = "hotdog"
		print("[Restaurant] Set Item1 display_name to 'hotdog'")

	var item2 = get_node_or_null("InteractiveItems/Item2")
	if item2:
		item2.display_name = "pizza"
		print("[Restaurant] Set Item2 display_name to 'pizza'")

	var item3 = get_node_or_null("InteractiveItems/Item3")
	if item3:
		item3.display_name = "skewers"
		print("[Restaurant] Set Item3 display_name to 'skewers'")

	var item4 = get_node_or_null("InteractiveItems/Item4")
	if item4:
		item4.display_name = "sandwich"
		print("[Restaurant] Set Item4 display_name to 'sandwich'")

	# 1. IMMEDIATELY discover all locations before anything else
	_discover_all_locations()

	# 2. Find the NavigationRegion2D
	var nav_region = $Navigation2D
	if nav_region:
		_bind_navigation_map_to_world()
		_setup_and_bake_navigation(nav_region)
	else:
		print("[Restaurant] NavigationRegion2D not found!")
	
	# 3. Register CustomerSpawner with GameManager
	_register_customer_spawner()

func _discover_all_locations():
	print("[Restaurant] Discovering ALL locations at startup...")
	
	var markers_node = get_node_or_null("LocationMarkers")
	if markers_node:
		for child in markers_node.get_children():
			if child is Marker2D:
				all_locations[child.name] = child.global_position
				print("  -> ", child.name, " at ", child.global_position)
	
	print("[Restaurant] Total locations: ", all_locations.keys())

# Static accessor for other scripts to get locations
func get_all_locations() -> Dictionary:
	return all_locations

func get_location(location_name: String) -> Vector2:
	return all_locations.get(location_name, Vector2.ZERO)

func _setup_and_bake_navigation(region: NavigationRegion2D):
	# DON'T create NavMesh in code - it doesn't work properly
	# Instead, just verify what exists and debug

	var nav_map = get_world_2d().navigation_map
	var nav_ready := await _wait_for_navigation_sync(nav_map)
	if not nav_ready:
		print("[Restaurant] Navigation map sync timeout. Skip startup nav query.")
		return
	
	var poly = region.navigation_polygon
	if not poly:
		print("[Restaurant] ERROR: No NavigationPolygon in scene!")
		return
	
	print("[Restaurant] Using scene NavigationPolygon:")
	print("  - Polygons: ", poly.get_polygon_count())
	print("  - Vertices: ", poly.vertices.size())
	print("  - Outlines: ", poly.get_outline_count())
	print("  - Map active: ", NavigationServer2D.map_is_active(nav_map))

func _bind_navigation_map_to_world() -> void:
	var world_map := get_world_2d().navigation_map
	var nav_regions := find_children("*", "NavigationRegion2D", true, false)
	for node in nav_regions:
		if node is NavigationRegion2D:
			(node as NavigationRegion2D).set_navigation_map(world_map)

	var nav_agents := find_children("*", "NavigationAgent2D", true, false)
	for node in nav_agents:
		if node is NavigationAgent2D:
			(node as NavigationAgent2D).set_navigation_map(world_map)

func _wait_for_navigation_sync(nav_map: RID, max_physics_frames: int = 60) -> bool:
	for _i in range(max_physics_frames):
		var iteration_id := NavigationServer2D.map_get_iteration_id(nav_map)
		if iteration_id > 0:
			return true
		await get_tree().physics_frame
	return false

func _recursively_add_to_group(node: Node, group: String):
	# Exclude Doors from the navigation mesh source so they don't cut holes in the mesh.
	# This allows the robot to plan a path *through* the door, but get blocked by physics,
	# which triggers the "Stuck" -> "Ask Help" logic.
	if "Door" in node.name:
		print("[Restaurant] Excluding ", node.name, " from nav bake.")
		return

	node.add_to_group(group)
	for child in node.get_children():
		_recursively_add_to_group(child, group)

func _register_customer_spawner():
	# Find CustomerSpawner in scene
	var spawner = get_node_or_null("CustomerSpawner")
	if not spawner:
		print("[Restaurant] CustomerSpawner not found in scene!")
		return
	
	# Register with GameManager (Autoload)
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("register_customer_spawner"):
		game_manager.register_customer_spawner(spawner)
		print("[Restaurant] CustomerSpawner registered with GameManager")
	else:
		print("[Restaurant] GameManager not found or doesn't have register_customer_spawner method")
