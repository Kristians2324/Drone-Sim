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

func _process(delta):
    if not active:
        return
    # TODO: swarm AI logic for each drone here, setting smoothed_input for behavior
    # Example: simple hover with random movement (placeholder)
    for drone_inst in drones:
        var random_input = Vector4(randf(), 0, 0, 0) # throttle only random
        drone_inst.smoothed_input = random_input

