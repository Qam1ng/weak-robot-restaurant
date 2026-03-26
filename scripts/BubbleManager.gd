extends Node

signal message_emitted(speaker: String, text: String, kind: String)
signal message_emitted_with_target(target: Node2D, speaker: String, text: String, kind: String)
signal message_routed(source: Node2D, recipient: Node2D, speaker: String, text: String, kind: String, recipient_kind: String)

func say(target: Node2D, text: String, _duration_sec: float = 2.4, _color: Color = Color(1, 1, 1, 1)) -> void:
	_emit_message(target, null, text)

func say_to(source: Node2D, recipient: Node2D, text: String, _duration_sec: float = 2.4, _color: Color = Color(1, 1, 1, 1)) -> void:
	_emit_message(source, recipient, text)

func _emit_message(source: Node2D, recipient: Node2D, text: String) -> void:
	if source == null or not is_instance_valid(source):
		return
	if recipient != null and not is_instance_valid(recipient):
		recipient = null
	var content := text.strip_edges()
	if content == "":
		return
	var speaker := _speaker_name_for(source)
	var kind := _kind_for(source)
	var recipient_kind := _kind_for(recipient)
	message_emitted.emit(speaker, content, kind)
	message_emitted_with_target.emit(source, speaker, content, kind)
	message_routed.emit(source, recipient, speaker, content, kind, recipient_kind)

func _speaker_name_for(target: Node2D) -> String:
	if target == null or not is_instance_valid(target):
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
