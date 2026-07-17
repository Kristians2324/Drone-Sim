extends Node3D
class_name SkyEnvironment

var wind_manager: WindManager = null

@export var wind_field_count: int = 24
@export var wind_field_radius: float = 220.0
@export var wind_field_height: float = 85.0
@export var wind_field_vertical_span: float = 45.0
@export var wind_field_speed_scale: float = 18.0
@export var wind_field_size_min: float = 18.0
@export var wind_field_size_max: float = 42.0

func setup():
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	
	env.background_mode = Environment.BG_SKY
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85, 1)
	sky_mat.sky_horizon_color = Color(0.65, 0.75, 0.85, 1)
	sky_mat.ground_bottom_color = Color(0.15, 0.15, 0.15, 1)
	sky_mat.ground_horizon_color = Color(0.65, 0.75, 0.85, 1)
	
	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.1
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	
	world_env.environment = env
	add_child(world_env)

	wind_manager = get_tree().current_scene.get_node_or_null("WindManager") as WindManager if get_tree().current_scene else null
	_setup_wind_field()
	
	var light = DirectionalLight3D.new()
	light.transform.basis = Basis.from_euler(Vector3(-0.866025, -0.433013, 0.25))
	light.light_energy = 2.0
	light.shadow_enabled = true
	light.shadow_bias = 0.03
	light.shadow_blur = 0.5
	add_child(light)

func _setup_wind_field() -> void:
	# Create a visible sky wind field made of translucent streaks moving with the current wind.
	for child in get_children():
		if child.name.begins_with("WindField_"):
			child.queue_free()

	var wind_dir := Vector3(1, 0, 0)
	var wind_strength := 1.0
	if wind_manager:
		wind_dir = wind_manager.wind_direction
		wind_strength = wind_manager.get_wind_strength()

	for i in wind_field_count:
		var streak := MeshInstance3D.new()
		streak.name = "WindField_%d" % i
		var mesh := BoxMesh.new()
		var length := randf_range(wind_field_size_min, wind_field_size_max)
		mesh.size = Vector3(0.18, 0.18, length)
		streak.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.70, 0.88, 1.0, 0.14)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = Color(0.40, 0.65, 0.95, 1.0)
		material.emission_energy_multiplier = 0.6
		streak.material_override = material
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var angle := randf_range(0.0, TAU)
		var radius := randf_range(35.0, wind_field_radius)
		var height := wind_field_height + randf_range(-wind_field_vertical_span, wind_field_vertical_span)
		streak.position = Vector3(cos(angle) * radius, height, sin(angle) * radius)
		if not wind_dir.is_zero_approx():
			streak.look_at(streak.position + wind_dir, Vector3.UP)
		streak.scale = Vector3(1.0, 1.0, maxf(0.75, wind_strength * 0.35))
		add_child(streak)

func _process(delta: float) -> void:
	if wind_manager == null:
		wind_manager = get_tree().current_scene.get_node_or_null("WindManager") as WindManager if get_tree().current_scene else null
	var wind_dir := Vector3(1, 0, 0)
	var wind_strength := 1.0
	if wind_manager:
		wind_dir = wind_manager.wind_direction
		wind_strength = wind_manager.get_wind_strength()

	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("WindField_"):
			var streak := child as MeshInstance3D
			var drift := wind_dir * (delta * wind_strength * wind_field_speed_scale)
			streak.position += drift
			if streak.position.length() > wind_field_radius * 1.5:
				streak.position.x = randf_range(-wind_field_radius, wind_field_radius)
				streak.position.z = randf_range(-wind_field_radius, wind_field_radius)
				streak.position.y = wind_field_height + randf_range(-wind_field_vertical_span, wind_field_vertical_span)
				if not wind_dir.is_zero_approx():
					streak.look_at(streak.position + wind_dir, Vector3.UP)