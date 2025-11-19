extends Resource
class_name BT

enum Status { SUCCESS, FAILURE, RUNNING }

class Task:
	func tick(_bb: Dictionary, _actor: Node) -> int:
		return Status.SUCCESS

class Composite extends Task:
	var children: Array[Task] = []

class Sequence extends Composite:
	var _i: int = 0
	func tick(bb: Dictionary, actor: Node) -> int:
		while _i < children.size():
			var s: int = children[_i].tick(bb, actor)
			if s == Status.RUNNING:
				return Status.RUNNING
			if s == Status.FAILURE:
				_i = 0
				return Status.FAILURE
			_i += 1
		_i = 0
		return Status.SUCCESS

class Selector extends Composite:
	var _i: int = 0
	func tick(bb: Dictionary, actor: Node) -> int:
		while _i < children.size():
			var s: int = children[_i].tick(bb, actor)
			if s == Status.RUNNING:
				return Status.RUNNING
			if s == Status.SUCCESS:
				_i = 0
				return Status.SUCCESS
			_i += 1
		_i = 0
		return Status.FAILURE

class Decorator extends Task:
	var child: Task = null

class Timeout extends Decorator:
	var seconds: float = 10.0
	var _start: float = -1.0

	func _init(sec: float = 10.0) -> void:
		seconds = sec

	func tick(bb: Dictionary, actor: Node) -> int:
		if _start < 0.0:
			_start = Time.get_ticks_msec() / 1000.0

		var s: int = child.tick(bb, actor)
		var now: float = Time.get_ticks_msec() / 1000.0

		if now - _start > seconds:
			_start = -1.0
			return Status.FAILURE

		if s != Status.RUNNING:
			_start = -1.0

		return s
