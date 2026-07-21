extends CanvasLayer

## Debug overlay inspired by Minecraft's F3 screen.
## Toggle with the V key. Shows FPS (top-right) and a
## detailed stats panel (right side): RAM, VRAM, GPU, draw calls, etc.

const TOGGLE_KEY := KEY_V
const FONT_SIZE_FPS := 22
const FONT_SIZE_STATS := 17
const FONT_SIZE_BATTERY := 28
const BATTERY_PANEL_WIDTH := 240
const BATTERY_PANEL_HEIGHT := 92
const PANEL_WIDTH := 340
const PADDING := 12
const LINE_HEIGHT := 22
const UPDATE_INTERVAL := 0.15  # seconds between stat refreshes

var _visible := false
var _timer := 0.0

# ── UI nodes ────────────────────────────────────────────────────────────────
var _fps_label: Label
var _battery_panel: PanelContainer
var _battery_margin: MarginContainer
var _battery_vbox: VBoxContainer
var _battery_icon_box: Control
var _battery_percent_label: Label
var _stats_panel: PanelContainer
var _stats_label: Label

# ── cached values updated on interval ────────────────────────────────────────
var _stat_lines: Array[String] = []

func _ready() -> void:
	layer = 128  # draw on top of everything
	_build_fps_label()
	_build_battery_hud()
	_build_stats_panel()
	_apply_visibility()

# ─────────────────────────────────────────────────────────────────────────────
#  Input
# ─────────────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEY:
			_visible = !_visible
			_apply_visibility()

# ─────────────────────────────────────────────────────────────────────────────
#  Per-frame update
# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	# FPS counter always updates every frame for accuracy
	var fps := Engine.get_frames_per_second()
	var fps_color := _fps_color(fps)
	_fps_label.text = "FPS: %d" % fps
	_fps_label.add_theme_color_override("font_color", fps_color)
	_update_battery_display()

	if not _visible:
		return

	_timer += delta
	if _timer >= UPDATE_INTERVAL:
		_timer = 0.0
		_refresh_stats()
		_stats_label.text = "\n".join(_stat_lines)

# ─────────────────────────────────────────────────────────────────────────────
#  Stat collection
# ─────────────────────────────────────────────────────────────────────────────
func _refresh_stats() -> void:
	_stat_lines.clear()

	var vp := get_viewport()
	var rs := RenderingServer

	# ── FPS / frame time ───────────────────────────────────────────────────
	var fps := Engine.get_frames_per_second()
	var ms  := 0.0
	if fps > 0:
		ms = 1000.0 / fps
	_stat_lines.append("─── Performance ───────────────")
	_stat_lines.append("FPS:        %d  (%.2f ms)" % [fps, ms])
	_stat_lines.append("Engine ver: %s" % Engine.get_version_info().string)

	# ── Memory ─────────────────────────────────────────────────────────────
	var static_mem  := float(OS.get_static_memory_usage())       # bytes
	var static_peak := float(OS.get_static_memory_peak_usage())
	_stat_lines.append("")
	_stat_lines.append("─── Memory ────────────────────")
	_stat_lines.append("RAM Used:   %s" % _fmt_bytes(static_mem))
	_stat_lines.append("RAM Peak:   %s" % _fmt_bytes(static_peak))

	# ── VRAM / GPU ─────────────────────────────────────────────────────────
	# RenderingServer exposes texture & buffer memory on supported backends
	var tex_mem    := float(rs.get_rendering_info(rs.RENDERING_INFO_TEXTURE_MEM_USED))
	var buf_mem    := float(rs.get_rendering_info(rs.RENDERING_INFO_BUFFER_MEM_USED))
	var total_vram := tex_mem + buf_mem
	_stat_lines.append("")
	_stat_lines.append("─── GPU / VRAM ─────────────────")
	_stat_lines.append("VRAM Total: %s" % _fmt_bytes(total_vram))
	_stat_lines.append("  Textures: %s" % _fmt_bytes(tex_mem))
	_stat_lines.append("  Buffers:  %s" % _fmt_bytes(buf_mem))
	_stat_lines.append("GPU:        %s" % rs.get_video_adapter_name())
	_stat_lines.append("API:        %s" % _get_renderer_name())

	# ── Draw calls / objects ───────────────────────────────────────────────
	var draw_calls := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims      := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objects    := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	_stat_lines.append("")
	_stat_lines.append("─── Render Stats ───────────────")
	_stat_lines.append("Draw Calls: %d" % draw_calls)
	_stat_lines.append("Objects:    %d" % objects)
	_stat_lines.append("Primitives: %s" % _fmt_large(prims))

	# ── Viewport ───────────────────────────────────────────────────────────
	if vp:
		var vp_size := vp.get_visible_rect().size
		_stat_lines.append("")
		_stat_lines.append("─── Viewport ───────────────────")
		_stat_lines.append("Resolution: %dx%d" % [int(vp_size.x), int(vp_size.y)])
		_stat_lines.append("MSAA:       %s" % _msaa_name(vp.msaa_3d))
		_stat_lines.append("V-Sync:     %s" % _vsync_name(DisplayServer.window_get_vsync_mode()))

	# ── Scene ──────────────────────────────────────────────────────────────
	var node_count := _count_nodes(get_tree().root)
	_stat_lines.append("")
	_stat_lines.append("─── Scene ──────────────────────")
	_stat_lines.append("Node count: %d" % node_count)
	_stat_lines.append("Scene:      %s" % get_tree().current_scene.name if get_tree().current_scene else "—")

	# ── OS / Hardware ──────────────────────────────────────────────────────
	_stat_lines.append("")
	_stat_lines.append("─── System ─────────────────────")
	_stat_lines.append("OS:         %s" % OS.get_name())
	_stat_lines.append("CPU cores:  %d" % OS.get_processor_count())
	_stat_lines.append("CPU:        %s" % OS.get_processor_name())

	# ── hint ───────────────────────────────────────────────────────────────
	_stat_lines.append("")
	_stat_lines.append("[V] toggle debug overlay")

# ─────────────────────────────────────────────────────────────────────────────
#  UI builders
# ─────────────────────────────────────────────────────────────────────────────
func _build_fps_label() -> void:
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", FONT_SIZE_FPS)
	_fps_label.add_theme_color_override("font_color", Color.WHITE)
	_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_fps_label.add_theme_constant_override("shadow_offset_x", 2)
	_fps_label.add_theme_constant_override("shadow_offset_y", 2)
	_fps_label.add_theme_constant_override("shadow_outline_size", 1)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.anchor_left   = 1.0
	_fps_label.anchor_right  = 1.0
	_fps_label.anchor_top    = 0.0
	_fps_label.anchor_bottom = 0.0
	_fps_label.offset_left   = -220
	_fps_label.offset_right  = -PADDING
	_fps_label.offset_top    = PADDING
	_fps_label.offset_bottom = PADDING + FONT_SIZE_FPS + 4
	add_child(_fps_label)

func _build_battery_hud() -> void:
	_battery_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_battery_panel.add_theme_stylebox_override("panel", style)
	_battery_panel.anchor_left = 1.0
	_battery_panel.anchor_right = 1.0
	_battery_panel.anchor_top = 1.0
	_battery_panel.anchor_bottom = 1.0
	_battery_panel.offset_left = -(BATTERY_PANEL_WIDTH + PADDING)
	_battery_panel.offset_right = -PADDING
	_battery_panel.offset_top = -(BATTERY_PANEL_HEIGHT + PADDING)
	_battery_panel.offset_bottom = -PADDING

	_battery_margin = MarginContainer.new()
	_battery_panel.add_child(_battery_margin)

	_battery_vbox = VBoxContainer.new()
	_battery_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battery_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battery_margin.add_child(_battery_vbox)

	_battery_icon_box = Control.new()
	_battery_icon_box.custom_minimum_size = Vector2(0, 42)
	_battery_icon_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battery_icon_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battery_icon_box.draw.connect(_draw_battery_icon)
	_battery_vbox.add_child(_battery_icon_box)

	_battery_percent_label = Label.new()
	_battery_percent_label.add_theme_font_size_override("font_size", FONT_SIZE_BATTERY)
	_battery_percent_label.add_theme_color_override("font_color", Color.WHITE)
	_battery_percent_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_battery_percent_label.add_theme_constant_override("shadow_offset_x", 2)
	_battery_percent_label.add_theme_constant_override("shadow_offset_y", 2)
	_battery_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battery_vbox.add_child(_battery_percent_label)
	add_child(_battery_panel)

func _build_stats_panel() -> void:
	# Semi-transparent dark background panel
	_stats_panel = PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color             = Color(0.0, 0.0, 0.0, 0.72)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = PADDING
	style.content_margin_right  = PADDING
	style.content_margin_top    = PADDING
	style.content_margin_bottom = PADDING
	_stats_panel.add_theme_stylebox_override("panel", style)

	# Anchor to top-right, below the FPS label
	_stats_panel.anchor_left   = 1.0
	_stats_panel.anchor_right  = 1.0
	_stats_panel.anchor_top    = 0.0
	_stats_panel.anchor_bottom = 0.0
	_stats_panel.offset_left   = -(PANEL_WIDTH + PADDING)
	_stats_panel.offset_right  = -PADDING
	_stats_panel.offset_top    = PADDING + FONT_SIZE_FPS + 14
	_stats_panel.offset_bottom = 900   # tall enough; PanelContainer clips content

	# Label inside the panel
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", FONT_SIZE_STATS)
	_stats_label.add_theme_color_override("font_color", Color.WHITE)
	_stats_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_stats_label.add_theme_constant_override("shadow_offset_x", 1)
	_stats_label.add_theme_constant_override("shadow_offset_y", 1)
	_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_stats_label.autowrap_mode      = TextServer.AUTOWRAP_OFF
	_stats_panel.add_child(_stats_label)
	add_child(_stats_panel)

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────
func _apply_visibility() -> void:
	_stats_panel.visible = _visible
	# FPS label is always visible
	_fps_label.visible = true
	_battery_panel.visible = true

func _update_battery_display() -> void:
	var drone := _get_drone()
	if drone == null:
		_battery_percent_label.text = "Battery: --"
		_battery_percent_label.add_theme_color_override("font_color", Color.WHITE)
		_battery_icon_box.queue_redraw()
		return

	var battery_percent := 0.0
	if drone.has_method("get_battery_percent"):
		battery_percent = float(drone.get_battery_percent())
	else:
		_battery_percent_label.text = "Battery: --"
		_battery_percent_label.add_theme_color_override("font_color", Color.WHITE)
		_battery_icon_box.queue_redraw()
		return

	var battery_color := _battery_color(battery_percent)
	var battery_text := "%d%%" % int(round(battery_percent))
	if drone.has_method("is_battery_auto_landing") and drone.is_battery_auto_landing():
		battery_text += "  LANDING"
	elif drone.has_method("is_battery_critical") and drone.is_battery_critical():
		battery_text += "  CRITICAL"
	elif drone.has_method("is_battery_low_warning") and drone.is_battery_low_warning():
		battery_text += "  LOW"

	_battery_percent_label.text = battery_text
	_battery_percent_label.add_theme_color_override("font_color", battery_color)
	_battery_icon_box.queue_redraw()

func _draw_battery_icon() -> void:
	if not is_instance_valid(_battery_icon_box):
		return

	var rect := _battery_icon_box.get_rect()
	var size := Vector2(rect.size.x, rect.size.y)
	var body_margin := 4.0
	var cap_width := 14.0
	var cap_height := 12.0
	var body_rect := Rect2(Vector2(0, 2), Vector2(size.x - cap_width - 2, size.y - 4))
	var cap_rect := Rect2(Vector2(size.x - cap_width, (size.y - cap_height) * 0.5), Vector2(cap_width, cap_height))

	var drone := _get_drone()
	var percent := 0.0
	if drone and drone.has_method("get_battery_percent"):
		percent = clampf(float(drone.get_battery_percent()), 0.0, 100.0)
	var fill_t := percent / 100.0
	var fill_color := _battery_color(percent)

	_battery_icon_box.draw_rect(body_rect, Color(0.1, 0.1, 0.1, 0.95), true)
	_battery_icon_box.draw_rect(body_rect, Color(1, 1, 1, 0.9), false, 2.0)
	_battery_icon_box.draw_rect(cap_rect, Color(1, 1, 1, 0.9), true)
	_battery_icon_box.draw_rect(cap_rect, Color(1, 1, 1, 0.9), false, 2.0)

	var inner := body_rect.grow(-body_margin)
	inner.size.x = maxf(inner.size.x, 1.0)
	inner.size.y = maxf(inner.size.y, 1.0)
	var fill_width := inner.size.x * fill_t
	var fill_rect := Rect2(inner.position, Vector2(fill_width, inner.size.y))
	if fill_width > 0.0:
		_battery_icon_box.draw_rect(fill_rect, fill_color, true)

	# Energy pulse lines to make the fill feel alive.
	if fill_width > 6.0:
		var pulse_x := inner.position.x + fill_width * 0.65
		for i in range(3):
			var x := pulse_x + float(i) * 5.0
			if x < inner.position.x + fill_width:
				_battery_icon_box.draw_line(Vector2(x, inner.position.y + 4), Vector2(x - 6, inner.position.y + inner.size.y - 4), Color(1, 1, 1, 0.25), 1.0)

func _battery_color(percent: float) -> Color:
	var t: float = clampf(percent / 100.0, 0.0, 1.0)
	# White at full battery, then increasingly red as it drains.
	return Color(1.0, t, t)

func _get_drone() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var manager := scene.get_node_or_null("DroneControllerManager")
	if manager == null:
		return null
	if manager.has_method("get_drone"):
		return manager.get_drone()
	if manager.has_variable("drone"):
		return manager.drone
	return null

func _fps_color(fps: int) -> Color:
	if fps >= 60:
		return Color(0.0, 1.0, 0.4)   # green
	elif fps >= 30:
		return Color(1.0, 0.85, 0.0)  # yellow
	else:
		return Color(1.0, 0.25, 0.25) # red

func _fmt_bytes(b: float) -> String:
	if b >= 1073741824.0:
		return "%.2f GB" % (b / 1073741824.0)
	elif b >= 1048576.0:
		return "%.1f MB" % (b / 1048576.0)
	elif b >= 1024.0:
		return "%.1f KB" % (b / 1024.0)
	return "%d B" % int(b)

func _fmt_large(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (float(n) / 1000000.0)
	elif n >= 1000:
		return "%.1fK" % (float(n) / 1000.0)
	return str(n)

func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count

func _get_renderer_name() -> String:
	match ProjectSettings.get_setting("rendering/renderer/rendering_method", ""):
		"forward_plus":      return "Forward+"
		"mobile":            return "Forward Mobile"
		"compatibility":     return "Compatibility (GL)"
		_:                   return "Unknown"

func _msaa_name(msaa) -> String:
	match msaa:
		Viewport.MSAA_DISABLED: return "Off"
		Viewport.MSAA_2X:       return "2×"
		Viewport.MSAA_4X:       return "4×"
		Viewport.MSAA_8X:       return "8×"
		_:                      return "?"

func _vsync_name(mode) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED:  return "Off"
		DisplayServer.VSYNC_ENABLED:   return "On"
		DisplayServer.VSYNC_ADAPTIVE:  return "Adaptive"
		DisplayServer.VSYNC_MAILBOX:   return "Mailbox"
		_:                             return "?"
