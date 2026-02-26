# scripts/HUD.gd
extends CanvasLayer

## This script attaches to scenes/HUD.tscn root.
## Registers itself to GameManager on start.

@onready var interaction_label: Label = $InteractionLabel

# Inventory UI Elements (Dynamically created if missing)
var inventory_panel: PanelContainer
var inventory_list: VBoxContainer

func _ready():
	if Engine.has_singleton("GameManager"):
		GameManager.register_hud(self)
	else:
		pass

	if interaction_label:
		interaction_label.hide()
	
	_setup_inventory_ui()
	
	# Connect to Robot Inventory after a brief delay
	await get_tree().process_frame
	var robots = get_tree().get_nodes_in_group("robot")
	if robots.size() > 0:
		var robot = robots[0]
		var inv = robot.get_node_or_null("Inventory")
		if inv:
			inv.inventory_changed.connect(_on_robot_inventory_changed)
			_on_robot_inventory_changed(inv.items) # Init
		else:
			print("[HUD] Robot found but no Inventory node.")
	else:
		print("[HUD] No robot found in group 'robot'.")

func _setup_inventory_ui():
	# Create Panel Container for background
	inventory_panel = PanelContainer.new()
	inventory_panel.name = "InventoryPanel"
	add_child(inventory_panel)
	inventory_panel.position = Vector2(20, 60)
	
	# Add style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	inventory_panel.add_theme_stylebox_override("panel", style)
	
	# Create VBox inside
	inventory_list = VBoxContainer.new()
	inventory_panel.add_child(inventory_list)
	
	var title = Label.new()
	title.text = "ROBOT INVENTORY"
	title.add_theme_color_override("font_color", Color.YELLOW)
	inventory_list.add_child(title)

func _on_robot_inventory_changed(items: Array):
	if not inventory_list: return
	
	# Clear old items (except title at index 0)
	for i in range(inventory_list.get_child_count() - 1, 0, -1):
		inventory_list.get_child(i).queue_free()
		
	if items.is_empty():
		var l = Label.new()
		l.text = "(Empty)"
		l.add_theme_color_override("font_color", Color.GRAY)
		inventory_list.add_child(l)
	else:
		for i in range(items.size()):
			var item = items[i]
			var l = Label.new()
			var n = item.get("name", "Unknown")
			# Stack visualization: index 0 is bottom, last index is top
			l.text = "[%d] %s" % [i + 1, n]
			inventory_list.add_child(l)

func on_interaction_prompt(do_show: bool, text: String):
	if not interaction_label:
		return

	if do_show:
		interaction_label.text = text
		interaction_label.show()
	else:
		interaction_label.hide()
