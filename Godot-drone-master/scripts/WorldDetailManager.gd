extends Node3D

@export var forest_radius = 1500.0

func _ready():
	# Seed for consistent world across runs
	seed(42)
	# Wait for physics to initialize so we can raycast the terrain height
	await get_tree().physics_frame
	generate_world()

func _get_glb_files(path: String) -> Array[String]:
	var files: Array[String] = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".glb"):
				files.append(path + "/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	return files

func _get_ground_height(x: float, z: float) -> float:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from := Vector3(x, 800.0, z)
	var to := Vector3(x, -200.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2 # ONLY collide with Terrain layer 2, not other trees/buildings
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return hit.position.y

func _create_collision_for_node(node: Node3D) -> void:
	var static_body := StaticBody3D.new()
	static_body.position = node.position
	static_body.rotation = node.rotation
	add_child(static_body)
	
	# Start recursion with children to ignore root transform since it's already on static_body
	for child in node.get_children():
		_add_collisions_recursive(child, static_body, Transform3D.IDENTITY, node.scale)

func _add_collisions_recursive(curr_node: Node, static_body: StaticBody3D, accumulated_transform: Transform3D, scale_factor: Vector3) -> void:
	var local_transform := accumulated_transform
	if curr_node is Node3D and curr_node != static_body:
		local_transform = accumulated_transform * curr_node.transform

	if curr_node is MeshInstance3D:
		if curr_node.mesh:
			var shape = curr_node.mesh.create_convex_shape(true, false)
			if shape:
				var col_shape := CollisionShape3D.new()
				col_shape.shape = shape
				
				# Apply scale factor directly to collision shape local transform
				var final_transform = local_transform
				final_transform.origin = final_transform.origin * scale_factor
				final_transform.basis = final_transform.basis.scaled(scale_factor)
				
				col_shape.transform = final_transform
				static_body.add_child(col_shape)
	
	for child in curr_node.get_children():
		_add_collisions_recursive(child, static_body, local_transform, scale_factor)

func generate_world():
	var all_glbs := _get_glb_files("res://assets/nature_kit")
	var tree_files: Array[String] = []
	var rock_files: Array[String] = []
	
	for f in all_glbs:
		var fn = f.get_file().to_lower()
		if "tree" in fn:
			# Prefer green trees; skip dark or fall/autumn ones to match the green theme
			if not ("dark" in fn or "fall" in fn):
				tree_files.append(f)
		elif "rock_" in fn or "stone_" in fn:
			# Focus on large/small rock models
			if "rock_large" in fn or "rock_small" in fn:
				rock_files.append(f)

	# 1. Generate Trees in dense clusters
	if tree_files.size() > 0:
		_generate_trees_assets(tree_files)
	else:
		_generate_trees_fallback()

	# 2. Generate Rocks in dense clusters
	if rock_files.size() > 0:
		_generate_rocks_assets(rock_files)
	else:
		_generate_rocks_fallback()

func _generate_trees_assets(tree_files: Array[String]) -> void:
	# Define natural forest groups/clusters (30 clusters of 35 trees = 1050 trees)
	var cluster_count = 80
	var trees_per_cluster = 40
	
	for c in range(cluster_count):
		# Pick center of the forest cluster
		var cluster_x = randf_range(-forest_radius, forest_radius)
		var cluster_z = randf_range(-forest_radius, forest_radius)
		var center = Vector3(cluster_x, 0.0, cluster_z)
		
		# Avoid town center (center 50, 50, radius 280m)
		var dist_to_town = (center - Vector3(50, 0.0, 50)).length()
		if dist_to_town < 320:
			continue
			
		for t in range(trees_per_cluster):
			var angle = randf() * PI * 2.0
			var dist = randf_range(5.0, 45.0) # Forest cluster radius (denser groups)
			var pos = center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			
			# Avoid town bounds
			if (pos - Vector3(50, 0.0, 50)).length() < 280:
				continue
				
			# Snap to terrain height
			var ground_y = _get_ground_height(pos.x, pos.z)
			if ground_y > 15.0 or ground_y < -2.0:
				continue # Skip spawning on mountains to avoid clipping/floating
			pos.y = ground_y
			
			var random_tree_path = tree_files[randi() % tree_files.size()]
			var tree_scene = load(random_tree_path)
			if not tree_scene:
				continue
				
			var tree = tree_scene.instantiate()
			if tree is Node3D:
				tree.position = pos
				# Slightly bigger tree sizes (20m to 38m) for massive canopy feel
				tree.scale = Vector3(randf_range(16.0, 24.0), randf_range(20.0, 38.0), randf_range(16.0, 24.0))
				tree.rotation.y = randf() * PI * 2.0
				add_child(tree)
				
				# Generate physics collision shapes
				_create_collision_for_node(tree)

func _generate_rocks_assets(rock_files: Array[String]) -> void:
	var cluster_count = 15
	var rocks_per_cluster = 12 # 180 rocks total
	
	for c in range(cluster_count):
		var cluster_x = randf_range(-forest_radius, forest_radius)
		var cluster_z = randf_range(-forest_radius, forest_radius)
		var center = Vector3(cluster_x, 0.0, cluster_z)
		
		var dist_to_town = (center - Vector3(50, 0.0, 50)).length()
		if dist_to_town < 320:
			continue
			
		for r in range(rocks_per_cluster):
			var angle = randf() * PI * 2.0
			var dist = randf_range(2.0, 30.0)
			var pos = center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			
			if (pos - Vector3(50, 0.0, 50)).length() < 280:
				continue
				
			var ground_y = _get_ground_height(pos.x, pos.z)
			if ground_y > 15.0 or ground_y < -2.0:
				continue
			pos.y = ground_y
			
			var random_rock_path = rock_files[randi() % rock_files.size()]
			var rock_scene = load(random_rock_path)
			if not rock_scene:
				continue
				
			var rock = rock_scene.instantiate()
			if rock is Node3D:
				rock.position = pos - Vector3(0, 1.0, 0)
				rock.scale = Vector3(randf_range(12.0, 25.0), randf_range(10.0, 18.0), randf_range(12.0, 25.0))
				rock.rotation = Vector3(randf(), randf(), randf()) * PI
				add_child(rock)
				_create_collision_for_node(rock)

func _generate_trees_fallback() -> void:
	# Fallback original cone-shaped cylinder trees
	var tree_multimesh = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 300
	
	var tree_mesh = CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 2.0
	tree_mesh.height = 6.0
	var tree_mat = StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.1, 0.3, 0.1)
	tree_mesh.material = tree_mat
	
	mm.mesh = tree_mesh
	tree_multimesh.multimesh = mm
	add_child(tree_multimesh)

	for i in range(300):
		var pos = Vector3(randf_range(-forest_radius, forest_radius), 0, randf_range(-forest_radius, forest_radius))
		if pos.length() < 20:
			pos *= 2.0
		
		var xform = Transform3D()
		xform = xform.scaled(Vector3(randf_range(0.8, 1.5), randf_range(1.0, 2.0), randf_range(0.8, 1.5)))
		xform.origin = pos + Vector3(0, tree_mesh.height * 0.5 * xform.basis.get_scale().y, 0)
		mm.set_instance_transform(i, xform)
		
		var tree_static = StaticBody3D.new()
		var tree_collision_node = CollisionShape3D.new()
		var tree_shape = CylinderShape3D.new()
		tree_shape.radius = 1.0
		tree_shape.height = 6.0 * xform.basis.get_scale().y
		
		tree_collision_node.shape = tree_shape
		tree_collision_node.position = pos + Vector3(0, tree_shape.height * 0.5, 0)
		tree_static.add_child(tree_collision_node)
		add_child(tree_static)

func _generate_rocks_fallback() -> void:
	for i in range(50):
		var rock = CSGSphere3D.new()
		rock.use_collision = true
		rock.radius = randf_range(2.0, 5.0)
		rock.radial_segments = 6
		rock.rings = 4
		var rock_mat = StandardMaterial3D.new()
		rock_mat.albedo_color = Color(0.4, 0.4, 0.43)
		rock_mat.roughness = 0.9
		rock.material = rock_mat
		
		var rock_pos = Vector3(randf_range(-forest_radius, forest_radius), -1, randf_range(-forest_radius, forest_radius))
		rock.position = rock_pos
		rock.scale = Vector3(randf_range(1.0, 2.0), randf_range(0.5, 1.0), randf_range(1.0, 2.0))
		rock.rotation_edit_mode = Node3D.ROTATION_EDIT_MODE_EULER
		rock.rotation = Vector3(randf(), randf(), randf()) * PI
		
		add_child(rock)
