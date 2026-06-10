extends Node3D

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
var drone: RigidBody3D = null
var drone_input: Node = null

var is_first_person: bool = true
var camera_toggle_cooldown: float = 0.0
var state_toggle_cooldown: float = 0.0

var spring_arm: SpringArm3D
var tp_camera: Camera3D
var fp_camera: Camera3D

# Swarm mode
var swarm_mode: bool = false
var swarm_controller: Node = null

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
	get_parent().add_child(drone)
	drone.global_position = Vector3(0, 5, 0)

	update_camera_views()
	print("SingleDroneController: Spawned player drone.")

func cleanup():
	if tp_camera: tp_camera.current = false
	if fp_camera: fp_camera.current = false
	if drone and is_instance_valid(drone):
		drone.queue_free()
		drone = null
	if swarm_controller and is_instance_valid(swarm_controller):
		swarm_controller.cleanup()
		swarm_controller.queue_free()
		swarm_controller = null
	print("DroneControllerManager: Cleaned up resources")

func update_camera_views():
	if not drone or not is_instance_valid(drone): return
	tp_camera.current = !is_first_person
	fp_camera.current = is_first_person

func _process(delta):
	if swarm_mode or not drone or not is_instance_valid(drone):
		return

	if camera_toggle_cooldown > 0: camera_toggle_cooldown -= delta
	if state_toggle_cooldown > 0: state_toggle_cooldown -= delta

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

	if Input.is_key_pressed(KEY_8) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		toggle_swarm_mode()

	spring_arm.global_position = drone.global_position + Vector3(0, 0.5, 0)
	spring_arm.global_transform.basis = drone.global_transform.basis
	spring_arm.rotate_object_local(Vector3.RIGHT, deg_to_rad(-20))

	var fp_pos = drone.global_transform * Vector3(0, 0.15, -0.35)
	fp_camera.global_position = fp_pos
	fp_camera.global_transform.basis = drone.global_transform.basis.rotated(drone.global_transform.basis.x, deg_to_rad(15))
	
	# Also allow swarm toggle even without drone
	if drone == null and Input.is_key_pressed(KEY_8) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		toggle_swarm_mode()

func _physics_process(delta):
	if swarm_mode:
		# Swarm mode is handled by SwarmController
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

func process_autopilot_flight(delta):
	# Navigate to waypoint
	var target = autopilot_waypoints[current_waypoint_index]
	var direction = (target - drone.global_position).normalized()
	var distance = drone.global_position.distance_to(target)
	
	# Check if reached waypoint
	if distance < waypoint_reach_distance:
		current_waypoint_index = (current_waypoint_index + 1) % autopilot_waypoints.size()
		print("DroneControllerManager: Reached waypoint, moving to next")
		return
	
	# Create input vector for autopilot
	var input_vec = Vector4(0.5, 0, 0, 0)  # Default throttle
	
	# Calculate desired direction and set input accordingly
	if direction.length() > 0:
		var forward = -drone.global_transform.basis.z
		var angle_to_target = forward.signed_angle_to(direction, drone.global_transform.basis.y)
		input_vec.y = clamp(angle_to_target * 0.5, -1.0, 1.0)
	
	drone.set_input_vector(input_vec)

func process_trick_loop(delta):
	trick_time += delta
	
	# Complete the loop after duration
	if trick_time >= LOOP_DURATION:
		flight_state = FlightState.MANUAL
		print("DroneControllerManager: Loop trick completed")
		return
	
	# Calculate position on circular path
	var progress = trick_time / LOOP_DURATION
	var angle = progress * TAU  # Full rotation
	
	# Position along loop
	var local_forward = cos(angle) * loop_radius
	var local_up = sin(angle) * loop_radius
	var target_pos = loop_center + loop_forward * local_forward + loop_up * local_up
	
	# Move drone to target position
	var direction = (target_pos - drone.global_position).normalized()
	drone.linear_velocity = direction * 20.0
	
	# Rotate drone along the loop
	var target_basis = Basis.looking_at(-direction, loop_up)
	drone.global_transform.basis = drone.global_transform.basis.slerp(target_basis, delta * 5.0)

func process_trick_barrel(delta):
	trick_time += delta
	
	# Complete barrel roll after duration
	if trick_time >= BARREL_DURATION:
		flight_state = FlightState.MANUAL
		print("DroneControllerManager: Barrel roll trick completed")
		return
	
	# Calculate position on barrel path
	var progress = trick_time / BARREL_DURATION
	var angle = progress * TAU  # Full rotation
	
	# Position along barrel roll path
	var forward_offset = progress * barrel_speed * BARREL_DURATION
	var lateral = cos(angle) * barrel_radius
	var vertical = sin(angle) * barrel_radius
	
	var target_pos = barrel_start_pos + barrel_forward * forward_offset + barrel_left * lateral + barrel_up * vertical
	
	# Move drone to target position
	var direction = (target_pos - drone.global_position).normalized()
	drone.linear_velocity = direction * barrel_speed
	
	# Rotate drone around forward axis (barrel roll)
	var rotation_basis = Basis.IDENTITY.rotated(barrel_forward, angle)
	drone.global_transform.basis = barrel_start_basis * rotation_basis

# Include the rest of your functions for autopilot and tricks here...

func toggle_autopilot():
	if flight_state == FlightState.MANUAL:
		flight_state = FlightState.AUTOPILOT
		print("DroneControllerManager: Autopilot engaged")
	else:
		flight_state = FlightState.MANUAL
		print("DroneControllerManager: Autopilot disengaged")

func start_trick_loop(from_manual = true):
	if from_manual and flight_state == FlightState.MANUAL:
		flight_state = FlightState.TRICK_LOOP
		trick_time = 0.0
		loop_start_pos = drone.global_position
		loop_forward = -drone.global_transform.basis.z
		loop_up = drone.global_transform.basis.y
		loop_center = loop_start_pos + loop_forward * 5.0
		print("DroneControllerManager: Loop trick started")

func start_trick_barrel(from_manual = true):
	if from_manual and flight_state == FlightState.MANUAL:
		flight_state = FlightState.TRICK_BARREL
		trick_time = 0.0
		barrel_start_pos = drone.global_position
		barrel_forward = -drone.global_transform.basis.z
		barrel_up = drone.global_transform.basis.y
		barrel_left = drone.global_transform.basis.x
		barrel_start_basis = drone.global_transform.basis
		print("DroneControllerManager: Barrel roll trick started")

func toggle_swarm_mode():
	swarm_mode = !swarm_mode
	
	if swarm_mode:
		# Enter swarm mode
		print("DroneControllerManager: Entering swarm mode")
		cleanup()
		
		# Find or create swarm controller
		swarm_controller = SwarmController.new()
		get_parent().add_child(swarm_controller)
		swarm_controller.initialize_swarm(10, Vector3(0, 5, 0))
		
	else:
		# Exit swarm mode
		print("DroneControllerManager: Exiting swarm mode")
		if swarm_controller and is_instance_valid(swarm_controller):
			swarm_controller.cleanup()
			swarm_controller.queue_free()
			swarm_controller = null
		
		# Respawn single drone
		spawn_drone()
