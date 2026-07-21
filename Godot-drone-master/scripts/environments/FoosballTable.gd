class_name FoosballTable
extends EnvironmentObject

func setup_object():
	object_name = "Foosball Table"
	var model = preload("res://FooslTable.gltf").instantiate()
	add_child(model)
	
	# Optional: Add some logic here if needed, like sounds or interactions
