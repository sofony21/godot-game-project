extends RefCounted

const CONFIG := preload("res://scripts/game_config.gd")

static func draw_layer(parent: Node2D, width: float, top_y: float) -> void:
	_add_rect(parent, Rect2(-width * 0.5, top_y, width, CONFIG.GROUND_TOP_THICKNESS), Color("#645348"))
	_add_rect(parent, Rect2(-width * 0.5, top_y, width, CONFIG.GROUND_TOP_SURFACE_BAND_THICKNESS), Color("#d1b477"))
	_add_rect(parent, Rect2(-width * 0.5, top_y, width, CONFIG.GROUND_TOP_HIGHLIGHT_BAND_THICKNESS), Color("#ead39a"))
	for tile_index in int(roundf(width / CONFIG.GRID_TILE_PIXELS)):
		var x := -width * 0.5 + float(tile_index) * CONFIG.GRID_TILE_PIXELS + 12.0
		_add_rect(parent, Rect2(x, top_y + CONFIG.GROUND_TOP_SURFACE_BAND_THICKNESS, 24.0, 8.0), Color("#504b4a"))
		_add_rect(parent, Rect2(x + 28.0, top_y + 32.0, 16.0, 8.0), Color("#806b55"))

static func _add_rect(parent: Node2D, rect: Rect2, color: Color) -> void:
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size, rect.position + Vector2(0.0, rect.size.y),
	])
	polygon.color = color
	polygon.z_index = -1
	parent.add_child(polygon)
