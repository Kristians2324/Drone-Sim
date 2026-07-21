extends Node
class_name DroneModel

@onready var design: Node3D = get_parent()

var drone_model: Node3D
var propellers: Array[Node3D] = []

func initialize():
	replace_drone_model()

func replace_drone_model():
	print("DroneModel: Starting model replacement...")
	# Hide/remove old procedural parts
	for child in design.get_children():
		if not child is Camera3D and not child is XROrigin3D and child != self:
			child.queue_free()
	
	# Load and instance the new model
	if not FileAccess.file_exists("res://Drone.gltf"):
		push_error("DroneModel: Drone.gltf NOT FOUND in res://")
		return
		
	var model_scene = load("res://Drone.gltf")
	if model_scene:
		drone_model = model_scene.instantiate()
		design.add_child(drone_model)
		
		# Center the model
		var model_aabb = _center_spline_model(drone_model)
		
		# Auto-scale
		var max_dim = max(model_aabb.size.x, model_aabb.size.z)
		if max_dim > 0:
			var target_scale = 3.5 / max_dim 
			drone_model.scale = Vector3(target_scale, target_scale, target_scale)
			print("DroneModel: Applied scale: ", target_scale)
		
		# Shrink central cube
		var central_cube = drone_model.find_child("Cube*", true, false)
		if not central_cube:
			central_cube = drone_model.find_child("*Cube*", true, false)
		if central_cube:
			central_cube.scale *= 0.4
			print("DroneModel: Shrunk central body")
			
		drone_model.rotation_degrees.y = 180
		
		# Find propellers
		_find_propellers(drone_model)
		print("DroneModel: Model loaded. Found ", propellers.size(), " propellers.")
		
		if propellers.size() == 0:
			_find_propellers_fallback(drone_model)
			print("DroneModel: Fallback found ", propellers.size(), " propellers.")

func _center_spline_model(model: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_get_all_meshes(model, meshes)
	
	var aabb = AABB()
	var first = true
	
	for mesh in meshes:
		var mesh_transform = model.global_transform.affine_inverse() * mesh.global_transform
		var mesh_aabb = mesh_transform * mesh.get_aabb()
		
		if first:
			aabb = mesh_aabb
			first = false
		else:
			aabb = aabb.merge(mesh_aabb)
	
	if not first:
		var center = aabb.get_center()
		for child in model.get_children():
			if child is Node3D:
				child.position -= center
		print("DroneModel: Auto-centered model. Offset: ", -center)
		aabb.position -= center
		return aabb
		
	return AABB()

func _get_all_meshes(node: Node, meshes: Array[MeshInstance3D]):
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_get_all_meshes(child, meshes)

func _find_propellers(node):
	var name_lower = node.name.to_lower()
	var is_prop = "prop" in name_lower or "blade" in name_lower or "rotor" in name_lower or "helix" in name_lower or "fan" in name_lower
	
	if is_prop and node is Node3D:
		propellers.append(node)
	
	for child in node.get_children():
		_find_propellers(child)

func _find_propellers_fallback(node):
	if node is MeshInstance3D:
		var name_lower = node.name.to_lower()
		if "cylinder" in name_lower:
			propellers.append(node)
	
	for child in node.get_children():
		_find_propellers_fallback(child)

func animate_propellers(delta: float, speed: float):
	for prop in propellers:
		prop.rotate_y(delta * speed)