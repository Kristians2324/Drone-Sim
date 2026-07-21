class_name MapEarthDay
extends BaseEnvironment

func setup_environment():
	# 1. Environment (Sky/Lighting)
	var env_scene = load("res://scenes/Environment.tscn").instantiate()
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
