extends SceneTree

func _init():
	var file = FileAccess.open("user://tree_output.txt", FileAccess.WRITE)
	if not file:
		print("Failed to open file")
		quit()
		return
		
	file.store_line("--- MODEL INSPECTION START ---")
	var model_scene = load("res://assets/drone_model/scene.gltf")
	if not model_scene:
		file.store_line("Failed to load scene.gltf")
		file.close()
		quit()
		return
		
	var drone_model = model_scene.instantiate()
	if not drone_model:
		file.store_line("Failed to instantiate model")
		file.close()
		quit()
		return
		
	_print_node_transforms(drone_model, 0, file)
	file.store_line("--- MODEL INSPECTION END ---")
	file.close()
	print("Successfully wrote tree_output.txt to user://")
	quit()

func _print_node_transforms(node: Node, depth: int, file: FileAccess):
	var indent = ""
	for i in range(depth):
		indent += "  "
		
	var line = indent + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		line += " pos=" + str(node.position) + " rot=" + str(node.rotation) + " scale=" + str(node.scale)
	if node is MeshInstance3D:
		line += " MESH aabb_center=" + str(node.get_aabb().get_center()) + " aabb_size=" + str(node.get_aabb().size)
	file.store_line(line)
	
	for child in node.get_children():
		_print_node_transforms(child, depth + 1, file)
