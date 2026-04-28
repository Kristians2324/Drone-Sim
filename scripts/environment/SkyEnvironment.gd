extends Node3D
class_name SkyEnvironment

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
	
	var light = DirectionalLight3D.new()
	light.transform.basis = Basis.from_euler(Vector3(-0.866025, -0.433013, 0.25))
	light.light_energy = 2.0
	light.shadow_enabled = true
	light.shadow_bias = 0.03
	light.shadow_blur = 0.5
	add_child(light)