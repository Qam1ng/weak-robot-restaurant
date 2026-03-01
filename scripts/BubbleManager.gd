extends Node

signal message_emitted(speaker: String, text: String, kind: String)

func say(target: Node2D, text: String, _duration_sec: float = 2.4, _color: Color = Color(1, 1, 1, 1)) -> void:
	if target == null or not is_instance_valid(target):
		return
	var content := text.strip_edges()
	if content == "":
		return
	var speaker := _speaker_name_for(target)
	var kind := _kind_for(target)
	message_emitted.emit(speaker, content, kind)

func _speaker_name_for(target: Node2D) -> String:
	if target == null:
		return "System"
	if target.is_in_group("robot"):
		return "Robot"
	if target.is_in_group("customer"):
		return "Customer"
	if target.is_in_group("player"):
		return "Player"
	return target.name

func _kind_for(target: Node2D) -> String:
	if target == null:
		return "system"
	if target.is_in_group("robot"):
		return "robot"
	if target.is_in_group("customer"):
		return "customer"
	if target.is_in_group("player"):
		return "player"
	return "system"
