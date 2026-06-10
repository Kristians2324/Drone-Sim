extends Node3D

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
var drone: RigidBody3D = null
var drone_input = null

var swarm_controller = null
var swarm_mode: bool = false

var is_first_person: bool = true
var camera_toggle_cooldown: float = 0.0
var state_toggle_cooldown: float = 0.0

var spring_arm: SpringArm3D
var tp_camera: Camera3D
var fp_camera: Camera3D

enum FlightState { MANUAL, AUTOPILOT, TRICK_LOOP, TRICK_BARREL }
var flight_state = FlightState.MANUAL

var autopilot_waypoints: Array[Vector3] = [
	Vector3(0, 15, 0),
	Vector3(120, 25, -120),
	Vector3(250, 45, -50),
	Vector3(150, 30, 150),
	Vector3(-100, 25, 200),
	Vector3(-250, 35, 50),
	Vector3(-150, 20, -150)
]
var current_waypoint_index = 0
var autopilot_speed = 22.0
var waypoint_reach_distance = 12.0

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

func _ready():
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 4.0
	add_child(spring_arm)

	tp_camera = Camera3D.new()
	spring_arm.add_child(tp_camera)

	fp_camera = Camera3D.new()
	add_child(fp_camera)
	drone_input = preload("res://scripts/drone/DroneInput.gd").new()
	drone_input.initialize(3.5)

	spawn_drone()

func spawn_drone():
	if drone and is_instance_valid(drone):
		return

	drone = drone_scene.instantiate()
	get_parent().call_deferred("add_child", drone)
	drone.call_deferred("set", "global_position", Vector3(0, 5, 0))

	update_camera_views()
	print("DroneControllerManager: Spawned player drone.")

func cleanup():
	if tp_camera: tp_camera.current = false
	if fp_camera: fp_camera.current = false
	if drone and is_instance_valid(drone):
		drone.queue_free()
		drone = null
	if swarm_controller and is_instance_valid(swarm_controller):
		if swarm_controller.has_method("cleanup"):
			swarm_controller.cleanup()
		swarm_controller.queue_free()
		swarm_controller = null
	print("DroneControllerManager: Cleaned up player drone and cameras.")

func update_camera_views():
	if not drone or not is_instance_valid(drone): return
	tp_camera.current = !is_first_person
	fp_camera.current = is_first_person

func _process(delta):
	if camera_toggle_cooldown > 0: camera_toggle_cooldown -= delta
	if state_toggle_cooldown > 0: state_toggle_cooldown -= delta

	# Handle Tab key to toggle swarm mode (always accessible)
	if Input.is_key_pressed(KEY_TAB) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.5
		toggle_swarm_mode()
		return  # Skip other processing when toggling

	if swarm_mode:
		return
	
	if not drone or not is_instance_valid(drone):
		return

	if Input.is_key_pressed(KEY_C) and camera_toggle_cooldown <= 0:
		is_first_person = !is_first_person
		update_camera_views()
		camera_toggle_cooldown = 0.2

	if Input.is_key_pressed(KEY_H) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		drone.hover_enabled = !drone.hover_enabled
		drone.apply_hover_mode()
		print("DroneControllerManager: Hover mode ", "enabled" if drone.hover_enabled else "disabled")

	if Input.is_key_pressed(KEY_5) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		toggle_autopilot()

	if Input.is_key_pressed(KEY_6) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		start_trick_loop(flight_state == FlightState.MANUAL)

	if Input.is_key_pressed(KEY_7) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		start_trick_barrel(flight_state == FlightState.MANUAL)

	if spring_arm and is_instance_valid(spring_arm) and spring_arm.is_inside_tree():
		if drone and is_instance_valid(drone) and drone.is_inside_tree():
			spring_arm.global_position = drone.global_position + Vector3(0, 0.5, 0)
			spring_arm.global_transform.basis = drone.global_transform.basis
			spring_arm.rotate_object_local(Vector3.RIGHT, deg_to_rad(-20))

	if fp_camera and is_instance_valid(fp_camera) and fp_camera.is_inside_tree():
		if drone and is_instance_valid(drone) and drone.is_inside_tree():
			var fp_pos = drone.global_transform * Vector3(0, 0.15, -0.35)
			fp_camera.global_position = fp_pos
			fp_camera.global_transform.basis = drone.global_transform.basis.rotated(drone.global_transform.basis.x, deg_to_rad(15))

func _physics_process(delta):
	if swarm_mode:
		return
	
	if not drone or not is_instance_valid(drone):
		return

	match flight_state:
		FlightState.MANUAL:
			var input_vec = drone_input.get_smoothed_input(delta)
			drone.set_input_vector(input_vec)
		FlightState.AUTOPILOT:
			process_autopilot_flight(delta)
		FlightState.TRICK_LOOP:
			process_trick_loop(delta)
		FlightState.TRICK_BARREL:
			process_trick_barrel(delta)

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = drone.get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from = Vector3(pos.x, 300.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [drone.get_rid()]
	var result = space_state.intersect_ray(query)
	if result.has("position"):
		return result.position.y
	return 0.0

func process_autopilot_flight(delta):
	var target_pos = autopilot_waypoints[current_waypoint_index]
	var base_terrain_height = get_terrain_height_at(target_pos)
	var waypoint_min_clearance = 15.0
	if target_pos.y < base_terrain_height + waypoint_min_clearance:
		target_pos.y = base_terrain_height + waypoint_min_clearance
		
	var dist_to_target = drone.global_position.distance_to(target_pos)
	
	if dist_to_target < waypoint_reach_distance:
		if current_waypoint_index == 2:
			start_trick_loop(false)
			current_waypoint_index = (current_waypoint_index + 1) % autopilot_waypoints.size()
			return
		elif current_waypoint_index == 4:
			start_trick_barrel(false)
			current_waypoint_index = (current_waypoint_index + 1) % autopilot_waypoints.size()
			return
		else:
			current_waypoint_index = (current_waypoint_index + 1) % autopilot_waypoints.size()
			target_pos = autopilot_waypoints[current_waypoint_index]
			var new_base_terrain = get_terrain_height_at(target_pos)
			if target_pos.y < new_base_terrain + waypoint_min_clearance:
				target_pos.y = new_base_terrain + waypoint_min_clearance
			
	var desired_dir = (target_pos - drone.global_position).normalized()
	
	var look_ahead_dist = 15.0
	var forward_dir = drone.linear_velocity.normalized()
	if forward_dir.is_zero_approx():
		forward_dir = -drone.global_transform.basis.z
		
	var check_pos = drone.global_position + forward_dir * look_ahead_dist
	var terrain_height_ahead = get_terrain_height_at(check_pos)
	var terrain_height_below = get_terrain_height_at(drone.global_position)
	
	var flight_min_clearance = 12.0
	var safe_y = max(terrain_height_below + flight_min_clearance, terrain_height_ahead + flight_min_clearance)
	
	var adjusted_target_pos = target_pos
	if adjusted_target_pos.y < safe_y:
		adjusted_target_pos.y = safe_y
		
	if drone.global_position.y < safe_y:
		adjusted_target_pos.y = max(adjusted_target_pos.y, safe_y + 8.0)
		
	desired_dir = (adjusted_target_pos - drone.global_position).normalized()
	var target_velocity = desired_dir * autopilot_speed
	drone.linear_velocity = drone.linear_velocity.lerp(target_velocity, delta * 3.0)
	
	var fwd = -drone.linear_velocity.normalized()
	if fwd.is_zero_approx():
		fwd = -drone.global_transform.basis.z
		
	var left = Vector3.UP.cross(fwd).normalized()
	if left.is_zero_approx():
		left = drone.global_transform.basis.x
		
	var up = fwd.cross(left).normalized()
	
	var current_fwd = -drone.global_transform.basis.z
	var yaw_cross = current_fwd.cross(desired_dir)
	var turn_amount = yaw_cross.dot(Vector3.UP)
	
	var target_roll = -turn_amount * 0.8
	target_roll = clamp(target_roll, -0.6, 0.6)
	var target_pitch = -0.15
	
	var target_basis = Basis(left, up, fwd)
	target_basis = target_basis.rotated(target_basis.z, target_roll)
	target_basis = target_basis.rotated(target_basis.x, target_pitch)
	
	drone.global_transform.basis = drone.global_transform.basis.slerp(target_basis.orthonormalized(), delta * 4.0)

# Include the rest of your functions for autopilot and tricks here...

func toggle_autopilot():
	if flight_state == FlightState.AUTOPILOT:
		flight_state = FlightState.MANUAL
		drone.set_input_vector(Vector4.ZERO)
		print("DroneControllerManager: Autopilot disabled. Returning to manual control.")
	else:
		flight_state = FlightState.AUTOPILOT
		var nearest_idx: int = 0
		var nearest_dist: float = 999999.0
		for i in range(autopilot_waypoints.size()):
			var d = drone.global_position.distance_to(autopilot_waypoints[i])
			if d < nearest_dist:
				nearest_dist = d
				nearest_idx = i
		current_waypoint_index = nearest_idx
		print("DroneControllerManager: Autopilot enabled! Heading to waypoint: ", nearest_idx)

func start_trick_loop(from_manual = true):
	flight_state = FlightState.TRICK_LOOP
	post_trick_state = FlightState.MANUAL if from_manual else FlightState.AUTOPILOT
	trick_time = 0.0
	loop_start_pos = drone.global_position
	loop_forward = -drone.global_transform.basis.z
	loop_up = drone.global_transform.basis.y
	loop_center = loop_start_pos + loop_up * loop_radius
	print("DroneControllerManager: Starting Loop-de-loop trick!")

func process_trick_loop(delta):
	trick_time += delta
	if trick_time >= LOOP_DURATION:
		flight_state = post_trick_state
		if flight_state == FlightState.MANUAL:
			drone.set_input_vector(Vector4.ZERO)
		drone.linear_velocity = loop_forward * autopilot_speed
		drone.angular_velocity = Vector3.ZERO
		print("DroneControllerManager: Loop-de-loop trick finished!")
		return
		
	var progress = trick_time / LOOP_DURATION
	var theta = -PI/2.0 + progress * TAU
	
	var target_pos = loop_center + loop_radius * cos(theta) * loop_forward + loop_radius * sin(theta) * loop_up
	var tangent_fwd = -sin(theta) * loop_forward + cos(theta) * loop_up
	var new_forward = -tangent_fwd.normalized()
	var new_up = (-cos(theta) * loop_forward - sin(theta) * loop_up).normalized()
	var new_left = new_up.cross(new_forward).normalized()
	
	drone.global_position = target_pos
	drone.global_transform.basis = Basis(new_left, new_up, new_forward).orthonormalized()
	
	drone.linear_velocity = tangent_fwd.normalized() * (2.0 * PI * loop_radius / LOOP_DURATION)
	drone.angular_velocity = new_left * (2.0 * PI / LOOP_DURATION)
	
	drone.set_input_vector(Vector4(0.95, 0, 0, 0))

func start_trick_barrel(from_manual = true):
	flight_state = FlightState.TRICK_BARREL
	post_trick_state = FlightState.MANUAL if from_manual else FlightState.AUTOPILOT
	trick_time = 0.0
	barrel_start_pos = drone.global_position
	barrel_forward = -drone.global_transform.basis.z
	barrel_left = drone.global_transform.basis.x
	barrel_up = drone.global_transform.basis.y
	barrel_start_basis = drone.global_transform.basis
	print("DroneControllerManager: Starting Barrel Roll trick!")

func process_trick_barrel(delta):
	trick_time += delta
	if trick_time >= BARREL_DURATION:
		flight_state = post_trick_state
		if flight_state == FlightState.MANUAL:
			drone.set_input_vector(Vector4.ZERO)
		drone.linear_velocity = barrel_forward * autopilot_speed
		drone.angular_velocity = Vector3.ZERO
		print("DroneControllerManager: Barrel Roll trick finished!")
		return
		
	var progress = trick_time / BARREL_DURATION
	var phi = progress * TAU
	
	var displacement = barrel_forward * barrel_speed * trick_time + barrel_left * barrel_radius * sin(phi) + barrel_up * barrel_radius * (1.0 - cos(phi))
	drone.global_position = barrel_start_pos + displacement
	
	var rolled_basis = barrel_start_basis.rotated(barrel_forward, phi)
	drone.global_transform.basis = rolled_basis.orthonormalized()
	
	drone.linear_velocity = barrel_forward * barrel_speed + barrel_left * barrel_radius * (2.0 * PI / BARREL_DURATION) * cos(phi) + barrel_up * barrel_radius * (2.0 * PI / BARREL_DURATION) * sin(phi)
	drone.angular_velocity = barrel_forward * (2.0 * PI / BARREL_DURATION)

func toggle_swarm_mode():
	if swarm_mode:
		disable_swarm_mode()
	else:
		enable_swarm_mode()

func enable_swarm_mode():
	print("DroneControllerManager: Enabling Swarm Mode...")
	swarm_mode = true
	
	# Disable single drone controller
	if drone and is_instance_valid(drone):
		drone.queue_free()
		drone = null
	
	# Create swarm controller
	if not swarm_controller or not is_instance_valid(swarm_controller):
		swarm_controller = Node3D.new()
		swarm_controller.name = "SwarmController"
		swarm_controller.set_script(preload("res://scripts/SwarmController.gd"))
		get_parent().add_child(swarm_controller)
	
	# Initialize swarm with 10 drones
	if swarm_controller and swarm_controller.has_method("initialize_swarm"):
		swarm_controller.initialize_swarm(10, Vector3(0, 5, 0))
	
	print("DroneControllerManager: Swarm mode enabled!")

func disable_swarm_mode():
	print("DroneControllerManager: Disabling Swarm Mode...")
	swarm_mode = false
	
	# Cleanup swarm
	if swarm_controller and is_instance_valid(swarm_controller):
		if swarm_controller.has_method("cleanup"):
			swarm_controller.cleanup()
		swarm_controller.queue_free()
		swarm_controller = null
	
	# Re-enable single drone
	spawn_drone()
	print("DroneControllerManager: Swarm mode disabled!")
