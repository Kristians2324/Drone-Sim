extends Node3D

@onready var menu_scene = preload("res://scenes/Menu.tscn")
var menu_instance: CanvasLayer
var vr_manager: Node
var current_environment: BaseEnvironment = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Initial VR Setup
	vr_manager = load("res://scripts/VRManager.gd").new()
	vr_manager.name = "VRManager"
	add_child(vr_manager)
	
	# Instantiate menu once at startup
	menu_instance = menu_scene.instantiate()
	add_child(menu_instance)
	menu_instance.hide()
	
	# Load default environment
	load_environment(MapEarthDay)

func load_environment(EnvironmentClass):
	if current_environment:
		current_environment.queue_free()
		current_environment = null
	
	current_environment = EnvironmentClass.new()
	current_environment.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(current_environment)

func _input(event):
	# Listen for ESC key globally
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if menu_instance:
			if menu_instance.visible:
				menu_instance.resume()
			else:
				menu_instance.pause()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			load_environment(MapEarthDay)
		elif event.keycode == KEY_2:
			load_environment(MapEarthNight)
		elif event.keycode == KEY_3:
			load_environment(MapMoon)
		elif event.keycode == KEY_4:
			load_environment(MapIndoor)
