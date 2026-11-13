extends Node2D

const EYE := Color("#221921")
const EYE_HIGHLIGHT := Color("#fff8e8")
const EYE_GLINT := Color("#bff5ff")
const CHEEK := Color("#f18a83")
const MOUTH := Color("#753d32")
const SWEAT := Color("#8fe4f2")
const LID := Color("#f2bd3e")

var expression := "happy"

func set_expression(next_expression: String) -> void:
	if expression == next_expression:
		return
	expression = next_expression
	queue_redraw()

func _draw() -> void:
	var left_eye := Vector2(-12.0, -4.0)
	var right_eye := Vector2(12.0, -4.0)
	if expression != "fear":
		_draw_cheeks()
	match expression:
		"fear":
			_draw_fear_eye(left_eye)
			_draw_fear_eye(right_eye)
			_draw_wobbly_mouth()
			_draw_sweat(32.0, -24.0, true)
		"surprised":
			_draw_open_eye(left_eye, false)
			_draw_open_eye(right_eye, false)
			_pixel(-4.0, 8.0, 8.0, 12.0, MOUTH)
		"shocked":
			_draw_open_eye(left_eye, false)
			_draw_open_eye(right_eye, false)
			_pixel(-8.0, 8.0, 16.0, 4.0, MOUTH)
			_pixel(-4.0, 12.0, 8.0, 8.0, MOUTH)
			_pixel(-4.0, 12.0, 4.0, 4.0, Color("#f4bd54"))
			_draw_sweat(32.0, -24.0, true)
		"slight":
			_draw_open_eye(left_eye, false)
			_draw_open_eye(right_eye, false)
			_draw_small_smile()
			_draw_sweat(32.0, -20.0, false)
		"heavy":
			_draw_half_eye(left_eye)
			_draw_half_eye(right_eye)
			_draw_wobbly_mouth()
			_draw_sweat(32.0, -20.0, false)
			_draw_sweat(-36.0, -12.0, false)
		"strained":
			_draw_squint(left_eye)
			_draw_squint(right_eye)
			_draw_grimace()
			_draw_sweat(32.0, -24.0, true)
		"sparkle":
			_draw_open_eye(left_eye, true)
			_draw_open_eye(right_eye, true)
			_draw_happy_smile()
			_draw_sparkle(left_eye + Vector2(-8.0, -12.0))
			_draw_sparkle(right_eye + Vector2(8.0, -12.0))
		_:
			_draw_open_eye(left_eye, false)
			_draw_open_eye(right_eye, false)
			_draw_happy_smile()

func _draw_open_eye(center: Vector2, sparkling: bool) -> void:
	_pixel(center.x - 4.0, center.y - 12.0, 8.0, 4.0, EYE)
	_pixel(center.x - 8.0, center.y - 8.0, 16.0, 12.0, EYE)
	_pixel(center.x - 4.0, center.y + 4.0, 8.0, 4.0, EYE)
	_pixel(center.x - 4.0, center.y - 8.0, 4.0, 4.0, EYE_HIGHLIGHT)
	_pixel(center.x + 4.0, center.y, 4.0, 4.0, EYE_GLINT)
	if not sparkling:
		return
	_pixel(center.x - 8.0, center.y - 16.0, 4.0, 4.0, EYE)
	_pixel(center.x + 4.0, center.y - 16.0, 4.0, 4.0, EYE)
	_pixel(center.x - 12.0, center.y - 12.0, 4.0, 4.0, EYE)
	_pixel(center.x + 8.0, center.y - 12.0, 4.0, 4.0, EYE)

func _draw_half_eye(center: Vector2) -> void:
	_pixel(center.x - 8.0, center.y - 4.0, 16.0, 8.0, EYE)
	_pixel(center.x - 4.0, center.y - 4.0, 4.0, 4.0, EYE_HIGHLIGHT)
	_pixel(center.x - 8.0, center.y - 12.0, 16.0, 4.0, LID)

func _draw_fear_eye(center: Vector2) -> void:
	_pixel(center.x - 8.0, center.y - 12.0, 16.0, 20.0, EYE_HIGHLIGHT)
	_pixel(center.x - 4.0, center.y - 4.0, 8.0, 12.0, EYE)
	_pixel(center.x - 4.0, center.y - 4.0, 4.0, 4.0, EYE_GLINT)

func _draw_squint(center: Vector2) -> void:
	_pixel(center.x - 8.0, center.y - 4.0, 16.0, 4.0, EYE)
	_pixel(center.x - 4.0, center.y - 8.0, 8.0, 4.0, EYE)
	_pixel(center.x - 12.0, center.y - 12.0, 8.0, 4.0, MOUTH)
	_pixel(center.x + 4.0, center.y - 12.0, 8.0, 4.0, MOUTH)

func _draw_cheeks() -> void:
	_pixel(-32.0, 8.0, 8.0, 4.0, CHEEK)
	_pixel(-28.0, 12.0, 8.0, 4.0, CHEEK)
	_pixel(20.0, 12.0, 8.0, 4.0, CHEEK)
	_pixel(24.0, 8.0, 8.0, 4.0, CHEEK)

func _draw_happy_smile() -> void:
	_pixel(-8.0, 8.0, 4.0, 4.0, MOUTH)
	_pixel(-4.0, 12.0, 12.0, 4.0, MOUTH)
	_pixel(8.0, 8.0, 4.0, 4.0, MOUTH)

func _draw_small_smile() -> void:
	_pixel(-4.0, 8.0, 4.0, 4.0, MOUTH)
	_pixel(0.0, 12.0, 8.0, 4.0, MOUTH)
	_pixel(8.0, 8.0, 4.0, 4.0, MOUTH)

func _draw_wobbly_mouth() -> void:
	_pixel(-8.0, 12.0, 4.0, 4.0, MOUTH)
	_pixel(-4.0, 8.0, 8.0, 4.0, MOUTH)
	_pixel(4.0, 12.0, 4.0, 4.0, MOUTH)
	_pixel(8.0, 8.0, 4.0, 4.0, MOUTH)

func _draw_grimace() -> void:
	_pixel(-8.0, 8.0, 20.0, 12.0, MOUTH)
	_pixel(-4.0, 8.0, 12.0, 4.0, EYE_HIGHLIGHT)
	_pixel(-4.0, 16.0, 12.0, 4.0, Color("#bd7050"))

func _draw_sweat(x: float, y: float, large: bool) -> void:
	var size := 8.0 if large else 4.0
	_pixel(x, y, size, size, SWEAT)
	_pixel(x - size, y + size, size * 2.0, size * 2.0, SWEAT)
	_pixel(x, y + size * 3.0, size, size, Color("#58bdd3"))
	_pixel(x, y + size, 4.0, 4.0, Color("#e2ffff"))

func _draw_sparkle(center: Vector2) -> void:
	_pixel(center.x, center.y - 4.0, 4.0, 12.0, EYE_HIGHLIGHT)
	_pixel(center.x - 4.0, center.y, 12.0, 4.0, EYE_HIGHLIGHT)

func _pixel(x: float, y: float, width: float, height: float, color: Color) -> void:
	draw_rect(Rect2(x, y, width, height), color)
