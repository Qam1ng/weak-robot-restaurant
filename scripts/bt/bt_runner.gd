# res://scripts/bt/bt_runner.gd
extends Node
class_name BTRunner

const Core = preload("res://scripts/bt/bt_core.gd")  # 一定要在类型注解前

var root: Core.Task = null
var bb: Dictionary = {}
var actor: Node = null   # 由外部（RobotServer）赋值

func _ready() -> void:
	if get_parent():
		actor = get_parent() # Auto-assign actor if added as child

func _physics_process(_dt: float) -> void:
	if root == null or actor == null:
		return
	
	# 1. Tick the tree
	var s: int = root.tick(bb, actor)
	
	# 2. Handle result
	if s == Core.Status.FAILURE:
		# If plan failed or queue empty, we just idle (and maybe retry next frame)
		pass
	elif s == Core.Status.SUCCESS:
		# Queue finished
		pass
