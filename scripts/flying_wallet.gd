@tool
extends Area2D

const CONFIG := preload("res://scripts/game_config.gd")
@export_enum("flying", "walking") var movement_type := "flying"
@export_range(0.75, 2.0, 0.05) var wallet_art_scale := CONFIG.WALLET_ART_SCALE
@export_range(80.0, 1000.0, 10.0) var detection_radius := CONFIG.WALLET_DETECTION_RADIUS:
	set(value):
		detection_radius = clampf(value, 80.0, 1000.0)
		queue_redraw()
@export_range(160.0, 1600.0, 20.0) var give_up_distance := CONFIG.WALLET_GIVE_UP_DISTANCE
@export_range(40.0, 900.0, 10.0) var flying_chase_speed := CONFIG.FLYING_WALLET_SPEED
@export_range(40.0, 900.0, 10.0) var walking_chase_speed := CONFIG.WALKING_WALLET_SPEED
@export_range(0.0, 2000.0, 16.0) var stop_before_next_safe := 0.0
@export_range(0.0, 10.0, 1.0) var animation_seed := 0.0

@onready var wallet_art: Sprite2D = $WalletArt
@onready var legs: Node2D = $Legs
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var patrol_left: Marker2D = get_node_or_null("PatrolLeft") as Marker2D
@onready var patrol_right: Marker2D = get_node_or_null("PatrolRight") as Marker2D
@onready var bob_top: Marker2D = get_node_or_null("BobTop") as Marker2D
@onready var bob_bottom: Marker2D = get_node_or_null("BobBottom") as Marker2D

var origin_global := Vector2.ZERO
var phase := 0.0
var flight_time := 0.0
var chasing := false
var hit_registered := false
var target_player: CharacterBody2D
var alert_label: Label
var eye_glow: Node2D

func _ready() -> void:
	add_to_group("wallet")
	origin_global = global_position
	phase = animation_seed * 0.71
	wallet_art.scale = Vector2.ONE * wallet_art_scale
	legs.scale = Vector2.ONE * wallet_art_scale
	var source_shape := collision_shape.shape as RectangleShape2D
	if source_shape != null:
		var scaled_shape := source_shape.duplicate() as RectangleShape2D
		if movement_type == "walking":
			scaled_shape.size = Vector2(88.0, 76.0)
		scaled_shape.size *= wallet_art_scale
		collision_shape.shape = scaled_shape
	if Engine.is_editor_hint():
		queue_redraw()
		for warning in _get_configuration_warnings():
			push_warning("Wallet '%s': %s" % [name, warning])
		return
	if patrol_left == null or patrol_right == null:
		push_error("Wallet '%s' is missing PatrolLeft or PatrolRight Marker2D children; chase and patrol are disabled." % name)
		return
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	target_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	alert_label = Label.new()
	alert_label.text = "!"
	alert_label.position = Vector2(-10.0, -60.0)
	alert_label.size = Vector2(20.0, 24.0)
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert_label.add_theme_font_size_override("font_size", 22)
	alert_label.add_theme_color_override("font_color", Color("#ff6a49"))
	alert_label.visible = false
	add_child(alert_label)
	eye_glow = Node2D.new()
	eye_glow.name = "EyeGlow"
	eye_glow.z_index = 2
	_add_eye_glow(Vector2(-8.0, 1.0))
	_add_eye_glow(Vector2(12.0, 1.0))
	add_child(eye_glow)
	if movement_type == "walking":
		_create_walking_legs()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_arc(Vector2.ZERO, detection_radius, 0.0, TAU, 96, Color(1.0, 0.32, 0.2, 0.48), 2.0, false)
	if stop_before_next_safe > 0.0:
		var boundary := _find_safe_boundary_x()
		if boundary >= 0.0:
			var local_boundary := boundary - global_position.x
			draw_line(Vector2(local_boundary, -180.0), Vector2(local_boundary, 180.0), Color(1.0, 0.55, 0.2, 0.7), 2.0, false)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_node_or_null("PatrolLeft") == null or get_node_or_null("PatrolRight") == null:
		warnings.append("Wallet '%s' needs PatrolLeft and PatrolRight Marker2D children." % name)
	var body_bounds := _collision_bounds(self)
	if body_bounds.size != Vector2.ZERO:
		for group_name in ["platform", "pit", "safe"]:
			for node in get_tree().get_nodes_in_group(group_name):
				if node == self or not node is Node2D:
					continue
				var other := _collision_bounds(node)
				var overlap := body_bounds.intersection(other)
				if other.size != Vector2.ZERO and overlap.size.x > 1.0 and overlap.size.y > 1.0:
					warnings.append("Wallet '%s' overlaps %s '%s'. Its position is preserved." % [name, group_name, node.name])
	if movement_type == "walking":
		var left_marker := get_node_or_null("PatrolLeft") as Marker2D
		var right_marker := get_node_or_null("PatrolRight") as Marker2D
		if left_marker != null and right_marker != null:
			var left_x := minf(left_marker.global_position.x, right_marker.global_position.x)
			var right_x := maxf(left_marker.global_position.x, right_marker.global_position.x)
			for pit in get_tree().get_nodes_in_group("pit"):
				var pit_node := pit as Node2D
				var half_width := float(pit_node.get("pit_width")) * 0.5
				if right_x >= pit_node.global_position.x - half_width and left_x <= pit_node.global_position.x + half_width:
					warnings.append("Walking wallet '%s' patrol crosses pit '%s'. Its position is preserved." % [name, pit_node.name])
	return warnings

func _collision_bounds(object: Node) -> Rect2:
	var result := Rect2()
	var has_result := false
	var shapes: Array[Node] = []
	_collect_collision_shapes(object, shapes)
	for node in shapes:
		var shape := node as CollisionShape2D
		if shape == null or shape.disabled or shape.shape == null:
			continue
		var size := Vector2.ZERO
		if shape.shape is RectangleShape2D:
			size = (shape.shape as RectangleShape2D).size * shape.global_scale.abs()
		elif shape.shape is CircleShape2D:
			var diameter := (shape.shape as CircleShape2D).radius * 2.0
			size = Vector2.ONE * diameter * shape.global_scale.abs()
		if size == Vector2.ZERO:
			continue
		var bounds := Rect2(shape.global_position - size * 0.5, size)
		result = bounds if not has_result else result.merge(bounds)
		has_result = true
	return result if has_result else Rect2()

func _collect_collision_shapes(node: Node, result: Array[Node]) -> void:
	if node is CollisionShape2D:
		result.append(node)
	for child in node.get_children():
		_collect_collision_shapes(child, result)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or hit_registered:
		return
	flight_time += delta
	if not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if is_instance_valid(target_player):
		var distance_to_hero := global_position.distance_to(target_player.global_position)
		if not chasing and distance_to_hero <= detection_radius:
			chasing = true
			alert_label.visible = true
			wallet_art.modulate = Color("#ffad78")
		elif chasing and distance_to_hero >= give_up_distance:
			chasing = false
			alert_label.visible = false
			wallet_art.modulate = Color.WHITE
	if chasing and is_instance_valid(target_player):
		var target_point := target_player.global_position + Vector2(0.0, CONFIG.WALLET_TARGET_OFFSET_Y)
		var chase_boundary := _find_safe_boundary_x()
		if chase_boundary >= 0.0:
			target_point.x = minf(target_point.x, chase_boundary)
		if movement_type == "flying":
			global_position = global_position.move_toward(target_point, flying_chase_speed * delta)
		else:
			global_position.x = move_toward(global_position.x, target_player.global_position.x, walking_chase_speed * delta)
			global_position.y = origin_global.y
	else:
		var left_x := origin_global.x + patrol_left.position.x
		var right_x := origin_global.x + patrol_right.position.x
		var patrol_center_x := (left_x + right_x) * 0.5
		var patrol_range_x := absf(right_x - left_x) * 0.5
		var patrol_x := patrol_center_x + sin(flight_time * 0.62 + phase) * patrol_range_x
		var patrol_boundary := _find_safe_boundary_x()
		if patrol_boundary >= 0.0:
			patrol_x = minf(patrol_x, patrol_boundary)
		if movement_type == "flying":
			var top_y := origin_global.y + (bob_top.position.y if bob_top != null else 0.0)
			var bottom_y := origin_global.y + (bob_bottom.position.y if bob_bottom != null else 0.0)
			var bob_center_y := (top_y + bottom_y) * 0.5
			var bob_range_y := absf(bottom_y - top_y) * 0.5
			global_position = Vector2(patrol_x, bob_center_y + sin(flight_time * 1.9 + phase) * bob_range_y)
		else:
			global_position = Vector2(patrol_x, origin_global.y)
	if movement_type == "walking":
		_animate_legs()
	_update_eye_glow()
	_snap_wallet_art()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or eye_glow == null:
		return
	_update_eye_glow()
	_snap_wallet_art()

func is_player_in_action_zone(player: Node2D) -> bool:
	return is_instance_valid(player) and global_position.distance_to(player.global_position) <= detection_radius

func _find_safe_boundary_x() -> float:
	if stop_before_next_safe <= 0.0:
		return -1.0
	var nearest_safe_x := INF
	for safe in get_tree().get_nodes_in_group("safe"):
		if not safe is Node2D:
			continue
		var safe_x := (safe as Node2D).global_position.x
		if safe_x > global_position.x and safe_x < nearest_safe_x:
			nearest_safe_x = safe_x
	return nearest_safe_x - stop_before_next_safe if is_finite(nearest_safe_x) else -1.0

func _update_eye_glow() -> void:
	var pulse := 0.55 + 0.35 * (0.5 + 0.5 * sin(flight_time * 3.0 + phase))
	var blink_phase := fposmod(flight_time + phase, 3.8)
	var blink := blink_phase > 3.48 and blink_phase < 3.62
	eye_glow.modulate.a = 1.0 if chasing else (0.08 if blink else pulse)

func _add_eye_glow(at: Vector2) -> void:
	var pixel := Polygon2D.new()
	pixel.polygon = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)])
	pixel.position = at
	pixel.color = Color("#ff6541")
	eye_glow.add_child(pixel)

func _snap_wallet_art() -> void:
	var snap_offset := Vector2(
		roundf(global_position.x / 4.0) * 4.0 - global_position.x,
		roundf((global_position.y - 2.0) / 4.0) * 4.0 + 2.0 - global_position.y
	)
	var menacing_bob := roundf(sin(flight_time * 6.0 + phase)) * 2.0
	wallet_art.position = snap_offset + Vector2(0.0, menacing_bob)
	if eye_glow != null:
		eye_glow.position = snap_offset + Vector2(0.0, menacing_bob)

func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("carried_coin_hitbox"):
		return
	var player := area.get_meta("coin_owner") as CharacterBody2D
	_register_hit(player, area)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_register_hit(body as CharacterBody2D)

func _register_hit(player: CharacterBody2D, entering_coin_area: Area2D = null) -> void:
	if hit_registered:
		return
	if not is_instance_valid(player) or not player.has_method("try_start_wallet_hit"):
		_bounce_away()
		return
	if int(player.get("coins_collected")) <= 0:
		return
	if not bool(player.call("try_start_wallet_hit")):
		_bounce_away()
		return
	hit_registered = true
	chasing = false
	if CONFIG.LOSE_ALL_COINS_ON_HIT:
		player.call("_lose_carried_coins")
	else:
		var overlapping := get_overlapping_areas()
		if entering_coin_area != null and not overlapping.has(entering_coin_area):
			overlapping.append(entering_coin_area)
		for coin_area in overlapping:
			if not coin_area.is_in_group("carried_coin_hitbox"):
				continue
			var coin_owner := coin_area.get_meta("coin_owner") as Node
			if coin_owner == player and bool(player.call("knock_off_coin", coin_area.get_parent() as Sprite2D)):
				break
	player.call("play_wallet_hit_reaction")
	_bounce_away(player)

func _bounce_away(player: Node2D = null) -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	var escape_direction := Vector2(-1.0, -0.8)
	if is_instance_valid(player):
		escape_direction = (global_position - player.global_position).normalized()
		if escape_direction.length_squared() < 0.01:
			escape_direction = Vector2(-1.0, -0.8)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", global_position + escape_direction * 170.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.42)
	tween.chain().tween_callback(queue_free)

func _create_walking_legs() -> void:
	legs.visible = true
	for leg_index in 2:
		var leg := Polygon2D.new()
		leg.name = "WalletLeg%d" % leg_index
		leg.polygon = PackedVector2Array([Vector2(-4.0, 0.0), Vector2(4.0, 0.0), Vector2(4.0, 12.0), Vector2(-4.0, 12.0)])
		leg.position = Vector2(-14.0 if leg_index == 0 else 14.0, 34.0)
		leg.color = Color("#702944") if leg_index == 0 else Color("#342037")
		legs.add_child(leg)

func _animate_legs() -> void:
	for leg_index in legs.get_child_count():
		var leg := legs.get_child(leg_index) as Polygon2D
		leg.position.y = 34.0 + sin(flight_time * 15.0 + float(leg_index) * PI) * 3.0
