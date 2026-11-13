@tool
extends Area2D

const CONFIG := preload("res://scripts/game_config.gd")
const EXCHANGE_ANIMATION_DURATION := CONFIG.CASHOUT_FLIGHT_SECONDS

@onready var station_art: Sprite2D = $StationArt

var player_in_zone: CharacterBody2D
var pass_exchanged := false
@export var golden_bonus := false
var pixel_font: SystemFont
var exchange_audio: AudioStreamPlayer

func _ready() -> void:
	add_to_group("safe")
	if Engine.is_editor_hint():
		set_notify_transform(true)
		station_art.modulate = Color("#ffd86a") if golden_bonus else Color.WHITE
		for warning in _get_configuration_warnings():
			push_warning("Safe '%s': %s" % [name, warning])
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if golden_bonus:
		station_art.modulate = Color("#ffd86a")
		_show_bonus_marker()
	_create_notice_arrow()
	_create_exchange_audio()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		update_configuration_warnings()

func get_payout_multiplier() -> float:
	return CONFIG.GOLDEN_SAFE_MULTIPLIER if golden_bonus else 1.0

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var safe_rect := _collision_bounds(self)
	if safe_rect.size == Vector2.ZERO:
		warnings.append("Safe needs a CollisionShape2D so its spacing can be checked.")
	else:
		for group_name in ["platform", "pit", "safe", "coin", "wallet", "portal"]:
			for other in get_tree().get_nodes_in_group(group_name):
				if other == self or not other is Node2D:
					continue
				var other_rect := _collision_bounds(other)
				if other_rect.size == Vector2.ZERO:
					continue
				var overlap := safe_rect.intersection(other_rect)
				if overlap.size.x <= 1.0 or overlap.size.y <= 1.0:
					continue
				var object_label: String = "another safe" if group_name == "safe" else group_name
				warnings.append("Safe '%s' overlaps %s '%s'. Position is preserved; review this placement." % [name, object_label, other.name])
				return warnings
	var found_finish := false
	for node in get_tree().get_nodes_in_group("portal"):
		var portal := node as Node2D
		if str(portal.get("portal_type")) != "finish":
			continue
		found_finish = true
		if absf(global_position.x - portal.global_position.x) < CONFIG.FINISH_CLEAR_RADIUS:
			warnings.append("Safe '%s' is %.0f pixels from finish portal '%s', inside the %d-pixel clear zone. Position is preserved; review manually." % [name, absf(global_position.x - portal.global_position.x), portal.name, int(CONFIG.FINISH_CLEAR_RADIUS)])
	if not found_finish:
		warnings.append("No finish portal is present in the level.")
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
			dimensions = Vector2(diameter, diameter) * collision.global_scale.abs()
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

func _show_bonus_marker() -> void:
	var marker := Label.new()
	marker.text = "GOLD SAFE  +25%"
	marker.position = Vector2(-100.0, -225.0)
	marker.size = Vector2(200.0, 32.0)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Terminal", "Consolas"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	marker.add_theme_font_override("font", font)
	marker.add_theme_font_size_override("font_size", 16)
	marker.add_theme_color_override("font_color", Color("#ffe27c"))
	add_child(marker)

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("deposit_coins") or pass_exchanged:
		return
	player_in_zone = body as CharacterBody2D
	if player_in_zone != null and overlaps_body(player_in_zone):
		pass_exchanged = true
		call_deferred("_exchange_after_enter", player_in_zone)

func _exchange_after_enter(body: CharacterBody2D) -> void:
	if body == player_in_zone and is_instance_valid(body):
		_exchange_coins()

func _exchange_coins() -> void:
	if player_in_zone == null or int(player_in_zone.get("coins_collected")) <= 0:
		return
	var money_before := float(player_in_zone.get("money_converted"))
	var deposited := int(player_in_zone.call("deposit_coins", self))
	if deposited <= 0:
		return
	var payout := float(player_in_zone.get("money_converted")) - money_before
	_flash()
	_show_payout(payout)
	exchange_audio.play()

func _on_body_exited(body: Node2D) -> void:
	if body == player_in_zone:
		player_in_zone = null
		pass_exchanged = false

func _create_notice_arrow() -> void:
	var arrow := Node2D.new()
	arrow.name = "NoticeArrow"
	arrow.position = Vector2(0.0, -150.0)
	var pointer := Polygon2D.new()
	pointer.polygon = PackedVector2Array([
		Vector2(-12.0, -12.0), Vector2(12.0, -12.0),
		Vector2(12.0, 0.0), Vector2(4.0, 0.0),
		Vector2(4.0, 12.0), Vector2(-4.0, 12.0),
		Vector2(-4.0, 0.0), Vector2(-12.0, 0.0),
	])
	pointer.color = Color("#ffd15d")
	arrow.add_child(pointer)
	var shine := Polygon2D.new()
	shine.polygon = PackedVector2Array([
		Vector2(-8.0, -8.0), Vector2(0.0, -8.0),
		Vector2(0.0, -4.0), Vector2(-8.0, -4.0),
	])
	shine.color = Color("#fff0a0")
	arrow.add_child(shine)
	add_child(arrow)
	var bob := create_tween().set_loops()
	bob.tween_property(arrow, "position:y", -142.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(arrow, "position:y", -154.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _show_payout(amount: float) -> void:
	pixel_font = SystemFont.new()
	pixel_font.font_names = PackedStringArray(["Terminal", "Consolas"])
	pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var payout_label := Label.new()
	payout_label.text = "+$%.2f" % amount
	payout_label.position = Vector2(-70.0, -190.0)
	payout_label.size = Vector2(140.0, 44.0)
	payout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	payout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	payout_label.add_theme_font_override("font", pixel_font)
	payout_label.add_theme_font_size_override("font_size", 26)
	payout_label.add_theme_color_override("font_color", Color("#ffe27c"))
	add_child(payout_label)
	var payout_tween := create_tween().set_parallel(true)
	payout_tween.tween_property(payout_label, "position:y", -245.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	payout_tween.tween_property(payout_label, "modulate:a", 0.0, 0.8).set_delay(0.2)
	payout_tween.chain().tween_callback(payout_label.queue_free)

func _create_exchange_audio() -> void:
	exchange_audio = AudioStreamPlayer.new()
	exchange_audio.name = "ExchangeChime"
	exchange_audio.stream = _make_chime_stream()
	exchange_audio.volume_db = -7.0
	add_child(exchange_audio)

func _make_chime_stream() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 0.28
	var sample_count := int(SAMPLE_RATE * DURATION)
	var samples := PackedByteArray()
	samples.resize(sample_count * 2)
	for index in sample_count:
		var time := float(index) / float(SAMPLE_RATE)
		var frequency := 880.0 if time < 0.13 else 1174.66
		var envelope := 1.0 - time / DURATION
		var sample := int(sin(TAU * frequency * time) * envelope * 9000.0)
		samples.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = samples
	return stream

func _flash() -> void:
	station_art.modulate = Color("#d6ffd8")
	var tween := create_tween()
	var base_color := Color("#ffd86a") if golden_bonus else Color.WHITE
	tween.tween_property(station_art, "modulate", base_color, 0.35)
