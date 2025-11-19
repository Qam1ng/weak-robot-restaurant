# Inventory.gd
extends Node
class_name Inventory

@export var capacity: int = 2
var items: Array = []  # 每个元素: {name, atlas, region}

func is_full() -> bool:
	if items.size() >= capacity:
		return true
	return false

func add_item(name: String, atlas: Texture2D, region: Rect2i) -> bool:
	if is_full():
		print("[Inventory] full, cannot add: ", name)
		return false
	items.append({"name": name, "atlas": atlas, "region": region})
	print("[Inventory] added: ", name, "  now=", items.size(), "/", capacity)
	return true

func remove_last() -> Dictionary:
	if items.is_empty():
		return {}
	return items.pop_back()
