extends Node3D
class_name Mountains

var mountain_scene = preload("res://scenes/Mountain.tscn")

func setup():
	var mountain1 = mountain_scene.instantiate()
	mountain1.transform = Transform3D(Basis(), Vector3(300, 0, -200))
	add_child(mountain1)
	
	var mountain2 = mountain_scene.instantiate()
	mountain2.transform = Transform3D(Basis.from_scale(Vector3(1.5, 1.5, 1.5)), Vector3(-400, 0, -500))
	add_child(mountain2)
