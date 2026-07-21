extends Node3D

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
@export var use_mavlink_bridge: bool = false
@export var mavlink_listen_port: int = 14550
@export var mavlink_remote_host: String = "127.0.0.1"
@export var mavlink_remote_port: int = 14551
var drone: RigidBody3D = null
var drone_input = null
var mavlink_bridge: MavlinkBridge = null

var swarm_controller = null
var swarm_mode: bool = false

var is_first_person: bool = true
var camera_toggle_cooldown: float = 0.0
var state_toggle_cooldown: float = 0.0

var spring_arm: SpringArm3D
var tp_camera: Camera3D
var fp_camera: Camera3D
var show_camera_rig: Node3D
var show_camera: Camera3D
var show_camera_active: bool = false
var show_camera_mode: int = 0
var show_camera_timer: float = 0.0
var show_camera_switch_interval: float = 4.0
var show_camera_presets: Array[Vector3] = [
	Vector3(0, 24, 48),
	Vector3(48, 20, 0),
	Vector3(0, 60, 0),
	Vector3(-42, 18, -30),
]
var launch_pad: StaticBody3D = null
var launch_pad_mesh: MeshInstance3D = null
var launch_pad_marker: MeshInstance3D = null
var recharge_structure: Node3D = null
var low_battery_return_active: bool = false
var low_battery_landing_active: bool = false

enum FlightState { MANUAL, AUTOPILOT, TRICK_LOOP, TRICK_BARREL }
var flight_state = FlightState.MANUAL

enum ShowMode { NONE, STAR_FORMATION, CIRCLE, HEART, DIAMOND, WAVE }
var show_mode = ShowMode.NONE
var show_controller: Node3D = null
var show_mode_sequence: Array[int] = [ShowMode.STAR_FORMATION, ShowMode.CIRCLE, ShowMode.HEART, ShowMode.DIAMOND, ShowMode.WAVE]
var show_mode_sequence_index: int = 0
var show_transition_active: bool = false
var show_transition_progress: float = 0.0
var show_transition_duration: float = 2.5
var show_mode_names := {
	"star": ShowMode.STAR_FORMATION,
	"circle": ShowMode.CIRCLE,
	"heart": ShowMode.HEART,
	"diamond": ShowMode.DIAMOND,
	"wave": ShowMode.WAVE,
}

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

var show_target_positions: Array[Vector3] = []
var show_altitude: float = 40.0
var show_center: Vector3 = Vector3.ZERO
var show_form_up_speed: float = 14.0
var show_form_hold_speed: float = 6.0
var show_form_spread: float = 18.0
var show_formation_radius: float = 20.0

var post_trick_state = FlightState.MANUAL



func _ready():
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 4.0
	add_child(spring_arm)

	tp_camera = Camera3D.new()
	spring_arm.add_child(tp_camera)

	fp_camera = Camera3D.new()
	add_child(fp_camera)

	show_camera_rig = Node3D.new()
	show_camera_rig.name = "ShowCameraRig"
	add_child(show_camera_rig)

	show_camera = Camera3D.new()
	show_camera.current = false
	show_camera_rig.add_child(show_camera)
	show_camera.position = Vector3(0, 18, 32)
	show_camera.look_at(Vector3.ZERO, Vector3.UP)

	create_launch_pad()
	show_pad_always_visible(true)

	drone_input = preload("res://scripts/drone/DroneInput.gd").new()
	drone_input.initialize(3.5)
	drone_input.input_sampled.connect(_on_drone_input_sampled)
	_setup_mavlink_bridge()

	spawn_drone()
	if mavlink_bridge and is_instance_valid(mavlink_bridge):
		mavlink_bridge.control_received.connect(_on_mavlink_control_received)

func spawn_drone():
	if drone and is_instance_valid(drone):
		return

	# Wait for physics so we can get ground height
	await get_tree().physics_frame
	
	# Position the launch pad at 350, 350 snapped to terrain height
	if launch_pad and is_instance_valid(launch_pad):
		var y_height = get_terrain_height_at(Vector3(350.0, 0.0, 350.0))
		launch_pad.global_position = Vector3(350.0, y_height, 350.0)
		launch_pad.visible = true

	drone = drone_scene.instantiate()
	get_parent().add_child(drone)
	
	if launch_pad and is_instance_valid(launch_pad):
		# Start on top of the tower (18m height + half height stand)
		drone.global_position = launch_pad.global_position + Vector3(0.0, 18.5, 0.0)
	else:
		drone.global_position = Vector3(0.0, 5.0, 0.0)
		
	recharge_structure = launch_pad
	update_camera_views()
	print("DroneControllerManager: Spawned player drone at RechargeTower starting pad.")

func _setup_mavlink_bridge() -> void:
	if not use_mavlink_bridge:
		return
	mavlink_bridge = MavlinkBridge.new()
	mavlink_bridge.enabled = true
	mavlink_bridge.listen_port = mavlink_listen_port
	mavlink_bridge.set_endpoint(mavlink_remote_host, mavlink_remote_port)
	add_child(mavlink_bridge)
	mavlink_bridge.connection_changed.connect(_on_mavlink_connection_changed)
	mavlink_bridge.heartbeat_received.connect(_on_mavlink_heartbeat_received)

func _on_drone_input_sampled(input_vec: Vector4) -> void:
	if mavlink_bridge and is_instance_valid(mavlink_bridge):
		mavlink_bridge.send_control_input(input_vec)

func cleanup():
	if tp_camera: tp_camera.current = false
	if fp_camera: fp_camera.current = false
	if show_camera: show_camera.current = false
	if launch_pad and is_instance_valid(launch_pad):
		launch_pad.queue_free()
		launch_pad = null
		launch_pad_mesh = null
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
	show_camera_active = show_mode != ShowMode.NONE
	if show_camera_active:
		tp_camera.current = false
		fp_camera.current = false
		show_camera.current = true
	elif is_first_person:
		tp_camera.current = false
		fp_camera.current = true
		show_camera.current = false
	else:
		tp_camera.current = true
		fp_camera.current = false
		show_camera.current = false

func _process(delta):
	if camera_toggle_cooldown > 0: camera_toggle_cooldown -= delta
	if state_toggle_cooldown > 0: state_toggle_cooldown -= delta

	# Handle Tab key to toggle swarm mode (always accessible)
	if Input.is_key_pressed(KEY_TAB) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.5
		toggle_swarm_mode()
		return  # Skip other processing when toggling

	if not drone or not is_instance_valid(drone):
		return

	_update_low_battery_behavior(delta)

	if Input.is_key_pressed(KEY_C) and camera_toggle_cooldown <= 0:
		is_first_person = !is_first_person
		update_camera_views()
		camera_toggle_cooldown = 0.2

	if Input.is_key_pressed(KEY_H) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		drone.hover_enabled = !drone.hover_enabled
		drone.apply_hover_mode()
		print("DroneControllerManager: Hover mode ", "enabled" if drone.hover_enabled else "disabled")

	# Formation selection is now driven by the pause/menu UI.

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
			var follow_pos = drone.global_position
			if swarm_mode and swarm_controller and is_instance_valid(swarm_controller) and swarm_controller.has_method("get_swarm_centroid"):
				follow_pos = swarm_controller.get_swarm_centroid()
			elif show_mode == ShowMode.STAR_FORMATION:
				follow_pos = show_center
			spring_arm.global_position = follow_pos + Vector3(0, 0.5, 0)
			spring_arm.global_transform.basis = drone.global_transform.basis
			spring_arm.rotate_object_local(Vector3.RIGHT, deg_to_rad(-20))

	if show_camera and is_instance_valid(show_camera) and show_camera.current:
		show_camera_timer += delta
		if show_camera_timer >= show_camera_switch_interval:
			show_camera_timer = 0.0
			show_camera_mode = (show_camera_mode + 1) % show_camera_presets.size()
		update_show_camera()

	if fp_camera and is_instance_valid(fp_camera) and fp_camera.is_inside_tree():
		if drone and is_instance_valid(drone) and drone.is_inside_tree():
			var fp_pos = drone.global_transform * Vector3(0, 0.15, -0.35)
			fp_camera.global_position = fp_pos
			fp_camera.global_transform.basis = drone.global_transform.basis.rotated(drone.global_transform.basis.x, deg_to_rad(15))

func _physics_process(delta):
	if not drone or not is_instance_valid(drone):
		return

	match flight_state:
		FlightState.MANUAL:
			if show_mode == ShowMode.STAR_FORMATION:
				process_show_mode(delta)
			else:
				var input_vec = _get_control_input(delta)
				drone.set_input_vector(input_vec)
		FlightState.AUTOPILOT:
			process_autopilot_flight(delta)
		FlightState.TRICK_LOOP:
			process_trick_loop(delta)
		FlightState.TRICK_BARREL:
			process_trick_barrel(delta)

func get_drone() -> RigidBody3D:
	return drone

func _get_control_input(delta: float) -> Vector4:
	if mavlink_bridge and use_mavlink_bridge:
		return drone_input.smoothed_input if drone_input else Vector4.ZERO
	return drone_input.get_smoothed_input(delta) if drone_input else Vector4.ZERO

func _on_mavlink_control_received(control: Vector4) -> void:
	if not drone_input:
		return
	drone_input.smoothed_input = control

func _on_mavlink_connection_changed(connected: bool) -> void:
	print("DroneControllerManager: MAVLink bridge ", "connected" if connected else "disconnected")

func _on_mavlink_heartbeat_received(sys_id: int, comp_id: int) -> void:
	print("DroneControllerManager: MAVLink heartbeat received from sys ", sys_id, " comp ", comp_id)

func _update_low_battery_behavior(delta: float) -> void:
	if not drone or not is_instance_valid(drone):
		return

	# Manual landing recharge detection:
	var recharge_node := _get_recharge_target()
	if recharge_node and is_instance_valid(recharge_node):
		var horiz_dist = Vector2(drone.global_position.x, drone.global_position.z).distance_to(Vector2(recharge_node.global_position.x, recharge_node.global_position.z))
		var vert_dist = absf(drone.global_position.y - (recharge_node.global_position.y + 18.0))
		if horiz_dist <= 6.5 and vert_dist <= 2.2:
			if drone.linear_velocity.length() < 0.6:
				if drone.has_method("start_battery_recharge") and not drone.get("battery_recharging"):
					drone.start_battery_recharge()
					print("DroneControllerManager: Drone manually landed on RechargeTower - Recharging started!")
					return

	if drone.has_method("is_battery_empty") and drone.is_battery_empty():
		return

	if not drone.has_method("is_battery_auto_landing") or not drone.is_battery_auto_landing():
		low_battery_return_active = false
		low_battery_landing_active = false
		return

	var target := _get_recharge_target()
	if target == null:
		return

	# If the drone is already sitting on the pad, trigger recharge immediately.
	if drone.global_position.distance_to(target.global_position) <= 3.5:
		if drone.has_method("apply_hover_mode"):
			drone.hover_enabled = true
			drone.apply_hover_mode()
		if drone.has_method("start_battery_recharge"):
			drone.start_battery_recharge()
		low_battery_return_active = false
		low_battery_landing_active = false
		return

	low_battery_return_active = true
	var target_pos := target.global_position + Vector3.UP * 2.0
	var to_target := target_pos - drone.global_position
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.01 else Vector3.ZERO

	if not drone.has_method("set_input_vector"):
		return

	# Steer gently toward the recharge structure.
	var input := Vector4.ZERO
	var local_dir := drone.global_transform.basis.inverse() * direction
	input.x = clamp((target_pos.y - drone.global_position.y) * 0.12, -0.55, 0.65)
	input.z = clamp(-local_dir.z * 0.6, -0.75, 0.75)
	input.w = clamp(local_dir.x * 0.6, -0.75, 0.75)

	# If we're close, level out and land.
	if distance < 10.0:
		low_battery_landing_active = true
		input.x = -0.15 if drone.global_position.y > target.global_position.y + 0.6 else 0.0
		input.z = 0.0
		input.w = 0.0

	drone.set_input_vector(input)

	if low_battery_landing_active and distance < 4.0:
		if drone.has_method("apply_hover_mode"):
			drone.hover_enabled = true
			drone.apply_hover_mode()
		if drone.has_method("start_battery_recharge"):
			drone.start_battery_recharge()
			low_battery_return_active = false
			low_battery_landing_active = false

func _get_recharge_target() -> Node3D:
	if recharge_structure and is_instance_valid(recharge_structure):
		return recharge_structure
	if launch_pad and is_instance_valid(launch_pad):
		return launch_pad
	return null

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from = Vector3(pos.x, 500.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2 # ONLY collide with Terrain layer 2
	if drone and is_instance_valid(drone):
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
	var terrain_height_below: float = get_terrain_height_at(drone.global_position)
	
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
	
	if not drone or not is_instance_valid(drone):
		spawn_drone()
	
	if drone:
		if drone.has_method("set_swarm_mode_active"):
			drone.set_swarm_mode_active(true)
		if drone.has_method("set_show_lighting_enabled"):
			drone.set_show_lighting_enabled(false)
		drone.collision_layer = 2
		drone.collision_mask = 1
	
	# Create swarm controller
	if not swarm_controller or not is_instance_valid(swarm_controller):
		swarm_controller = Node3D.new()
		swarm_controller.name = "SwarmController"
		swarm_controller.set_script(preload("res://scripts/SwarmController.gd"))
		get_parent().add_child(swarm_controller)
	
	# Initialize swarm with follower drones, passing player drone as the leader target
	if swarm_controller and swarm_controller.has_method("initialize_swarm"):
		swarm_controller.initialize_swarm(drone, 39, drone.global_position)
	
	update_camera_views()
	print("DroneControllerManager: Swarm mode enabled!")

func disable_swarm_mode():
	print("DroneControllerManager: Disabling Swarm Mode...")
	swarm_mode = false
	
	if drone and is_instance_valid(drone):
		if drone.has_method("set_swarm_mode_active"):
			drone.set_swarm_mode_active(false)
		if drone.has_method("set_show_lighting_enabled"):
			drone.set_show_lighting_enabled(true)
		drone.collision_layer = 1
		drone.collision_mask = 1
	
	# Cleanup swarm controller
	if swarm_controller and is_instance_valid(swarm_controller):
		if swarm_controller.has_method("cleanup"):
			swarm_controller.cleanup()
		swarm_controller.queue_free()
		swarm_controller = null
	
	if not drone or not is_instance_valid(drone):
		spawn_drone()
		
	update_camera_views()
	print("DroneControllerManager: Swarm mode disabled!")

func toggle_show_mode():
	if show_mode == ShowMode.STAR_FORMATION:
		disable_show_mode()
	else:
		enable_show_mode()

func cycle_show_mode() -> void:
	if show_mode == ShowMode.NONE:
		enable_show_mode()
		return
	show_mode_sequence_index = (show_mode_sequence_index + 1) % show_mode_sequence.size()
	set_show_shape_by_mode(show_mode_sequence[show_mode_sequence_index])

func enable_show_mode():
	print("DroneControllerManager: Enabling Drone Show Mode...")
	show_mode = show_mode_sequence[show_mode_sequence_index]
	show_camera_mode = 0
	show_camera_timer = 0.0
	show_transition_active = true
	show_transition_progress = 0.0

	if swarm_mode:
		disable_swarm_mode()

	if not drone or not is_instance_valid(drone):
		spawn_drone()

	if drone and drone.has_method("set_swarm_mode_active"):
		drone.set_swarm_mode_active(true)
	if drone and drone.has_method("set_show_lighting_enabled"):
		drone.set_show_lighting_enabled(true)
	if drone:
		drone.collision_layer = 2
		drone.collision_mask = 1
		show_center = drone.global_position + Vector3(0, show_altitude, 0)
		if launch_pad:
			launch_pad.global_position = Vector3(show_center.x, 0.0, show_center.z)
			launch_pad.visible = true
			var active_town = get_tree().current_scene
			if active_town:
				for child in active_town.get_children():
					if child and child.name.to_lower().find("town") != -1:
						child.set("protected_center", launch_pad.global_position)
						child.set("protected_radius", 50.0)

	create_show_targets_for_mode(show_mode, 39)

	# Spawn the formation swarm once and then let it hold the cached star points.
	if not swarm_controller or not is_instance_valid(swarm_controller):
		swarm_controller = Node3D.new()
		swarm_controller.name = "ShowFormationSwarmController"
		swarm_controller.set_script(preload("res://scripts/SwarmController.gd"))
		get_parent().add_child(swarm_controller)

	if swarm_controller and swarm_controller.has_method("initialize_formation"):
		swarm_controller.initialize_formation(drone, show_target_positions, drone.global_position)

	if not show_controller or not is_instance_valid(show_controller):
		show_controller = Node3D.new()
		show_controller.name = "ShowFormationController"
		get_parent().add_child(show_controller)

	update_camera_views()
	print("DroneControllerManager: Drone show mode enabled!")

func disable_show_mode():
	print("DroneControllerManager: Disabling Drone Show Mode...")
	show_mode = ShowMode.NONE
	show_camera_active = false
	show_camera_mode = 0
	show_camera_timer = 0.0
	show_target_positions.clear()
	if drone and is_instance_valid(drone):
		if drone.has_method("set_swarm_mode_active"):
			drone.set_swarm_mode_active(false)
		drone.collision_layer = 1
		drone.collision_mask = 1
	if show_controller and is_instance_valid(show_controller):
		show_controller.queue_free()
		show_controller = null
	if launch_pad and is_instance_valid(launch_pad):
		launch_pad.visible = true
	if swarm_controller and is_instance_valid(swarm_controller):
		if swarm_controller.has_method("cleanup"):
			swarm_controller.cleanup()
		swarm_controller.queue_free()
		swarm_controller = null
	update_camera_views()
	print("DroneControllerManager: Drone show mode disabled!")

func show_pad_always_visible(enabled: bool) -> void:
	if launch_pad and is_instance_valid(launch_pad):
		launch_pad.visible = enabled
	if launch_pad_marker and is_instance_valid(launch_pad_marker):
		launch_pad_marker.visible = enabled

func advance_show_mode() -> void:
	show_mode_sequence_index = (show_mode_sequence_index + 1) % show_mode_sequence.size()
	if show_mode == ShowMode.NONE:
		enable_show_mode()
	else:
		cycle_show_mode()

func select_show_shape(shape_name: String) -> void:
	var key := shape_name.to_lower()
	if not show_mode_names.has(key):
		return
	show_mode_sequence_index = show_mode_sequence.find(show_mode_names[key])
	_force_reset_show_shape(show_mode_names[key])

func set_show_mode_by_index(idx: int) -> void:
	if idx < 0 or idx >= show_mode_sequence.size():
		return
	show_mode_sequence_index = idx
	_force_reset_show_shape(show_mode_sequence[idx])

func _force_reset_show_shape(new_mode: int) -> void:
	# Always fully reset the show so every button press starts from a clean state.
	if swarm_controller and is_instance_valid(swarm_controller):
		if swarm_controller.has_method("cleanup"):
			swarm_controller.cleanup()
		swarm_controller.queue_free()
		swarm_controller = null
	if show_controller and is_instance_valid(show_controller):
		show_controller.queue_free()
		show_controller = null
	show_mode = ShowMode.NONE
	show_transition_active = false
	show_transition_progress = 0.0
	show_camera_mode = 0
	show_camera_timer = 0.0
	show_target_positions.clear()
	if drone and is_instance_valid(drone):
		drone.set_input_vector(Vector4.ZERO)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
	enable_show_mode()
	set_show_shape_by_mode(new_mode)

func refresh_show_targets() -> void:
	create_show_targets_for_mode(show_mode, 39)
	if swarm_controller and is_instance_valid(swarm_controller):
		if swarm_controller.has_method("update_formation_targets"):
			swarm_controller.update_formation_targets(show_target_positions)
		else:
			if swarm_controller.has_method("initialize_formation"):
				swarm_controller.initialize_formation(drone, show_target_positions, drone.global_position)

func set_show_shape_by_mode(new_mode: int) -> void:
	show_mode = new_mode
	show_transition_active = true
	show_transition_progress = 0.0
	show_camera_mode = 0
	show_camera_timer = 0.0
	if drone and is_instance_valid(drone):
		show_center = drone.global_position + Vector3(0, show_altitude, 0)
	create_show_targets_for_mode(show_mode, 39)
	if swarm_controller and is_instance_valid(swarm_controller):
		if swarm_controller.has_method("initialize_formation"):
			swarm_controller.initialize_formation(drone, show_target_positions, drone.global_position)

func update_show_camera() -> void:
	if not show_camera or not is_instance_valid(show_camera):
		return
	var center: Vector3 = show_center
	if swarm_controller and is_instance_valid(swarm_controller) and swarm_controller.has_method("get_swarm_centroid"):
		center = swarm_controller.get_swarm_centroid()
	var cam_offset: Vector3 = show_camera_presets[show_camera_mode]
	show_camera.global_position = show_camera.global_position.lerp(center + cam_offset, 0.08)
	show_camera.look_at(center, Vector3.UP)

func create_show_targets_for_mode(mode: int, count: int) -> void:
	show_target_positions.clear()
	var points: int = max(count, 24)
	var outer_r: float = show_formation_radius
	match mode:
		ShowMode.STAR_FORMATION:
			var inner_r: float = show_formation_radius * 0.45
			for i in range(points):
				var a: float = TAU * float(i) / float(points)
				var use_outer: bool = (i % 2) == 0
				var radius: float = outer_r if use_outer else inner_r
				show_target_positions.append(show_center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
			show_target_positions.append(show_center)
			show_target_positions.append(show_center + Vector3(0, 0, outer_r * 0.25))
		ShowMode.CIRCLE:
			for i in range(points):
				var a2: float = TAU * float(i) / float(points)
				show_target_positions.append(show_center + Vector3(cos(a2) * outer_r, 0.0, sin(a2) * outer_r))
		ShowMode.HEART:
			for i in range(points):
				var t: float = TAU * float(i) / float(points)
				var x: float = 16.0 * pow(sin(t), 3)
				var z: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
				show_target_positions.append(show_center + Vector3(x, 0.0, z) * 1.3)
		ShowMode.DIAMOND:
			for i in range(points):
				var t3: float = float(i) / float(points)
				var scaled: float = t3 * 4.0
				var side: int = int(floor(scaled))
				var u: float = scaled - float(side)
				var p: Vector3 = Vector3.ZERO
				if side == 0:
					p = Vector3(lerp(0.0, outer_r, u), 0.0, lerp(0.0, outer_r, u))
				elif side == 1:
					p = Vector3(lerp(outer_r, 0.0, u), 0.0, lerp(outer_r, -outer_r, u))
				elif side == 2:
					p = Vector3(lerp(0.0, -outer_r, u), 0.0, lerp(-outer_r, outer_r, u))
				else:
					p = Vector3(lerp(-outer_r, 0.0, u), 0.0, lerp(outer_r, 0.0, u))
				show_target_positions.append(show_center + p)
		ShowMode.WAVE:
			for i in range(points):
				var s2: float = float(i) / float(points - 1)
				var x2: float = lerp(-outer_r, outer_r, s2)
				var y2: float = sin(s2 * TAU * 2.0) * 8.0
				var z2: float = cos(s2 * TAU * 3.0) * 6.0
				show_target_positions.append(show_center + Vector3(x2, y2, z2))

func process_show_mode(delta: float) -> void:
	if not drone or not is_instance_valid(drone):
		return
	if show_transition_active:
		show_transition_progress = min(show_transition_progress + delta, show_transition_duration)
		var t: float = show_transition_progress / show_transition_duration
		t = t * t * (3.0 - 2.0 * t)
		var target_hover: Vector3 = show_center
		var hover_height: float = lerp(drone.global_position.y, target_hover.y, t)
		var hover_target := Vector3(show_center.x, hover_height, show_center.z)
		var to_target: Vector3 = hover_target - drone.global_position
		var lift: float = clamp(to_target.y * 0.06, -0.25, 0.75)
		drone.set_input_vector(Vector4(0.48 + lift, 0.0, 0.0, 0.0))
		if show_transition_progress >= show_transition_duration:
			show_transition_active = false
			drone.linear_velocity = Vector3.ZERO
			drone.angular_velocity = Vector3.ZERO
			refresh_show_targets()
	else:
		# Keep the leader drone steady while the formation swarm handles the shape.
		var target_hover: Vector3 = show_center
		var to_target: Vector3 = target_hover - drone.global_position
		var lift: float = clamp(to_target.y * 0.08, -0.4, 0.8)
		drone.set_input_vector(Vector4(0.5 + lift, 0.0, 0.0, 0.0))
	

func create_launch_pad() -> void:
	if launch_pad and is_instance_valid(launch_pad):
		return
	launch_pad = StaticBody3D.new()
	launch_pad.name = "RechargeTower"
	launch_pad.collision_layer = 1
	launch_pad.collision_mask = 1
	launch_pad.position = Vector3(350.0, 0.0, 350.0)
	add_child(launch_pad)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var tower_shape: CylinderShape3D = CylinderShape3D.new()
	tower_shape.height = 18.0
	tower_shape.radius = 4.5
	collision_shape.shape = tower_shape
	collision_shape.position = Vector3(0.0, 9.0, 0.0)
	launch_pad.add_child(collision_shape)

	# Main Tower: Hexagonal futuristic obelisk
	var tower := MeshInstance3D.new()
	var tower_mesh := CylinderMesh.new()
	tower_mesh.top_radius = 4.8
	tower_mesh.bottom_radius = 5.6
	tower_mesh.height = 18.0
	tower_mesh.radial_segments = 6 # Sleek hexagonal structure
	tower.mesh = tower_mesh
	tower.position = Vector3(0.0, 9.0, 0.0)
	launch_pad.add_child(tower)

	# Futuristic materials
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.12, 0.12, 0.15, 1.0) # Carbon dark finish
	pad_mat.metallic = 0.85
	pad_mat.roughness = 0.2
	tower.material_override = pad_mat

	var neon_mat := StandardMaterial3D.new()
	neon_mat.albedo_color = Color(1.0, 0.45, 0.0, 1.0) # Golden/orange neon highlights
	neon_mat.emission_enabled = true
	neon_mat.emission = Color(1.0, 0.45, 0.0, 1.0)
	neon_mat.emission_energy_multiplier = 3.5
	neon_mat.roughness = 0.1

	# 6 Vertical neon columns running up the corners of the hexagon
	var corner_radius = 5.3
	for i in range(6):
		var angle = i * PI / 3.0
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.2, 18.0, 0.2)
		bar.mesh = bar_mesh
		bar.position = Vector3(cos(angle) * corner_radius, 9.0, sin(angle) * corner_radius)
		bar.material_override = neon_mat
		launch_pad.add_child(bar)

	# Charging stand
	var landing_stand := MeshInstance3D.new()
	var stand_mesh := CylinderMesh.new()
	stand_mesh.top_radius = 1.2
	stand_mesh.bottom_radius = 1.2
	stand_mesh.height = 2.5
	stand_mesh.radial_segments = 16
	landing_stand.mesh = stand_mesh
	landing_stand.position = Vector3(0.0, 1.25, 0.0)
	landing_stand.material_override = pad_mat
	launch_pad.add_child(landing_stand)

	# Glowing Torus charging ring sitting on the top surface
	var pad_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.outer_radius = 1.1
	ring_mesh.inner_radius = 0.95
	pad_ring.mesh = ring_mesh
	pad_ring.position = Vector3(0.0, 2.51, 0.0)
	pad_ring.material_override = neon_mat
	launch_pad.add_child(pad_ring)

	# Soft pulsing top OmniLight3D
	var top_light := OmniLight3D.new()
	top_light.light_color = Color(1.0, 0.45, 0.0)
	top_light.light_energy = 2.5
	top_light.omni_range = 15.0
	top_light.position = Vector3(0.0, 3.5, 0.0)
	launch_pad.add_child(top_light)

	launch_pad_mesh = tower
	launch_pad_marker = null
	launch_pad.visible = true
