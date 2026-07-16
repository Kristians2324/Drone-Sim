class_name MapEarthDay
extends BaseEnvironment

func setup_environment():
	# Environment (Sky/Lighting)
	var env_scene = preload("res://scenes/Environment.tscn").instantiate()
	add_child(env_scene)
	
	# Terrain
	var terrain_scene = preload("res://scenes/Terrain.tscn").instantiate()
	add_child(terrain_scene)

	# Apply lightweight visual setup so the runtime scene actually changes.
	var env_setup = Node3D.new()
	env_setup.set_script(preload("res://scripts/environment/EnvironmentSetup.gd"))
	env_setup.directional_light_path = NodePath("../Environment/DirectionalLight3D")
	add_child(env_setup)

	var terrain_setup = Node.new()
	terrain_setup.set_script(preload("res://scripts/environment/TerrainMaterialSetup.gd"))
	terrain_setup.terrain_material_path = terrain_scene.get_path()
	add_child(terrain_setup)
	
	# Mountains
	var mountain_scene = preload("res://scenes/Mountain.tscn")
	var m1 = mountain_scene.instantiate()
	m1.transform = Transform3D().translated(Vector3(300, 0, -200))
	add_child(m1)
	
	var m2 = mountain_scene.instantiate()
	m2.transform = Transform3D(Basis().scaled(Vector3(1.5, 1.5, 1.5)), Vector3(-400, 0, -500))
	add_child(m2)
	
	# Town
	var town = Node3D.new()
	town.set_script(preload("res://scripts/TownGenerator.gd"))
	add_child(town)

	# Trees
	var tree_spawner = MultiMeshInstance3D.new()
	tree_spawner.set_script(preload("res://scripts/environment/TreeSpawner.gd"))
	tree_spawner.terrain_root_path = terrain_scene.get_path()
	tree_spawner.collision_parent_path = get_path()
	add_child(tree_spawner)
	
	# Foosball Table
	add_foosball_table(Vector3(50, 0, 50), Vector3(0, 10, 0), Vector3(5, 5, 5))
