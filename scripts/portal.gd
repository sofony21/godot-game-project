@tool
extends Area2D

const CONFIG := preload("res://scripts/game_config.gd")

signal entered(portal: Area2D)

@export_enum("start", "finish") var portal_type := "finish"

@onready var portal_art: Sprite2D = $PortalArt
var swirl_time := 0.0

func _ready() -> void:
	add_to_group("portal")
	set_notify_transform(true)
	body_entered.connect(_on_body_entered)
	if Engine.is_editor_hint():
		portal_art.scale = Vector2.ONE
		portal_art.modulate.a = 1.0
		for warning in _get_configuration_warnings():
			push_warning("Portal '%s': %s" % [name, warning])
		return
	monitoring = false
	portal_art.scale = Vector2.ONE
	portal_art.modulate.a = 0.0

func _process(delta: float) -> void:
	if portal_type != "start":
		return
	swirl_time += delta
	portal_art.rotation = sin(swirl_time * 1.1) * 0.035
	portal_art.position.y = -96.0 + roundf(sin(swirl_time * 1.7) * 2.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_inside_tree():
		return warnings
	if portal_type == "start" and absf(global_position.y - CONFIG.GROUND_Y) > 4.0:
		warnings.append("Start portal '%s' is not resting on the ground line (y=%.0f). Its position is preserved." % [name, global_position.y])
	var portal_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if portal_type == "start" and portal_shape != null and portal_shape.shape is RectangleShape2D:
		var portal_size := (portal_shape.shape as RectangleShape2D).size * portal_shape.global_scale.abs()
		var portal_bounds := Rect2(portal_shape.global_position - portal_size * 0.5, portal_size)
		for group_name in ["pit", "platform", "wallet", "coin"]:
			for node in get_tree().get_nodes_in_group(group_name):
				if node == self or not node is Node2D:
					continue
				var shape := _first_collision_shape(node)
				if shape == null:
					continue
				var bounds := _shape_bounds(shape)
				var overlap := portal_bounds.intersection(bounds)
				if overlap.size.x > 1.0 and overlap.size.y > 1.0:
					warnings.append("Start portal '%s' overlaps %s '%s'. Its position is preserved." % [name, group_name, node.name])
	return warnings

func _first_collision_shape(node: Node) -> CollisionShape2D:
	if node is CollisionShape2D:
		return node as CollisionShape2D
	for child in node.get_children():
		var found := _first_collision_shape(child)
		if found != null:
			return found
	return null

func _shape_bounds(shape_node: CollisionShape2D) -> Rect2:
	if shape_node.shape is RectangleShape2D:
		var size := (shape_node.shape as RectangleShape2D).size * shape_node.global_scale.abs()
		return Rect2(shape_node.global_position - size * 0.5, size)
	return Rect2()

func play_open(duration: float = 0.55) -> void:
	var tween := create_tween()
	tween.tween_property(portal_art, "modulate:a", 1.0, duration)
	await tween.finished
	if portal_type == "finish":
		monitoring = true

func play_close(duration: float = 0.45) -> void:
	monitoring = false
	var tween := create_tween()
	tween.tween_property(portal_art, "modulate:a", 0.0, duration)
	await tween.finished

func _on_body_entered(body: Node2D) -> void:
	if portal_type == "finish" and body.has_method("deposit_coins"):
		set_deferred("monitoring", false)
		entered.emit(self)
