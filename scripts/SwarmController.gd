extends Node

@export var drone_scene: PackedScene
var drones: Array = []
var active = false

func initialize_swarm(count = 10):
    if drone_scene == null:
        push_error("SwarmController: drone_scene not assigned.")
        return

    active = true
    # Clear existing drones
    for d in drones:
        if d and d.is_inside_tree():
            d.queue_free()
    drones.clear()
    
    # Spawn multiple drone instances from drone_scene
    for i in count:
        var drone_instance = drone_scene.instantiate()
        get_parent().add_child(drone_instance)
        drone_instance.position = Vector3(randf() * 20 - 10, 10, randf() * 20 - 10) # spawn at some random start positions
        drones.append(drone_instance)
        # Clear input on swarm drones
        if drone_instance.has_method("set_input_vector"):
            # Instead of inputVector, we set property smoothed_input for swarm AI
            drone_instance.smoothed_input = Vector4.ZERO

func clear_swarm():
    for d in drones:
        if d and d.is_inside_tree():
            d.queue_free()
    drones.clear()
    active = false

var update_accumulator = 0.0
var update_interval = 0.1  # 10 updates per second for swarm to reduce CPU usage

func _process(delta):
    if not active:
        return

    update_accumulator += delta
    if update_accumulator < update_interval:
        return
    update_accumulator = 0.0

    # Simple swarm behavior placeholder: hover with random minor throttle adjustments
    var center_pos = Vector3.ZERO
    for drone_inst in drones:
        center_pos += drone_inst.global_position
    center_pos /= drones.size()

    for drone_inst in drones:
        # Compute direction from center to drone to keep swarm cohesive (simple cohesion)
        var dir_to_center = (center_pos - drone_inst.global_position).normalized()
        var input_vec = Vector4(0.5, 0, dir_to_center.z, dir_to_center.x)  # moderate throttle, pitch and roll to move closer
        drone_inst.smoothed_input = input_vec

