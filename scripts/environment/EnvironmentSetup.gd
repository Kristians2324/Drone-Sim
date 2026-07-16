extends Node3D

@export var ground_albedo_path: String = "res://assets/textures/real_ground_albedo.png"
@export var bark_albedo_path: String = "res://assets/textures/real_bark_albedo.png"
@export var rock_albedo_path: String = "res://assets/textures/real_rock_albedo.png"
@export var skybox_texture_path: String = "res://assets/textures/skybox.png"

var ground_albedo: Texture2D
var bark_albedo: Texture2D
var rock_albedo: Texture2D
var skybox_texture: Texture2D

@export var directional_light_path: NodePath
@export var environment_node_path: NodePath

@export var ambient_energy: float = 1.0
@export var sky_energy: float = 1.0
@export var fog_enabled: bool = true
@export var fog_density: float = 0.0009


func _ready() -> void:
	ground_albedo = load(ground_albedo_path) as Texture2D
	bark_albedo = load(bark_albedo_path) as Texture2D
	rock_albedo = load(rock_albedo_path) as Texture2D
	skybox_texture = load(skybox_texture_path) as Texture2D
	_apply_environment()


func _apply_environment() -> void:
	var world_env := _get_or_create_world_environment()
	if world_env == null:
		return

	var env := world_env.environment
	if env == null:
		env = Environment.new()
		world_env.environment = env

	env.background_mode = Environment.BG_SKY
	env.ambient_light_energy = ambient_energy
	env.fog_enabled = fog_enabled
	env.fog_density = fog_density

	if skybox_texture != null:
		var sky := Sky.new()
		var panorama := PanoramaSkyMaterial.new()
		panorama.panorama = skybox_texture
		sky.sky_material = panorama
		env.sky = sky
		env.sky_rotation = Vector3(0.0, 0.0, 0.0)
		env.sky_energy_multiplier = sky_energy

	if ground_albedo != null:
		env.ambient_light_color = Color(0.88, 0.92, 0.86)
	if bark_albedo != null or rock_albedo != null:
		env.reflected_light_color = Color(0.15, 0.16, 0.18)

	var sun := _get_directional_light()
	if sun != null:
		sun.light_energy = 2.0
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 250.0


func _get_or_create_world_environment() -> WorldEnvironment:
	if environment_node_path != NodePath():
		var node := get_node_or_null(environment_node_path)
		if node is WorldEnvironment:
			return node as WorldEnvironment

	for child in get_tree().current_scene.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment

	var created := WorldEnvironment.new()
	created.name = "WorldEnvironment"
	get_tree().current_scene.add_child(created)
	created.owner = get_tree().current_scene
	return created


func _get_directional_light() -> DirectionalLight3D:
	if directional_light_path != NodePath():
		var node := get_node_or_null(directional_light_path)
		if node is DirectionalLight3D:
			return node as DirectionalLight3D
	return get_tree().current_scene.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
