extends Node3D
class_name DroneShowLightRig

var drone_index: int = 0
var drone_total: int = 1
var is_player_drone: bool = false

var show_time: float = 0.0
var phase_offset: float = 0.0

var palette_core: Color = Color.CYAN
var palette_secondary: Color = Color.MAGENTA
var palette_highlight: Color = Color.WHITE
var palette_body: Color = Color(0.1, 0.1, 0.14)

var halo_light: OmniLight3D
var down_light: SpotLight3D
var halo_mesh: MeshInstance3D
var halo_material: StandardMaterial3D

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)
	_build_rig()
	_rebuild_palette()
	_apply_palette_to_visuals()

func configure(index: int, total: int, player_drone: bool = false):
	drone_index = max(index, 0)
	drone_total = max(total, 1)
	is_player_drone = player_drone
	_rebuild_palette()
	_apply_palette_to_visuals()

func get_palette() -> Dictionary:
	return {
		"core": palette_core,
		"secondary": palette_secondary,
		"highlight": palette_highlight,
		"body": palette_body,
	}

func _build_rig():
	if halo_light != null:
		return

	halo_light = OmniLight3D.new()
	halo_light.name = "UnderglowLight"
	halo_light.omni_range = 11.0
	halo_light.omni_attenuation = 1.3
	halo_light.light_energy = 2.5
	halo_light.shadow_enabled = false
	add_child(halo_light)

	down_light = SpotLight3D.new()
	down_light.name = "UnderglowSpot"
	down_light.position = Vector3(0.0, -0.05, 0.0)
	down_light.rotation_degrees.x = -90.0
	down_light.spot_angle = 55.0
	down_light.spot_attenuation = 1.5
	down_light.light_energy = 3.2
	down_light.shadow_enabled = false
	add_child(down_light)

	halo_mesh = MeshInstance3D.new()
	halo_mesh.name = "UnderglowDisc"
	var disc = CylinderMesh.new()
	disc.top_radius = 0.12
	disc.bottom_radius = 0.22
	disc.height = 0.03
	halo_mesh.mesh = disc
	halo_mesh.position = Vector3(0.0, -0.03, 0.0)
	add_child(halo_mesh)

	halo_material = StandardMaterial3D.new()
	halo_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	halo_material.albedo_color = Color(1, 1, 1, 0.85)
	halo_material.emission_enabled = true
	halo_material.emission = Color.WHITE
	halo_material.emission_energy_multiplier = 3.0
	halo_mesh.material_override = halo_material

func _rebuild_palette():
	var count: int = int(drone_total)
	if count < 1:
		count = 1
	var ratio: float = 0.0
	if count > 1:
		ratio = float(int(drone_index) % count) / float(count - 1)

	if is_player_drone:
		palette_core = Color.from_hsv(0.57, 0.92, 1.0)      # Ice cyan
		palette_secondary = Color.from_hsv(0.78, 0.88, 1.0) # Violet
		palette_highlight = Color.from_hsv(0.03, 0.78, 1.0)  # Warm amber accent
		palette_body = Color(0.08, 0.10, 0.16)
		phase_offset = 0.0
	else:
		var band: int = int(floor(ratio * 4.0))
		var band_ratio: float = fposmod(ratio * 4.0, 1.0)
		match band:
			0:
				palette_core = Color.from_hsv(0.30 + band_ratio * 0.05, 0.95, 1.0) # green -> lime
				palette_secondary = Color.from_hsv(0.45, 0.90, 1.0) # aqua
				palette_highlight = Color.from_hsv(0.58, 0.70, 1.0) # cyan
				palette_body = Color.from_hsv(0.28, 0.35, 0.22)
			1:
				palette_core = Color.from_hsv(0.56 + band_ratio * 0.05, 0.95, 1.0) # cyan -> blue
				palette_secondary = Color.from_hsv(0.66, 0.90, 1.0) # blue-violet
				palette_highlight = Color.from_hsv(0.77, 0.65, 1.0) # magenta
				palette_body = Color.from_hsv(0.60, 0.32, 0.22)
			2:
				palette_core = Color.from_hsv(0.83 + band_ratio * 0.05, 0.95, 1.0) # magenta -> pink
				palette_secondary = Color.from_hsv(0.92, 0.88, 1.0) # red-pink
				palette_highlight = Color.from_hsv(0.06, 0.72, 1.0) # gold
				palette_body = Color.from_hsv(0.88, 0.28, 0.24)
			_:
				palette_core = Color.from_hsv(0.11 + band_ratio * 0.04, 0.95, 1.0) # gold -> orange
				palette_secondary = Color.from_hsv(0.18, 0.90, 1.0) # yellow
				palette_highlight = Color.from_hsv(0.95, 0.65, 1.0) # pink accent
				palette_body = Color.from_hsv(0.10, 0.36, 0.22)
		phase_offset = (ratio * TAU * 2.0) + float(band) * 0.7

func _apply_palette_to_visuals():
	if halo_light == null or halo_material == null:
		return

	var base_color: Color = palette_core.lerp(palette_secondary, 0.35)
	if is_player_drone:
		base_color = base_color.lerp(Color.WHITE, 0.14)

	halo_light.light_color = base_color
	halo_light.light_energy = 2.6 if is_player_drone else 2.0
	if down_light:
		down_light.light_color = base_color.lerp(Color.WHITE, 0.1)
		down_light.light_energy = 3.6 if is_player_drone else 2.8
	halo_material.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.85)
	halo_material.emission = base_color
	halo_material.emission_energy_multiplier = 3.4 if is_player_drone else 2.8

func _process(delta: float):
	show_time += delta

	var slow_wave: float = 0.5 + 0.5 * sin(show_time * (2.2 if is_player_drone else 1.9) + phase_offset)
	var fast_wave: float = 0.5 + 0.5 * sin(show_time * (4.6 if is_player_drone else 3.8) + phase_offset * 1.7 + 0.7)

	var color: Color = palette_core.lerp(palette_secondary, slow_wave)
	color = color.lerp(palette_highlight, fast_wave * 0.40)
	if is_player_drone:
		color = color.lerp(Color.WHITE, 0.18 + fast_wave * 0.08)

	if halo_light:
		halo_light.light_color = color
		halo_light.light_energy = (4.2 if is_player_drone else 2.3) + slow_wave * (2.1 if is_player_drone else 1.2)
	if down_light:
		down_light.light_color = color.lerp(Color.WHITE, 0.08)
		down_light.light_energy = (5.0 if is_player_drone else 3.2) + slow_wave * (2.6 if is_player_drone else 1.4)

	if halo_material:
		halo_material.albedo_color = Color(color.r, color.g, color.b, 0.78 if is_player_drone else 0.82)
		halo_material.emission = color
		halo_material.emission_energy_multiplier = (4.6 if is_player_drone else 3.2) + fast_wave * 1.0
