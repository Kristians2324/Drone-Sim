extends Node3D

@export var grid_size: int = 9
@export var spacing: float = 48.0
@export_file("*.tscn") var house_scene_path: String = "res://scenes/House.tscn"

var house_scene: PackedScene

func _ready() -> void:
	if house_scene_path != "":
		house_scene = load(house_scene_path)

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
	query.collision_mask = 2 # ONLY collide with Terrain layer 2
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
				
				# Apply parent scaling to shape local transform to avoid scaling StaticBody3D
				var final_transform = local_transform
				final_transform.origin = final_transform.origin * scale_factor
				final_transform.basis = final_transform.basis.scaled(scale_factor)
				
				col_shape.transform = final_transform
				static_body.add_child(col_shape)
	
	for child in curr_node.get_children():
		_add_collisions_recursive(child, static_body, local_transform, scale_factor)

func generate() -> void:
	if not is_inside_tree():
		await ready
	await get_tree().physics_frame
	
	seed(123)
	
	var building_files: Array[String] = []
	var all_glbs := _get_glb_files("res://assets/city_kit")
	for f in all_glbs:
		var fn = f.get_file().to_lower()
		# Select building GLBs, skip details like awnings, parasols, etc.
		if "building" in fn and not "detail-" in fn:
			building_files.append(f)

	if building_files.size() > 0:
		_generate_buildings_assets(building_files)
	else:
		_generate_buildings_fallback()

func _generate_buildings_assets(building_files: Array[String]) -> void:
	# 1. Spawn buildings in grid
	for x in range(grid_size):
		for z in range(grid_size):
			# Skip the exact center spawn coordinate where the drone starts
			if x == grid_size / 2 and z == grid_size / 2:
				continue

			var test_pos = Vector3(x * spacing, 0.0, z * spacing)
			var center_offset = Vector3(grid_size * spacing * 0.5, 0.0, grid_size * spacing * 0.5)
			var final_pos = test_pos - center_offset + Vector3(50, 0, 50)
			
			# Check ground height first
			var ground_height = _get_ground_height(final_pos.x, final_pos.z)
			if ground_height > 15.0 or ground_height < -2.0:
				# This is on a mountain or steep slope, skip spawning here to avoid clipping
				continue

			var random_building_path = building_files[randi() % building_files.size()]
			var building_scene = load(random_building_path)
			if not building_scene:
				continue
				
			var building = building_scene.instantiate()
			if building is Node3D:
				building.position = final_pos
				building.position.y = ground_height
				building.rotation.y = (randi() % 4) * (PI / 2.0) # 90 degree snap rotation
				
				# Scale skyscrapers and buildings proportionally for a dense city feel
				var fn = random_building_path.get_file().to_lower()
				if "skyscraper" in fn:
					building.scale = Vector3(25.0, randf_range(60.0, 110.0), 25.0)
				else:
					building.scale = Vector3(18.0, randf_range(15.0, 30.0), 18.0)
					
				add_child(building)
				
				# Generate correct physics collisions
				_create_collision_for_node(building)

	# 2. Spawn asphalt roads
	var road_parent = Node3D.new()
	road_parent.name = "Roads"
	add_child(road_parent)
	
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.12, 0.12, 0.13)
	road_mat.roughness = 1.0
	
	var center_offset = Vector3(grid_size * spacing * 0.5, 0.0, grid_size * spacing * 0.5)
	
	# Horizontal roads (running along X axis, between Z building rows)
	for z_idx in range(grid_size - 1):
		var z_pos = (z_idx + 0.5) * spacing - center_offset.z + 50.0
		var road := CSGBox3D.new()
		road.name = "Road_H_%d" % z_idx
		road.size = Vector3(grid_size * spacing, 0.1, 9.0) # 9m wide road
		road.position = Vector3(50.0, _get_ground_height(50.0, z_pos) + 0.05, z_pos)
		road.material = road_mat
		road.use_collision = true
		road_parent.add_child(road)
		
	# Vertical roads (running along Z axis, between X building columns)
	for x_idx in range(grid_size - 1):
		var x_pos = (x_idx + 0.5) * spacing - center_offset.x + 50.0
		var road := CSGBox3D.new()
		road.name = "Road_V_%d" % x_idx
		road.size = Vector3(9.0, 0.1, grid_size * spacing)
		road.position = Vector3(x_pos, _get_ground_height(x_pos, 50.0) + 0.05, 50.0)
		road.material = road_mat
		road.use_collision = true
		road_parent.add_child(road)

	# 3. Spawn streetlights at road intersections (on sidewalks, not in the middle of roads)
	for x_idx in range(grid_size - 1):
		for z_idx in range(grid_size - 1):
			var x_pos = (x_idx + 0.5) * spacing - center_offset.x + 50.0
			var z_pos = (z_idx + 0.5) * spacing - center_offset.z + 50.0
			
			# Southwest corner of intersection, rotated Northeast
			var sw_pos = Vector3(x_pos - 5.5, _get_ground_height(x_pos - 5.5, z_pos - 5.5), z_pos - 5.5)
			_create_streetlight(sw_pos, PI / 4.0)
			
			# Northeast corner of intersection, rotated Southwest
			var ne_pos = Vector3(x_pos + 5.5, _get_ground_height(x_pos + 5.5, z_pos + 5.5), z_pos + 5.5)
			_create_streetlight(ne_pos, -3.0 * PI / 4.0)

	# 4. Spawn parked cars along the road curbs
	for x in range(grid_size):
		for z in range(grid_size):
			if x == grid_size / 2 and z == grid_size / 2:
				continue
				
			var b_pos = Vector3(x * spacing, 0.0, z * spacing) - center_offset + Vector3(50, 0, 50)
			var b_height = _get_ground_height(b_pos.x, b_pos.z)
			if b_height > 15.0 or b_height < -2.0:
				continue
				
			# Spawn cars parked along horizontal curbs
			if z < grid_size - 1 and randf() < 0.7:
				var z_road = (z + 0.5) * spacing - center_offset.z + 50.0
				var rx = b_pos.x + randf_range(-12.0, 12.0)
				var car_pos = Vector3(rx, _get_ground_height(rx, z_road - 4.3) + 0.05, z_road - 4.3)
				_create_procedural_car(car_pos, 0.0)
				
			if z > 0 and randf() < 0.7:
				var z_road = (z - 0.5) * spacing - center_offset.z + 50.0
				var rx = b_pos.x + randf_range(-12.0, 12.0)
				var car_pos = Vector3(rx, _get_ground_height(rx, z_road + 4.3) + 0.05, z_road + 4.3)
				_create_procedural_car(car_pos, PI)

			# Spawn cars parked along vertical curbs
			if x < grid_size - 1 and randf() < 0.6:
				var x_road = (x + 0.5) * spacing - center_offset.x + 50.0
				var rz = b_pos.z + randf_range(-12.0, 12.0)
				var car_pos = Vector3(x_road - 4.3, _get_ground_height(x_road - 4.3, rz) + 0.05, rz)
				_create_procedural_car(car_pos, PI / 2.0)

			if x > 0 and randf() < 0.6:
				var x_road = (x - 0.5) * spacing - center_offset.x + 50.0
				var rz = b_pos.z + randf_range(-12.0, 12.0)
				var car_pos = Vector3(x_road + 4.3, _get_ground_height(x_road + 4.3, rz) + 0.05, rz)
				_create_procedural_car(car_pos, -PI / 2.0)

func _create_streetlight(pos: Vector3, rot_y: float) -> void:
	var light_node := Node3D.new()
	light_node.name = "StreetLight"
	light_node.position = pos
	light_node.rotation.y = rot_y
	add_child(light_node)
	
	# Metal pole material
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.25, 0.25, 0.28)
	pole_mat.roughness = 0.6
	pole_mat.metallic = 0.8
	
	# Vertical pole
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.1
	pole_mesh.bottom_radius = 0.18
	pole_mesh.height = 7.0
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 3.5, 0)
	pole.material_override = pole_mat
	light_node.add_child(pole)
	
	# Horizontal arm
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.06
	arm_mesh.bottom_radius = 0.06
	arm_mesh.height = 1.8
	arm.mesh = arm_mesh
	arm.position = Vector3(0.7, 6.9, 0)
	arm.rotation_degrees.z = 90.0
	arm.material_override = pole_mat
	light_node.add_child(arm)
	
	# Light bulb
	var bulb := MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.25
	bulb_mesh.height = 0.4
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(1.5, 6.7, 0)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.95, 0.7)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.95, 0.7)
	bulb_mat.emission_energy_multiplier = 4.0
	bulb.material_override = bulb_mat
	light_node.add_child(bulb)
	
	# OmniLight3D
	var light := OmniLight3D.new()
	light.position = Vector3(1.5, 6.4, 0)
	light.light_color = Color(1.0, 0.92, 0.75)
	light.light_energy = 3.5
	light.omni_range = 15.0
	light.shadow_enabled = true
	light_node.add_child(light)

func _create_procedural_car(pos: Vector3, rot_y: float) -> void:
	var car := CSGCombiner3D.new()
	car.name = "ParkedCar"
	car.position = pos
	car.rotation.y = rot_y
	car.use_collision = true
	add_child(car)
	
	var body_colors = [
		Color(0.8, 0.1, 0.1),
		Color(0.1, 0.3, 0.8),
		Color(0.1, 0.7, 0.2),
		Color(0.9, 0.8, 0.1),
		Color(0.85, 0.85, 0.85),
		Color(0.1, 0.1, 0.12),
		Color(0.95, 0.95, 0.95)
	]
	var color = body_colors[randi() % body_colors.size()]
	
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = color
	body_mat.roughness = 0.2
	body_mat.metallic = 0.7
	
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.08, 0.08, 0.1)
	glass_mat.roughness = 0.1
	glass_mat.metallic = 0.9
	
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.05, 0.05, 0.05)
	wheel_mat.roughness = 0.9
	
	var chrome_mat := StandardMaterial3D.new()
	chrome_mat.albedo_color = Color(0.8, 0.8, 0.8)
	chrome_mat.roughness = 0.1
	chrome_mat.metallic = 1.0

	var lower_box := CSGBox3D.new()
	lower_box.size = Vector3(4.2, 0.8, 1.8)
	lower_box.position = Vector3(0.0, 0.45, 0.0)
	lower_box.material = body_mat
	car.add_child(lower_box)
	
	var upper_box := CSGBox3D.new()
	upper_box.size = Vector3(2.3, 0.7, 1.6)
	upper_box.position = Vector3(-0.2, 1.1, 0.0)
	upper_box.material = glass_mat
	car.add_child(upper_box)
	
	var roof_plate := CSGBox3D.new()
	roof_plate.size = Vector3(2.2, 0.08, 1.55)
	roof_plate.position = Vector3(-0.2, 1.45, 0.0)
	roof_plate.material = body_mat
	car.add_child(roof_plate)
	
	var wheel_positions = [
		Vector3(-1.25, 0.35, 0.9),
		Vector3(1.25, 0.35, 0.9),
		Vector3(-1.25, 0.35, -0.9),
		Vector3(1.25, 0.35, -0.9)
	]
	for wp in wheel_positions:
		var wheel := CSGBox3D.new()
		wheel.size = Vector3(0.7, 0.7, 0.25)
		wheel.position = wp
		wheel.material = wheel_mat
		car.add_child(wheel)
		
		var hubcap := CSGBox3D.new()
		hubcap.size = Vector3(0.3, 0.3, 0.28)
		hubcap.position = wp + Vector3(0, 0, 0.01 if wp.z > 0 else -0.01)
		hubcap.material = chrome_mat
		car.add_child(hubcap)
		
	var headlight_positions = [
		Vector3(2.1, 0.55, 0.6),
		Vector3(2.1, 0.55, -0.6)
	]
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.98, 0.9)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.98, 0.9)
	head_mat.emission_energy_multiplier = 2.0
	
	for hp in headlight_positions:
		var hl := CSGBox3D.new()
		hl.size = Vector3(0.1, 0.15, 0.25)
		hl.position = hp
		hl.material = head_mat
		car.add_child(hl)
		
	var taillight_positions = [
		Vector3(-2.1, 0.55, 0.6),
		Vector3(-2.1, 0.55, -0.6)
	]
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.9, 0.05, 0.05)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(0.9, 0.05, 0.05)
	tail_mat.emission_energy_multiplier = 1.8
	
	for tp in taillight_positions:
		var tl := CSGBox3D.new()
		tl.size = Vector3(0.1, 0.15, 0.25)
		tl.position = tp
		tl.material = tail_mat
		car.add_child(tl)

func _generate_buildings_fallback() -> void:
	if house_scene == null and house_scene_path != "":
		house_scene = load(house_scene_path)
	if house_scene == null:
		push_error("TownGenerator: house scene path could not be loaded: %s" % house_scene_path)
		return

	for x in range(grid_size):
		for z in range(grid_size):
			if x % 2 == 0 and z % 2 == 0:
				continue

			var test_pos = Vector3(x * spacing, 0.0, z * spacing)
			var center_offset = Vector3(grid_size * spacing * 0.5, 0.0, grid_size * spacing * 0.5)
			var final_pos = test_pos - center_offset + Vector3(50, 0, 50)
			
			var ground_height = _get_ground_height(final_pos.x, final_pos.z)
			if ground_height > 15.0 or ground_height < -2.0:
				continue

			var house := house_scene.instantiate()
			if house is Node3D:
				house.position = final_pos
				house.position.y = ground_height
				house.rotation.y = randf() * PI * 2.0
				house.scale = Vector3(15.0, randf_range(12.0, 24.0), 15.0)
				add_child(house)
				_create_collision_for_node(house)
