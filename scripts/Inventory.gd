# Inventory.gd
extends Node
class_name Inventory

signal inventory_changed(items: Array)

@export var capacity: int = 2
var items: Array = []  # 每个元素: {name, atlas, region}

func is_full() -> bool:
	if items.size() >= capacity:
		return true
	return false

func add_item(item_name: String, atlas: Texture2D, region: Rect2i) -> bool:
	if is_full():
		print("[Inventory] full, cannot add: ", item_name)
		return false
	items.append({"name": item_name, "atlas": atlas, "region": region})
	print("[Inventory] added: ", item_name, "  now=", items.size(), "/", capacity)
	emit_signal("inventory_changed", items)
	return true

func find_item(partial_name: String) -> int:
	for i in range(items.size()):
		var iname = items[i].get("name", "").to_lower()
		if partial_name.to_lower() in iname:
			return i
	return -1

func remove_last() -> Dictionary:
	if items.is_empty():
		return {}
	var item = items.pop_back()
	emit_signal("inventory_changed", items)
	return item
