extends Node

@export var single_drone_controller_scene: PackedScene
@export var swarm_controller_scene: PackedScene

var single_drone_controller: Node = null
var swarm_controller: Node = null
var use_swarm: bool = false

func _ready():
    # Instantiate controllers
    if single_drone_controller_scene:
        single_drone_controller = single_drone_controller_scene.instantiate()
        add_child(single_drone_controller)
        single_drone_controller.visible = true
    if swarm_controller_scene:
        swarm_controller = swarm_controller_scene.instantiate()
        add_child(swarm_controller)
        swarm_controller.visible = false

func _process(delta):
    if Input.is_key_pressed(KEY_TAB):
        toggle_control_mode()

func toggle_control_mode():
    use_swarm = !use_swarm
    if single_drone_controller:
        single_drone_controller.visible = !use_swarm
    if swarm_controller:
        swarm_controller.visible = use_swarm
    print("Control mode switched to: ", "Swarm" if use_swarm else "Single Drone")

    # Enable or disable as needed
    if single_drone_controller:
        single_drone_controller.set_process(!use_swarm)
    if swarm_controller:
        swarm_controller.set_process(use_swarm)

    # Clear swarm if toggling off
    if swarm_controller and not use_swarm:
        swarm_controller.clear_swarm() if swarm_controller.has_method("clear_swarm") else null
    if swarm_controller and use_swarm and swarm_controller.has_method("initialize_swarm"):
        swarm_controller.initialize_swarm(10) # spawn 10 drones in swarm
