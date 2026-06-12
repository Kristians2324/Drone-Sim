extends CanvasLayer

## Debug overlay inspired by Minecraft's F3 screen.
## Toggle with the V key. Shows FPS (top-right) and a
## detailed stats panel (right side): RAM, VRAM, GPU, draw calls, etc.

const TOGGLE_KEY := KEY_V
const FONT_SIZE_FPS := 22
const FONT_SIZE_STATS := 17
const PANEL_WIDTH := 340
const PADDING := 12
const LINE_HEIGHT := 22
const UPDATE_INTERVAL := 0.15  # seconds between stat refreshes

var _visible := false
var _timer := 0.0

# ── UI nodes ────────────────────────────────────────────────────────────────
var _fps_label: Label
var _stats_panel: PanelContainer
var _stats_label: Label

# ── cached values updated on interval ────────────────────────────────────────
var _stat_lines: Array[String] = []

func _ready() -> void:
	layer = 128  # draw on top of everything
	_build_fps_label()
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