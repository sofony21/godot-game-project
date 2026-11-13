@tool
extends Node2D

const CONFIG := preload("res://scripts/game_config.gd")
const TILE_SIZE := CONFIG.GRID_TILE_PIXELS
const PIXEL_SIZE := 4.0
const FLAME_COLUMN_SIZE := 16.0
const FRAME_INTERVAL := 0.12
const SPARK_COUNT := 8
const BILL_COUNT := 3

@export_range(2.0, 10.0, 2.0) var width_tiles := 4.0:
	set(value):
		width_tiles = clampf(roundf(value / 2.0) * 2.0, 2.0, 10.0)
		pit_width = width_tiles * TILE_SIZE
		if Engine.is_editor_hint() and is_inside_tree():
			update_configuration_warnings()
		_rebuild_visuals()
@export_node_path("Node2D") var left_ground_path: NodePath
@export_node_path("Node2D") var right_ground_path: NodePath
@export var random_seed := 1

@onready var fire_visuals: Node2D = $FireVisuals
@onready var death_area: Area2D = $DeathZone
@onready var death_shape: CollisionShape2D = $DeathZone/CollisionShape2D

var pit_width := 256.0
var pit_depth := CONFIG.PIT_DEPTH
var elapsed := 0.0
var frame_clock := 0.0
var frame_index := 0
var rng := RandomNumberGenerator.new()
var flames: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var bills: Array[Dictionary] = []
var fire_base_outer: Polygon2D
var fire_base_core: Polygon2D
var _editor_ready := false

func _ready() -> void:
	add_to_group("pit")
	set_notify_transform(true)
	_editor_ready = true
	death_area.body_entered.connect(_on_body_entered)
	_rebuild_visuals()
	if Engine.is_editor_hint():
		for warning in _get_configuration_warnings():
			push_warning("Pit '%s': %s" % [name, warning])

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_equal_approx(width_tiles, roundf(width_tiles / 2.0) * 2.0):
		warnings.append("Pit width must use an even whole number of 64-pixel grid units.")
	if pit_width > CONFIG.PIT_MAX_CROSS_WIDTH:
		warnings.append("This pit may be too wide to cross safely. Keep it at %d pixels or less." % int(CONFIG.PIT_MAX_CROSS_WIDTH))
	var left_ground := get_node_or_null(left_ground_path) as Node2D
	var right_ground := get_node_or_null(right_ground_path) as Node2D
	if left_ground == null or right_ground == null:
		warnings.append("This pit needs linked ground segments on both sides.")
		return warnings
	var expected_left := global_position.x - pit_width * 0.5
	var expected_right := global_position.x + pit_width * 0.5
	var actual_left := left_ground.global_position.x + float(left_ground.get("width_pixels")) * 0.5
	var actual_right := right_ground.global_position.x - float(right_ground.get("width_pixels")) * 0.5
	if absf(actual_left - expected_left) > 1.0 or absf(actual_right - expected_right) > 1.0:
		warnings.append("Pit '%s' fire/death area edges do not match the linked ground segments. Position is preserved; review the width and links." % name)
	return warnings

func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED or not Engine.is_editor_hint() or not _editor_ready:
		return
	update_configuration_warnings()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	elapsed += delta
	frame_clock += delta
	if frame_clock >= FRAME_INTERVAL:
		frame_clock = 0.0
		frame_index = posmod(frame_index + 1, 4)
	_update_frames()
	_update_particle_positions()

func _rebuild_visuals() -> void:
	if fire_visuals == null or death_shape == null:
		return
	for child in fire_visuals.get_children():
		child.free()
	flames.clear()
	sparks.clear()
	bills.clear()
	rng.seed = hash([random_seed, width_tiles])
	var area_rectangle := RectangleShape2D.new()
	area_rectangle.size = Vector2(pit_width, pit_depth)
	death_shape.shape = area_rectangle
	death_area.position = Vector2(0.0, pit_depth * 0.5)
	_create_flames()
	_create_sparks()
	_create_bills()
	_update_frames()
	_update_particle_positions()

func _create_flames() -> void:
	fire_base_outer = _pixel_rect("FireBaseOrange", Color("#e34b20"))
	fire_base_core = _pixel_rect("FireBaseYellow", Color("#ffc536"))
	var column_count := int(pit_width / FLAME_COLUMN_SIZE)
	for index in column_count:
		var x := -pit_width * 0.5 + float(index) * FLAME_COLUMN_SIZE
		var outer := _pixel_rect("FlameBodyOrange", Color("#ff8126"))
		var mid := _pixel_rect("FlameBandRed", Color("#c9341d"))
		var core := _pixel_rect("FlameCoreYellow", Color("#ffc536"))
		var tip := _pixel_rect("FlameTipOrange", Color("#e34b20"))
		flames.append({"x": x, "phase": index * 2.3, "outer": outer, "mid": mid, "core": core, "tip": tip})

func _create_sparks() -> void:
	for index in SPARK_COUNT:
		var spark := _pixel_rect("Ember", Color("#ffd044"))
		sparks.append({"node": spark, "phase": rng.randf_range(0.0, TAU), "x": rng.randf_range(-pit_width * 0.5 + 4.0, pit_width * 0.5 - 4.0), "speed": rng.randf_range(24.0, 58.0)})

func _create_bills() -> void:
	for index in BILL_COUNT:
		var bill := Node2D.new()
		bill.name = "BurningDollarBill"
		fire_visuals.add_child(bill)
		var base := _pixel_rect("BillGreen", Color("#43b95d"), bill)
		var light := _pixel_rect("BillCurl", Color("#6bc75b"), bill)
		var dollar := _pixel_rect("DollarMark", Color("#83d36c"), bill)
		var dollar_top := _pixel_rect("DollarTop", Color("#83d36c"), bill)
		var dollar_bottom := _pixel_rect("DollarBottom", Color("#83d36c"), bill)
		bills.append({"node": bill, "base": base, "light": light, "dollar": dollar, "dollar_top": dollar_top, "dollar_bottom": dollar_bottom, "phase": float(index) / float(BILL_COUNT), "x": rng.randf_range(-pit_width * 0.5 + 16.0, pit_width * 0.5 - 16.0)})

func _pixel_rect(node_name: String, color: Color, parent: Node = null) -> Polygon2D:
	var pixel := Polygon2D.new()
	pixel.name = node_name
	pixel.color = color
	var target_parent := fire_visuals if parent == null else parent
	target_parent.add_child(pixel)
	return pixel

func _set_rect(node: Polygon2D, rect: Rect2, color: Color) -> void:
	var left := clampf(rect.position.x, -pit_width * 0.5, pit_width * 0.5)
	var right := clampf(rect.end.x, -pit_width * 0.5, pit_width * 0.5)
	var top := clampf(rect.position.y, 0.0, pit_depth)
	var bottom := clampf(rect.end.y, 0.0, pit_depth)
	node.polygon = PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)])
	node.color = color

func _update_frames() -> void:
	if not is_instance_valid(fire_base_outer) or not is_instance_valid(fire_base_core):
		return
	_set_rect(fire_base_outer, Rect2(-pit_width * 0.5, pit_depth - 28.0, pit_width, 28.0), Color("#e34b20"))
	_set_rect(fire_base_core, Rect2(-pit_width * 0.5, pit_depth - 12.0, pit_width, 12.0), Color("#ffc536"))
	for flame in flames:
		var phase := float(flame["phase"])
		var flicker := float([0, 1, 2, 1][posmod(frame_index + int(phase), 4)]) * 12.0
		var height := minf(pit_depth, 200.0 + flicker + float(posmod(int(phase * 11.0), 4)) * 16.0)
		var x := float(flame["x"])
		var tip_y := pit_depth - height
		_set_rect(flame["outer"], Rect2(x, tip_y + 4.0, FLAME_COLUMN_SIZE, height - 4.0), Color("#ff8126"))
		_set_rect(flame["mid"], Rect2(x + 4.0, tip_y + 12.0, 8.0, height - 12.0), Color("#c9341d"))
		_set_rect(flame["core"], Rect2(x + 6.0, pit_depth - 92.0, 4.0, 76.0), Color("#ffc536"))
		_set_rect(flame["tip"], Rect2(x + 4.0, tip_y, 8.0, 8.0), Color("#e34b20"))
	for bill_data in bills:
		var bill := bill_data["node"] as Node2D
		var progress := fposmod(elapsed * 0.12 + float(bill_data["phase"]), 1.0)
		var ash := progress > 0.78
		var bill_color := Color("#77796b") if ash else Color("#43b95d")
		_set_rect(bill_data["base"], Rect2(-14.0, -8.0, 28.0, 16.0), bill_color)
		var curl_width := 8.0 if posmod(frame_index + int(float(bill_data["phase"] * 10.0)), 2) == 0 else 4.0
		_set_rect(bill_data["light"], Rect2(8.0, -8.0, curl_width, 4.0), Color("#6bc75b") if not ash else Color("#8d7968"))
		_set_rect(bill_data["dollar"], Rect2(-2.0, -4.0, 4.0, 8.0), Color("#83d36c") if not ash else Color("#8d7968"))
		_set_rect(bill_data["dollar_top"], Rect2(-6.0, -4.0, 8.0, 3.0), Color("#83d36c") if not ash else Color("#8d7968"))
		_set_rect(bill_data["dollar_bottom"], Rect2(-2.0, 1.0, 8.0, 3.0), Color("#83d36c") if not ash else Color("#8d7968"))
		bill.modulate.a = 1.0 - smoothstep(0.88, 1.0, progress)

func _update_particle_positions() -> void:
	for spark_data in sparks:
		var progress := fposmod(elapsed * float(spark_data["speed"]) / pit_depth + float(spark_data["phase"]), 1.0)
		var x := float(spark_data["x"]) + sin(elapsed * 2.4 + float(spark_data["phase"])) * 8.0
		var y := pit_depth - progress * pit_depth
		var spark := spark_data["node"] as Polygon2D
		var ember_color := Color("#ffad28") if posmod(int(float(spark_data["phase"]) * 10.0), 2) == 0 else Color("#ffd044")
		_set_rect(spark, Rect2(roundf(x / PIXEL_SIZE) * PIXEL_SIZE, roundf(y / PIXEL_SIZE) * PIXEL_SIZE, PIXEL_SIZE, PIXEL_SIZE), ember_color)
	for bill_data in bills:
		var progress := fposmod(elapsed * 0.12 + float(bill_data["phase"]), 1.0)
		var x := float(bill_data["x"]) + sin(elapsed * 1.5 + float(bill_data["phase"]) * TAU) * 14.0
		var y := lerpf(pit_depth - 12.0, 12.0, progress)
		var bill := bill_data["node"] as Node2D
		bill.position = Vector2(roundf(x / PIXEL_SIZE) * PIXEL_SIZE, roundf(y / PIXEL_SIZE) * PIXEL_SIZE)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("_die"):
		body.call("_die")

