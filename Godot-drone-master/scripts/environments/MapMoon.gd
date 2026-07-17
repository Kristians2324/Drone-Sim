class_name MapMoon
extends BaseEnvironment

func setup_environment():
	# Dark sky, moon-like lighting
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.15, 0.2)
	
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	
	var sun = DirectionalLight3D.new()
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-45, 45, 0)
	add_child(sun)
	
	# Moon Surface with Craters
	var moon_surface = CSGCombiner3D.new()
	moon_surface.use_collision = true
	add_child(moon_surface)
	
	# Main Ground (Thick enough to handle deep craters)
	var ground = CSGBox3D.new()
	ground.size = Vector3(500, 100, 500)
	ground.position = Vector3(0, -50, 0) # Top surface at Y=0
	var moon_mat = StandardMaterial3D.new()
	moon_mat.albedo_color = Color(0.3, 0.3, 0.35)
	moon_mat.roughness = 1.0
	ground.material_override = moon_mat
	moon_surface.add_child(ground)
	
	# Add some procedural craters
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(30):
		var crater = CSGSphere3D.new()
		crater.operation = CSGShape3D.OPERATION_SUBTRACTION
		var radius = rng.randf_range(5.0, 30.0)
		crater.radius = radius
		crater.position = Vector3(rng.randf_range(-200, 200), 0, rng.randf_range(-200, 200))
		crater.scale.y = 0.25
		moon_surface.add_child(crater)
	
	# Moon Base Alpha (More Modules)
	_add_moon_base(Vector3(0, 0, 0))
	_add_radar_dish(Vector3(-40, 0, -40))
	
	# Environment Objects
	add_charging_station(Vector3(25, 0, 0))
	add_foosball_table(Vector3(-25, 0, 5), Vector3(0, 45, 0), Vector3(2, 2, 2))

func _add_radar_dish(pos):
	var base = CSGCylinder3D.new()
	base.radius = 2.0
	base.height = 1.0
	base.position = pos + Vector3(0, 0.5, 0)
	base.use_collision = true
	add_child(base)
	
	var dish = CSGSphere3D.new()
	dish.radius = 8.0
	dish.operation = CSGShape3D.OPERATION_UNION
	dish.position = pos + Vector3(0, 8, 0)
	dish.rotation_degrees.x = -45
	
	var cutout = CSGSphere3D.new()
	cutout.radius = 7.8
	cutout.operation = CSGShape3D.OPERATION_SUBTRACTION
	cutout.position = Vector3(0, 0.5, 0) # Relative to dish
	dish.add_child(cutout)
	add_child(dish)

func _add_moon_base(pos):
	# Use a combiner for the base to ensure collisions are unified
	var base_group = CSGCombiner3D.new()
	base_group.use_collision = true
	base_group.position = pos
	add_child(base_group)
	
	# Main Dome
	var dome = CSGSphere3D.new()
	dome.radius = 12.0
	dome.position = Vector3(0, -2, 0)
	var base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.8, 0.8, 0.9)
	base_mat.metallic = 0.8
	base_mat.roughness = 0.2
	dome.material_override = base_mat
	base_group.add_child(dome)
	
	# Corridors
	for rot in [0, 90, 180, 270]:
		var corridor = CSGBox3D.new()
		corridor.size = Vector3(20, 4, 4)
		corridor.position = pos + Vector3(15, 1, 0).rotated(Vector3.UP, deg_to_rad(rot))
		corridor.rotation_degrees.y = rot
		corridor.material_override = base_mat
		base_group.add_child(corridor)
		
		# Smaller outer pods
		var pod = CSGSphere3D.new()
		pod.radius = 4.0
		pod.position = Vector3(25, 1, 0).rotated(Vector3.UP, deg_to_rad(rot))
		pod.material_override = base_mat
		base_group.add_child(pod)
	
	# Beacon Lights
	var light = OmniLight3D.new()
	light.position = pos + Vector3(0, 12, 0)
	light.light_color = Color(1, 0, 0)
	light.light_energy = 5.0
	add_child(light)
