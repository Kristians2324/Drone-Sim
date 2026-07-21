extends Node

var xr_interface: XRInterface

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_fullscreen_to_primary_display()
	initialize_vr()

func _apply_fullscreen_to_primary_display():
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen_index)

	DisplayServer.window_set_current_screen(screen_index)
	DisplayServer.window_set_size(screen_size)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func initialize_vr():
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("VR: OpenXR Interface initialized sucessfully")
		
		# Set the viewport to use XR
		get_viewport().use_xr = true
		
		# Low processor mode should be off for VR
		OS.low_processor_usage_mode = false
		
		# Disable VSync for VR (OpenXR handles it)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		print("VR: OpenXR Interface NOT detected or failed to initialize. Continuing in Desktop mode.")
		xr_interface = null

func is_vr_active() -> bool:
	return xr_interface != null
