class_name MapEarthNight
extends BaseEnvironment

func setup_environment():
	# Environment (Sky/Lighting)
	var env_scene = preload("res://scenes/Environment.tscn").instantiate()
	
	# Modify the environment to be night
	var env_node = env_scene.get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		# Need to duplicate the resource to avoid changing the day one globally
		env_node.environment = env_node.environment.duplicate()
		env_node.environment.sky = env_node.environment.sky.duplicate()
		env_node.environment.sky.sky_material = env_node.environment.sky.sky_material.duplicate()
		
		env_node.environment.sky.sky_material.sky_top_color = Color(0.05, 0.05, 0.15)
		env_node.environment.sky.sky_material.sky_horizon_color = Color(0.1, 0.1, 0.25)
		env_node.environment.sky.sky_material.ground_horizon_color = Color(0.05, 0.05, 0.15)
		env_node.environment.sky.sky_material.ground_bottom_color = Color(0.02, 0.02, 0.05)
		
		# Increase ambient light so things aren't pitch black
		env_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env_node.environment.ambient_light_color = Color(0.3, 0.3, 0.5)
		env_node.environment.ambient_light_energy = 1.5
		
	var light = env_scene.get_node_or_null("DirectionalLight3D")
	if light:
		# Stronger moon light
		light.light_energy = 0.8
		light.light_color = Color(0.7, 0.8, 1.0)
		light.shadow_enabled = true
		
	add_child(env_scene)
	
	# Terrain
	var terrain_scene = preload("res://scenes/Terrain.tscn").instantiate()
	add_child(terrain_scene)
	
	# Town
	var town = Node3D.new()
	town.set_script(preload("res://scripts/TownGenerator.gd"))
	add_child(town)
