extends Node2D

const LEG_SHADOW := Color("#a75e28")
const LEG_MID := Color("#e99735")
const LEG_LIGHT := Color("#ffd260")
const LEG_PIXEL := 4.0

var run_phase := 0.0
var running := false
var facing := 1.0
var crouching := false
var run_rate := 1.0
var weight := 0.0

func _process(delta: float) -> void:
	if running:
		run_phase = fposmod(run_phase + delta * lerpf(10.0, 4.0, weight) * run_rate, TAU)
	queue_redraw()

func _draw() -> void:
	var body: Sprite2D = get_parent().get_node("CoinBody")
	var hip_y := _snap(body.position.y + body.texture.get_height() * body.scale.y * 0.5 - 4.0 + weight * 4.0)
	var stride_strength := 1.0 - weight * 0.4
	var stride := roundi(sin(run_phase) * 2.0 * stride_strength) * LEG_PIXEL if running else 0.0
	var tremble := roundi(sin(run_phase * 13.0) * weight) * LEG_PIXEL if running and weight >= 0.8 else 0.0
	var left_hip := Vector2(_snap(-16.0 * facing + tremble), hip_y)
	var right_hip := Vector2(_snap(12.0 * facing - tremble), hip_y)
	if crouching:
		_draw_pixel_leg(left_hip, left_hip + Vector2(-8.0 * facing, 12.0), left_hip + Vector2(-16.0 * facing, 8.0))
		_draw_pixel_leg(right_hip, right_hip + Vector2(8.0 * facing, 12.0), right_hip + Vector2(16.0 * facing, 8.0))
	else:
		_draw_pixel_leg(left_hip, left_hip + Vector2(stride, 12.0), Vector2(left_hip.x + stride * 1.5, 0.0))
		_draw_pixel_leg(right_hip, right_hip + Vector2(-stride, 12.0), Vector2(right_hip.x - stride * 1.5, 0.0))

func _draw_pixel_leg(hip: Vector2, knee: Vector2, foot: Vector2) -> void:
	_draw_pixel_segment(hip, knee)
	_draw_pixel_segment(knee, foot)
	draw_rect(Rect2(hip - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), LEG_MID)
	draw_rect(Rect2(hip - Vector2(4.0, 4.0), Vector2(4.0, 4.0)), LEG_LIGHT)

func _draw_pixel_segment(start: Vector2, finish: Vector2) -> void:
	var distance := start.distance_to(finish)
	var steps := maxi(1, ceili(distance / LEG_PIXEL))
	for step_index in steps + 1:
		var amount := float(step_index) / float(steps)
		var point := Vector2(_snap(lerpf(start.x, finish.x, amount)), _snap(lerpf(start.y, finish.y, amount)))
		draw_rect(Rect2(point - Vector2(4.0, 2.0), Vector2(8.0, 8.0)), LEG_SHADOW)
		draw_rect(Rect2(point - Vector2(4.0, 2.0), Vector2(4.0, 4.0)), LEG_MID)

func _snap(value: float) -> float:
	return roundf(value / LEG_PIXEL) * LEG_PIXEL
