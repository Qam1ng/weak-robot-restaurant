# Item.gd
extends Node2D
class_name Item

@export var display_name: String = "item"
@export var atlas: Texture2D        # 可空；为空时沿用编辑器里 Sprite2D.texture
@export var region: Rect2i = Rect2i(0, 0, 32, 32)
@export var override_region: bool = false  # 新增：是否用导出的 region 覆盖编辑器设置

var _player_in_range: Node = null

func _ready() -> void:
	add_to_group("interaction")

	var spr: Sprite2D = $Sprite2D

	# 仅当 atlas 非空时才改贴图；否则保留编辑器里设置好的 texture
	if atlas != null:
		spr.texture = atlas

	# 始终启用裁剪，但是否覆盖 rect 由开关决定
	spr.region_enabled = true
	if override_region:
		# 只有你明确想用导出的 region 时，才写入 rect
		spr.region_rect = Rect2(region.position, region.size)

	# 调试：运行一次看看是否是“裁到透明区”
	# print("tex=", spr.texture, " region_enabled=", spr.region_enabled, " rect=", spr.region_rect)

	# 连接 Area2D 信号（保持不变）
	if not $Area2D.body_entered.is_connected(_on_Area2D_body_entered):
		$Area2D.body_entered.connect(_on_Area2D_body_entered)
	if not $Area2D.body_exited.is_connected(_on_Area2D_body_exited):
		$Area2D.body_exited.connect(_on_Area2D_body_exited)

func on_player_interact(player: Node) -> void:
	if player != _player_in_range: return
	var inv := player.get_node_or_null("Inventory")
	if inv == null:
		print("[Item] player has no Inventory node"); return
	if inv.add_item(display_name, $Sprite2D.texture, Rect2i($Sprite2D.region_rect.position, $Sprite2D.region_rect.size)):
		queue_free()
	else:
		print("[Item] inventory full")

func _on_Area2D_body_entered(body: Node) -> void:
	if body.is_in_group("player"): _player_in_range = body

func _on_Area2D_body_exited(body: Node) -> void:
	if body == _player_in_range: _player_in_range = null
