extends SceneTree

func _init():
	var scene = load("res://Drone.gltf")
	if scene:
		var instance = scene.instantiate()
		print("Nodes in Drone.gltf:")
		_print_nodes(instance, "")
	quit()

func _print_nodes(node, indent):
	print(indent + node.name + " (" + node.get_class() + ")")
	for child in node.get_children():
		_print_nodes(child, indent + "  ")
