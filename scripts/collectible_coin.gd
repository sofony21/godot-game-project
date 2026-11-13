@tool
extends Area2D

const CONFIG := preload("res://scripts/game_config.gd")
const STACK_GOLD_TEXTURE := preload("res://assets/coin_body.svg")

@onready var art: Sprite2D = $CoinArt
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var elapsed := 0.0
var collected := false
var shine: Polygon2D
var base_art_y := 0.0
var map_coin_scale := CONFIG.MAP_COIN_SCALE

func _ready() -> void:
	add_to_group("coin")
	set_notify_transform(true)
	body_entered.connect(_on_body_entered)
	art.scale = Vector2.ONE * map_coin_scale
	var hitbox := (collision_shape.shape as RectangleShape2D).duplicate() as RectangleShape2D
	hitbox.size = Vector2.ONE * CONFIG.MAP_COIN_HITBOX_SIZE * map_coin_scale
	collision_shape.shape = hitbox
	base_art_y = art.position.y
	shine = art.get_node_or_null("CoinShine") as Polygon2D
	if shine == null:
		shine = Polygon2D.new()
		shine.name = "CoinShine"
		shine.polygon = PackedVector2Array([
			Vector2(-2.0, -2.0), Vector2(2.0, -2.0),
			Vector2(2.0, 2.0), Vector2(-2.0, 2.0),
		])
		shine.color = Color("#fffbe0")
		shine.position = Vector2(-32.0, 16.0)
		shine.rotation = -PI / 4.0
		shine.visible = false
		art.add_child(shine)
	if Engine.is_editor_hint():
		for warning in _get_configuration_warnings():
			push_warning("Coin '%s': %s" % [name, warning])

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_inside_tree():
		return warnings
	var half_size := CONFIG.MAP_COIN_HITBOX_SIZE * map_coin_scale * 0.5
	var coin_bounds := Rect2(global_position - Vector2.ONE * half_size, Vector2.ONE * half_size * 2.0)
	for group_name in ["platform", "ground", "safe", "wallet", "pit", "portal"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node == self:
				continue
			var object_bounds := _collision_bounds(node)
			if object_bounds.size == Vector2.ZERO:
				continue
			var overlap := coin_bounds.intersection(object_bounds)
			if overlap.size.x > 1.0 and overlap.size.y > 1.0:
				warnings.append("Coin '%s' overlaps %s '%s'. Its current position is preserved." % [name, group_name, node.name])
	return warnings

func _collision_bounds(object: Node) -> Rect2:
	var bounds := Rect2()
	var found_shape := false
	var shapes: Array[Node] = []
	_collect_collision_shapes(object, shapes)
	for shape_node in shapes:
		var collision := shape_node as CollisionShape2D
		if collision == null or collision.shape == null or collision.disabled:
			continue
		var dimensions := Vector2.ZERO
		if collision.shape is RectangleShape2D:
			dimensions = (collision.shape as RectangleShape2D).size * collision.global_scale.abs()
		elif collision.shape is CircleShape2D:
			var diameter := (collision.shape as CircleShape2D).radius * 2.0
			dimensions = Vector2.ONE * diameter * collision.global_scale.abs()
		elif collision.shape is CapsuleShape2D:
			var capsule := collision.shape as CapsuleShape2D
			dimensions = Vector2(capsule.radius * 2.0, capsule.height) * collision.global_scale.abs()
		if dimensions == Vector2.ZERO:
			continue
		var shape_rect := Rect2(collision.global_position - dimensions * 0.5, dimensions)
		bounds = shape_rect if not found_shape else bounds.merge(shape_rect)
		found_shape = true
	return bounds if found_shape else Rect2()

func _collect_collision_shapes(node: Node, result: Array[Node]) -> void:
	if node is CollisionShape2D:
		result.append(node)
	for child in node.get_children():
		_collect_collision_shapes(child, result)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	elapsed += delta
	art.position.y = base_art_y + roundf(sin(elapsed * 2.2)) * 4.0
	art.rotation = 0.0
	var shine_progress := fposmod(elapsed, 3.2)
	shine.visible = shine_progress < 0.42
	if shine.visible:
		var sweep := shine_progress / 0.42
		shine.position.x = roundf(lerpf(-32.0, 32.0, sweep) / 4.0) * 4.0
		shine.position.y = roundf(lerpf(16.0, -16.0, sweep) / 4.0) * 4.0

func _on_body_entered(body: Node2D) -> void:
	if collected or not body.has_method("collect_coin"):
		return
	collected = true
	set_deferred("monitoring", false)
	body.call("collect_coin", art.global_position, STACK_GOLD_TEXTURE, art.texture, art.scale)
	queue_free()
