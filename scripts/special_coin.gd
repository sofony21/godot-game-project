@tool
extends Area2D

const CONFIG := preload("res://scripts/game_config.gd")
const STACK_BLUE_TEXTURE := preload("res://assets/blue_coin_body.svg")
const STACK_RED_TEXTURE := preload("res://assets/red_coin_body.svg")

@export var effect_type := "speed"

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
	map_coin_scale = CONFIG.MAP_COIN_SCALE
	art.scale = Vector2.ONE * CONFIG.MAP_COIN_SCALE
	var hitbox := collision_shape.shape as RectangleShape2D
	var local_hitbox := hitbox.duplicate() as RectangleShape2D
	local_hitbox.size = Vector2.ONE * CONFIG.MAP_COIN_HITBOX_SIZE * CONFIG.MAP_COIN_SCALE
	collision_shape.shape = local_hitbox
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

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_inside_tree():
		return warnings
	var half_size := CONFIG.MAP_COIN_HITBOX_SIZE * CONFIG.MAP_COIN_SCALE * 0.5
	var coin_bounds := Rect2(global_position - Vector2.ONE * half_size, Vector2.ONE * half_size * 2.0)
	for group_name in ["platform", "ground", "safe", "wallet", "pit", "portal"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node == self or not node is Node2D:
				continue
			var bounds := _collision_bounds(node)
			if bounds.size == Vector2.ZERO:
				continue
			var overlap := coin_bounds.intersection(bounds)
			if overlap.size.x > 1.0 and overlap.size.y > 1.0:
				warnings.append("Coin '%s' overlaps %s '%s'. Its current position is preserved." % [name, group_name, node.name])
	return warnings

func _collision_bounds(object: Node) -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	var nodes: Array[Node] = []
	_collect_shapes(object, nodes)
	for node in nodes:
		var shape_node := node as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var dimensions := Vector2.ZERO
		if shape_node.shape is RectangleShape2D:
			dimensions = (shape_node.shape as RectangleShape2D).size * shape_node.global_scale.abs()
		elif shape_node.shape is CircleShape2D:
			var diameter := (shape_node.shape as CircleShape2D).radius * 2.0
			dimensions = Vector2.ONE * diameter * shape_node.global_scale.abs()
		if dimensions == Vector2.ZERO:
			continue
		var rect := Rect2(shape_node.global_position - dimensions * 0.5, dimensions)
		bounds = rect if not has_bounds else bounds.merge(rect)
		has_bounds = true
	return bounds if has_bounds else Rect2()

func _collect_shapes(node: Node, result: Array[Node]) -> void:
	if node is CollisionShape2D:
		result.append(node)
	for child in node.get_children():
		_collect_shapes(child, result)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	elapsed += delta
	art.position.y = base_art_y + roundf(sin(elapsed * 2.4)) * 4.0
	art.rotation = 0.0
	var shine_progress := fposmod(elapsed, 3.2)
	shine.visible = shine_progress < 0.42
	if shine.visible:
		var sweep := shine_progress / 0.42
		shine.position.x = roundf(lerpf(-32.0, 32.0, sweep) / 4.0) * 4.0
		shine.position.y = roundf(lerpf(16.0, -16.0, sweep) / 4.0) * 4.0

func _on_body_entered(body: Node2D) -> void:
	if collected:
		return
	var method_name := "collect_speed_powerup" if effect_type == "speed" else "collect_red_powerup"
	if not body.has_method(method_name) or not body.has_method("collect_coin"):
		return
	collected = true
	set_deferred("monitoring", false)
	body.call(method_name)
	var carried_texture := STACK_BLUE_TEXTURE if effect_type == "speed" else STACK_RED_TEXTURE
	body.call("collect_coin", art.global_position, carried_texture, art.texture, art.scale)
	queue_free()
