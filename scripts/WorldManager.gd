extends Node3D

@onready var environment_parent = get_node("../Environment") # Wait, I'll need to check the path

var day_scene = preload("res://scenes/Environment.tscn")
var night_scene = preload("res://scenes/Environment_Night.tscn")
var is_night = false

func _input(event):
	if event.is_action_pressed("toggle_environment") or (event is InputEventKey and event.pressed and event.keycode == KEY_T):
		toggle_world()

func toggle_world():
	is_night = !is_night
	
	# Find current environment node
	var current_env = get_tree().root.find_child("Environment*", true, false)
	if current_env:
		var parent = current_env.get_parent()
		var new_scene = night_scene if is_night else day_scene
		var new_env = new_scene.instantiate()
		
		parent.add_child(new_env)
		current_env.queue_free()
		
		print("Environment toggled to: ", "Night" if is_night else "Day")
