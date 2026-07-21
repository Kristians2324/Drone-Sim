extends Node3D
class_name Town

@export var grid_size: int = 5
@export var spacing: float = 15.0
@export_file("*.tscn") var house_scene_path: String = "res://scenes/House.tscn"

var FLOOR_ALBEDO := load("res://assets/textures/floor_albedo.png")
var FLOOR_NORMAL := load("res://assets/textures/floor_normal.png")

var house_scene: PackedScene

func _ready():
	if house_scene_path != "":
		house_scene = load(house_scene_path)

func _build_lot_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = FLOOR_ALBEDO
	mat.normal_texture = FLOOR_NORMAL
	mat.normal_enabled = true
	mat.roughness = 1.0
	mat.albedo_color = Color(0.44, 0.41, 0.35)
	mat.uv1_scale = Vector3(3.5, 3.5, 3.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat

func generate():
	seed(123)
	if house_scene == null:
		if house_scene_path != "":
			house_scene = load(house_scene_path)
	if house_scene == null:
		push_error("Town: house scene path could not be loaded: %s" % house_scene_path)
		return
	
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
			lot.material = _build_lot_material()
			add_child(lot)