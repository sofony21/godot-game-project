extends CharacterBody2D

const CONFIG := preload("res://scripts/game_config.gd")
const RUN_SPEED := CONFIG.RUN_SPEED
const SPEED_LOSS_PER_COIN := CONFIG.SPEED_LOSS_PER_COIN
const MIN_RUN_SPEED := RUN_SPEED * CONFIG.MIN_RUN_SPEED_RATIO
const STEERING_SPEED_TRIM := CONFIG.STEERING_SPEED_TRIM
const SPEED_BOOST_DURATION := CONFIG.SPEED_BOOST_SECONDS
const RED_COIN_DURATION := CONFIG.RED_COIN_SECONDS
const GRAVITY := CONFIG.GRAVITY
const JUMP_SPEED := CONFIG.JUMP_SPEED
const DOUBLE_JUMP_SPEED := CONFIG.JUMP_SPEED
const EXCHANGE_FLIGHT_DURATION := 0.34
const STACK_COIN_TEXTURE := preload("res://assets/coin_body.svg")
const STACK_COIN_SCALE := CONFIG.STACK_COIN_SCALE
const STACK_COIN_FIRST_Y := CONFIG.STACK_COIN_FIRST_Y
const STACK_COIN_STEP := CONFIG.STACK_COIN_STEP
const STACK_HITBOX_SIZE := CONFIG.STACK_HITBOX_SIZE
signal wallet_changed(coins_carried: int, converted_money: float)
signal died

@onready var pixel_visuals: Node2D = $PixelVisuals
@onready var coin_body: Sprite2D = $PixelVisuals/CoinBody
@onready var legs: Node2D = $PixelVisuals/Legs
@onready var hero_face: Node2D = $PixelVisuals/HeroFace
@onready var coin_stack: Node2D = $PixelVisuals/CoinStack

var coins_collected := 0
var money_converted := 0.0
var speed_boost_time_left := 0.0
var red_coin_time_left := 0.0
var red_exchange_pending := false
var controls_locked := false
var dead := false
var stack_sway_phase := 0.0
var fear_shake_phase := 0.0
var current_run_speed := RUN_SPEED
var run_entry_speed := 0.0
var run_entry_blend_left := 0.0
var run_entry_blend_duration := 0.0
var wallet_invulnerability_time_left := 0.0
var wallet_hit_invulnerability := 1.0
var wallet_hit_shock_time_left := 0.0

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return
	if global_position.y > CONFIG.FALL_DEATH_Y:
		_die()
		return

	if controls_locked:
		velocity = Vector2.ZERO
		legs.set("running", false)
		move_and_slide()
		_snap_pixel_visuals()
		return
	wallet_invulnerability_time_left = maxf(0.0, wallet_invulnerability_time_left - delta)
	wallet_hit_shock_time_left = maxf(0.0, wallet_hit_shock_time_left - delta)
	_update_invulnerability_blink()
	speed_boost_time_left = maxf(0.0, speed_boost_time_left - delta)
	if red_coin_time_left > 0.0:
		red_coin_time_left = maxf(0.0, red_coin_time_left - delta)
	var crouching := false
	var steering := Input.get_axis("ui_left", "ui_right")
	var speed_penalty := float(coins_collected) * SPEED_LOSS_PER_COIN
	var base_speed := RUN_SPEED if speed_boost_time_left > 0.0 else maxf(MIN_RUN_SPEED, RUN_SPEED - speed_penalty)
	var blended_base_speed := base_speed
	if run_entry_blend_left > 0.0 and run_entry_blend_duration > 0.0:
		var blend_progress := 1.0 - run_entry_blend_left / run_entry_blend_duration
		var blend_ease := 1.0 - pow(1.0 - blend_progress, 3.0)
		blended_base_speed = lerpf(run_entry_speed, base_speed, blend_ease)
		run_entry_blend_left = maxf(0.0, run_entry_blend_left - delta)
	current_run_speed = clampf(blended_base_speed * (1.0 + steering * STEERING_SPEED_TRIM), MIN_RUN_SPEED, RUN_SPEED)
	var speed_ratio := current_run_speed / RUN_SPEED
	var coin_weight := clampf(float(coins_collected) / 12.0, 0.0, 1.0)
	velocity.x = current_run_speed
	legs.set("facing", 1.0)
	legs.set("running", true)
	legs.set("run_rate", speed_ratio)
	legs.set("weight", 0.0 if speed_boost_time_left > 0.0 else coin_weight)
	legs.set("crouching", crouching)
	_update_face_expression()
	if coins_collected > 0:
		stack_sway_phase += delta * 7.0 * maxf(0.35, speed_ratio)
		coin_stack.rotation = sin(stack_sway_phase) * deg_to_rad(minf(float(coins_collected) * 0.18, 2.0))
	else:
		coin_stack.rotation = move_toward(coin_stack.rotation, 0.0, delta * 0.08)
	coin_body.scale.y = 1.0
	coin_body.position.y = -36.0 if crouching else -40.0
	_update_fear_shake(delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += GRAVITY * delta
	var jump_pressed := Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up")
	if not crouching and jump_pressed:
		if is_on_floor():
			velocity.y = JUMP_SPEED
		else:
			velocity.y = DOUBLE_JUMP_SPEED
			_spawn_air_jump_bubbles()
	var jump_held := Input.is_action_pressed("ui_accept") or Input.is_action_pressed("ui_up")
	if not is_on_floor() and velocity.y < 0.0 and jump_held:
		velocity.y += GRAVITY * delta * 0.45
	move_and_slide()
	_snap_pixel_visuals()

func _snap_pixel_visuals() -> void:
	var snapped_x := roundf(global_position.x / 4.0) * 4.0
	var snapped_y := roundf((global_position.y - 2.0) / 4.0) * 4.0 + 2.0
	pixel_visuals.global_position = Vector2(snapped_x, snapped_y)

func _spawn_air_jump_bubbles() -> void:
	var puff := Node2D.new()
	puff.name = "AirJumpBubbles"
	puff.z_index = 1
	get_parent().add_child(puff)
	puff.global_position = global_position + Vector2(0.0, -2.0)
	var bubble_positions := [Vector2(-18.0, 8.0), Vector2(-6.0, 2.0), Vector2(8.0, 7.0), Vector2(18.0, 1.0)]
	var bubble_colors := [Color("#a8f3e8"), Color("#e0fff5"), Color("#71d9d4"), Color("#b8f7ee")]
	for index in bubble_positions.size():
		var bubble := Polygon2D.new()
		bubble.polygon = PackedVector2Array([
			Vector2(-4.0, -4.0), Vector2(4.0, -4.0),
			Vector2(4.0, 4.0), Vector2(-4.0, 4.0),
		])
		bubble.position = bubble_positions[index]
		bubble.color = bubble_colors[index]
		puff.add_child(bubble)
	var puff_tween := create_tween().set_parallel(true)
	puff_tween.tween_property(puff, "global_position", puff.global_position + Vector2(0.0, -28.0), 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	puff_tween.tween_property(puff, "modulate:a", 0.0, 0.38)
	puff_tween.chain().tween_callback(puff.queue_free)


func _die() -> void:
	if dead:
		return
	dead = true
	velocity = Vector2.ZERO
	died.emit()

func collect_coin(
	source_position: Vector2 = Vector2.ZERO,
	carried_texture: Texture2D = STACK_COIN_TEXTURE,
	pickup_texture: Texture2D = STACK_COIN_TEXTURE,
	pickup_scale: Vector2 = Vector2.ONE
) -> void:
	coins_collected += 1
	var layer := Sprite2D.new()
	layer.texture = pickup_texture if source_position != Vector2.ZERO else carried_texture
	var target_position := Vector2(0.0, STACK_COIN_FIRST_Y - STACK_COIN_STEP * float(coins_collected - 1))
	layer.position = coin_stack.to_local(source_position) if source_position != Vector2.ZERO else target_position
	layer.scale = pickup_scale if source_position != Vector2.ZERO else Vector2.ONE * STACK_COIN_SCALE
	coin_stack.add_child(layer)
	var hitbox := Area2D.new()
	hitbox.name = "WalletHitbox"
	hitbox.add_to_group("carried_coin_hitbox")
	hitbox.collision_layer = 2
	hitbox.collision_mask = 2
	hitbox.scale = Vector2.ONE / STACK_COIN_SCALE
	hitbox.set_meta("coin_owner", self)
	var hit_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = STACK_HITBOX_SIZE
	hit_shape.shape = rectangle
	hitbox.add_child(hit_shape)
	layer.call_deferred("add_child", hitbox)
	if source_position != Vector2.ZERO:
		var flight_tween := layer.create_tween()
		flight_tween.tween_property(layer, "position", target_position, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var turn_tween := layer.create_tween()
		turn_tween.tween_property(layer, "scale:x", 0.08, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		turn_tween.tween_callback(func() -> void: layer.texture = carried_texture)
		turn_tween.tween_property(layer, "scale:x", STACK_COIN_SCALE, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var size_tween := layer.create_tween()
		size_tween.tween_property(layer, "scale:y", STACK_COIN_SCALE, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	wallet_changed.emit(coins_collected, money_converted)

func collect_speed_powerup() -> void:
	speed_boost_time_left = SPEED_BOOST_DURATION

func begin_run_blend(start_speed: float, duration: float) -> void:
	run_entry_speed = clampf(start_speed, MIN_RUN_SPEED, RUN_SPEED)
	run_entry_blend_duration = maxf(0.01, duration)
	run_entry_blend_left = run_entry_blend_duration

func try_start_wallet_hit() -> bool:
	if wallet_invulnerability_time_left > 0.0:
		return false
	wallet_invulnerability_time_left = wallet_hit_invulnerability
	return true

func play_wallet_hit_reaction() -> void:
	wallet_hit_shock_time_left = 0.8

func get_speed_ratio() -> float:
	return current_run_speed / RUN_SPEED

func _update_face_expression() -> void:
	var expression := "happy"
	if wallet_hit_shock_time_left > 0.0:
		expression = "shocked"
	elif _is_in_enemy_action_zone():
		expression = "fear"
	elif speed_boost_time_left > 0.0:
		expression = "sparkle"
	elif coins_collected >= 10:
		expression = "strained"
	elif coins_collected >= 5:
		expression = "heavy"
	elif coins_collected >= 2:
		expression = "slight"
	hero_face.call("set_expression", expression)

func _is_in_enemy_action_zone() -> bool:
	for enemy in get_tree().get_nodes_in_group("wallet"):
		if enemy.has_method("is_player_in_action_zone") and bool(enemy.call("is_player_in_action_zone", self)):
			return true
	return false

func _update_fear_shake(delta: float) -> void:
	var shake_x := 0.0
	if _is_in_enemy_action_zone():
		fear_shake_phase += delta * 28.0
		shake_x = 4.0 if sin(fear_shake_phase) >= 0.0 else -4.0
	coin_body.position.x = shake_x
	legs.position.x = -shake_x
	coin_stack.position.x = shake_x

func _update_invulnerability_blink() -> void:
	if wallet_invulnerability_time_left > 0.0:
		modulate.a = 0.32 if fposmod(wallet_invulnerability_time_left, 0.14) < 0.07 else 1.0
	else:
		modulate.a = 1.0

func collect_red_powerup() -> void:
	red_coin_time_left = RED_COIN_DURATION
	red_exchange_pending = true

func knock_off_coin(layer: Sprite2D) -> bool:
	if coins_collected <= 0 or not is_instance_valid(layer) or layer.get_parent() != coin_stack:
		return false
	var hitbox := layer.get_node_or_null("WalletHitbox") as Area2D
	if hitbox != null:
		if hitbox.get_meta("knocked_off", false):
			return false
		hitbox.set_meta("knocked_off", true)
		hitbox.set_deferred("monitorable", false)
		hitbox.set_deferred("monitoring", false)
	coins_collected -= 1
	var visible_index := 0
	for remaining in coin_stack.get_children():
		if remaining == layer:
			continue
		var remaining_hitbox := remaining.get_node_or_null("WalletHitbox") as Area2D
		if remaining_hitbox != null and remaining_hitbox.get_meta("knocked_off", false):
			continue
		var target_position := Vector2(0.0, STACK_COIN_FIRST_Y - STACK_COIN_STEP * float(visible_index))
		remaining.position = target_position
		visible_index += 1
	var scatter_direction := -1.0 if layer.get_index() % 2 == 0 else 1.0
	var fall := create_tween().set_parallel(true)
	fall.tween_property(layer, "position", layer.position + Vector2(scatter_direction * 40.0, 48.0), 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(layer, "modulate:a", 0.0, 0.38)
	fall.chain().tween_callback(layer.queue_free)
	wallet_changed.emit(coins_collected, money_converted)
	return true

func shed_coins_above(layer: Sprite2D) -> void:
	if coins_collected <= 0 or not is_instance_valid(layer) or layer.get_parent() != coin_stack:
		return
	var first_coin_index := layer.get_index()
	var layers_to_drop: Array[Sprite2D] = []
	for index in range(first_coin_index, coin_stack.get_child_count()):
		var coin_layer := coin_stack.get_child(index) as Sprite2D
		var hitbox := coin_layer.get_node_or_null("WalletHitbox") as Area2D
		if hitbox == null or not hitbox.get_meta("knocked_off", false):
			layers_to_drop.append(coin_layer)
	for coin_layer in layers_to_drop:
		knock_off_coin(coin_layer)

func deposit_coins(exchange_target: Node2D = null) -> int:
	if coins_collected == 0:
		return 0
	var deposited := coins_collected
	# Each exchange pays the square of the coins carried in that batch.
	var payout_multiplier := 2.0 if red_exchange_pending else 1.0
	if is_instance_valid(exchange_target) and exchange_target.has_method("get_payout_multiplier"):
		payout_multiplier *= float(exchange_target.call("get_payout_multiplier"))
	money_converted += pow(float(deposited), 2.0) * payout_multiplier
	coins_collected = 0
	red_coin_time_left = 0.0
	red_exchange_pending = false
	var destination := exchange_target.global_position if is_instance_valid(exchange_target) else Vector2.ZERO
	if is_instance_valid(exchange_target):
		var station_art := exchange_target.get_node_or_null("StationArt") as Node2D
		if station_art != null:
			destination = station_art.global_position
	for layer in coin_stack.get_children():
		if is_instance_valid(exchange_target):
			layer.reparent(exchange_target, true)
			var coin_flight := layer.create_tween().set_parallel(true)
			coin_flight.tween_property(layer, "global_position", destination, EXCHANGE_FLIGHT_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			coin_flight.tween_property(layer, "scale", Vector2.ZERO, EXCHANGE_FLIGHT_DURATION)
			coin_flight.tween_property(layer, "modulate:a", 0.0, EXCHANGE_FLIGHT_DURATION)
			coin_flight.chain().tween_callback(layer.queue_free)
		else:
			layer.queue_free()
	current_run_speed = RUN_SPEED
	wallet_changed.emit(coins_collected, money_converted)
	return deposited

func _lose_carried_coins() -> void:
	if coins_collected == 0:
		return
	var level := get_tree().get_first_node_in_group("level")
	var scatter_parent := level if level != null else get_parent()
	var coin_layers: Array[Sprite2D] = []
	var coin_positions: Array[Vector2] = []
	for child in coin_stack.get_children():
		if child is Sprite2D:
			coin_layers.append(child as Sprite2D)
			coin_positions.append((child as Sprite2D).global_position)
	coins_collected = 0
	current_run_speed = RUN_SPEED
	velocity.x = RUN_SPEED
	wallet_changed.emit(coins_collected, money_converted)
	call_deferred("_animate_lost_coins", coin_layers, coin_positions, scatter_parent)

func _animate_lost_coins(coin_layers: Array, coin_positions: Array, scatter_parent: Node) -> void:
	for index in coin_layers.size():
		var layer := coin_layers[index] as Sprite2D
		if not is_instance_valid(layer):
			continue
		var start_position: Vector2 = coin_positions[index]
		var hitbox := layer.get_node_or_null("WalletHitbox") as Area2D
		if hitbox != null:
			hitbox.set_deferred("monitoring", false)
			hitbox.set_deferred("monitorable", false)
			hitbox.queue_free()
		layer.reparent(scatter_parent, true)
		layer.global_position = start_position
		layer.z_index = 3
		var direction := -1.0 if index % 2 == 0 else 1.0
		var spread := 52.0 + (float(index) / 2.0) * 18.0
		var burst_position := start_position + Vector2(direction * spread * 0.35, -36.0 - float(index % 3) * 8.0)
		var fall_position := start_position + Vector2(direction * spread, 132.0 + float(index) * 5.0)
		var motion := layer.create_tween()
		motion.tween_property(layer, "global_position", burst_position, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		motion.tween_property(layer, "global_position", fall_position, 0.68).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var tumble := layer.create_tween()
		tumble.tween_property(layer, "rotation", layer.rotation + direction * TAU * (1.0 + float(index % 2)), 0.84).set_trans(Tween.TRANS_LINEAR)
		var fade := layer.create_tween()
		fade.tween_interval(0.68)
		fade.tween_property(layer, "modulate:a", 0.0, 0.32)
		fade.tween_callback(layer.queue_free)
