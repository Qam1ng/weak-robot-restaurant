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
	
	# 等待 NavigationServer 完成地图同步
	for i in range(5):
		await get_tree().physics_frame
	
	var poly = region.navigation_polygon
	if not poly:
		print("[Restaurant] ERROR: No NavigationPolygon in scene!")
		return
	
	var nav_map = region.get_navigation_map()
	print("[Restaurant] Using scene NavigationPolygon:")
	print("  - Polygons: ", poly.get_polygon_count())
	print("  - Vertices: ", poly.vertices.size())
	print("  - Outlines: ", poly.get_outline_count())
	print("  - Map active: ", NavigationServer2D.map_is_active(nav_map))
	
	# Test navigation
	var robot_pos = Vector2(99, -84)
	var pizza_pos = Vector2(-168, -328)
	
	var closest_robot = NavigationServer2D.map_get_closest_point(nav_map, robot_pos)
	var closest_pizza = NavigationServer2D.map_get_closest_point(nav_map, pizza_pos)
	
	print("  Robot ", robot_pos, " -> ", closest_robot)
	print("  Pizza ", pizza_pos, " -> ", closest_pizza)
	
	var path = NavigationServer2D.map_get_path(nav_map, robot_pos, pizza_pos, true)
	print("  Path: ", path.size(), " waypoints")
	
	if path.size() == 0:
		print("[Restaurant] No path found - NavMesh is disconnected or invalid")

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
