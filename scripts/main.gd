extends Node2D

const CONFIG := preload("res://scripts/game_config.gd")
const PIXEL_SKY_SHADER := preload("res://assets/pixel_sky.gdshader")
const HUD_COIN_ICON := preload("res://assets/hud_coin_icon.svg")
const HUD_MONEY_ICON := preload("res://assets/money_icon.svg")
const HUD_CLOCK_ICON := preload("res://assets/clock_icon.svg")
const HUD_BLUE_ICON := preload("res://assets/hud_blue_icon.svg")
const HUD_RED_ICON := preload("res://assets/hud_red_icon.svg")

var player: CharacterBody2D
var camera: Camera2D
var start_portal: Area2D
var finish_portal: Area2D
var finish_portal_opening := false
var pixel_font: SystemFont
var carried_label: Label
var converted_label: Label
var goal_label: Label
var exit_hint_label: Label
var route_hint_label: Label
var speed_boost_label: Label
var red_coin_label: Label
var speed_indicator_label: Label
var speed_bar: ProgressBar
var hud_layer: CanvasLayer
var speed_row: HBoxContainer
var red_row: HBoxContainer
var water_shader_material: ShaderMaterial
var background_particles: Array[Dictionary] = []
var background_bubble_timer := 0.0
var layout_rng := RandomNumberGenerator.new()
var shown_route_hint_platforms: Dictionary = {}
var exit_hint_shown := false
var exit_hint_time_left := 0.0
var route_hint_time_left := 0.0
var end_screen_shown := false
var end_scene_started := false
var death_restart_started := false
var level_time_left := CONFIG.LEVEL_TIME_SECONDS
var level_timer_active := false
var intro_sequence_active := true

func _ready() -> void:
	player = _require_group("player", "hero") as CharacterBody2D
	camera = _require_group("camera", "camera") as Camera2D
	if player == null or camera == null:
		return
	player.set("wallet_hit_invulnerability", CONFIG.WALLET_HIT_INVULNERABILITY)
	player.controls_locked = true
	camera.zoom = Vector2.ONE * CONFIG.CAMERA_ZOOM
	_create_underwater_background()
	_configure_pixel_font()
	_create_hud()
	player.wallet_changed.connect(_refresh_wallet)
	player.died.connect(_on_player_died)
	_refresh_wallet(int(player.get("coins_collected")), float(player.get("money_converted")))
	for portal_node in get_tree().get_nodes_in_group("portal"):
		var portal := portal_node as Area2D
		if portal == null:
			continue
		if str(portal.get("portal_type")) == "start":
			start_portal = portal
		else:
			finish_portal = portal
			if not portal.entered.is_connected(_on_finish_portal_entered):
				portal.entered.connect(_on_finish_portal_entered)
	if start_portal == null:
		push_error("Level is missing a start portal in group 'portal'. Add PortalStart.tscn to Level/Portals.")
		return
	if finish_portal == null:
		push_error("Level is missing a finish portal in group 'portal'. Add PortalFinish.tscn to Level/Portals.")
		return
	_validate_map_coin_count()
	_validate_placed_elements()
	_run_start_sequence()

func _validate_map_coin_count() -> void:
	var gold_count := 0
	var blue_count := 0
	var red_count := 0
	for coin in get_tree().get_nodes_in_group("coin"):
		var coin_script := coin.get_script() as Script
		if coin_script == null or not coin_script.resource_path.ends_with("special_coin.gd"):
			gold_count += 1
		elif str(coin.get("effect_type")) == "double_cash":
			red_count += 1
		else:
			blue_count += 1
	var expected_gold := CONFIG.MAP_GOLD_COIN_COUNT
	if gold_count != expected_gold or blue_count != CONFIG.MAP_BLUE_COIN_COUNT or red_count != CONFIG.MAP_RED_COIN_COUNT:
		push_error("Map coin setup mismatch: found %d gold, %d blue and %d red coins; GameConfig expects %d, %d and %d." % [gold_count, blue_count, red_count, expected_gold, CONFIG.MAP_BLUE_COIN_COUNT, CONFIG.MAP_RED_COIN_COUNT])

func _validate_placed_elements() -> void:
	for group_name in ["coin", "platform", "pit", "safe", "wallet", "portal"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node.has_method("_get_configuration_warnings"):
				continue
			var warnings: PackedStringArray = node.call("_get_configuration_warnings")
			for warning in warnings:
				push_warning("Placement check '%s': %s" % [node.name, warning])

func _require_group(group_name: StringName, expected: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group_name)
	if nodes.is_empty():
		push_error("Level is missing required %s node (group '%s')." % [expected, group_name])
		return null
	return nodes[0]

func _physics_process(_delta: float) -> void:
	if player == null or camera == null:
		return
	var camera_target_x := (start_portal.global_position.x + CONFIG.CAMERA_LEAD) if intro_sequence_active and start_portal != null else player.global_position.x + CONFIG.CAMERA_LEAD
	var camera_follow := 1.0 - exp(-CONFIG.CAMERA_FOLLOW_SHARPNESS * get_physics_process_delta_time())
	camera.global_position.x = lerpf(camera.global_position.x, camera_target_x, camera_follow)
	camera.global_position.y = CONFIG.CAMERA_TARGET_Y
	_update_finish_portal()
	_update_route_hint()
	if not end_scene_started and finish_portal != null and finish_portal.monitoring and finish_portal.overlaps_body(player):
		_on_finish_portal_entered(finish_portal)

func _process(delta: float) -> void:
	if player == null or camera == null:
		return
	_update_background_bubbles(delta)
	if exit_hint_time_left > 0.0:
		exit_hint_time_left -= delta
		if exit_hint_time_left <= 0.0 and exit_hint_label != null:
			exit_hint_label.visible = false
	if route_hint_time_left > 0.0:
		route_hint_time_left -= delta
		if route_hint_time_left <= 0.0 and route_hint_label != null:
			route_hint_label.visible = false
	if player != null and speed_bar != null:
		var speed_ratio := float(player.get("current_run_speed")) / CONFIG.RUN_SPEED
		speed_bar.value = speed_ratio * 100.0
		speed_indicator_label.text = "Run speed: %d%%" % roundi(speed_ratio * 100.0)
		speed_row.visible = float(player.get("speed_boost_time_left")) > 0.0
		red_row.visible = float(player.get("red_coin_time_left")) > 0.0
		speed_boost_label.text = "BOOST: %.1fs" % float(player.get("speed_boost_time_left"))
		red_coin_label.text = "RED COIN: %.1fs" % float(player.get("red_coin_time_left"))
	if level_timer_active and goal_label != null:
		level_time_left = maxf(0.0, level_time_left - delta)
		goal_label.text = "Your goal: $%.0f  |  %02d:%02d" % [CONFIG.MONEY_GOAL, floori(level_time_left / 60.0), int(level_time_left) % 60]

func _run_start_sequence() -> void:
	var portal_art := start_portal.get_node_or_null("PortalArt") as Sprite2D
	var run_start := start_portal.get_node_or_null("StartPortal_Position") as Marker2D
	if portal_art == null or run_start == null:
		push_error("Level needs PortalStart/PortalArt and PortalStart/StartPortal_Position markers.")
		return
	intro_sequence_active = true
	player.global_position = portal_art.global_position
	player.visible = false
	if hud_layer != null:
		hud_layer.visible = false
	await start_portal.call("play_open", CONFIG.START_PORTAL_OPEN_SECONDS)
	await get_tree().create_timer(CONFIG.INTRO_PAUSE).timeout
	player.visible = true
	player.get_node("PixelVisuals/HeroFace").call("set_expression", "surprised")
	var from_position := portal_art.global_position
	var to_position := run_start.global_position
	var elapsed := 0.0
	var next_bubble := 0.0
	while elapsed < CONFIG.INTRO_DURATION:
		var delta := get_process_delta_time()
		elapsed = minf(CONFIG.INTRO_DURATION, elapsed + delta)
		var progress := elapsed / CONFIG.INTRO_DURATION
		var descent_ease := 1.0 - pow(1.0 - progress, 3.0)
		var pop_ease := smoothstep(0.0, 1.0, progress)
		var position := Vector2(
			lerpf(from_position.x, to_position.x, pop_ease),
			lerpf(from_position.y, to_position.y, descent_ease)
		)
		position.y -= sin(progress * PI) * 4.0
		player.global_position = Vector2(roundf(position.x / 4.0) * 4.0, roundf(position.y / 4.0) * 4.0)
		player.velocity = Vector2.ZERO
		next_bubble -= delta
		if next_bubble <= 0.0:
			_spawn_intro_bubble()
			next_bubble = 0.28
		await get_tree().process_frame
	player.global_position = to_position
	player.call("begin_run_blend", CONFIG.INTRO_EXIT_SPEED, CONFIG.INTRO_RUN_ACCEL_SECONDS)
	level_time_left = CONFIG.LEVEL_TIME_SECONDS
	level_timer_active = true
	player.controls_locked = false
	intro_sequence_active = false
	player.get_node("PixelVisuals/HeroFace").call("set_expression", "happy")
	if hud_layer != null:
		hud_layer.visible = true
		for hud_item in hud_layer.get_children():
			if hud_item is CanvasItem:
				hud_item.modulate.a = 0.0
				var hud_appear := hud_layer.create_tween()
				hud_appear.tween_property(hud_item, "modulate:a", 1.0, 0.25)
	await start_portal.call("play_close", 0.45)

func _spawn_intro_bubble() -> void:
	var bubble := Polygon2D.new()
	bubble.name = "IntroBubble"
	bubble.polygon = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])
	bubble.color = Color("#b8eeeb")
	bubble.global_position = player.global_position + Vector2(layout_rng.randf_range(-20.0, 20.0), 18.0)
	add_child(bubble)
	var tween := bubble.create_tween().set_parallel(true)
	tween.tween_property(bubble, "global_position:y", bubble.global_position.y - 28.0, 0.7)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(bubble.queue_free)

func _update_route_hint() -> void:
	if not CONFIG.SHOW_ROUTE_HINTS or route_hint_label == null or route_hint_time_left > 0.0:
		return
	var platforms := get_tree().get_nodes_in_group("platform")
	platforms.sort_custom(func(a: Node, b: Node): return (a as Node2D).global_position.x < (b as Node2D).global_position.x)
	for platform_index in platforms.size():
		if posmod(platform_index, CONFIG.ROUTE_HINT_PLATFORM_INTERVAL) != 0 or shown_route_hint_platforms.has(platform_index):
			continue
		var platform_node := platforms[platform_index]
		var platform := platform_node as Node2D
		var distance := platform.global_position.x - player.global_position.x
		if distance < 0.0 or distance > 620.0:
			continue
		shown_route_hint_platforms[platform_index] = true
		var tier := int(platform.get("tier"))
		route_hint_label.text = "^ HIGH ROUTE AHEAD: MORE COINS, MORE WALLETS!" if tier >= 3 else "^ MID ROUTE AHEAD: COIN CLUSTERS, SOME WALLETS."
		route_hint_time_left = CONFIG.ROUTE_HINT_DURATION
		route_hint_label.visible = true
		return

func _update_finish_portal() -> void:
	var distance := finish_portal.global_position.x - player.global_position.x
	if not exit_hint_shown and distance <= CONFIG.FINISH_WARNING_DISTANCE:
		exit_hint_shown = true
		exit_hint_time_left = 6.0
		exit_hint_label.text = "EXIT PORTAL AHEAD!  EXCHANGE COINS NOW!"
		exit_hint_label.visible = true
	if distance <= CONFIG.FINISH_OPEN_DISTANCE and not finish_portal_opening:
		finish_portal_opening = true
		finish_portal.call("play_open", CONFIG.FINISH_PORTAL_OPEN_SECONDS)

func _on_finish_portal_entered(portal: Area2D) -> void:
	if end_scene_started:
		return
	end_scene_started = true
	end_screen_shown = true
	level_timer_active = false
	player.controls_locked = true
	var hud_fade := create_tween().set_parallel(true)
	if hud_layer != null:
		for item in hud_layer.get_children():
			if item is CanvasItem:
				hud_fade.tween_property(item, "modulate:a", 0.0, 0.4)
	var pull := create_tween().set_parallel(true)
	pull.tween_property(player, "global_position", portal.global_position + Vector2(0.0, -96.0), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	pull.tween_property(player, "modulate:a", 0.0, 0.7)
	await pull.finished
	await portal.call("play_close", 0.35)
	await hud_fade.finished
	_show_background_only()
	await get_tree().create_timer(CONFIG.END_SCENE_DURATION).timeout

func _on_player_died() -> void:
	if death_restart_started:
		return
	death_restart_started = true
	player.controls_locked = true
	player.call("_lose_carried_coins")
	var death_tween := create_tween().set_parallel(true)
	death_tween.tween_property(player, "global_position", player.global_position + Vector2(0.0, 64.0), CONFIG.DEATH_ANIMATION_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	death_tween.tween_property(player, "modulate:a", 0.0, CONFIG.DEATH_ANIMATION_SECONDS)
	await death_tween.finished
	var message_layer := CanvasLayer.new()
	message_layer.layer = 4
	add_child(message_layer)
	var message := Label.new()
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	message.position = Vector2(-180.0, -30.0)
	message.custom_minimum_size = Vector2(360.0, 60.0)
	message.text = "YOU FELL!"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(message, 32, Color("#ffe27c"))
	message_layer.add_child(message)
	await get_tree().create_timer(CONFIG.RESTART_DELAY_SECONDS).timeout
	get_tree().reload_current_scene()

func _create_hud() -> void:
	var ui_container := get_node_or_null("UI") as Node2D
	if ui_container == null:
		push_error("Level is missing the locked UI container node.")
		return
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUD"
	hud_layer.layer = 2
	ui_container.add_child(hud_layer)
	var rows := VBoxContainer.new()
	rows.position = Vector2(14.0, 12.0)
	rows.add_theme_constant_override("separation", 3)
	hud_layer.add_child(rows)
	carried_label = Label.new()
	converted_label = Label.new()
	goal_label = Label.new()
	speed_boost_label = Label.new()
	red_coin_label = Label.new()
	speed_indicator_label = Label.new()
	_add_hud_row(rows, carried_label, HUD_COIN_ICON)
	_add_hud_row(rows, converted_label, HUD_MONEY_ICON)
	_add_hud_row(rows, goal_label, HUD_CLOCK_ICON)
	var speed_row_local := _add_hud_row(rows, speed_indicator_label, HUD_BLUE_ICON)
	speed_bar = ProgressBar.new()
	speed_bar.max_value = 100.0
	speed_bar.show_percentage = false
	speed_bar.custom_minimum_size = Vector2(128.0, 16.0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#254b5b")
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ffd15d")
	speed_bar.add_theme_stylebox_override("background", track)
	speed_bar.add_theme_stylebox_override("fill", fill)
	speed_row_local.add_child(speed_bar)
	speed_row = _add_hud_row(rows, speed_boost_label, HUD_BLUE_ICON)
	red_row = _add_hud_row(rows, red_coin_label, HUD_RED_ICON)
	speed_row.visible = false
	red_row.visible = false
	exit_hint_label = Label.new()
	exit_hint_label.visible = false
	exit_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	exit_hint_label.position = Vector2(-300.0, 18.0)
	exit_hint_label.custom_minimum_size = Vector2(600.0, 36.0)
	exit_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(exit_hint_label, 18, Color.WHITE)
	hud_layer.add_child(exit_hint_label)
	route_hint_label = Label.new()
	route_hint_label.visible = false
	route_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	route_hint_label.position = Vector2(-320.0, 56.0)
	route_hint_label.custom_minimum_size = Vector2(640.0, 30.0)
	route_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(route_hint_label, 15, Color("#d5fff7"))
	hud_layer.add_child(route_hint_label)

func _add_hud_row(parent: VBoxContainer, label: Label, icon: Texture2D) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var image := TextureRect.new()
	image.texture = icon
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.custom_minimum_size = Vector2(28.0, 28.0)
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(image)
	label.add_theme_font_override("font", pixel_font)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(label)
	return row

func _configure_pixel_font() -> void:
	pixel_font = SystemFont.new()
	pixel_font.font_names = PackedStringArray(["Terminal", "Consolas"])
	pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE

func _style_label(label: Control, size: int, color: Color) -> void:
	label.add_theme_font_override("font", pixel_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)

func _refresh_wallet(coins_carried: int, converted_money: float) -> void:
	if carried_label == null:
		return
	carried_label.text = "Coins carried: %d" % coins_carried
	converted_label.text = "Converted money: $%.2f" % converted_money
	goal_label.text = "Your goal: $%.0f" % CONFIG.MONEY_GOAL
	if level_timer_active:
		goal_label.text = "Your goal: $%.0f  |  %02d:%02d" % [CONFIG.MONEY_GOAL, floori(level_time_left / 60.0), int(level_time_left) % 60]

func _show_background_only() -> void:
	for child in get_children():
		if child.name in ["BackgroundLayers", "Camera2D", "WaterBubbleParticle"]:
			continue
		if child is CanvasItem:
			child.visible = false
	var ui_container := get_node_or_null("UI") as Node2D
	if ui_container != null:
		for child in ui_container.get_children():
			if child is CanvasLayer:
				child.visible = false

func _create_underwater_background() -> void:
	var background_container := get_node_or_null("BackgroundLayers") as Node2D
	if background_container == null:
		push_error("Level is missing the locked BackgroundLayers container node.")
		return
	var background_layer := CanvasLayer.new()
	background_layer.name = "BackgroundLayers"
	background_layer.layer = -10
	background_container.add_child(background_layer)
	var water_fill := ColorRect.new()
	water_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	water_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water_shader_material = ShaderMaterial.new()
	water_shader_material.shader = PIXEL_SKY_SHADER
	water_shader_material.set_shader_parameter("animation_rate", CONFIG.BACKGROUND_ANIMATION_SPEED)
	water_fill.material = water_shader_material
	background_layer.add_child(water_fill)

func _update_background_bubbles(delta: float) -> void:
	background_bubble_timer += delta
	if background_bubble_timer >= CONFIG.BACKGROUND_BUBBLE_INTERVAL:
		background_bubble_timer = 0.0
		if background_particles.size() < CONFIG.MAX_BACKGROUND_BUBBLES:
			_spawn_background_bubble()
	var view_size := get_viewport_rect().size / CONFIG.CAMERA_ZOOM
	var view_left := camera.global_position.x - view_size.x * 0.7
	var view_right := camera.global_position.x + view_size.x * 0.7
	for index in range(background_particles.size() - 1, -1, -1):
		var particle: Dictionary = background_particles[index]
		var bubble := particle.node as Node2D
		particle.age = float(particle.age) + delta
		background_particles[index] = particle
		if float(particle.age) >= float(particle.duration) or bubble.global_position.x < view_left or bubble.global_position.x > view_right:
			bubble.queue_free()
			background_particles.remove_at(index)
			continue
		var origin: Vector2 = particle.origin
		bubble.global_position = Vector2(roundf((origin.x + sin(float(particle.age) * 1.4 + float(particle.phase)) * 12.0) / 4.0) * 4.0, roundf((origin.y - float(particle.age) * float(particle.speed)) / 4.0) * 4.0)
		bubble.modulate.a = clampf(1.0 - pow(float(particle.age) / float(particle.duration), 2.2), 0.0, 1.0)

func _spawn_background_bubble() -> void:
	var bubble := Node2D.new()
	bubble.name = "WaterBubbleParticle"
	var start_position := player.global_position + Vector2(layout_rng.randf_range(-28.0, 28.0), -28.0) if layout_rng.randf() < 0.35 else Vector2(camera.global_position.x + layout_rng.randf_range(-get_viewport_rect().size.x / CONFIG.CAMERA_ZOOM * 0.5, get_viewport_rect().size.x / CONFIG.CAMERA_ZOOM * 0.5), CONFIG.GROUND_Y - 8.0)
	start_position = Vector2(roundf(start_position.x / 4.0) * 4.0, roundf(start_position.y / 4.0) * 4.0)
	bubble.global_position = start_position
	_add_pixel_rect(bubble, Rect2(-4.0, -4.0, 8.0, 8.0), Color("#b8eeeb"))
	_add_pixel_rect(bubble, Rect2(-2.0, -2.0, 4.0, 4.0), Color("#397b91"))
	_add_pixel_rect(bubble, Rect2(-2.0, -2.0, 2.0, 2.0), Color("#e2fff7"))
	add_child(bubble)
	var top_y := camera.global_position.y - get_viewport_rect().size.y / CONFIG.CAMERA_ZOOM * 0.5 - 20.0
	var rise_speed := CONFIG.BACKGROUND_BUBBLE_RISE_SPEED * layout_rng.randf_range(0.8, 1.2)
	var duration := maxf(5.0, (start_position.y - top_y) / rise_speed)
	background_particles.append({"node": bubble, "origin": start_position, "age": 0.0, "duration": duration, "speed": rise_speed, "phase": layout_rng.randf_range(0.0, TAU)})

func _add_pixel_rect(parent: Node2D, rect: Rect2, color: Color) -> void:
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.position + rect.size, rect.position + Vector2(0.0, rect.size.y)])
	polygon.color = color
	parent.add_child(polygon)
