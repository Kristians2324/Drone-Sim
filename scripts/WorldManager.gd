extends Node3D

@onready var menu_scene = preload("res://scenes/Menu.tscn")
var menu_instance: CanvasLayer
var vr_manager: Node

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

func _input(event):
	# Listen for ESC key globally
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if menu_instance:
			if menu_instance.visible:
				menu_instance.resume()
			else:
				menu_instance.pause()
			get_viewport().set_input_as_handled()
