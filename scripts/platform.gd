@tool
extends StaticBody2D

const TILE_SIZE := 64.0
const CONFIG := preload("res://scripts/game_config.gd")
const TOP_LAYER := preload("res://scripts/ground_top_layer.gd")

@export_range(4.0, 12.0, 1.0) var width_tiles := 8.0:
	set(value):
		width_tiles = clampf(roundf(value), 4.0, 12.0)
		_rebuild()
		if Engine.is_editor_hint() and is_inside_tree():
			update_configuration_warnings()
@export_range(2, 4, 1) var tier := 2:
	set(value):
		tier = clampi(value, 2, 4)
		height_above_ground = float(CONFIG.PLATFORM_TIER_HEIGHTS[tier])
		_rebuild()
		if Engine.is_editor_hint() and is_inside_tree():
			update_configuration_warnings()
@export_range(64.0, 960.0, 16.0) var height_above_ground := float(CONFIG.PLATFORM_TIER_HEIGHTS[2]):
	set(value):
		height_above_ground = clampf(roundf(value / CONFIG.PIXEL_SNAP_SIZE) * CONFIG.PIXEL_SNAP_SIZE, 64.0, 960.0)
		_rebuild()
@export var bridge := false
@export var decoration_seed := 0

@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var art: Node2D = $Art

var _rebuilding := false

func _ready() -> void:
	add_to_group("platform")
	_rebuild()
	_report_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if width_tiles * TILE_SIZE < 256.0:
		warnings.append("This platform is too narrow for a reliable landing.")
	if absf(global_position.y - (CONFIG.GROUND_Y - height_above_ground)) > 4.0:
		warnings.append("Platform '%s' is placed at y=%.0f, which differs from its tier setting (%.0f). Its scene position is preserved; check whether the current height is reachable." % [name, global_position.y, CONFIG.GROUND_Y - height_above_ground])
	return warnings

func _report_configuration_warnings() -> void:
	if not Engine.is_editor_hint():
		return
	for warning in _get_configuration_warnings():
		push_warning("Platform '%s': %s" % [name, warning])

func _rebuild() -> void:
	if _rebuilding or not is_inside_tree() or collision == null or art == null:
		return
	_rebuilding = true
	for child in art.get_children():
		child.free()
	var width := width_tiles * TILE_SIZE
	var platform_thickness := CONFIG.GROUND_TOP_THICKNESS
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, platform_thickness)
	collision.shape = shape
	collision.position = Vector2(0.0, platform_thickness * 0.5)
	collision.one_way_collision = true
	collision.one_way_collision_margin = 4.0
	TOP_LAYER.draw_layer(art, width, 0.0)
	_add_decoration(width)
	_rebuilding = false

func _add_decoration(width: float) -> void:
	if tier <= 3:
		if posmod(decoration_seed, 3) == 0:
			var x := -width * 0.5 + 24.0
			_add_rect(Rect2(x, -12.0, 6.0, 12.0), Color("#327e78"))
			_add_rect(Rect2(x + 6.0, -18.0, 6.0, 18.0), Color("#438f78"))
		return
	if posmod(decoration_seed, 2) != 0:
		return
	var jellyfish := Node2D.new()
	jellyfish.name = "TierLightJellyfish"
	jellyfish.position = Vector2(width * 0.25, -42.0)
	jellyfish.z_index = 1
	art.add_child(jellyfish)
	_add_rect(Rect2(-12.0, -6.0, 24.0, 6.0), Color("#a5f5ed"), jellyfish)
	_add_rect(Rect2(-8.0, -12.0, 16.0, 6.0), Color("#bdfbf2"), jellyfish)
	_add_rect(Rect2(-6.0, 0.0, 3.0, 9.0), Color("#8bd8d2"), jellyfish)
	_add_rect(Rect2(3.0, 0.0, 3.0, 9.0), Color("#8bd8d2"), jellyfish)

func _add_rect(rect: Rect2, color: Color, parent: Node2D = null) -> void:
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size, rect.position + Vector2(0.0, rect.size.y),
	])
	polygon.color = color
	polygon.z_index = -1
	(art if parent == null else parent).add_child(polygon)

