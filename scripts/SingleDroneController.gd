extends Node

var drone: Node = null
var drone_input: Node

func _ready():
    # Auto-find first Drone node in scene tree
    drone = get_tree().get_root().find_node("Drone", true, false)
    if drone == null:
        print("SingleDroneController: Drone node not found in scene tree.")
        return

    # Initialize drone input helper
    drone_input = preload("res://scripts/drone/DroneInput.gd").new()
    drone_input.initialize(3.5) # smoothing factor

func _process(delta):
    print("SingleDroneController _process running")
    if drone == null:
        return
    var input_vec = drone_input.get_smoothed_input(delta)
    print("SingleDroneController input_vec:", input_vec)
    # Send input vector to drone
    if drone.has_method("set_input_vector"):
        drone.call("set_input_vector", input_vec)

