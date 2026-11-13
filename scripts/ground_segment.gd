@tool
extends Node2D

const TILE_SIZE := 64.0
const SEABED_DEPTH := 225.0
const TOP_LAYER := preload("res://scripts/ground_top_layer.gd")

@export_range(64.0, 20000.0, 64.0) var width_pixels := 640.0:
	set(value):
		width_pixels = maxf(TILE_SIZE, roundf(value / TILE_SIZE) * TILE_SIZE)
		_rebuild()

@onready var collision: CollisionShape2D = $GroundRun/CollisionShape2D
@onready var art: Node2D = $Art

var _rebuilding := false

func _ready() -> void:
	add_to_group("ground")
	_rebuild()
	if Engine.is_editor_hint():
		update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_zero_approx(fposmod(width_pixels, TILE_SIZE)):
		warnings.append("Ground width must be a whole 64-pixel grid size.")
	if not is_zero_approx(fposmod(position.x, TILE_SIZE * 0.5)):
		warnings.append("Move ground so its edges align with the 64-pixel level grid.")
	return warnings

func set_dimensions(next_width: float, next_center_x: float) -> void:
	position.x = roundf(next_center_x / (TILE_SIZE * 0.5)) * TILE_SIZE * 0.5
	width_pixels = next_width

func _rebuild() -> void:
	if _rebuilding or not is_inside_tree() or collision == null or art == null:
		return
	_rebuilding = true
	for child in art.get_children():
		child.free()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width_pixels, 20.0)
	collision.shape = shape
	_add_rect(Rect2(-width_pixels * 0.5, -10.0, width_pixels, SEABED_DEPTH), Color("#283b49"))
	TOP_LAYER.draw_layer(art, width_pixels, -10.0)
	_rebuilding = false

func _add_rect(rect: Rect2, color: Color) -> void:
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size, rect.position + Vector2(0.0, rect.size.y),
	])
	polygon.color = color
	polygon.z_index = -1
	art.add_child(polygon)

