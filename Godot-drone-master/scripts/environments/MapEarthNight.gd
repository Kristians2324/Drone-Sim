class_name MapEarthNight
extends BaseEnvironment

func setup_environment():
	# 1. Environment (Sky/Lighting)
	var env_scene = load("res://scenes/Environment.tscn").instantiate()
	var env_node = env_scene.get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		env_node.environment = env_node.environment.duplicate()
		env_node.environment.sky = env_node.environment.sky.duplicate()
		env_node.environment.sky.sky_material = env_node.environment.sky.sky_material.duplicate()
		
		# Dark night colors
		env_node.environment.sky.sky_material.sky_top_color = Color(0.02, 0.02, 0.06)
		env_node.environment.sky.sky_material.sky_horizon_color = Color(0.05, 0.05, 0.12)
		env_node.environment.sky.sky_material.ground_horizon_color = Color(0.02, 0.02, 0.06)
		env_node.environment.sky.sky_material.ground_bottom_color = Color(0.01, 0.01, 0.02)
		
		# Moon ambient light
		env_node.environment.ambient_light_source = 2
		env_node.environment.ambient_light_color = Color(0.2, 0.22, 0.35)
		env_node.environment.ambient_light_energy = 1.3
		
	var light = env_scene.get_node_or_null("DirectionalLight3D")
	if light:
		light.light_energy = 0.5
		light.light_color = Color(0.65, 0.75, 1.0)
		light.shadow_enabled = true
	add_child(env_scene)

	# 2. Terrain (Ground & Mountains)
	var terrain_scene = load("res://scenes/Terrain.tscn").instantiate()
	add_child(terrain_scene)

	# Mountains
	var mountain_scene = preload("res://scenes/Mountain.tscn")
	var m1 = mountain_scene.instantiate()
	m1.transform = Transform3D(Basis().scaled(Vector3(8.0, 8.0, 8.0)), Vector3(1200, 0, -600))
	add_child(m1)
	
	var m2 = mountain_scene.instantiate()
	m2.transform = Transform3D(Basis().scaled(Vector3(12.0, 10.0, 12.0)), Vector3(-1200, 0, 800))
	add_child(m2)

	# 3. Town (Procedural Skyscrapers)
	var town = Node3D.new()
	town.name = "Town"
	town.set_script(preload("res://scripts/TownGenerator.gd"))
	add_child(town)
	town.generate()

	# 4. World Details (Procedural Trees/Rocks)
	var world_details = Node3D.new()
	world_details.name = "WorldDetails"
	world_details.set_script(preload("res://scripts/WorldDetailManager.gd"))
	add_child(world_details)
