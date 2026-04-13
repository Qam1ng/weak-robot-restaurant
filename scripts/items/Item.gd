# Item.gd
extends Node2D
class_name Item

@export var display_name: String = "item"
@export var atlas: Texture2D
@export var region: Rect2i = Rect2i(0, 0, 32, 32)
@export var override_region: bool = false
@export var kitchen_only_pickup: bool = true
@export var allow_manual_player_pickup: bool = false

var _player_in_range: Node = null

func _ready() -> void:
	add_to_group("interaction")

	var spr: Sprite2D = $Sprite2D


	if atlas != null:
		spr.texture = atlas


	spr.region_enabled = true
	if override_region:

		spr.region_rect = Rect2(region.position, region.size)


	# print("tex=", spr.texture, " region_enabled=", spr.region_enabled, " rect=", spr.region_rect)


	if not $Area2D.body_entered.is_connected(_on_Area2D_body_entered):
		$Area2D.body_entered.connect(_on_Area2D_body_entered)
	if not $Area2D.body_exited.is_connected(_on_Area2D_body_exited):
		$Area2D.body_exited.connect(_on_Area2D_body_exited)

func on_player_interact(player: Node) -> void:
	if not allow_manual_player_pickup:
		return
	if player != _player_in_range: return
	if kitchen_only_pickup and player.global_position.y >= -150.0:
		return
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
