# Inventory.gd
extends Node
class_name Inventory

signal inventory_changed(items: Array)

@export var capacity: int = 2
var items: Array = []  # 每个元素: {name, atlas, region}
var _next_item_uid: int = 1

func is_full() -> bool:
	if items.size() >= capacity:
		return true
	return false

func add_item(item_name: String, atlas: Texture2D, region: Rect2i, meta: Dictionary = {}) -> bool:
	if is_full():
		return false
	var entry := {
		"uid": _next_item_uid,
		"name": item_name,
		"atlas": atlas,
		"region": region
	}
	_next_item_uid += 1
	for key in meta.keys():
		entry[key] = meta[key]
	items.append(entry)
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

func remove_at(index: int) -> Dictionary:
	if index < 0 or index >= items.size():
		return {}
	var item: Dictionary = items.pop_at(index)
	emit_signal("inventory_changed", items)
	return item

func remove_matching(partial_name: String) -> Dictionary:
	var idx := find_item(partial_name)
	if idx == -1:
		return {}
	return remove_at(idx)
