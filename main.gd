extends Node2D

## IBS Runner — An auto-scrolling parkour platformer where your
## irritable bowels provide emergency rocket propulsion.

## --- Tuning ---
@export var run_speed: float = 350.0
@export var speed_increase: float = 8.0        ## per second
@export var max_speed: float = 700.0
@export var jump_force: float = 520.0
@export var gravity: float = 1200.0
@export var boost_thrust: float = 900.0        ## IBS upward force
@export var boost_forward: float = 150.0       ## IBS forward push
@export var max_gas: float = 100.0
@export var gas_drain: float = 40.0            ## per second while boosting
@export var gas_recharge: float = 15.0         ## per second on ground
@export var platform_min_w: float = 200.0
@export var platform_max_w: float = 500.0
@export var gap_min: float = 80.0
@export var gap_max_base: float = 200.0
@export var gap_growth: float = 0.15           ## gap max grows with distance
@export var platform_y_base: float = 550.0
@export var platform_y_variance: float = 80.0
## --- End Tuning ---

# ─── State ───
var player_pos := Vector2(200, 400)
var player_vel := Vector2.ZERO
var on_ground := false
var is_boosting := false
var gas: float = 100.0
var current_speed: float = 350.0
var camera_x: float = 0.0
var distance: float = 0.0
var game_over := false
var game_started := false
var high_score: float = 0.0

# Player dimensions
const PW := 24.0
const PH := 36.0

# Platforms: [{x, y, w}]
var platforms: Array = []

# Boost particles: [{pos, vel, life, max_life, color}]
var particles: Array = []

# Background buildings: [{x, w, h, color}]
var bg_buildings: Array = []
var bg_far_buildings: Array = []

# Animation
var leg_timer: float = 0.0
var shake_amount: float = 0.0

# UI
var cam: Camera2D
var score_label: Label
var gas_label: Label
var status_label: Label
var hint_label: Label

# Colors
const SKY_TOP := Color("#0a0a1a")
const SKY_BOT := Color("#1a1a3e")
const PLATFORM_COLOR := Color("#2c3e50")
const PLATFORM_TOP := Color("#34495e")
const PLAYER_COLOR := Color("#4ecdc4")
const PLAYER_PANTS := Color("#2c3e50")
const BOOST_COLOR_1 := Color("#8B4513")
const BOOST_COLOR_2 := Color("#D2691E")
const BOOST_COLOR_3 := Color("#DAA520")
const CLOUD_COLOR := Color("#4ecdc4", 0.15)
const BUILDING_DARK := Color("#0d1117")
const BUILDING_MID := Color("#161b22")
const TEXT_COLOR := Color("#eee")
const GAS_FULL := Color("#66bb6a")
const GAS_MID := Color("#ffb74d")
const GAS_LOW := Color("#ef5350")
const DANGER_COLOR := Color("#ef5350")


func _ready():
	cam = Camera2D.new()
	cam.enabled = true
	add_child(cam)

	var canvas := CanvasLayer.new()
	add_child(canvas)

	score_label = Label.new()
	score_label.position = Vector2(20, 15)
	score_label.add_theme_font_size_override("font_size", 24)
	score_label.add_theme_color_override("font_color", TEXT_COLOR)
	canvas.add_child(score_label)

	gas_label = Label.new()
	gas_label.position = Vector2(20, 50)
	gas_label.add_theme_font_size_override("font_size", 18)
	gas_label.add_theme_color_override("font_color", GAS_FULL)
	canvas.add_child(gas_label)

	hint_label = Label.new()
	hint_label.position = Vector2(20, 690)
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color("#8899aa"))
	hint_label.text = "Space/Up: Jump  |  Shift/F: IBS Boost  |  R: Restart  |  Esc: Quit"
	canvas.add_child(hint_label)

	# Centered status label
	var status_container := ColorRect.new()
	status_container.color = Color.TRANSPARENT
	status_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(status_container)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 36)
	status_label.add_theme_color_override("font_color", Color("#ffe66d"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_container.add_child(status_label)

	_generate_initial_world()
	status_label.text = "IBS RUNNER\n\nPress Space to Start\n\n[Shift for emergency boost]"


func _generate_initial_world():
	platforms.clear()
	particles.clear()

	# Starting platform (wide, easy)
	platforms.append({"x": -100.0, "y": platform_y_base, "w": 600.0})

	# Generate ahead
	var last_x: float = 500.0
	var last_y: float = platform_y_base
	for i in 15:
		var gap: float = randf_range(gap_min, gap_max_base)
		var w: float = randf_range(platform_min_w, platform_max_w)
		var y_off: float = randf_range(-platform_y_variance * 0.5, platform_y_variance * 0.5)
		var py: float = clampf(last_y + y_off, platform_y_base - 100, platform_y_base + 60)
		platforms.append({"x": last_x + gap, "y": py, "w": w})
		last_x = last_x + gap + w
		last_y = py

	# Background buildings
	_generate_buildings()

	player_pos = Vector2(200, platforms[0]["y"] - PH)
	player_vel = Vector2.ZERO
	camera_x = 0.0
	distance = 0.0
	current_speed = run_speed
	gas = max_gas
	on_ground = true
	is_boosting = false
	game_over = false
	shake_amount = 0.0


func _generate_buildings():
	bg_buildings.clear()
	bg_far_buildings.clear()
	for i in 60:
		bg_far_buildings.append({
			"x": i * 120.0 - 200, "w": randf_range(60, 110),
			"h": randf_range(80, 300),
			"color": BUILDING_DARK.lightened(randf_range(0, 0.05))
		})
	for i in 40:
		bg_buildings.append({
			"x": i * 180.0 - 200, "w": randf_range(80, 160),
			"h": randf_range(100, 350),
			"color": BUILDING_MID.lightened(randf_range(0, 0.04))
		})


func _process(delta: float):
	if game_over:
		return

	if not game_started:
		if Input.is_action_just_pressed("ui_accept"):
			game_started = true
			status_label.text = ""
		else:
			queue_redraw()
			return

	# ── Speed increases over time ──
	current_speed = minf(current_speed + speed_increase * delta, max_speed)
	distance += current_speed * delta

	# ── Player auto-run ──
	player_vel.x = current_speed

	# ── Jump ──
	if (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up")) and on_ground:
		player_vel.y = -jump_force
		on_ground = false

	# ── IBS Boost ──
	is_boosting = false
	if (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_F)) and gas > 0 and not on_ground:
		is_boosting = true
		gas -= gas_drain * delta
		gas = maxf(gas, 0)
		player_vel.y -= boost_thrust * delta
		player_vel.x += boost_forward * delta
		shake_amount = 3.0
		# Spawn boost particles
		_spawn_boost_particles(delta)
	else:
		shake_amount = maxf(shake_amount - 15.0 * delta, 0)

	# ── Gas recharge on ground ──
	if on_ground:
		gas = minf(gas + gas_recharge * delta, max_gas)

	# ── Gravity ──
	player_vel.y += gravity * delta
	player_vel.y = minf(player_vel.y, 800.0)

	# ── Move player ──
	player_pos += player_vel * delta

	# ── Platform collision ──
	on_ground = false
	for plat in platforms:
		if _collide_platform(plat):
			break

	# ── Camera follows player ──
	camera_x = player_pos.x + 300
	cam.position = Vector2(camera_x, 360)
	cam.position += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amount

	# ── Death: fell off bottom or left behind ──
	if player_pos.y > 900:
		_die("Fell into the void!")
	elif player_pos.x < camera_x - 700:
		_die("Too slow!")

	# ── Generate more platforms ahead ──
	_extend_platforms()

	# ── Update particles ──
	_update_particles(delta)

	# ── Update UI ──
	score_label.text = "Distance: %dm  |  Speed: %d" % [int(distance / 50), int(current_speed)]

	var gas_pct: float = gas / max_gas
	var gas_bar := ""
	var bar_len := 20
	var filled := int(gas_pct * bar_len)
	for i in bar_len:
		gas_bar += "█" if i < filled else "░"
	gas_label.text = "GAS [%s] %d%%" % [gas_bar, int(gas_pct * 100)]
	if gas_pct > 0.5:
		gas_label.add_theme_color_override("font_color", GAS_FULL)
	elif gas_pct > 0.25:
		gas_label.add_theme_color_override("font_color", GAS_MID)
	else:
		gas_label.add_theme_color_override("font_color", GAS_LOW)

	queue_redraw()


func _collide_platform(plat: Dictionary) -> bool:
	var px: float = plat["x"]
	var py: float = plat["y"]
	var pw: float = plat["w"]

	# Player feet
	var feet_y: float = player_pos.y + PH
	var prev_feet_y: float = feet_y - player_vel.y * get_process_delta_time()

	# Check horizontal overlap
	if player_pos.x + PW > px and player_pos.x < px + pw:
		# Landing on top (was above, now at or below platform top)
		if prev_feet_y <= py + 2 and feet_y >= py - 2 and player_vel.y >= 0:
			player_pos.y = py - PH
			player_vel.y = 0
			on_ground = true
			return true
	return false


func _die(reason: String):
	game_over = true
	var dist_m := int(distance / 50)
	if dist_m > high_score:
		high_score = dist_m
	status_label.text = "%s\n\nDistance: %dm\nBest: %dm\n\nPress R to retry" % [reason, dist_m, int(high_score)]


func _extend_platforms():
	# Remove platforms far behind camera
	while not platforms.is_empty() and platforms[0]["x"] + platforms[0]["w"] < camera_x - 800:
		platforms.pop_front()

	# Generate platforms ahead
	var view_right := camera_x + 900
	if platforms.is_empty():
		return
	var last: Dictionary = platforms.back()
	var last_end: float = last["x"] + last["w"]

	while last_end < view_right + 600:
		# Gap grows with distance
		var gap_max_now: float = gap_max_base + distance * gap_growth * 0.01
		gap_max_now = minf(gap_max_now, 500.0)
		var gap: float = randf_range(gap_min, gap_max_now)

		# Occasionally create a big "IBS gap"
		if randf() < 0.15 and distance > 2000:
			gap = randf_range(gap_max_now * 0.8, gap_max_now * 1.2)

		var w: float = randf_range(platform_min_w, platform_max_w)
		var y_off: float = randf_range(-platform_y_variance, platform_y_variance * 0.3)
		var py: float = clampf(last["y"] + y_off, platform_y_base - 120, platform_y_base + 60)

		platforms.append({"x": last_end + gap, "y": py, "w": w})
		last = platforms.back()
		last_end = last["x"] + last["w"]


func _spawn_boost_particles(delta: float):
	var spawn_count := int(30 * delta) + 1
	for i in spawn_count:
		var offset := Vector2(-PW * 0.3, PH * 0.7 + randf_range(-4, 4))
		var p_pos := player_pos + offset
		var spread := randf_range(-0.4, 0.4)
		var p_vel := Vector2(
			-randf_range(80, 250) + player_vel.x * 0.3,
			randf_range(100, 350)
		).rotated(spread)
		var colors := [BOOST_COLOR_1, BOOST_COLOR_2, BOOST_COLOR_3]
		particles.append({
			"pos": p_pos,
			"vel": p_vel,
			"life": randf_range(0.3, 0.7),
			"max_life": 0.7,
			"size": randf_range(3, 8),
			"color": colors[randi() % 3],
		})


func _update_particles(delta: float):
	var alive: Array = []
	for p in particles:
		p["life"] -= delta
		if p["life"] > 0:
			p["pos"] += p["vel"] * delta
			p["vel"].y += 200 * delta  # particles fall
			alive.append(p)
	particles = alive


func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_generate_initial_world()
		game_started = false
		game_over = false
		status_label.text = "IBS RUNNER\n\nPress Space to Start\n\n[Shift for emergency boost]"


# ═══════════════════════════════════════
# RENDERING
# ═══════════════════════════════════════

func _draw():
	var view_left := camera_x - 660.0
	var view_right := camera_x + 660.0

	# ── Sky gradient ──
	draw_rect(Rect2(view_left, -200, 1320, 1100), SKY_TOP)

	# ── Far buildings (parallax 0.3x) ──
	for b in bg_far_buildings:
		var bx: float = b["x"] - camera_x * 0.3
		# Wrap
		bx = fmod(bx + 4000, 7200.0) - 1000 + view_left
		if bx + b["w"] > view_left and bx < view_right:
			var by: float = platform_y_base + 40 - b["h"]
			draw_rect(Rect2(bx, by, b["w"], b["h"] + 200), b["color"])

	# ── Near buildings (parallax 0.6x) ──
	for b in bg_buildings:
		var bx: float = b["x"] - camera_x * 0.6
		bx = fmod(bx + 4000, 7200.0) - 1000 + view_left
		if bx + b["w"] > view_left and bx < view_right:
			var by: float = platform_y_base + 20 - b["h"]
			draw_rect(Rect2(bx, by, b["w"], b["h"] + 200), b["color"])
			# Window lights
			for wy in range(3, int(b["h"] / 25)):
				for wx in range(1, int(b["w"] / 20)):
					if randf() < 0.0005:  # very sparse to avoid flickering
						continue
					var lx := bx + wx * 20.0
					var ly := by + wy * 25.0
					draw_rect(Rect2(lx, ly, 6, 8), Color("#ffdd44", 0.15))

	# ── Platforms ──
	for plat in platforms:
		var px: float = plat["x"]
		var py: float = plat["y"]
		var pw: float = plat["w"]
		if px + pw < view_left or px > view_right:
			continue

		# Platform body
		draw_rect(Rect2(px, py, pw, 300), PLATFORM_COLOR)
		# Top edge highlight
		draw_rect(Rect2(px, py, pw, 4), PLATFORM_TOP)
		# Left/right edges
		draw_line(Vector2(px, py), Vector2(px, py + 300), PLATFORM_TOP, 2.0)
		draw_line(Vector2(px + pw, py), Vector2(px + pw, py + 300), PLATFORM_TOP, 2.0)

	# ── Danger zone indicator (left edge of screen) ──
	if game_started and not game_over:
		var danger_x := camera_x - 640
		draw_rect(Rect2(danger_x, -200, 15, 1100), Color(DANGER_COLOR, 0.3))
		draw_rect(Rect2(danger_x, -200, 3, 1100), DANGER_COLOR)

	# ── Boost particles ──
	for p in particles:
		var alpha: float = clampf(p["life"] / p["max_life"], 0, 1)
		var col: Color = p["color"]
		col.a = alpha
		var sz: float = p["size"] * alpha
		draw_circle(p["pos"], sz, col)

	# ── Player ──
	if not game_over:
		_draw_player()


func _draw_player():
	var px := player_pos.x
	var py := player_pos.y

	# Body
	draw_rect(Rect2(px + 4, py + 2, PW - 8, PH * 0.55), PLAYER_COLOR)

	# Head
	draw_circle(Vector2(px + PW * 0.5, py + 4), 8, PLAYER_COLOR)

	# Pants / legs
	draw_rect(Rect2(px + 4, py + PH * 0.5, PW - 8, PH * 0.35), PLAYER_PANTS)

	# Animated legs
	leg_timer += get_process_delta_time() * current_speed * 0.03
	if on_ground:
		var leg_offset := sin(leg_timer) * 6
		# Left leg
		draw_line(
			Vector2(px + 8, py + PH * 0.8),
			Vector2(px + 8 + leg_offset, py + PH),
			PLAYER_PANTS, 3.0)
		# Right leg
		draw_line(
			Vector2(px + PW - 8, py + PH * 0.8),
			Vector2(px + PW - 8 - leg_offset, py + PH),
			PLAYER_PANTS, 3.0)
	else:
		# Legs tucked in air
		draw_line(
			Vector2(px + 8, py + PH * 0.8),
			Vector2(px + 4, py + PH - 2),
			PLAYER_PANTS, 3.0)
		draw_line(
			Vector2(px + PW - 8, py + PH * 0.8),
			Vector2(px + PW - 4, py + PH - 2),
			PLAYER_PANTS, 3.0)

	# Eyes (looking forward)
	draw_circle(Vector2(px + PW * 0.6, py + 2), 2.0, Color.WHITE)
	draw_circle(Vector2(px + PW * 0.6 + 1, py + 2), 1.0, Color("#333"))

	# Boost effect: strained face + rumble lines
	if is_boosting:
		# Strained expression
		draw_circle(Vector2(px + PW * 0.65, py + 7), 1.5, DANGER_COLOR)
		# Boost cloud behind
		for i in 3:
			var cloud_x := px - 5 - i * 8
			var cloud_y := py + PH * 0.7 + randf_range(-3, 3)
			draw_circle(Vector2(cloud_x, cloud_y), 5 + i * 2, Color(BOOST_COLOR_2, 0.4))
