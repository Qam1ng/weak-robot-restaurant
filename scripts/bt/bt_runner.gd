# res://scripts/bt/bt_runner.gd
extends Node
class_name BTRunner

const Core = preload("res://scripts/bt/bt_core.gd")  # 一定要在类型注解前

var root: Core.Task = null
var bb: Dictionary = {}
var actor: Node = null   # 由外部（RobotServer）赋值

func _physics_process(_dt: float) -> void:
	if root == null or actor == null:
		return
	var s: int = root.tick(bb, actor)
	if s == Core.Status.FAILURE and actor.has_method("speak"):
		actor.speak("[Robot] Task failed, requesting help…")
