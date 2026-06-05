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
	print("SingleDroneController: Cleaned up player drone and cameras.")

func update_camera_views():
	if not drone or not is_instance_valid(drone): return
	tp_camera.current = !is_first_person
	fp_camera.current = is_first_person

func _process(delta):
	if not drone or not is_instance_valid(drone):
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
		print("SingleDroneController: Hover mode ", "enabled" if drone.hover_enabled else "disabled")

	if Input.is_key_pressed(KEY_5) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		toggle_autopilot()

	if Input.is_key_pressed(KEY_6) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		start_trick_loop(flight_state == FlightState.MANUAL)

	if Input.is_key_pressed(KEY_7) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		start_trick_barrel(flight_state == FlightState.MANUAL)

	spring_arm.global_position = drone.global_position + Vector3(0, 0.5, 0)
	spring_arm.global_transform.basis = drone.global_transform.basis
	spring_arm.rotate_object_local(Vector3.RIGHT, deg_to_rad(-20))

	var fp_pos = drone.global_transform * Vector3(0, 0.15, -0.35)
	fp_camera.global_position = fp_pos
	fp_camera.global_transform.basis = drone.global_transform.basis.rotated(drone.global_transform.basis.x, deg_to_rad(15))

func _physics_process(delta):
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

# Include the rest of your functions for autopilot and tricks here...

func toggle_autopilot():
	# Implement toggle autopilot as before
	pass

func start_trick_loop(from_manual = true):
	# Implement start_trick_loop as before
	pass

func start_trick_barrel(from_manual = true):
	# Implement start_trick_barrel as before
	pass
