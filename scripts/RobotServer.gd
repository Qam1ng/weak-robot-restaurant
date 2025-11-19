# RobotServer.gd  (Godot 4.x)
extends CharacterBody2D
class_name RobotServer

# ---------- Movement / spawn ----------
@export var spawn_path: NodePath
@export var move_speed: float = 120.0
@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var anim: AnimatedSprite2D   = $AnimatedSprite2D
var _moving: bool = false
var _last_dir: Vector2 = Vector2.DOWN

# ---------- BT (方案B：preload 脚本作命名空间) ----------
const Core = preload("res://scripts/bt/bt_core.gd")
const Act  = preload("res://scripts/bt/bt_actions.gd")
const BTRunnerScript = preload("res://scripts/bt/bt_runner.gd")
@onready var bt_runner := BTRunnerScript.new()

# ---------- OpenAI ----------
const OPENAI_URL: String = "https://api.openai.com/v1/chat/completions"
const OPENAI_MODEL: String = "gpt-4o-mini"
var OPENAI_KEY: String = OS.get_environment("OPENAI_API_KEY")
@onready var http: HTTPRequest = $HTTPRequest

func _ready() -> void:
	add_to_group("robot")

	# spawn
	if spawn_path != NodePath():
		var rs := get_node(spawn_path) as Node2D
		global_position = rs.global_position

	# navigation / avoidance wiring
	await get_tree().physics_frame
	agent.avoidance_enabled = true
	agent.max_speed = move_speed
	agent.velocity_computed.connect(_on_agent_velocity_computed) # safe velocity callback

	# customer wiring
	_connect_all_customers()
	get_tree().node_added.connect(_on_node_added)

	# HTTP callback
	http.request_completed.connect(_on_http_completed)

	# ---------- build Behavior Tree ----------
	var get_req   = Act.ActGetRequest.new()
	var parse_req = Act.ActParseRequest.new()
	var exec_req  = Act.ActExecuteRequest.new()

	var seq := Core.Sequence.new()
	var timeout := Core.Timeout.new(15.0)   # 执行超 15 秒则失败，转入求助
	timeout.child = exec_req
	seq.children = [get_req, parse_req, timeout]

	var send_help := Act.ActSendRequest.new()
	var root := Core.Selector.new()
	root.children = [seq, send_help]

	bt_runner.root = root
	bt_runner.bb = {
		"counter_pos": Vector2(500, 160),   # TODO: 换成你 Counter 的 Marker2D 坐标
		"carrying_item": false
	}
	add_child(bt_runner)

func _physics_process(_dt: float) -> void:
	# 由 BT 的 ActNavigate 负责 agent.set_velocity();
	# 这里只根据方向切动画，避免重复 set_velocity。
	if not _moving:
		_update_anim(Vector2.ZERO)
		return

	var next: Vector2 = agent.get_next_path_position()
	var to_next: Vector2 = next - global_position
	var preview_dir: Vector2 = Vector2.ZERO
	if to_next.length() > 1e-3:
		preview_dir = to_next.normalized() * move_speed
	_update_anim(preview_dir)

# safe velocity from avoidance (把“移动”放在这里)
func _on_agent_velocity_computed(safe_velocity: Vector2) -> void:
	if not _moving:
		agent.set_velocity(Vector2.ZERO)
		return
	velocity = safe_velocity
	move_and_slide()

# ---------- Customer wiring ----------
func _connect_all_customers() -> void:
	var customers: Array = get_tree().get_nodes_in_group("customer")
	print("[RobotServer] customers in scene:", customers.size())
	for c in customers:
		_connect_customer(c)

func _on_node_added(n: Node) -> void:
	if n.is_in_group("customer"):
		_connect_customer(n)

func _connect_customer(c: Node) -> void:
	if c.has_signal("request_emitted"):
		if not c.request_emitted.is_connected(_on_customer_request):
			c.request_emitted.connect(_on_customer_request, CONNECT_DEFERRED)

# ---------- When a customer requests ----------
func _on_customer_request(customer: Node) -> void:
	# 将“目标顾客 + 原始请求”写入黑板；由 BT 去导航/取放物/求助
	bt_runner.bb["target_customer"] = customer as Node2D
	bt_runner.bb["request_text"]    = "Please bring me a bowl of beef soup."
	_moving = true  # 允许 velocity_computed 驱动移动 & 播放行走动画

	# 保留你的 LLM 解析（BT 的 Parse 节点会等待结果入黑板）
	_call_openai_for_task("Can I order a pizza?")

# ---------- OpenAI call + parsing ----------
func _call_openai_for_task(request_text: String) -> void:
	if OPENAI_KEY == "":
		push_error("OPENAI_API_KEY not set.")
		return

	var sys: String = """
You are a restaurant service robot. Output ONLY valid JSON with two fields:
{"reply_to_customer": string,
 "task_parser": {"task_type": string, "substeps": string[], "preconditions": string[]}}
Do not include markdown or any extra text.
"""
	var user_text: String = "Customer request: " + request_text + " First, provide a short acknowledgement to the customer. Then parse the task into executable substeps."

	var payload: Dictionary = {
		"model": OPENAI_MODEL,
		"response_format": {"type": "json_object"},
		"messages": [
			{"role":"system", "content": sys},
			{"role":"user", "content": user_text}
		],
		"temperature": 0.2
	}

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + OPENAI_KEY
	])

	var err: int = http.request(OPENAI_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		push_error("HTTP request failed: " + str(err))

func _on_http_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code < 200 or code >= 300:
		push_error("OpenAI HTTP status: " + str(code))
		return

	var txt: String = body.get_string_from_utf8()
	var top_var = JSON.parse_string(txt)
	if typeof(top_var) != TYPE_DICTIONARY:
		push_error("Invalid OpenAI response"); return
	var top: Dictionary = top_var

	var choices: Array = top.get("choices", [])
	if choices.is_empty():
		push_error("No choices in OpenAI response"); return
	var message: Dictionary = choices[0].get("message", {}) as Dictionary
	var content_str: String = str(message.get("content", ""))
	var obj_var = JSON.parse_string(content_str)
	if typeof(obj_var) != TYPE_DICTIONARY:
		push_error("Model content is not valid JSON"); return
	var obj: Dictionary = obj_var

	var reply: String = str(obj.get("reply_to_customer", "Okay, one moment."))
	var parser: Dictionary = (obj.get("task_parser", {}) as Dictionary)
	print("[RobotServer] reply_to_customer -> ", reply)
	print("[RobotServer] task_parser -> ", parser)

	# 把 LLM 解析结果回写到黑板，BT 的 Parse 节点会转入 SUCCESS
	bt_runner.bb["task_parser"] = parser
	bt_runner.bb["item_name"]   = "beef_soup"  # 如需可按 parser 推断具体物品

# ---------- Anim helper ----------
func _update_anim(v: Vector2) -> void:
	var moving := v.length() > 1.0
	if moving:
		_last_dir = v

	var dir_name := ""
	if abs(_last_dir.x) > abs(_last_dir.y):
		dir_name = "right" if _last_dir.x > 0.0 else "left"
	else:
		dir_name = "down" if _last_dir.y > 0.0 else "up"

	var anim_name := ("walk_" + dir_name) if moving else ("idle_" + dir_name)
	if anim.animation != anim_name:
		anim.play(anim_name)

# ---------- Hooks for BT actions ----------
func speak(text: String) -> void:
	print(text)  # TODO: 可接入你的气泡 UI 或 TTS

func _bt_start_parse_request(req_text: String) -> void:
	_call_openai_for_task(req_text)
