extends Node3D
class_name BoidManager

@export var boid_count: int = 60
@export var neighborhood_radius: float = 12.0
@export var separation_radius: float = 3.5

# Steering weights
@export var cohesion_weight: float = 1.0
@export var separation_weight: float = 2.2
@export var alignment_weight: float = 0.8
@export var target_weight: float = 2.5
@export var target_separation_weight: float = 3.5
@export var ground_avoid_weight: float = 5.0

@export var target_arrival_radius: float = 15.0
@export var target_separation_radius: float = 6.0

@export var max_speed: float = 20.0
@export var max_force: float = 12.0

var boids: Array[Boid] = []
var target_node: Node3D = null

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	# Raycast from high up straight down
	var from = Vector3(pos.x, 300.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	
	# Exclude target player drone
	if target_node:
		query.exclude = [target_node.get_rid()]
		
	var result = space_state.intersect_ray(query)
	if result.has("position"):
		return result.position.y
	return 0.0

func initialize(target: Node3D):
	target_node = target
	spawn_boids()

func spawn_boids():
	var spawn_center = target_node.global_position if target_node else Vector3.ZERO
	for i in range(boid_count):
		var boid = Boid.new()
		# Random position within a sphere around the player
		var offset = Vector3(
			randf_range(-10.0, 10.0),
			randf_range(2.0, 10.0),
			randf_range(-10.0, 10.0)
		)
		boid.global_position = spawn_center + offset
		
		# Random initial velocity
		boid.velocity = Vector3(
			randf_range(-5.0, 5.0),
			randf_range(-2.0, 5.0),
			randf_range(-5.0, 5.0)
		).normalized() * randf_range(5.0, 10.0)
		
		# Set colors in a beautiful palette (varying green, cyan, blue, magenta)
		var hue = randf_range(0.3, 0.9)
		if hue > 0.55 and hue < 0.7: # Skip dark blues
			hue = randf_range(0.3, 0.5)
		var col = Color.from_hsv(hue, 0.9, 0.95)
		
		# Make sure materials are fully initialized in ready before modifying, 
		# but since we are modifying them here after instantiation, let's call _ready if not ready,
		# or just update them. In Godot, ready is called when node is added to scene tree.
		# Since we haven't added it to scene tree yet, the node's _ready hasn't run.
		# Let's add it to the scene tree first!
		add_child(boid)
		
		# Now that it's added to the tree, its _ready has run and mesh_instance exists.
		if boid.mesh_instance and boid.mesh_instance.material_override:
			boid.mesh_instance.material_override.albedo_color = col
		if boid.trail_particles and boid.trail_particles.color_ramp:
			boid.trail_particles.color_ramp.set_color(0, Color(col.r, col.g, col.b, 0.8))
			boid.trail_particles.color_ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
			
		boids.append(boid)

func _physics_process(delta):
	if boids.size() == 0:
		return
		
	var target_pos = target_node.global_position if target_node else Vector3.ZERO
	
	# Pre-fetch arrays to optimize iteration
	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	positions.resize(boids.size())
	velocities.resize(boids.size())
	
	for i in range(boids.size()):
		positions[i] = boids[i].global_position
		velocities[i] = boids[i].velocity
		
	for i in range(boids.size()):
		var boid = boids[i]
		var pos = positions[i]
		var vel = velocities[i]
		
		# Initialize steering forces
		var steer_cohesion = Vector3.ZERO
		var steer_separation = Vector3.ZERO
		var steer_alignment = Vector3.ZERO
		
		var cohesion_center = Vector3.ZERO
		var alignment_vel = Vector3.ZERO
		
		var cohesion_count = 0
		var separation_count = 0
		var alignment_count = 0
		
		for j in range(boids.size()):
			if i == j:
				continue
			var other_pos = positions[j]
			var other_vel = velocities[j]
			
			var dist = pos.distance_to(other_pos)
			
			if dist < neighborhood_radius:
				cohesion_center += other_pos
				cohesion_count += 1
				
				alignment_vel += other_vel
				alignment_count += 1
				
			if dist < separation_radius and dist > 0.001:
				var diff = (pos - other_pos).normalized() / dist
				steer_separation += diff
				separation_count += 1
				
		# Compute Cohesion
		if cohesion_count > 0:
			cohesion_center /= cohesion_count
			var desired = (cohesion_center - pos).normalized() * max_speed
			steer_cohesion = (desired - vel).limit_length(max_force)
			
		# Compute Alignment
		if alignment_count > 0:
			alignment_vel /= alignment_count
			var desired = alignment_vel.normalized() * max_speed
			steer_alignment = (desired - vel).limit_length(max_force)
			
		# Compute Separation
		if separation_count > 0:
			steer_separation /= separation_count
			var desired = steer_separation.normalized() * max_speed
			steer_separation = (desired - vel).limit_length(max_force)
			
		# Target Seeking (Seek player drone with Arrival behavior)
		var dist_to_target = pos.distance_to(target_pos)
		var steer_target = Vector3.ZERO
		if dist_to_target > 0.001:
			var speed = max_speed
			if dist_to_target < target_arrival_radius:
				speed = max_speed * (dist_to_target / target_arrival_radius)
			var desired_target = (target_pos - pos).normalized() * speed
			steer_target = (desired_target - vel).limit_length(max_force)
			
		# Separation from the player/target drone to avoid collision
		var steer_target_separation = Vector3.ZERO
		if dist_to_target < target_separation_radius and dist_to_target > 0.001:
			var diff = (pos - target_pos).normalized() / dist_to_target
			var desired = diff * max_speed
			steer_target_separation = (desired - vel).limit_length(max_force)
			
		# Ground Avoidance (Stay above terrain dynamically using raycast query)
		var steer_ground = Vector3.ZERO
		var terrain_height = get_terrain_height_at(pos)
		var min_height_above_ground = 7.0
		if pos.y < terrain_height + min_height_above_ground:
			var desired_up = Vector3(vel.x, max_speed, vel.z).normalized() * max_speed
			var correction_depth = (terrain_height + min_height_above_ground) - pos.y
			var scale_factor = clamp(1.0 + (correction_depth / 2.0), 1.0, 3.0)
			steer_ground = (desired_up - vel).limit_length(max_force * scale_factor)
			
		# Sum of steering forces
		var total_force = (
			steer_cohesion * cohesion_weight +
			steer_separation * separation_weight +
			steer_alignment * alignment_weight +
			steer_target * target_weight +
			steer_target_separation * target_separation_weight +
			steer_ground * ground_avoid_weight
		)
		
		# Apply velocity update
		boid.velocity = (vel + total_force * delta).limit_length(max_speed)
		
		# Update position and rotation
		boid.update_boid(delta)
