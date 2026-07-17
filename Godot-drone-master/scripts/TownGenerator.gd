extends Node3D

@export var grid_size: int = 5
@export var spacing: float = 15.0
@export_file("*.tscn") var house_scene_path: String = "res://scenes/House.tscn"

const FLOOR_ALBEDO_PATH := "res://assets/textures/real_ground_albedo.png"
const FLOOR_NORMAL_PATH := "res://assets/textures/floor_normal.png"

var house_scene: PackedScene

func _ready() -> void:
	if house_scene_path != "":
		house_scene = load(house_scene_path)

func _build_lot_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(FLOOR_ALBEDO_PATH)
	mat.normal_texture = load(FLOOR_NORMAL_PATH)
	mat.normal_enabled = true
	mat.roughness = 0.98
	mat.albedo_color = Color(0.52, 0.46, 0.38)
	mat.uv1_scale = Vector3(2.5, 2.5, 2.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat

func generate() -> void:
	seed(123)
	if house_scene == null and house_scene_path != "":
		house_scene = load(house_scene_path)
	if house_scene == null:
		push_error("TownGenerator: house scene path could not be loaded: %s" % house_scene_path)
		return

	for x in range(grid_size):
		for z in range(grid_size):
			if x % 2 == 0 and z % 2 == 0:
				continue

			var house := house_scene.instantiate()
			if house is Node3D:
				var pos = Vector3(x * spacing, 0.0, z * spacing)
				house.position = pos - Vector3(grid_size * spacing * 0.5, 0.0, grid_size * spacing * 0.5) + Vector3(50, 0, 50)
				house.rotation.y = randf() * PI * 2.0
				house.scale = Vector3(randf_range(0.8, 1.2), randf_range(0.8, 1.5), randf_range(0.8, 1.2))
				add_child(house)

				var lot := CSGBox3D.new()
				lot.size = Vector3(spacing * 0.8, 0.1, spacing * 0.8)
				lot.use_collision = true
				lot.position = house.position - Vector3(0, 0.05, 0)
				lot.material = _build_lot_material()
				add_child(lot)
