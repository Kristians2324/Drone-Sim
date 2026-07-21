class_name MapIndoor
extends BaseEnvironment

func setup_environment():
	# Large House Layout using CSG
	var house_base = CSGCombiner3D.new()
	house_base.use_collision = true
	add_child(house_base)
	
	# Main Living Room (huge)
	var main_room = CSGBox3D.new()
	main_room.size = Vector3(50, 20, 50)
	main_room.position = Vector3(0, 10, 0)
	main_room.flip_faces = true
	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.9, 0.85, 0.8)
	main_room.material_override = wall_mat
	house_base.add_child(main_room)
	
	# Hallway to Bedroom
	var hallway = CSGBox3D.new()
	hallway.size = Vector3(10, 10, 30)
	hallway.position = Vector3(30, 5, 0)
	hallway.flip_faces = true
	house_base.add_child(hallway)
	
	# Bedroom
	var bedroom = CSGBox3D.new()
	bedroom.size = Vector3(30, 15, 30)
	bedroom.position = Vector3(50, 7.5, 0)
	bedroom.flip_faces = true
	house_base.add_child(bedroom)
	
	# Furniture & Obstacles
	# 1. Large dining table in main room
	_create_table(house_base, Vector3(0, 0, 10), Vector3(8, 1, 4))
	
	# 2. Kitchen Island
	_create_table(house_base, Vector3(-15, 0, -10), Vector3(10, 2, 3), Color(0.2, 0.2, 0.2))
	
	# 3. TV and Entertainment Center
	_create_entertainment_center(house_base, Vector3(0, 0, -23))
	
	# 4. Sofa Set
	_create_sofa(house_base, Vector3(0, 0, -12), 0)
	
	# 5. Bookshelves along walls
	for i in range(3):
		_create_bookshelf(house_base, Vector3(-23, 0, 5 * i), 90)
	
	# 6. Pillars for maneuvering
	for i in range(4):
		var pillar = CSGBox3D.new()
		pillar.size = Vector3(1, 20, 1)
		pillar.position = Vector3(15 * (1 if i < 2 else -1), 10, 15 * (1 if i % 2 == 0 else -1))
		house_base.add_child(pillar)
	
	# Lighting Setup
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.4)
	
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	
	# Ceiling Lights
	_add_ceiling_light(Vector3(0, 18, 0))
	_add_ceiling_light(Vector3(50, 13, 0))
	_add_ceiling_light(Vector3(30, 9, 0))
	
	# Environment Objects
	add_foosball_table(Vector3(5, 0, -15), Vector3(0, 90, 0), Vector3(3, 3, 3))
	add_charging_station(Vector3(-20, 0, 20))

func _create_table(parent, pos, size, color = Color(0.4, 0.2, 0.1)):
	var top = CSGBox3D.new()
	top.size = size
	top.position = pos + Vector3(0, size.y + 0.5, 0) # Raise it a bit
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	top.material_override = mat
	parent.add_child(top)
	
	for x in [-1, 1]:
		for z in [-1, 1]:
			var leg = CSGBox3D.new()
			leg.size = Vector3(0.4, size.y + 0.5, 0.4)
			leg.position = pos + Vector3((size.x/2.5) * x, (size.y+0.5)/2, (size.z/2.5) * z)
			leg.material_override = mat
			parent.add_child(leg)

func _create_entertainment_center(parent, pos):
	# The Stand
	var stand = CSGBox3D.new()
	stand.size = Vector3(12, 1.5, 3)
	stand.position = pos + Vector3(0, 0.75, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	stand.material_override = mat
	parent.add_child(stand)
	
	# The TV
	var tv = CSGBox3D.new()
	tv.size = Vector3(10, 6, 0.3)
	tv.position = pos + Vector3(0, 4.5, 0)
	var screen_mat = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0, 0, 0)
	screen_mat.metallic = 1.0
	screen_mat.roughness = 0.1
	tv.material_override = screen_mat
	parent.add_child(tv)

func _create_sofa(parent, pos, rot):
	var sofa_group = CSGCombiner3D.new()
	sofa_group.position = pos
	sofa_group.rotation_degrees.y = rot
	parent.add_child(sofa_group)
	
	var base = CSGBox3D.new()
	base.size = Vector3(10, 1.5, 4)
	base.position = Vector3(0, 0.75, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.4) # Dark blue fabric
	base.material_override = mat
	sofa_group.add_child(base)
	
	var back = CSGBox3D.new()
	back.size = Vector3(10, 3, 1)
	back.position = Vector3(0, 2, 1.5)
	back.material_override = mat
	sofa_group.add_child(back)
	
	for x in [-1, 1]:
		var arm = CSGBox3D.new()
		arm.size = Vector3(1, 2.5, 4)
		arm.position = Vector3(4.5 * x, 1.25, 0)
		arm.material_override = mat
		sofa_group.add_child(arm)

func _create_bookshelf(parent, pos, rot):
	var shelf = CSGBox3D.new()
	shelf.size = Vector3(4, 10, 2)
	shelf.position = pos + Vector3(0, 5, 0)
	shelf.rotation_degrees.y = rot
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.15, 0.05)
	shelf.material_override = mat
	parent.add_child(shelf)
	
	# Cut out shelves
	for i in range(4):
		var cut = CSGBox3D.new()
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		cut.size = Vector3(3.6, 1.5, 1.8)
		cut.position = Vector3(0, -3 + i * 2.5, 0.2)
		shelf.add_child(cut)

func _add_ceiling_light(pos):
	var light = OmniLight3D.new()
	light.position = pos
	light.omni_range = 40.0
	light.light_energy = 2.5
	light.shadow_enabled = true
	add_child(light)
	
	# Visual for the light
	var mesh = CSGCylinder3D.new()
	mesh.radius = 1.0
	mesh.height = 0.2
	mesh.position = pos + Vector3(0, 0.1, 0)
	var mat = StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0.8)
	mesh.material_override = mat
	add_child(mesh)
