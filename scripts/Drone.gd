extends RigidBody3D

# --- POWERFUL SMOOTH FLIGHT CONFIG ---
const THROTTLE_POWER = 180.0   
const FORWARD_POWER = 120.0    
const TURN_POWER = 18.0
const STABILIZE_FORCE = 45.0
const INPUT_SMOOTHING = 3.5
const HOVER_MIN_CLEARANCE = 2.0
const HOVER_HOLD_FORCE = 55.0
const HOVER_HOLD_DAMPING = 12.0
const HOVER_MAX_HOLD_FORCE = 90.0

var smoothed_input = Vector4.ZERO # throttle, yaw, pitch, roll
var hover_enabled = false

# Audio Variables
var motor_audio: AudioStreamPlayer3D
var motor_playback: AudioStreamGeneratorPlayback
var crash_audio: AudioStreamPlayer3D
var crash_playback: AudioStreamGeneratorPlayback
var audio_hz = 44100.0
var motor_phase = 0.0

@onready var design = $Design
@onready var collision_shape: CollisionShape3D = $Collision

var drone_model: Node3D
var propellers: Array[Node3D] = []
var show_rig: DroneShowLightRig

func _ready():
	# Professional heavy physics for maximum stability
	mass = 5.0
	gravity_scale = 1.0
	linear_damp = 2.0
	angular_damp = 8.0
	
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# Enable collision detection for sound
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_drone_collision)
	
	# Ensure collision shape is properly set on the body
	collision_shape.shape = BoxShape3D.new()
	collision_shape.shape.size = Vector3(1.2, 0.2, 1.2)
	collision_shape.transform = Transform3D.IDENTITY
	
	# Setup procedural audio
	setup_drone_audio()
	
	# Find and initialize propellers from the built-in Godot scene model
	propellers.clear()
	var props_node = design.get_node_or_null("Props")
	if props_node:
		for prop in props_node.get_children():
			if prop is Node3D:
				propellers.append(prop)
		print("Drone: Found ", propellers.size(), " procedural propellers in the Godot model.")

	setup_show_lights()
	apply_hover_mode()

func replace_drone_model():
	print("Drone: Starting model replacement...")
	# Hide/Remove old procedural parts
	for child in design.get_children():
		if not child is Camera3D and not child is XROrigin3D:
			if child == show_rig:
				show_rig = null
			child.queue_free()
	
	# Load and instance the new model
	if not FileAccess.file_exists("res://Drone.gltf"):
		push_error("Drone: Drone.gltf NOT FOUND in res://")
		return
		
	var model_scene: PackedScene = load("res://Drone.gltf")
	if model_scene:
		drone_model = model_scene.instantiate()
		design.add_child(drone_model)
		design.visible = true
		
		# Center the model
		var model_aabb: AABB = _center_spline_model(drone_model)
		
		# Auto-scale to a reasonable 3.5m wingspan
		var max_dim: float = max(model_aabb.size.x, model_aabb.size.z)
		if max_dim > 0:
			var target_scale = 3.5 / max_dim 
			drone_model.scale = Vector3(target_scale, target_scale, target_scale)
			print("Drone: Applied reasonable scale: ", target_scale)
		else:
			drone_model.scale = Vector3(2.5, 2.5, 2.5)
			
		# Shrink the central body block
		var central_cube: Node = drone_model.find_child("Cube*", true, false)
		if not central_cube: central_cube = drone_model.find_child("*Cube*", true, false)
		if central_cube:
			central_cube.scale *= 0.4 
			print("Drone: Shrunk central body node: ", central_cube.name)
			
		drone_model.rotation_degrees.y = 180 
		
		# Find propellers
		propellers.clear()
		_find_propellers(drone_model)
		print("Drone: Model loaded successfully. Found ", propellers.size(), " propellers.")

		if propellers.size() == 0:
			print("Drone: No propellers found by name, attempting fallback by height...")
			_find_propellers_fallback(drone_model)
			print("Drone: Fallback found ", propellers.size(), " potential propellers.")

		setup_show_lights()
	else:
		push_error("Drone: Failed to load Drone.gltf as a scene.")

func _center_spline_model(model: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_get_all_meshes(model, meshes)
	
	var aabb = AABB()
	var first = true
	
	for mesh in meshes:
		var mesh_transform = model.global_transform.affine_inverse() * mesh.global_transform
		var mesh_aabb = mesh_transform * mesh.get_aabb()
		
		if first:
			aabb = mesh_aabb
			first = false
		else:
			aabb = aabb.merge(mesh_aabb)
	
	if not first:
		var center = aabb.get_center()
		for child in model.get_children():
			if child is Node3D:
				child.position -= center
		print("Drone: Auto-centered Spline model. Offset by: ", -center)
		aabb.position -= center
		return aabb
		
	return AABB()

func _get_all_meshes(node: Node, meshes: Array[MeshInstance3D]):
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_get_all_meshes(child, meshes)

func _find_propellers_fallback(node):
	if node is MeshInstance3D:
		var name_lower = node.name.to_lower()
		if "cylinder" in name_lower:
			propellers.append(node)
	
	for child in node.get_children():
		_find_propellers_fallback(child)

func _find_propellers(node):
	var name_lower = node.name.to_lower()
	var is_prop = "prop" in name_lower or "blade" in name_lower or "rotor" in name_lower or "helix" in name_lower or "fan" in name_lower
	
	if is_prop and node is Node3D:
		propellers.append(node)
	
	for child in node.get_children():
		_find_propellers(child)

func _physics_process(delta):
	if get_tree().paused: return

	# Always fill motor audio buffer
	fill_motor_buffer()

	_apply_input_forces(delta, smoothed_input)

var smoothed_input_internal = Vector4.ZERO

func _apply_input_forces(delta, input_vec: Vector4):
	smoothed_input_internal = smoothed_input_internal.lerp(input_vec, delta * INPUT_SMOOTHING)

	var local_up = Vector3.UP if hover_enabled else global_transform.basis.y
	var forward_dir = -global_transform.basis.z
	var strafe_dir = global_transform.basis.x
	if hover_enabled:
		forward_dir.y = 0.0
		strafe_dir.y = 0.0
		if not forward_dir.is_zero_approx():
			forward_dir = forward_dir.normalized()
		if not strafe_dir.is_zero_approx():
			strafe_dir = strafe_dir.normalized()

	var vertical_thrust = local_up * smoothed_input_internal.x * THROTTLE_POWER
	var forward_force = forward_dir * smoothed_input_internal.z * FORWARD_POWER
	var strafe_force = strafe_dir * smoothed_input_internal.w * FORWARD_POWER

	apply_central_force(vertical_thrust + forward_force + strafe_force)

	if hover_enabled:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var from = global_position + Vector3.UP * 0.1
			var to = global_position + Vector3.DOWN * 20.0
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.exclude = [get_rid()]
			var result = space_state.intersect_ray(query)
			if result.has("position"):
				var ground_distance = global_position.y - result.position.y
				if ground_distance < HOVER_MIN_CLEARANCE:
					var hover_force = (HOVER_MIN_CLEARANCE - ground_distance) * HOVER_HOLD_FORCE
					hover_force -= linear_velocity.y * HOVER_HOLD_DAMPING
					hover_force = clamp(hover_force, 0.0, HOVER_MAX_HOLD_FORCE)
					apply_central_force(Vector3.UP * hover_force)

	apply_torque(global_transform.basis.x * -smoothed_input_internal.z * TURN_POWER)
	apply_torque(global_transform.basis.z * -smoothed_input_internal.w * TURN_POWER)
	apply_torque(global_transform.basis.y * -smoothed_input_internal.y * TURN_POWER)

	var up = global_transform.basis.y
	var correction = up.cross(Vector3.UP)
	
	var current_stabilize = STABILIZE_FORCE
	if abs(smoothed_input_internal.z) < 0.05 and abs(smoothed_input_internal.w) < 0.05:
		current_stabilize = STABILIZE_FORCE * 3.0
		
	apply_torque(correction * current_stabilize)

	var prop_speed = 30.0 + (smoothed_input_internal.x * 60.0)
	for prop in propellers:
		prop.rotate_y(delta * prop_speed)

	var legacy_props = design.get_node_or_null("Props")
	if legacy_props:
		for prop in legacy_props.get_children():
			prop.rotate_y(delta * prop_speed)

func set_input_vector(input_vec: Vector4) -> void:
	smoothed_input = input_vec

func apply_hover_mode():
	gravity_scale = 0.0 if hover_enabled else 1.0

func get_propeller_count() -> int:
	return propellers.size()

func setup_show_lights():
	if show_rig != null:
		return

	show_rig = DroneShowLightRig.new()
	show_rig.name = "ShowLights"
	show_rig.position = Vector3(0, -0.18, 0)
	add_child(show_rig)
	show_rig.configure(0, 1, true)

func setup_drone_audio():
	motor_audio = AudioStreamPlayer3D.new()
	var generator = AudioStreamGenerator.new()
	generator.buffer_length = 0.1
	motor_audio.stream = generator
	motor_audio.unit_size = 5.0
	motor_audio.max_distance = 100.0
	add_child(motor_audio)
	motor_audio.play()
	motor_playback = motor_audio.get_stream_playback()
	
	crash_audio = AudioStreamPlayer3D.new()
	var crash_gen = AudioStreamGenerator.new()
	crash_gen.buffer_length = 0.05
	crash_audio.stream = crash_gen
	add_child(crash_audio)
	crash_audio.play()
	crash_playback = crash_audio.get_stream_playback()

func _on_drone_collision(_body):
	var impact = linear_velocity.length()
	if impact > 1.5: 
		play_crash_sound(impact)

func play_crash_sound(intensity: float):
	if crash_playback == null: return
	
	var vol = clamp(intensity / 10.0, 0.2, 0.5) 
	var frames_to_push = 2205 
	
	for i in range(frames_to_push):
		var sample = (randf() * 2.0 - 1.0) * vol
		sample *= (1.0 - float(i) / frames_to_push)
		crash_playback.push_frame(Vector2(sample, sample))
	
	if not crash_audio.playing:
		crash_audio.play()

func fill_motor_buffer():
	if motor_playback == null: return
	
	var n = motor_playback.get_frames_available()
	
	var input_thrust = abs(smoothed_input.x)
	var input_movement = Vector2(smoothed_input.z, smoothed_input.w).length()
	var input_yaw = abs(smoothed_input.y)
	
	var motor_effort = max(input_thrust, input_movement * 0.45 + input_yaw * 0.25)
	var speed_contrib = clamp(linear_velocity.length() / 20.0, 0.0, 0.5)
	
	var throttle = clamp(max(motor_effort, speed_contrib), 0.0, 1.0)
	var freq = 60.0 + (throttle * 120.0) 
	var volume = 0.005 + (throttle * 0.015) 
	
	while n > 0:
		var sample = sin(motor_phase * TAU)
		sample += sin(motor_phase * 2.0 * TAU) * 0.3
		sample *= volume
		
		if not is_inf(sample) and not is_nan(sample):
			motor_playback.push_frame(Vector2(sample, sample))
		
		motor_phase = fmod(motor_phase + freq / audio_hz, 1.0)
		n -= 1
