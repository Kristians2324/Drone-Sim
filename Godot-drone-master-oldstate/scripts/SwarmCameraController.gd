extends Node3D

@export var swarm_controller_path: NodePath
@export var smoothing : float = 5.0
@export var camera_node_path: NodePath
@export var camera_collision_layer: int = 1 << 31

var swarm_controller: Node3D = null
var camera_node: Camera3D = null
var target_position: Vector3

func _ready():
    if has_node(swarm_controller_path):
        swarm_controller = get_node(swarm_controller_path)
    else:
        push_warning("SwarmCameraController: Swarm controller not found at path "+str(swarm_controller_path))

    if has_node(camera_node_path):
        camera_node = get_node(camera_node_path)
		_configure_camera_collision()
    else:
        push_warning("SwarmCameraController: Camera node not found at path "+str(camera_node_path))

func _configure_camera_collision() -> void:
	if camera_node == null:
		return

	# Make the camera itself non-solid for all swarm drones.
	# Drones are configured to ignore this layer so the camera can pass through them.
	camera_node.collision_layer = camera_collision_layer
	camera_node.collision_mask = 0

	# If the camera sits inside a rig with physics bodies, also clear their masks.
	for child in camera_node.get_parent().get_children():
		if child is CollisionObject3D:
			child.collision_layer = camera_collision_layer
			child.collision_mask = 0

func _process(delta):
    if swarm_controller == null or swarm_controller.drones.size() == 0 or camera_node == null:
        return

    # Compute average position (centroid) of swarm drones
    var center = Vector3.ZERO
    for drone_inst in swarm_controller.drones:
        center += drone_inst.global_position
    center /= swarm_controller.drones.size()

    # Smoothly move camera towards swarm center
    target_position = center + Vector3(0, 20, 40) # Adjust height and distance
    camera_node.global_transform.origin = camera_node.global_transform.origin.linear_interpolate(target_position, delta * smoothing)

    # Optionally, look at the swarm center
    camera_node.look_at(center, Vector3.UP)
