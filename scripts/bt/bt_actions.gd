# res://scripts/bt/bt_actions.gd
extends Resource
class_name BT_Actions

const Core = preload("res://scripts/bt/bt_core.gd")
# 约定黑板键：
# request_text: String
# task_parser: Dictionary
# target_customer: Node2D
# counter_pos: Vector2
# target_pos: Vector2
# carrying_item: bool
# item_name: String

# 导航：把 bb.target_pos 作为目标
class ActNavigate extends Core.Task:
	func tick(bb: Dictionary, actor: Node) -> int:
		if not bb.has("target_pos"):
			return Core.Status.FAILURE

		var agent: NavigationAgent2D = actor.get_node("NavigationAgent2D")
		agent.avoidance_enabled = true
		agent.max_speed = actor.move_speed
		agent.target_position = bb.target_pos

		var next: Vector2 = agent.get_next_path_position()
		var to_next: Vector2 = next - actor.global_position
		var desired := Vector2.ZERO
		if to_next.length() > 1e-3:
			desired = to_next.normalized() * actor.move_speed

		# 交给导航服处理，稍后在 velocity_computed 用 safe_velocity 来移动
		agent.set_velocity(desired)  # 文档：提交速度 → 触发 velocity_computed。:contentReference[oaicite:3]{index=3}

		if actor.global_position.distance_to(bb.target_pos) < 8.0:
			return Core.Status.SUCCESS
		return Core.Status.RUNNING

# 取物：把 carrying_item 设为 true
class ActPickItem extends Core.Task:
	func tick(bb: Dictionary, actor: Node) -> int:
		if bb.get("carrying_item", false):
			return Core.Status.SUCCESS
		bb.carrying_item = true
		bb.item_name = bb.get("item_name", "beef_soup")
		actor.speak("[Robot] Picked " + bb.item_name)
		return Core.Status.SUCCESS

# 放物：把 carrying_item 清空
class ActDropItem extends Core.Task:
	func tick(bb: Dictionary, actor: Node) -> int:
		if not bb.get("carrying_item", false):
			return Core.Status.SUCCESS
		bb.carrying_item = false
		actor.speak("[Robot] Delivered " + str(bb.item_name))
		return Core.Status.SUCCESS

# 说话：支持直接文本或从黑板取键
class ActSpeak extends Core.Task:
	var text_key := ""
	func _init(k: String = "") -> void:
		text_key = k
	func tick(bb: Dictionary, actor: Node) -> int:
		var msg := text_key
		if bb.has(text_key):
			msg = str(bb[text_key])
		actor.speak(msg)
		return Core.Status.SUCCESS

# 读取请求：确保 request_text 存在
class ActGetRequest extends Core.Task:
	func tick(bb: Dictionary, _actor: Node) -> int:
		if not bb.has("target_customer"):
			return Core.Status.FAILURE
		if not bb.has("request_text") or str(bb.request_text) == "":
			bb.request_text = "Please bring me a bowl of beef soup."
		return Core.Status.SUCCESS

# 解析请求：调用机器人挂的钩子异步解析，等黑板出现 task_parser
class ActParseRequest extends Core.Task:
	var _started := false
	func tick(bb: Dictionary, actor: Node) -> int:
		if bb.has("task_parser"):
			_started = false
			return Core.Status.SUCCESS
		if not _started:
			_started = true
			actor.call_deferred("_bt_start_parse_request", bb.request_text)
			return Core.Status.RUNNING
		return Core.Status.RUNNING

# 执行请求：去取餐台→取物→去顾客→放物
class ActExecuteRequest extends Core.Task:
	var _phase := 0
	func tick(bb: Dictionary, actor: Node) -> int:
		match _phase:
			0:
				if not bb.has("counter_pos"):
					return Core.Status.FAILURE
				bb.target_pos = bb.counter_pos
				var s := ActNavigate.new().tick(bb, actor)
				if s == Core.Status.SUCCESS: _phase = 1
				return s
			1:
				var s2 := ActPickItem.new().tick(bb, actor)
				if s2 == Core.Status.SUCCESS: _phase = 2
				return s2
			2:
				if not bb.has("target_customer"):
					return Core.Status.FAILURE
				bb.target_pos = (bb.target_customer as Node2D).global_position
				var s3 := ActNavigate.new().tick(bb, actor)
				if s3 == Core.Status.SUCCESS: _phase = 3
				return s3
			3:
				var s4 := ActDropItem.new().tick(bb, actor)
				if s4 == Core.Status.SUCCESS:
					_phase = 0
					return Core.Status.SUCCESS
				return s4
		return Core.Status.RUNNING

# 求助
class ActSendRequest extends Core.Task:
	func tick(_bb: Dictionary, actor: Node) -> int:
		actor.speak("[Robot] Need human help! (stuck)")
		return Core.Status.SUCCESS
