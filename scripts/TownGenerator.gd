extends Node3D

@export var grid_size = 5
@export var spacing = 15.0
@export var town_center: Vector3 = Vector3(800, 0, 800)
@export var protected_center: Vector3 = Vector3(800, 0, 800)
@export var protected_radius: float = 45.0
var house_scene = preload("res://scenes/House.tscn")

func _ready():
	seed(123)
	generate_town()

func generate_town():
	for x in range(grid_size):
		for z in range(grid_size):
			# Leave room for "streets"
			if x % 2 == 0 and z % 2 == 0:
				continue
				
			var house = house_scene.instantiate()
			var pos = Vector3(x * spacing, 0, z * spacing)
			var world_pos = pos - Vector3(grid_size * spacing * 0.5, 0, grid_size * spacing * 0.5) + town_center
			if world_pos.distance_to(protected_center) < protected_radius:
				continue
			house.position = world_pos
			
			# Randomize look
			house.rotation.y = randf() * PI * 2.0
			house.scale = Vector3(randf_range(0.8, 1.2), randf_range(0.8, 1.5), randf_range(0.8, 1.2))
			
			add_child(house)
			
			# Add a "lot" (dirt patch)
			var lot = CSGBox3D.new()
			lot.size = Vector3(spacing * 0.8, 0.1, spacing * 0.8)
			lot.use_collision = true
			lot.position = house.position - Vector3(0, 0.05, 0)
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.25, 0.2)
			lot.material = mat
			add_child(lot)
