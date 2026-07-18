extends CanvasLayer
## Sea of Thieves-style wind compass with animated flow ribbons, rotating arrow,
## cardinal labels, speed arc, state badge, and gust flash.
class_name WindCompass

# ── Layout constants ────────────────────────────────────────────────────────
const COMPASS_RADIUS  := 100.0
const ARROW_LEN       := 76.0
const RIBBON_COUNT    := 14
const RIBBON_LEN      := 85.0
const RIBBON_SPACING  := 7.0
const ARC_WIDTH       := 13.0
const PANEL_MARGIN    := 24.0

# ── Runtime state ──────────────────────────────────────────────────────────
var _wind_direction: Vector3  = Vector3(1.0, 0.0, 0.0)
var _wind_strength: float     = 0.0
var _gust_factor: float       = 0.0
var _state_name: String       = "Normal"
var _smooth_strength: float   = 0.0
var _smooth_angle: float      = 0.0   # radians in XZ plane
var _gust_flash: float        = 0.0   # 0-1 flash alpha triggered on big gust
var _prev_gust_factor: float  = 0.0
var _time: float              = 0.0

# ── Nodes ──────────────────────────────────────────────────────────────────
var _canvas: Control
var _wind_manager: WindManager = null

func _ready() -> void:
	layer = 125
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	_connect_wind_manager()

func _connect_wind_manager() -> void:
	_wind_manager = _find_wind_manager()
	if _wind_manager:
		if not _wind_manager.wind_changed.is_connected(_on_wind_changed):
			_wind_manager.wind_changed.connect(_on_wind_changed)
	else:
		# Retry next frame in case scene isn't fully loaded
		call_deferred("_connect_wind_manager")

func _find_wind_manager() -> WindManager:
	var scene := get_tree().current_scene if get_tree() else null
	if scene == null:
		return null
	var direct := scene.get_node_or_null("WindManager")
	if direct is WindManager:
		return direct as WindManager
	for child in scene.get_children():
		if child is WindManager:
			return child as WindManager
		var nested := child.find_child("WindManager", true, false)
		if nested is WindManager:
			return nested as WindManager
	return null

func _on_wind_changed(direction: Vector3, strength: float, gust_factor: float, state_name: String) -> void:
	_wind_direction = direction
	_wind_strength  = strength
	_gust_factor    = gust_factor
	_state_name     = state_name
	if gust_factor - _prev_gust_factor > 0.18:
		_gust_flash = 1.0
	_prev_gust_factor = gust_factor

func _process(delta: float) -> void:
	_time += delta

	# Smooth displayed strength and angle
	_smooth_strength = lerpf(_smooth_strength, _wind_strength, delta * 2.5)

	# Compute target angle from wind direction in XZ plane
	var target_angle := atan2(-_wind_direction.x, -_wind_direction.z)
	var angle_diff := fmod(target_angle - _smooth_angle + PI * 3.0, TAU) - PI
	_smooth_angle += angle_diff * delta * 3.5

	# Gust flash decay
	_gust_flash = maxf(0.0, _gust_flash - delta * 2.2)

	if _wind_manager == null:
		_wind_manager = _find_wind_manager()
		if _wind_manager:
			if not _wind_manager.wind_changed.is_connected(_on_wind_changed):
				_wind_manager.wind_changed.connect(_on_wind_changed)

	_canvas.queue_redraw()

func _on_draw() -> void:
	var vp_size := _canvas.get_rect().size
	# Anchor compass to bottom-LEFT corner (away from battery HUD on the right)
	var cx := COMPASS_RADIUS + PANEL_MARGIN + ARC_WIDTH
	var cy := vp_size.y - COMPASS_RADIUS - PANEL_MARGIN - ARC_WIDTH - 36.0
	var center := Vector2(cx, cy)

	_draw_backing(center)
	_draw_speed_arc(center)
	_draw_cardinal_labels(center)
	_draw_flow_ribbons(center)
	_draw_compass_ring(center)
	_draw_direction_arrow(center)
	_draw_state_badge(center)
	if _gust_flash > 0.01:
		_draw_gust_flash(center)

# ── Panel background ────────────────────────────────────────────────────────
func _draw_backing(center: Vector2) -> void:
	var r := COMPASS_RADIUS + ARC_WIDTH + 6.0
	# Soft shadow circle
	_canvas.draw_circle(center, r + 4.0, Color(0.0, 0.0, 0.0, 0.28))
	# Dark glass panel
	_canvas.draw_circle(center, r, Color(0.03, 0.06, 0.10, 0.78))

# ── Outer speed arc (coloured fill arc) ─────────────────────────────────────
func _draw_speed_arc(center: Vector2) -> void:
	var max_speed := 7.5
	var fill := clampf(_smooth_strength / max_speed, 0.0, 1.0)
	var r    := COMPASS_RADIUS + ARC_WIDTH * 0.5

	# Background arc (full circle, dim)
	_draw_arc_thick(center, r, 0.0, TAU, ARC_WIDTH, Color(0.1, 0.15, 0.2, 0.6))

	# Coloured fill arc
	if fill > 0.001:
		var arc_col := _speed_colour(fill)
		_draw_arc_thick(center, r, -PI * 0.5, -PI * 0.5 + fill * TAU, ARC_WIDTH, arc_col)

func _speed_colour(t: float) -> Color:
	# Calm=cyan → Normal=sky → Heavy=orange/red
	if t < 0.4:
		return Color(0.2, 0.85, 1.0, 0.9).lerp(Color(0.3, 0.65, 1.0, 0.9), t / 0.4)
	elif t < 0.75:
		return Color(0.3, 0.65, 1.0, 0.9).lerp(Color(1.0, 0.65, 0.15, 0.9), (t - 0.4) / 0.35)
	else:
		return Color(1.0, 0.65, 0.15, 0.9).lerp(Color(1.0, 0.2, 0.1, 0.95), (t - 0.75) / 0.25)

func _draw_arc_thick(center: Vector2, radius: float, from_angle: float, to_angle: float, width: float, color: Color) -> void:
	var steps: int = max(int(abs(to_angle - from_angle) / 0.08), 6)
	var prev := Vector2.ZERO
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := lerpf(from_angle, to_angle, t)
		var pt := center + Vector2(cos(a), sin(a)) * radius
		if i > 0:
			_canvas.draw_line(prev, pt, color, width, true)
		prev = pt

# ── Compass ring and tick marks ─────────────────────────────────────────────
func _draw_compass_ring(center: Vector2) -> void:
	# Outer ring
	_draw_arc_thick(center, COMPASS_RADIUS, 0.0, TAU, 1.6, Color(0.5, 0.75, 1.0, 0.45))

	# Tick marks every 45°
	for i in range(8):
		var angle := (PI / 4.0) * float(i)
		var inner := COMPASS_RADIUS - (8.0 if i % 2 == 0 else 4.0)
		var p0 := center + Vector2(cos(angle), sin(angle)) * inner
		var p1 := center + Vector2(cos(angle), sin(angle)) * COMPASS_RADIUS
		var col := Color(0.7, 0.9, 1.0, 0.8) if i % 2 == 0 else Color(0.5, 0.7, 0.9, 0.5)
		_canvas.draw_line(p0, p1, col, 1.5)

# ── Cardinal direction labels ────────────────────────────────────────────────
func _draw_cardinal_labels(center: Vector2) -> void:
	# Angles: N=top (-π/2), E=right (0), S=bottom (π/2), W=left (π)
	var cardinals := {
		"N": -PI * 0.5,
		"E": 0.0,
		"S": PI * 0.5,
		"W": PI,
	}
	var label_r := COMPASS_RADIUS - 18.0
	for label in cardinals:
		var a: float = cardinals[label]
		var pt := center + Vector2(cos(a), sin(a)) * label_r - Vector2(5.0, 7.0)
		var col := Color(0.9, 0.95, 1.0, 0.85) if label != "N" else Color(1.0, 0.35, 0.35, 1.0)
		_canvas.draw_string(ThemeDB.fallback_font, pt, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, col)

# ── Animated flow ribbons (Sea of Thieves style) ─────────────────────────────
func _draw_flow_ribbons(center: Vector2) -> void:
	if _smooth_strength < 0.05:
		return

	# Arrow direction in 2D (wind blows "from" this angle, ribbons flow "toward")
	var flow_angle := _smooth_angle   # direction wind is blowing toward

	# Speed-dependent ribbon properties
	var speed_t := clampf(_smooth_strength / 7.0, 0.0, 1.0)
	var ribbon_alpha := lerpf(0.08, 0.55, speed_t)
	var ribbon_speed := lerpf(18.0, 60.0, speed_t)
	var ribbon_len_t := lerpf(18.0, RIBBON_LEN, speed_t)

	# Perpendicular offset base
	var perp := Vector2(cos(flow_angle + PI * 0.5), sin(flow_angle + PI * 0.5))
	var flow  := Vector2(cos(flow_angle), sin(flow_angle))

	for i in range(RIBBON_COUNT):
		var idx := i - RIBBON_COUNT / 2
		var offset := perp * idx * RIBBON_SPACING

		# Time offset per ribbon for staggered animation
		var t_offset := fmod(_time * ribbon_speed + float(i) * 8.5, RIBBON_LEN * 1.8)

		# Each ribbon fades as it extends outward
		for seg in range(6):
			var t0 := t_offset + seg * ribbon_len_t / 6.0
			var t1 := t0 + ribbon_len_t / 6.0
			# Only draw inside compass area with fade at edges
			var edge_fade := 1.0 - clampf((t0 / RIBBON_LEN) * 0.9, 0.0, 0.9)
			var seg_alpha := ribbon_alpha * edge_fade * lerpf(0.2, 1.0, float(seg + 1) / 6.0)

			# Only inside compass circle
			var p0 := center + offset + flow * fmod(t0, RIBBON_LEN)
			var p1 := center + offset + flow * fmod(t1, RIBBON_LEN)
			if center.distance_to(p0) < COMPASS_RADIUS - 4.0 and center.distance_to(p1) < COMPASS_RADIUS - 4.0:
				var col := Color(0.55, 0.88, 1.0, seg_alpha)
				_canvas.draw_line(p0, p1, col, lerpf(1.0, 2.0, speed_t), true)

# ── Directional arrow ────────────────────────────────────────────────────────
func _draw_direction_arrow(center: Vector2) -> void:
	var angle := _smooth_angle
	var dir   := Vector2(cos(angle), sin(angle))
	var perp  := Vector2(-dir.y, dir.x)

	var tip  := center + dir * ARROW_LEN
	var base := center - dir * (ARROW_LEN * 0.35)

	# Shaft
	_canvas.draw_line(base, tip, Color(1.0, 1.0, 1.0, 0.2), 2.5, true)

	# Arrowhead
	var head_back := tip - dir * 14.0
	var h_left    := head_back + perp * 7.0
	var h_right   := head_back - perp * 7.0

	var speed_t := clampf(_smooth_strength / 7.0, 0.0, 1.0)
	var arrow_col := _speed_colour(speed_t).lightened(0.2)
	arrow_col.a = 1.0

	var pts := PackedVector2Array([tip, h_left, h_right])
	_canvas.draw_colored_polygon(pts, arrow_col)
	_canvas.draw_polyline(PackedVector2Array([h_left, tip, h_right]), Color(1.0, 1.0, 1.0, 0.6), 1.5, true)

	# Centre dot
	_canvas.draw_circle(center, 3.5, Color(1.0, 1.0, 1.0, 0.7))
	_canvas.draw_arc(center, 3.5, 0.0, TAU, 16, Color(0.5, 0.8, 1.0, 0.9), 1.0)

# ── State badge label ────────────────────────────────────────────────────────
func _draw_state_badge(center: Vector2) -> void:
	var speed_t  := clampf(_smooth_strength / 7.0, 0.0, 1.0)
	var badge_col := _speed_colour(speed_t)

	# State text just below compass
	var state_pos := center + Vector2(-28.0, COMPASS_RADIUS + ARC_WIDTH + 10.0)
	var mps_text := "%s  %.1f m/s" % [_state_name, _smooth_strength]
	# Shadow
	_canvas.draw_string(ThemeDB.fallback_font, state_pos + Vector2(1, 1), mps_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.0, 0.0, 0.7))
	# Label
	_canvas.draw_string(ThemeDB.fallback_font, state_pos, mps_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, badge_col)

# ── Gust flash pulse ─────────────────────────────────────────────────────────
func _draw_gust_flash(center: Vector2) -> void:
	var alpha := _gust_flash * 0.35
	_canvas.draw_circle(center, COMPASS_RADIUS + ARC_WIDTH + 4.0, Color(0.6, 0.9, 1.0, alpha))
