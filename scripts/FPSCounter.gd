extends CanvasLayer

var fps_label: Label
var debug_label: Label
var verbose_mode: bool = false

func _ready():
	# Basic FPS label
	fps_label = Label.new()
	fps_label.position = Vector2(10, 10)
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.0))
	fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	fps_label.add_theme_constant_override("shadow_offset_x", 1)
	fps_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(fps_label)
	
	# Debug/verbose label
	debug_label = Label.new()
	debug_label.position = Vector2(10, 40)
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	debug_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_label.add_theme_constant_override("shadow_offset_y", 1)
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
	
	if Input.is_key_pressed(KEY_V):
		verbose_mode = !verbose_mode
		debug_label.visible = verbose_mode
		if verbose_mode:
			print("Verbose mode enabled")
		else:
			print("Verbose mode disabled")
	
	if verbose_mode:
		var debug_text = ""
		debug_text += "GPU: " + RenderingServer.get_video_adapter_name() + "\n"
		debug_text += "Memory: " + format_bytes(OS.get_static_memory_usage()) + " / " + format_bytes(OS.get_static_memory_peak_usage()) + "\n"
		debug_text += "Draw Calls: %d\n" % RenderingServer.get_frame_drawn_calls()
		debug_text += "Frames: %d" % Engine.get_frame_number()
		debug_label.text = debug_text

func format_bytes(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	elif bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	else:
		return "%.1f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))
