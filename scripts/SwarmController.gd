extends Node3D

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
@export var swarm_count: int = 39

var drones: Array[RigidBody3D] = []
var leader_drone: RigidBody3D = null
var active: bool = false

var target_position: Vector3 = Vector3.ZERO
var formation_targets: Array[Vector3] = []
var formation_active: bool = false
var formation_settling: bool = false
var formation_transition_time: float = 0.0
var formation_transition_duration: float = 2.5
var formation_hold_altitude: float = 40.0
var formation_arrival_radius: float = 2.0
var formation_ascent_speed: float = 10.0
var formation_settle_speed: float = 6.0
var formation_hold_tolerance: float = 0.75

# Boids parameters
var neighborhood_radius: float = 12.0
var separation_radius: float = 4.5
var cohesion_weight: float = 0.8
var separation_weight: float = 6.0
var alignment_weight: float = 0.4
var target_weight: float = 7.0 # High weight to keep them aligned to the leader
var ground_avoid_weight: float = 12.0
var upward_bias_weight: float = 2.0
var max_speed: float = 35.0 # Fast so they can catch up
var max_force: float = 30.0 # High force to avoid lag

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE

func initialize_swarm(leader: RigidBody3D, count: int = 39, spawn_pos: Vector3 = Vector3(0, 15, 0)):
	clear_swarm()
	leader_drone = leader
	swarm_count = count
	active = true
	formation_active = false
	formation_targets.clear()

	target_position = spawn_pos

	for i in range(swarm_count):
		var drone_inst = drone_scene.instantiate()
		get_parent().add_child(drone_inst)
		
		# Spawn followers in a sphere shell around the leader
		var angle1 = randf() * TAU
		var angle2 = randf() * PI
		var r = randf_range(4.0, 12.0)
		var offset = Vector3(
			r * sin(angle2) * cos(angle1),
			r * cos(angle2) + 2.0, # slight offset upwards
			r * sin(angle2) * sin(angle1)
		)
		drone_inst.global_position = spawn_pos + offset
		
		# Disable physics collisions with other drones (only collide with Environment on Layer 1)
		drone_inst.collision_layer = 4
		drone_inst.collision_mask = 1
		
		# Configure light rig for show colors
		if drone_inst.has_method("setup_show_lights") and drone_inst.get("show_rig") != null:
			drone_inst.show_rig.configure(i, swarm_count, false)
			
		drones.append(drone_inst)

	print("SwarmController: Swarm initialized with ", drones.size(), " follower drones.")

func initialize_formation(leader: RigidBody3D, targets: Array[Vector3], spawn_pos: Vector3 = Vector3(0, 15, 0)):
	clear_swarm()
	leader_drone = leader
	swarm_count = targets.size()
	active = true
	formation_active = true
	formation_settling = true
	formation_transition_time = 0.0
	formation_targets = targets.duplicate()
	target_position = spawn_pos
	formation_hold_altitude = spawn_pos.y + 40.0

	for i in range(swarm_count):
		var drone_inst: RigidBody3D = drone_scene.instantiate()
		get_parent().add_child(drone_inst)
		var target_spawn: Vector3 = targets[i]
		drone_inst.global_position = Vector3(
			target_spawn.x + randf_range(-1.0, 1.0),
			spawn_pos.y,
			target_spawn.z + randf_range(-1.0, 1.0)
		)
		drone_inst.linear_velocity = Vector3.ZERO
		drone_inst.angular_velocity = Vector3.ZERO
		if drone_inst.has_method("set_input_vector"):
			drone_inst.set_input_vector(Vector4.ZERO)
		drone_inst.collision_layer = 4
		drone_inst.collision_mask = 1
		if drone_inst.has_method("setup_show_lights") and drone_inst.get("show_rig") != null:
			drone_inst.show_rig.configure(i, swarm_count, false)
		drones.append(drone_inst)

	print("SwarmController: Formation initialized with ", drones.size(), " drones.")

func update_formation_targets(targets: Array[Vector3]) -> void:
	formation_targets = targets.duplicate()
	formation_active = true
	formation_settling = true
	formation_transition_time = 0.0
	formation_hold_altitude = leader_drone.global_position.y + 40.0 if leader_drone and is_instance_valid(leader_drone) else formation_hold_altitude
	var should_force_reseed: bool = formation_targets.size() != 0
	if formation_targets.size() > 0:
		# Spiral is especially sensitive to stale height/phase, so reseed any time targets are refreshed.
		var min_y := formation_targets[0].y
		var max_y := formation_targets[0].y
		for t in formation_targets:
			min_y = min(min_y, t.y)
			max_y = max(max_y, t.y)
		if abs(max_y - min_y) < 0.001:
			should_force_reseed = false

	# Reposition followers at their current target projection so each new shape starts fresh.
	# This avoids carrying over the old shape's layout into the next one.
	for i in range(min(drones.size(), formation_targets.size())):
		var d = drones[i]
		if d and is_instance_valid(d):
			var target_spawn := formation_targets[i]
			d.global_position = Vector3(target_spawn.x, target_position.y, target_spawn.z) if should_force_reseed else d.global_position
			d.linear_velocity = Vector3.ZERO
			d.angular_velocity = Vector3.ZERO
			if d.has_method("set_input_vector"):
				d.set_input_vector(Vector4.ZERO)
	# Clear any leftover motion so every new shape starts from a clean slate.
	for d in drones:
		if d and is_instance_valid(d):
			d.linear_velocity = Vector3.ZERO
			d.angular_velocity = Vector3.ZERO
			if d.has_method("set_input_vector"):
				d.set_input_vector(Vector4.ZERO)
	# If the shape size changed, the existing swarm count no longer matches.
	# Rebuild the formation so the new pattern isn't influenced by stale drone placement.
	if drones.size() != formation_targets.size():
		if leader_drone and is_instance_valid(leader_drone):
			initialize_formation(leader_drone, formation_targets, target_position)
		return

func set_formation_active(enabled: bool) -> void:
	formation_active = enabled

func clear_swarm():
	for d in drones:
		if d and is_instance_valid(d):
			d.queue_free()
	drones.clear()
	active = false
	print("SwarmController: Swarm cleared.")

func cleanup():
	clear_swarm()

func _physics_process(delta):
	if not active or drones.size() == 0 or not leader_drone or not is_instance_valid(leader_drone):
		return

	if formation_active:
		_process_formation(delta)
		return

	# Pre-calculate global centroid and average velocity of the entire swarm (including leader)
	var centroid = get_swarm_centroid()
	var avg_velocity = get_swarm_average_velocity()

	# Retrieve positions and velocities of all drones
	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	var valids: Array[bool] = []
	positions.resize(drones.size())
	velocities.resize(drones.size())
	valids.resize(drones.size())

	for i in range(drones.size()):
		var d = drones[i]
		if d and is_instance_valid(d):
			positions[i] = d.global_position
			velocities[i] = d.linear_velocity
			valids[i] = true
		else:
			positions[i] = Vector3.ZERO
			velocities[i] = Vector3.ZERO
			valids[i] = false

	var leader_pos = leader_drone.global_position
	var leader_vel = leader_drone.linear_velocity

	for i in range(drones.size()):
		var drone_inst = drones[i]
		if not drone_inst or not is_instance_valid(drone_inst) or not valids[i]:
			continue

		var pos = positions[i]
		var vel = velocities[i]

		var steer_cohesion = Vector3.ZERO
		var steer_separation = Vector3.ZERO
		var steer_alignment = Vector3.ZERO
		var steer_target = Vector3.ZERO
		var steer_ground = Vector3.ZERO
		var steer_upward = Vector3.ZERO

		# 1. OPTIMIZED SEPARATION: only calculate against the single closest neighbor
		var closest_dist_sq = 999999.0
		var closest_pos = Vector3.ZERO

		# Check against leader drone
		var d_leader_sq = pos.distance_squared_to(leader_pos)
		if d_leader_sq < closest_dist_sq:
			closest_dist_sq = d_leader_sq
			closest_pos = leader_pos

		# Check against other follower drones
		for j in range(drones.size()):
			if i == j or not valids[j]:
				continue
			var other_pos = positions[j]
			var d_sq = pos.distance_squared_to(other_pos)
			if d_sq < closest_dist_sq:
				closest_dist_sq = d_sq
				closest_pos = other_pos

		var closest_dist = sqrt(closest_dist_sq)
		if closest_dist < separation_radius and closest_dist > 0.001:
			var desired_sep = (pos - closest_pos).normalized() * max_speed
			# Separation force gets stronger the closer they are
			var dist_factor = clamp((separation_radius - closest_dist) / separation_radius, 0.1, 1.0)
			steer_separation = (desired_sep - vel).limit_length(max_force * dist_factor * 1.5)

		# 2. COHESION: seek global centroid
		var desired_coh = (centroid - pos).normalized() * max_speed
		steer_cohesion = (desired_coh - vel).limit_length(max_force)

		# 3. ALIGNMENT: align velocity with average swarm velocity
		if avg_velocity.length_squared() > 0.01:
			var desired_align = avg_velocity.normalized() * max_speed
			steer_alignment = (desired_align - vel).limit_length(max_force)

		# 4. ZERO-LAG TARGET SEEKING: velocity matching + positional correction
		var correction = (leader_pos - pos) * 3.0 # proportional pull towards leader
		var desired_tgt = leader_vel + correction
		desired_tgt = desired_tgt.limit_length(max_speed)
		steer_target = (desired_tgt - vel).limit_length(max_force)

		# 5. GROUND AVOIDANCE
		var terrain_height = get_terrain_height_at(pos)
		var min_height_above_ground = 8.0
		if pos.y < terrain_height + min_height_above_ground:
			var desired_up = Vector3(vel.x, max_speed, vel.z).normalized() * max_speed
			var correction_depth = (terrain_height + min_height_above_ground) - pos.y
			var scale_factor = clamp(1.0 + (correction_depth / 2.0), 1.0, 3.5)
			steer_ground = (desired_up - vel).limit_length(max_force * scale_factor)

		# 6. UPWARD BIAS (keep drones airborne if they drift too low)
		var steer_up = Vector3(0, max_speed * 0.8, 0)
		steer_upward = (steer_up - vel).limit_length(max_force)

		# Combine steering forces
		var total_force = (
			steer_cohesion * cohesion_weight +
			steer_separation * separation_weight +
			steer_alignment * alignment_weight +
			steer_target * target_weight +
			steer_ground * ground_avoid_weight +
			steer_upward * upward_bias_weight
		)

		# Translate total_force to local drone coordinates for control mapping
		var local_force = drone_inst.global_transform.basis.inverse() * total_force

		# Map local forces to input vector:
		# throttle (x), yaw (y), pitch (z), roll (w)
		var throttle = clamp(0.55 + total_force.y * 0.05, 0.35, 1.0)
		
		# Auto-yaw towards flight direction
		var yaw = 0.0
		if vel.length_squared() > 0.5:
			var target_dir = vel.normalized()
			var current_dir = -drone_inst.global_transform.basis.z
			var angle = current_dir.signed_angle_to(target_dir, Vector3.UP)
			yaw = clamp(angle * 1.2, -1.0, 1.0)

		# Pitch and roll tilts the drone in the direction of the force
		var pitch = clamp(-local_force.z * 0.10, -1.0, 1.0)
		var roll = clamp(local_force.x * 0.10, -1.0, 1.0)

		drone_inst.set_input_vector(Vector4(throttle, yaw, pitch, roll))

func _process_formation(delta: float) -> void:
	formation_transition_time = min(formation_transition_time + delta, formation_transition_duration)
	var formation_count: int = min(drones.size(), formation_targets.size())
	if formation_count == 0:
		return

	for i in range(formation_count):
		var drone_inst: RigidBody3D = drones[i]
		if not drone_inst or not is_instance_valid(drone_inst):
			continue

		var target_pos: Vector3 = formation_targets[i]
		var pos: Vector3 = drone_inst.global_position
		var vel: Vector3 = drone_inst.linear_velocity
		var show_target: Vector3 = Vector3(target_pos.x, formation_hold_altitude, target_pos.z)
		if formation_settling:
			var settle_t: float = formation_transition_time / formation_transition_duration
			settle_t = settle_t * settle_t * (3.0 - 2.0 * settle_t)
			show_target.y = lerp(pos.y, formation_hold_altitude, settle_t)
		var horizontal_to_target: Vector3 = Vector3(show_target.x - pos.x, 0.0, show_target.z - pos.z)
		var vertical_error: float = show_target.y - pos.y
		var dist: float = horizontal_to_target.length()

		# Stage 1: rise from the ground; Stage 2: settle at the final show height.
		var desired_up: float = 0.0
		if pos.y < formation_hold_altitude - formation_hold_tolerance:
			desired_up = clamp(0.65 + vertical_error * 0.03, 0.45, 1.0)
		else:
			desired_up = clamp(0.5 + vertical_error * 0.12, 0.35, 0.72)

		var horizontal_dir: Vector3 = horizontal_to_target
		var forward_drive: float = 0.0
		if horizontal_dir.length_squared() > 0.01:
			forward_drive = clamp(horizontal_dir.length() * 0.02, -0.25, 0.25)

		var local_force: Vector3 = drone_inst.global_transform.basis.inverse() * Vector3(horizontal_to_target.x, 0.0, horizontal_to_target.z)
		var pitch: float = clamp(-local_force.z * 0.02, -0.25, 0.25)
		var roll: float = clamp(local_force.x * 0.02, -0.25, 0.25)
		var yaw: float = 0.0
		if vel.length_squared() > 0.15:
			var target_dir: Vector3 = vel.normalized()
			var current_dir: Vector3 = -drone_inst.global_transform.basis.z
			yaw = clamp(current_dir.signed_angle_to(target_dir, Vector3.UP) * 0.35, -0.25, 0.25)

		if abs(vertical_error) <= formation_hold_tolerance and dist <= formation_arrival_radius:
			desired_up = 0.48
			forward_drive = 0.0
			pitch = 0.0
			roll = 0.0
			yaw = 0.0
			if formation_transition_time >= formation_transition_duration:
				formation_settling = false

		var throttle: float = clamp(desired_up + forward_drive, 0.0, 1.0)
		drone_inst.set_input_vector(Vector4(throttle, yaw, pitch, roll))

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from = Vector3(pos.x, 300.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	
	# Exclude leader and all swarm drones to prevent raycast collision with itself/each other
	var exclude_list = []
	if leader_drone and is_instance_valid(leader_drone):
		exclude_list.append(leader_drone.get_rid())
	for d in drones:
		if d and is_instance_valid(d):
			exclude_list.append(d.get_rid())
	query.exclude = exclude_list

	var result = space_state.intersect_ray(query)
	if result.has("position"):
		return result.position.y
	return 0.0

func get_swarm_centroid() -> Vector3:
	var center = Vector3.ZERO
	var count = 0
	if leader_drone and is_instance_valid(leader_drone):
		center += leader_drone.global_position
		count += 1
	for d in drones:
		if d and is_instance_valid(d):
			center += d.global_position
			count += 1
	if count > 0:
		return center / count
	return target_position

func get_swarm_average_velocity() -> Vector3:
	var avg_vel = Vector3.ZERO
	var count = 0
	if leader_drone and is_instance_valid(leader_drone):
		avg_vel += leader_drone.linear_velocity
		count += 1
	for d in drones:
		if d and is_instance_valid(d):
			avg_vel += d.linear_velocity
			count += 1
	if count > 0:
		return avg_vel / count
	return Vector3.ZERO
