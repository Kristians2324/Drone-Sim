extends Node3D
class_name Town

@export var grid_size: int = 5
@export var spacing: float = 15.0

var house_scene = preload("res://scenes/House.tscn")

func generate():
	seed(123)
	
	for x in range(grid_size):
		for z in range(grid_size):
			if x % 2 == 0 and z % 2 == 0:
				continue
				
			var house = house_scene.instantiate()
			var pos = Vector3(x * spacing, 0, z * spacing)
			house.position = pos - Vector3(grid_size * spacing * 0.5, 0, grid_size * spacing * 0.5) + Vector3(50, 0, 50)
			
			house.rotation.y = randf() * PI * 2.0
			house.scale = Vector3(randf_range(0.8, 1.2), randf_range(0.8, 1.5), randf_range(0.8, 1.2))
			
			add_child(house)
			
			# Lot
			var lot = CSGBox3D.new()
			lot.size = Vector3(spacing * 0.8, 0.1, spacing * 0.8)
			lot.use_collision = true
			lot.position = house.position - Vector3(0, 0.05, 0)
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.25, 0.2)
			lot.material = mat
			add_child(lot)