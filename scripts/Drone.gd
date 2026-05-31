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

# Autopilot & Tricks configuration
enum FlightState { MANUAL, AUTOPILOT, TRICK_LOOP, TRICK_BARREL }
var flight_state = FlightState.MANUAL
var state_toggle_cooldown = 0.0

var autopilot_waypoints: Array[Vector3] = [
	Vector3(0, 15, 0),
	Vector3(120, 25, -120),
	Vector3(250, 45, -50),   # High altitude, trigger loop-de-loop
	Vector3(150, 30, 150),
	Vector3(-100, 25, 200),  # Mid altitude, trigger barrel roll
	Vector3(-250, 35, 50),
	Vector3(-150, 20, -150)
]
var current_waypoint_index = 0
var autopilot_speed = 22.0
var waypoint_reach_distance = 12.0

# Trick variables
var trick_time = 0.0
const LOOP_DURATION = 2.2
var loop_start_pos = Vector3.ZERO
var loop_center = Vector3.ZERO
var loop_forward = Vector3.ZERO
var loop_up = Vector3.ZERO
var loop_radius = 20.0

const BARREL_DURATION = 1.2
var barrel_start_pos = Vector3.ZERO
var barrel_forward = Vector3.ZERO
var barrel_left = Vector3.ZERO
var barrel_up = Vector3.ZERO
var barrel_start_basis = Basis.IDENTITY
var barrel_speed = 20.0
var barrel_radius = 2.0

var post_trick_state = FlightState.MANUAL

# Swarm variables
var boids_manager: Node3D = null

# Camera toggle
var is_first_person = true
var third_person_camera: Camera3D
var first_person_camera: Camera3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var camera_toggle_cooldown = 0.0

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

var hover_enabled = false

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
	
	# Setup standard cameras
	third_person_camera = $SpringArm3D/Camera3D
	first_person_camera = Camera3D.new()
	design.add_child(first_person_camera)
	first_person_camera.position = Vector3(0, 0.15, -0.35)
	first_person_camera.rotation_degrees = Vector3(15, 0, 0)
	
	# Setup VR nodes (Optional)
	setup_vr()
	
	# Initial camera state
	update_camera_views()
	
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
	# 1. Hide/Remove old procedural parts
	for child in design.get_children():
		if not child is Camera3D and not child is XROrigin3D:
			if child == show_rig:
				show_rig = null
			child.queue_free()
	
	# 2. Load and instance the new model
	if not FileAccess.file_exists("res://Drone.gltf"):
		push_error("Drone: Drone.gltf NOT FOUND in res://")
		return
		
	var model_scene: PackedScene = load("res://Drone.gltf")
	if model_scene:
		drone_model = model_scene.instantiate()
		design.add_child(drone_model)
		design.visible = true
		
		# 3. Handle Spline's massive offset and scale
		# We'll group the model under a wrapper to center it
		var model_aabb: AABB = _center_spline_model(drone_model)
		
		# Auto-scale to a reasonable 3.5m wingspan
		var max_dim: float = max(model_aabb.size.x, model_aabb.size.z)
		if max_dim > 0:
			var target_scale = 3.5 / max_dim 
			drone_model.scale = Vector3(target_scale, target_scale, target_scale)
			print("Drone: Applied reasonable scale: ", target_scale)
		else:
			drone_model.scale = Vector3(2.5, 2.5, 2.5)
			
		# Shrink the "square in the middle" (usually named Cube in Spline)
		var central_cube: Node = drone_model.find_child("Cube*", true, false)
		if not central_cube: central_cube = drone_model.find_child("*Cube*", true, false)
		if central_cube:
			central_cube.scale *= 0.4 # Make the body block much smaller
			print("Drone: Shrunk central body node: ", central_cube.name)
			
		drone_model.rotation_degrees.y = 180 # Face forward
		
		# 4. Find propellers
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
	# Spline exports often have huge world-space offsets and deep hierarchies.
	# We find all meshes in the subtree to calculate the true center.
	var meshes: Array[MeshInstance3D] = []
	_get_all_meshes(model, meshes)
	
	var aabb = AABB()
	var first = true
	
	for mesh in meshes:
		# Get the mesh transform relative to the 'model' root
		var mesh_transform = model.global_transform.affine_inverse() * mesh.global_transform
		# Transform the local AABB into the model's local space
		var mesh_aabb = mesh_transform * mesh.get_aabb()
		
		if first:
			aabb = mesh_aabb
			first = false
		else:
			aabb = aabb.merge(mesh_aabb)
	
	if not first:
		var center = aabb.get_center()
		# Offset the top-most wrapper nodes so they align with our physics body
		for child in model.get_children():
			if child is Node3D:
				child.position -= center
		print("Drone: Auto-centered Spline model. Offset by: ", -center)
		
		# Return the AABB relative to the center
		aabb.position -= center
		return aabb
		
	return AABB()

func _get_all_meshes(node: Node, meshes: Array[MeshInstance3D]):
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_get_all_meshes(child, meshes)

func _find_propellers_fallback(node):
	# In Spline exports, propellers are often just "Cylinder" nodes
	# We look for MeshInstances that are thin cylinders or high up
	if node is MeshInstance3D:
		var name_lower = node.name.to_lower()
		if "cylinder" in name_lower:
			# Check if it's likely a propeller (usually higher than the body)
			# or if it has many of them. For now, we'll take all cylinders 
			# except the one that might be the main body.
			propellers.append(node)
	
	for child in node.get_children():
		_find_propellers_fallback(child)

func _find_propellers(node):
	# Look for nodes containing "Prop", "Blade", "Rotor", "Helix", "Fan"
	var name_lower = node.name.to_lower()
	var is_prop = "prop" in name_lower or "blade" in name_lower or "rotor" in name_lower or "helix" in name_lower or "fan" in name_lower
	
	if is_prop and node is Node3D:
		propellers.append(node)
		# If we found a propeller group, we might not need to search its children 
		# for more propellers (to avoid double rotation), but we'll keep searching 
		# just in case the meshes are separate.
	
	for child in node.get_children():
		_find_propellers(child)

func setup_vr():
	# Create VR rig at the FPV position
	xr_origin = XROrigin3D.new()
	design.add_child(xr_origin)
	xr_origin.position = first_person_camera.position
	xr_origin.rotation = first_person_camera.rotation
	
	xr_camera = XRCamera3D.new()
	xr_origin.add_child(xr_camera)
	
	# Check if VR is actually active
	var main = get_tree().root.find_child("Main", true, false)
	var vr_manager = null
	if main: vr_manager = main.get_node_or_null("VRManager")
	
	if vr_manager and vr_manager.has_method("is_vr_active") and vr_manager.is_vr_active():
		print("Drone: VR Mode detected, configuring headset view.")
		is_first_person = true # Force FPV in VR
	else:
		xr_origin.visible = false

func update_camera_views():
	var main = get_tree().root.find_child("Main", true, false)
	var vr_manager = null
	if main: vr_manager = main.get_node_or_null("VRManager")
	var is_vr = vr_manager and vr_manager.has_method("is_vr_active") and vr_manager.is_vr_active()

	if is_vr:
		# In VR, we always use the XR Camera when in FPV
		third_person_camera.current = false
		first_person_camera.current = false
		# Note: XRCamera3D doesn't need 'current = true' as much as use_xr = true handles it,
		# but we hide the standard ones.
	else:
		third_person_camera.current = !is_first_person
		first_person_camera.current = is_first_person

func _physics_process(delta):
	if get_tree().paused: return
	
	# Fill audio buffer (needs smoothed_input.x, which is set in state processors)
	fill_motor_buffer()
	
	match flight_state:
		FlightState.MANUAL:
			process_manual_flight(delta)
		FlightState.AUTOPILOT:
			process_autopilot_flight(delta)
		FlightState.TRICK_LOOP:
			process_trick_loop(delta)
		FlightState.TRICK_BARREL:
			process_trick_barrel(delta)

func process_manual_flight(delta):
	# 1. Inputs (Works for Keyboard + Xbox natively via Action Map)
	var target = Vector4(
		Input.get_axis("throttle_down", "throttle_up"),
		Input.get_axis("turn_left", "turn_right"),
		Input.get_axis("move_back", "move_forward"),
		Input.get_axis("move_left", "move_right")
	)
	
	smoothed_input = smoothed_input.lerp(target, delta * INPUT_SMOOTHING)

	# 2. MOVEMENT
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
	var vertical_thrust = local_up * smoothed_input.x * THROTTLE_POWER
	var forward_force = forward_dir * smoothed_input.z * FORWARD_POWER
	var strafe_force = strafe_dir * smoothed_input.w * FORWARD_POWER
	
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
	
	# 3. Rotation
	apply_torque(global_transform.basis.x * -smoothed_input.z * TURN_POWER)
	apply_torque(global_transform.basis.z * -smoothed_input.w * TURN_POWER)
	apply_torque(global_transform.basis.y * -smoothed_input.y * TURN_POWER)
	
	# 4. Stabilization
	var up = global_transform.basis.y
	var correction = up.cross(Vector3.UP)
	apply_torque(correction * STABILIZE_FORCE)
	
	# Props
	var prop_speed = 30.0 + (smoothed_input.x * 60.0)
	for prop in propellers:
		prop.rotate_y(delta * prop_speed)
	
	# Legacy props (if any left)
	var legacy_props = design.get_node_or_null("Props")
	if legacy_props:
		for prop in legacy_props.get_children():
			prop.rotate_y(delta * prop_speed)

func apply_hover_mode():
	gravity_scale = 0.0 if hover_enabled else 1.0

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from = Vector3(pos.x, 300.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result = space_state.intersect_ray(query)
	if result.has("position"):
		return result.position.y
	return 0.0

func process_autopilot_flight(delta):
	# 1. Waypoint target matching
	var target_pos = autopilot_waypoints[current_waypoint_index]
	
	# Dynamically ensure the waypoint's base target height clears the terrain below it
	var base_terrain_height = get_terrain_height_at(target_pos)
	var waypoint_min_clearance = 15.0
	if target_pos.y < base_terrain_height + waypoint_min_clearance:
		target_pos.y = base_terrain_height + waypoint_min_clearance
		
	var dist_to_target = global_position.distance_to(target_pos)
	
	if dist_to_target < waypoint_reach_distance:
		# Trigger tricks at specific waypoints on the track
		if current_waypoint_index == 2: # High altitude loop
			start_trick_loop(false)
			current_waypoint_index = (current_waypoint_index + 1) % autopilot_waypoints.size()
			return
		elif current_waypoint_index == 4: # Mid altitude barrel roll
			start_trick_barrel(false)
			current_waypoint_index = (current_waypoint_index + 1) % autopilot_waypoints.size()
			return
		else:
			current_waypoint_index = (current_waypoint_index + 1) % autopilot_waypoints.size()
			target_pos = autopilot_waypoints[current_waypoint_index]
			# Adjust the new target waypoint too
			var new_base_terrain = get_terrain_height_at(target_pos)
			if target_pos.y < new_base_terrain + waypoint_min_clearance:
				target_pos.y = new_base_terrain + waypoint_min_clearance
			
	# 2. Steer velocity towards the target waypoint, with real-time terrain contouring
	var desired_dir = (target_pos - global_position).normalized()
	
	# Look ahead to detect upcoming hills or mountains in our path
	var look_ahead_dist = 15.0
	var forward_dir = linear_velocity.normalized()
	if forward_dir.is_zero_approx():
		forward_dir = -global_transform.basis.z
		
	var check_pos = global_position + forward_dir * look_ahead_dist
	var terrain_height_ahead = get_terrain_height_at(check_pos)
	var terrain_height_below = get_terrain_height_at(global_position)
	
	# Safe target altitude for the drone at its current horizontal position
	var flight_min_clearance = 12.0
	var safe_y = max(terrain_height_below + flight_min_clearance, terrain_height_ahead + flight_min_clearance)
	
	# Ensure the flight target is adjusted up if terrain demands it
	var adjusted_target_pos = target_pos
	if adjusted_target_pos.y < safe_y:
		adjusted_target_pos.y = safe_y
		
	# If the drone itself has fallen below safe altitude, apply an extra climbing boost
	if global_position.y < safe_y:
		adjusted_target_pos.y = max(adjusted_target_pos.y, safe_y + 8.0)
		
	desired_dir = (adjusted_target_pos - global_position).normalized()
	var target_velocity = desired_dir * autopilot_speed
	linear_velocity = linear_velocity.lerp(target_velocity, delta * 3.0)
	
	# 3. Orient the drone realistically
	# Forward direction along velocity
	var fwd = -linear_velocity.normalized()
	if fwd.is_zero_approx():
		fwd = -global_transform.basis.z
		
	var left = Vector3.UP.cross(fwd).normalized()
	if left.is_zero_approx():
		left = global_transform.basis.x
		
	var up = fwd.cross(left).normalized()
	
	# Banking/rolling into turns
	var current_fwd = -global_transform.basis.z
	var yaw_cross = current_fwd.cross(desired_dir)
	var turn_amount = yaw_cross.dot(Vector3.UP) # Positive: turn left, Negative: turn right
	
	# Max roll of ~35 degrees
	var target_roll = -turn_amount * 0.8
	target_roll = clamp(target_roll, -0.6, 0.6)
	
	# Slight pitch down during autopilot flight to signify forward thrust
	var target_pitch = -0.15
	
	# Build the target basis
	var target_basis = Basis(left, up, fwd)
	target_basis = target_basis.rotated(target_basis.z, target_roll)
	target_basis = target_basis.rotated(target_basis.x, target_pitch)
	
	# Slerp orientation
	global_transform.basis = global_transform.basis.slerp(target_basis.orthonormalized(), delta * 4.0)
	
	# Constant throttle values for propellers/motor sound
	smoothed_input.x = 0.6
	
	# Propellers
	var prop_speed = 30.0 + (smoothed_input.x * 60.0)
	for prop in propellers:
		prop.rotate_y(delta * prop_speed)
	
	var legacy_props = design.get_node_or_null("Props")
	if legacy_props:
		for prop in legacy_props.get_children():
			prop.rotate_y(delta * prop_speed)

func start_trick_loop(from_manual = false):
	flight_state = FlightState.TRICK_LOOP
	post_trick_state = FlightState.MANUAL if from_manual else FlightState.AUTOPILOT
	trick_time = 0.0
	loop_start_pos = global_position
	loop_forward = -global_transform.basis.z
	loop_up = global_transform.basis.y
	loop_center = loop_start_pos + loop_up * loop_radius
	print("Drone: Starting Loop-de-loop trick!")

func process_trick_loop(delta):
	trick_time += delta
	if trick_time >= LOOP_DURATION:
		flight_state = post_trick_state
		linear_velocity = loop_forward * autopilot_speed
		angular_velocity = Vector3.ZERO
		print("Drone: Loop-de-loop trick finished!")
		return
		
	var progress = trick_time / LOOP_DURATION
	var theta = -PI/2.0 + progress * TAU
	
	var target_pos = loop_center + loop_radius * cos(theta) * loop_forward + loop_radius * sin(theta) * loop_up
	
	# Forward tangent vector
	var tangent_fwd = -sin(theta) * loop_forward + cos(theta) * loop_up
	var new_forward = -tangent_fwd.normalized()
	
	# Upward vector pointing outward
	var new_up = (-cos(theta) * loop_forward - sin(theta) * loop_up).normalized()
	var new_left = new_up.cross(new_forward).normalized()
	
	global_position = target_pos
	global_transform.basis = Basis(new_left, new_up, new_forward).orthonormalized()
	
	# Update velocities for physical accuracy during the trick
	linear_velocity = tangent_fwd.normalized() * (2.0 * PI * loop_radius / LOOP_DURATION)
	angular_velocity = new_left * (2.0 * PI / LOOP_DURATION)
	
	# Simulate loop throttle sound
	smoothed_input.x = 0.95
	
	var prop_speed = 30.0 + (smoothed_input.x * 60.0)
	for prop in propellers:
		prop.rotate_y(delta * prop_speed)

func start_trick_barrel(from_manual = false):
	flight_state = FlightState.TRICK_BARREL
	post_trick_state = FlightState.MANUAL if from_manual else FlightState.AUTOPILOT
	trick_time = 0.0
	barrel_start_pos = global_position
	barrel_forward = -global_transform.basis.z
	barrel_left = global_transform.basis.x
	barrel_up = global_transform.basis.y
	barrel_start_basis = global_transform.basis
	print("Drone: Starting Barrel Roll trick!")

func process_trick_barrel(delta):
	trick_time += delta
	if trick_time >= BARREL_DURATION:
		flight_state = post_trick_state
		linear_velocity = barrel_forward * autopilot_speed
		angular_velocity = Vector3.ZERO
		print("Drone: Barrel Roll trick finished!")
		return
		
	var progress = trick_time / BARREL_DURATION
	var phi = progress * TAU
	
	# Helical position curve
	var displacement = barrel_forward * barrel_speed * trick_time + barrel_left * barrel_radius * sin(phi) + barrel_up * barrel_radius * (1.0 - cos(phi))
	global_position = barrel_start_pos + displacement
	
	# Roll around the barrel_forward vector
	var rolled_basis = barrel_start_basis.rotated(barrel_forward, phi)
	global_transform.basis = rolled_basis.orthonormalized()
	
	# Update velocities for physical accuracy during the trick
	linear_velocity = barrel_forward * barrel_speed + barrel_left * barrel_radius * (2.0 * PI / BARREL_DURATION) * cos(phi) + barrel_up * barrel_radius * (2.0 * PI / BARREL_DURATION) * sin(phi)
	angular_velocity = barrel_forward * (2.0 * PI / BARREL_DURATION)
	
	# Simulate roll throttle sound
	smoothed_input.x = 0.85
	
	var prop_speed = 30.0 + (smoothed_input.x * 60.0)
	for prop in propellers:
		prop.rotate_y(delta * prop_speed)

func toggle_boids_swarm():
	if boids_manager:
		print("Drone: Disabling Boids Swarm.")
		boids_manager.queue_free()
		boids_manager = null
	else:
		print("Drone: Enabling Boids Swarm!")
		var boid_mgr_script: Script = load("res://scripts/BoidManager.gd")
		if not boid_mgr_script:
			push_error("Drone: BoidManager.gd script not found.")
			return
		boids_manager = Node3D.new()
		boids_manager.set_script(boid_mgr_script)
		boids_manager.process_mode = Node.PROCESS_MODE_PAUSABLE
		get_parent().add_child(boids_manager)
		boids_manager.initialize(self)

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

func _process(_delta):
	if get_tree().paused: return
	
	if camera_toggle_cooldown > 0:
		camera_toggle_cooldown -= _delta
		
	if state_toggle_cooldown > 0:
		state_toggle_cooldown -= _delta
	
	if Input.is_key_pressed(KEY_C) and camera_toggle_cooldown <= 0:
		is_first_person = !is_first_person
		update_camera_views()
		camera_toggle_cooldown = 0.2
	
	if Input.is_key_pressed(KEY_R): get_tree().reload_current_scene()

	# Key H: Toggle hover mode to cancel gravity without changing movement controls
	if Input.is_key_pressed(KEY_H) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		hover_enabled = !hover_enabled
		apply_hover_mode()
		print("Drone: Hover mode ", "enabled" if hover_enabled else "disabled", ".")

	# Key 5: Toggle Autopilot (Track Flight)
	if Input.is_key_pressed(KEY_5) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		if flight_state == FlightState.AUTOPILOT:
			flight_state = FlightState.MANUAL
			print("Drone: Autopilot disabled. Returning to manual control.")
		else:
			flight_state = FlightState.AUTOPILOT
			# Find nearest waypoint to start from
			var nearest_idx: int = 0
			var nearest_dist: float = 999999.0
			for i in range(autopilot_waypoints.size()):
				var d = global_position.distance_to(autopilot_waypoints[i])
				if d < nearest_dist:
					nearest_dist = d
					nearest_idx = i
			current_waypoint_index = nearest_idx
			print("Drone: Autopilot enabled! Heading to waypoint: ", nearest_idx)
			
	# Key 6: Perform Loop-de-loop
	if Input.is_key_pressed(KEY_6) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		start_trick_loop(flight_state == FlightState.MANUAL)
		
	# Key 7: Perform Barrel Roll
	if Input.is_key_pressed(KEY_7) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		start_trick_barrel(flight_state == FlightState.MANUAL)
		
	# Key 8: Toggle Swarm (Boids Mode)
	if Input.is_key_pressed(KEY_8) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		toggle_boids_swarm()

func setup_drone_audio():
	# 1. Continuous Motor Sound
	motor_audio = AudioStreamPlayer3D.new()
	var generator = AudioStreamGenerator.new()
	generator.buffer_length = 0.1
	motor_audio.stream = generator
	motor_audio.unit_size = 5.0
	motor_audio.max_distance = 100.0
	add_child(motor_audio)
	motor_audio.play()
	motor_playback = motor_audio.get_stream_playback()
	
	# 2. Crash Sound Generator
	crash_audio = AudioStreamPlayer3D.new()
	var crash_gen = AudioStreamGenerator.new()
	crash_gen.buffer_length = 0.05
	crash_audio.stream = crash_gen
	add_child(crash_audio)
	crash_audio.play()
	crash_playback = crash_audio.get_stream_playback()

func _on_drone_collision(_body):
	# Calculate impact intensity based on velocity
	var impact = linear_velocity.length()
	if impact > 1.5: # Lower threshold to catch more bumps
		play_crash_sound(impact)

func play_crash_sound(intensity: float):
	if crash_playback == null: return
	
	# Push a short, sharp burst of noise for the 'thud'
	var vol = clamp(intensity / 10.0, 0.2, 0.5) 
	var frames_to_push = 2205 # ~50ms of sound
	
	for i in range(frames_to_push):
		var sample = (randf() * 2.0 - 1.0) * vol
		# Rapid decay for the thud effect
		sample *= (1.0 - float(i) / frames_to_push)
		crash_playback.push_frame(Vector2(sample, sample))
	
	if not crash_audio.playing:
		crash_audio.play()

func fill_motor_buffer():
	if motor_playback == null: return
	
	var n = motor_playback.get_frames_available()
	# Gentle hum range
	var throttle = clamp(smoothed_input.x, 0.0, 1.0)
	var freq = 60.0 + (throttle * 120.0) 
	var volume = 0.005 + (throttle * 0.015) # Near-silent base volume
	
	while n > 0:
		# Very soft layered sines
		var sample = sin(motor_phase * TAU)
		sample += sin(motor_phase * 2.0 * TAU) * 0.3
		sample *= volume
		
		# Prevent clipping and filter out peaks
		if not is_inf(sample) and not is_nan(sample):
			motor_playback.push_frame(Vector2(sample, sample))
		
		motor_phase = fmod(motor_phase + freq / audio_hz, 1.0)
		n -= 1
