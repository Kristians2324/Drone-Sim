extends CanvasLayer

var fps_label: Label
var debug_label: Label
var debug_background: Panel
var verbose_mode: bool = false
var v_key_pressed: bool = false

func _ready():
	# Basic FPS label - TOP RIGHT, LARGER
	fps_label = Label.new()
	fps_label.anchor_left = 1.0
	fps_label.anchor_top = 0.0
	fps_label.anchor_right = 1.0
	fps_label.anchor_bottom = 0.0
	fps_label.offset_left = -250
	fps_label.offset_top = 10
	fps_label.offset_right = -10
	fps_label.offset_bottom = 60
	fps_label.add_theme_font_size_override("font_size", 28)
	fps_label.add_theme_color_override("font_color", Color.WHITE)
	fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	fps_label.add_theme_constant_override("shadow_offset_x", 3)
	fps_label.add_theme_constant_override("shadow_offset_y", 3)
	add_child(fps_label)
	
	# Background panel for debug text - for better readability
	debug_background = Panel.new()
	debug_background.anchor_left = 1.0
	debug_background.anchor_top = 0.0
	debug_background.anchor_right = 1.0
	debug_background.anchor_bottom = 1.0
	debug_background.offset_left = -420
	debug_background.offset_top = 40
	debug_background.offset_right = 0
	debug_background.offset_bottom = -10
	var background_style = StyleBoxFlat.new()
	background_style.bg_color = Color(0, 0, 0, 0.7)
	debug_background.add_theme_stylebox_override("panel", background_style)
	add_child(debug_background)
	debug_background.visible = false
	
	# Debug/verbose label - TOP RIGHT, MUCH LARGER
	debug_label = Label.new()
	debug_label.anchor_left = 1.0
	debug_label.anchor_top = 0.0
	debug_label.anchor_right = 1.0
	debug_label.anchor_bottom = 1.0
	debug_label.offset_left = -410
	debug_label.offset_top = 50
	debug_label.offset_right = -10
	debug_label.offset_bottom = -20
	debug_label.add_theme_font_size_override("font_size", 18)
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	debug_label.add_theme_constant_override("shadow_offset_x", 2)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(debug_label)
	debug_label.visible = false
	
	print_hardware_info()

func print_hardware_info():
	print("=== Hardware Information ===")
	print("GPU: ", RenderingServer.get_video_adapter_name())
	print("Vendor: ", RenderingServer.get_video_adapter_vendor())
	print("VRAM: ", RenderingServer.get_video_adapter_api_version())
	print("OS: ", OS.get_name())
	print("Processor Count: ", OS.get_processor_count())

func _process(_delta):
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	
	# Proper V key toggle - only trigger on release
	var v_currently_pressed = Input.is_key_pressed(KEY_V)
	if v_currently_pressed and not v_key_pressed:
		# Key just pressed
		verbose_mode = !verbose_mode
		debug_label.visible = verbose_mode
		debug_background.visible = verbose_mode
		if verbose_mode:
			print("Debug mode ENABLED (Press V to disable)")
		else:
			print("Debug mode DISABLED (Press V to enable)")
	v_key_pressed = v_currently_pressed
	
	if verbose_mode:
		var debug_text = ""
		debug_text += "=== DEBUG INFO ===\n"
		debug_text += "FPS: %d\n" % Engine.get_frames_per_second()
		debug_text += "\n--- MEMORY ---\n"
		debug_text += "Used: " + format_bytes(OS.get_static_memory_usage()) + "\n"
		debug_text += "Peak: " + format_bytes(OS.get_static_memory_peak_usage()) + "\n"
		debug_text += "\n--- SYSTEM ---\n"
		debug_text += "GPU: " + RenderingServer.get_video_adapter_name() + "\n"
		debug_text += "CPU Cores: %d\n" % OS.get_processor_count()
		debug_text += "OS: " + OS.get_name() + "\n"
		debug_text += "\n--- RENDERING ---\n"
		debug_text += "Delta Time: %.3f ms\n" % (Engine.get_physics_frames() * 1000.0 / Engine.get_frames_per_second())
		
		var root = get_tree().root
		if root:
			debug_text += "Nodes in Scene: %d\n" % count_nodes(root)
		
		debug_label.text = debug_text

func count_nodes(node: Node) -> int:
	var count = 1
	for child in node.get_children():
		count += count_nodes(child)
	return count

func format_bytes(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	elif bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	else:
		return "%.1f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))
