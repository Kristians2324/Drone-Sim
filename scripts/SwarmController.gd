extends Node3D

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
@export var swarm_count: int = 10
@export var max_neighbours: int = 7

var drones: Array[RigidBody3D] = []
var active: bool = false

var target_position: Vector3 = Vector3(0, 10, 0)
var target_indicator: MeshInstance3D = null

# Boids parameters
var neighborhood_radius: float = 15.0
var separation_radius: float = 4.0
var cohesion_weight: float = 1.2
var separation_weight: float = 2.5
var alignment_weight: float = 1.0
var target_weight: float = 3.0
var ground_avoid_weight: float = 5.0
var max_speed: float = 22.0
var max_force: float = 15.0

# Camera
var camera: Camera3D = null
var camera_smoothing: float = 3.0

func _ready():
	target_indicator = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	target_indicator.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.8)
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	target_indicator.material_override = mat
	add_child(target_indicator)
	target_indicator.visible = false

	camera = Camera3D.new()
	add_child(camera)
	camera.current = false

func initialize_swarm(count: int = 10, spawn_pos: Vector3 = Vector3(0, 5, 0)):
	swarm_count = count
	active = true
	clear_swarm()

	target_position = spawn_pos + Vector3(0, 5, 0)
	if target_indicator:
		target_indicator.visible = true
		target_indicator.global_position = target_position

	for i in range(swarm_count):
		var drone_inst = drone_scene.instantiate()
		get_parent().add_child(drone_inst)
		var offset = Vector3(
			randf_range(-12.0, 12.0),
			randf_range(5.0, 15.0),
			randf_range(-12.0, 12.0)
		)
		drone_inst.global_position = spawn_pos + offset
		if drone_inst.show_rig:
			drone_inst.show_rig.configure(i, swarm_count, false)
		drones.append(drone_inst)

	if camera:
		camera.current = true
		var center = get_swarm_centroid()
		camera.global_position = center + Vector3(0, 18, 30)
		camera.look_at(center, Vector3.UP)

	print("SwarmController: Swarm initialized with ", drones.size(), " drones at ", spawn_pos)

func clear_swarm():
	if camera:
		camera.current = false
	if target_indicator:
		target_indicator.visible = false
	for d in drones:
		if d and is_instance_valid(d):
			d.queue_free()
	drones.clear()
	active = false
	print("SwarmController: Swarm cleared.")

func cleanup():
	clear_swarm()

func _process(delta):
	if not active or drones.size() == 0:
		return
	var input_dir = Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("throttle_down", "throttle_up"),
		Input.get_axis("move_back", "move_forward")
	)
	target_position += input_dir * (delta * 18.0)
	if target_indicator:
		target_indicator.global_position = target_position
	var centroid = get_swarm_centroid()
	var target_cam_pos = centroid + Vector3(0, 20, 35)
	if camera and camera.current:
		camera.global_position = camera.global_position.lerp(target_cam_pos, delta * camera_smoothing)
		camera.look_at(centroid, Vector3.UP)

func _physics_process(delta):
	if not active or drones.size() == 0:
		return

	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	positions.resize(drones.size())
	velocities.resize(drones.size())

	for i in range(drones.size()):
		var d = drones[i]
		if d and is_instance_valid(d):
			positions[i] = d.global_position
			velocities[i] = d.linear_velocity
		else:
			positions[i] = Vector3.ZERO
			velocities[i] = Vector3.ZERO

	for i in range(drones.size()):
		var drone_inst = drones[i]
		if not drone_inst or not is_instance_valid(drone_inst):
			continue

		var pos = positions[i]
		var vel = velocities[i]

		var steer_cohesion = Vector3.ZERO
		var steer_separation = Vector3.ZERO
		var steer_alignment = Vector3.ZERO
		var cohesion_center = Vector3.ZERO
		var alignment_vel = Vector3.ZERO
		var cohesion_count = 0
		var separation_count = 0
		var alignment_count = 0

		# Nearest-neighbour culling: only consider closest max_neighbours within radius
		var neighbour_entries: Array = []
		var nr_sq = neighborhood_radius * neighborhood_radius
		for j in range(drones.size()):
			if i == j:
				continue
			var d_sq = pos.distance_squared_to(positions[j])
			if d_sq < nr_sq:
				neighbour_entries.append([d_sq, j])
		neighbour_entries.sort_custom(func(a, b): return a[0] < b[0])
		var neighbours = neighbour_entries.slice(0, max_neighbours)

		for entry in neighbours:
			var j = entry[1]
			var other_pos = positions[j]
			var other_vel = velocities[j]
			var dist = sqrt(entry[0])

			cohesion_center += other_pos
			cohesion_count += 1
			alignment_vel += other_vel
			alignment_count += 1

			if dist < separation_radius and dist > 0.001:
				var diff = (pos - other_pos).normalized() / dist
				steer_separation += diff
				separation_count += 1

		if cohesion_count > 0:
			cohesion_center /= cohesion_count
			var desired = (cohesion_center - pos).normalized() * max_speed
			steer_cohesion = (desired - vel).limit_length(max_force)

		if alignment_count > 0:
			alignment_vel /= alignment_count
			var desired = alignment_vel.normalized() * max_speed
			steer_alignment = (desired - vel).limit_length(max_force)

		if separation_count > 0:
			steer_separation /= separation_count
			var desired = steer_separation.normalized() * max_speed
			steer_separation = (desired - vel).limit_length(max_force)

		var dist_to_target = pos.distance_to(target_position)
		var steer_target = Vector3.ZERO
		if dist_to_target > 0.001:
			var desired = (target_position - pos).normalized() * max_speed
			steer_target = (desired - vel).limit_length(max_force)

		var steer_ground = Vector3.ZERO
		var terrain_height = get_terrain_height_at(pos)
		var min_height_above_ground = 7.0
		if pos.y < terrain_height + min_height_above_ground:
			var desired_up = Vector3(vel.x, max_speed, vel.z).normalized() * max_speed
			var correction_depth = (terrain_height + min_height_above_ground) - pos.y
			var scale_factor = clamp(1.0 + (correction_depth / 2.0), 1.0, 3.0)
			steer_ground = (desired_up - vel).limit_length(max_force * scale_factor)

		var total_force = (
			steer_cohesion * cohesion_weight +
			steer_separation * separation_weight +
			steer_alignment * alignment_weight +
			steer_target * target_weight +
			steer_ground * ground_avoid_weight
		)

		var local_force = drone_inst.global_transform.basis.inverse() * total_force
		var throttle = clamp(0.5 + total_force.y * 0.05, 0.0, 1.0)
		var yaw = 0.0

		if vel.length_squared() > 1.0:
			var target_dir = vel.normalized()
			var current_dir = -drone_inst.global_transform.basis.z
			var angle = current_dir.signed_angle_to(target_dir, Vector3.UP)
			yaw = clamp(angle * 1.5, -1.0, 1.0)

		var pitch = clamp(-local_force.z * 0.05, -1.0, 1.0)
		var roll = clamp(local_force.x * 0.05, -1.0, 1.0)

		drone_inst.set_input_vector(Vector4(throttle, yaw, pitch, roll))

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from = Vector3(pos.x, 300.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var exclude_list = []
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
	for d in drones:
		if d and is_instance_valid(d):
			center += d.global_position
			count += 1
	if count > 0:
		return center / count
	return target_position
