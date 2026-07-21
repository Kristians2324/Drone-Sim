extends Node3D
class_name Boid

var velocity = Vector3.ZERO
var max_speed = 25.0
var max_force = 15.0

@onready var trail_particles = CPUParticles3D.new()

# Store propeller nodes to animate them in flight
var propellers: Array[MeshInstance3D] = []

var light_rig: DroneShowLightRig

var body_material: StandardMaterial3D
var arm_material: StandardMaterial3D
var prop_material: StandardMaterial3D
var trail_gradient: Gradient

var show_index: int = 0
var show_total: int = 1
var show_is_player: bool = false

# Expose mesh_instance to match manager expectations for colorization
var mesh_instance: MeshInstance3D

func _ready():
	# Create a visual wrapper to scale the drone model down
	var model_wrapper = Node3D.new()
	model_wrapper.scale = Vector3(0.4, 0.4, 0.4) # 0.4x scale mini drone
	add_child(model_wrapper)
	
	# Create the drone body mesh
	var body_mesh_inst = MeshInstance3D.new()
	var body_mesh = BoxMesh.new()
	body_mesh.size = Vector3(0.4, 0.15, 0.6)
	body_mesh_inst.mesh = body_mesh
	
	var body_mat = StandardMaterial3D.new()
	body_material = body_mat
	body_material.albedo_color = Color(0.15, 0.15, 0.2) # Dark metallic body
	body_material.metallic = 0.8
	body_material.roughness = 0.2
	body_mesh_inst.material_override = body_material
	model_wrapper.add_child(body_mesh_inst)
	mesh_instance = body_mesh_inst
	
	# Create Arm 1
	var arm1_mesh_inst = MeshInstance3D.new()
	var arm_mesh = BoxMesh.new()
	arm_mesh.size = Vector3(0.1, 0.05, 0.8)
	arm1_mesh_inst.mesh = arm_mesh
	arm1_mesh_inst.rotation_degrees.y = 45
	
	var arm_mat = StandardMaterial3D.new()
	arm_material = arm_mat
	arm_material.albedo_color = Color(0.3, 0.3, 0.35) # Grey metallic arm
	arm_material.metallic = 0.7
	arm_material.roughness = 0.3
	arm1_mesh_inst.material_override = arm_material
	model_wrapper.add_child(arm1_mesh_inst)
	
	# Create Arm 2
	var arm2_mesh_inst = MeshInstance3D.new()
	arm2_mesh_inst.mesh = arm_mesh
	arm2_mesh_inst.rotation_degrees.y = -45
	arm2_mesh_inst.material_override = arm_material
	model_wrapper.add_child(arm2_mesh_inst)
	
	# Create 4 propellers
	var prop_mesh = CylinderMesh.new()
	prop_mesh.top_radius = 0.25
	prop_mesh.bottom_radius = 0.25
	prop_mesh.height = 0.01
	
	var prop_mat = StandardMaterial3D.new()
	prop_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	prop_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	prop_mat.metallic = 0.5
	prop_material = prop_mat
	
	var prop_positions = [
		Vector3(0.3, 0.1, 0.3),
		Vector3(-0.3, 0.1, 0.3),
		Vector3(0.3, 0.1, -0.3),
		Vector3(-0.3, 0.1, -0.3)
	]
	
	for i in range(4):
		var prop_inst = MeshInstance3D.new()
		prop_inst.mesh = prop_mesh
		prop_inst.position = prop_positions[i]
		prop_inst.material_override = prop_mat
		model_wrapper.add_child(prop_inst)
		propellers.append(prop_inst)
		
	# Setup the glow trail particles
	var particle_mat = StandardMaterial3D.new()
	particle_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.vertex_color_use_as_albedo = true
	particle_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	
	trail_particles.material_override = particle_mat
	trail_particles.amount = 12
	trail_particles.lifetime = 0.5
	trail_particles.speed_scale = 1.0
	trail_particles.explosiveness = 0.0
	trail_particles.randomness = 0.1
	trail_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail_particles.emission_sphere_radius = 0.04
	trail_particles.direction = Vector3.ZERO
	trail_particles.spread = 180.0
	trail_particles.gravity = Vector3(0, -0.2, 0)
	trail_particles.initial_velocity_min = 0.05
	trail_particles.initial_velocity_max = 0.2
	trail_particles.scale_amount_min = 0.02
	trail_particles.scale_amount_max = 0.06
	
	# Color ramp for fading out particles
	var gradient = Gradient.new()
	trail_gradient = gradient
	if trail_gradient.get_point_count() == 0:
		trail_gradient.add_point(0.0, Color(0.0, 1.0, 0.8, 0.85))
		trail_gradient.add_point(1.0, Color(0.0, 1.0, 0.8, 0.0))
	trail_particles.color_ramp = trail_gradient
	
	add_child(trail_particles)
	setup_show_lights()
	_apply_show_palette()
	trail_particles.emitting = true

func configure_show_lights(index: int, total: int, player_drone: bool = false):
	show_index = max(index, 0)
	show_total = max(total, 1)
	show_is_player = player_drone
	if light_rig:
		light_rig.configure(show_index, show_total, show_is_player)
	_apply_show_palette()

func setup_show_lights():
	if light_rig != null:
		return

	light_rig = DroneShowLightRig.new()
	light_rig.name = "ShowLights"
	light_rig.position = Vector3(0, -0.16, 0)
	add_child(light_rig)
	light_rig.configure(show_index, show_total, show_is_player)

func _apply_show_palette():
	var palette: Dictionary = _get_show_palette()
	if body_material:
		body_material.albedo_color = palette["body"]
	if arm_material:
		arm_material.albedo_color = palette["body"].lerp(palette["secondary"], 0.45)
	if prop_material:
		prop_material.albedo_color = palette["highlight"].lerp(Color.BLACK, 0.60)
	if trail_gradient:
		if trail_gradient.get_point_count() < 2:
			trail_gradient.add_point(0.0, palette["core"])
			trail_gradient.add_point(1.0, Color(palette["core"].r, palette["core"].g, palette["core"].b, 0.0))
		else:
			trail_gradient.set_color(0, palette["core"])
			trail_gradient.set_color(1, Color(palette["core"].r, palette["core"].g, palette["core"].b, 0.0))

func _get_show_palette() -> Dictionary:
	if light_rig:
		return light_rig.get_palette()

	return {
		"core": Color.CYAN,
		"secondary": Color.MAGENTA,
		"highlight": Color.WHITE,
		"body": Color(0.14, 0.14, 0.18),
	}

func update_boid(delta: float):
	# Move position by velocity
	global_position += velocity * delta
	
	# Orient towards velocity direction
	if velocity.length_squared() > 0.01:
		var fwd = -velocity.normalized() # basis.z is backward in Godot
		var left = Vector3.UP.cross(fwd).normalized()
		if left.is_zero_approx():
			left = Vector3.RIGHT
		var up = fwd.cross(left).normalized()
		
		var target_basis = Basis(left, up, fwd).orthonormalized()
		global_transform.basis = global_transform.basis.slerp(target_basis, delta * 6.0)
		
	# Rotate mini propellers
	var rotation_speed = delta * 40.0
	for prop in propellers:
		prop.rotate_y(rotation_speed)
