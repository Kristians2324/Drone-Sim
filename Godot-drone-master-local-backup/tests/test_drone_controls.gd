extends Node

func _ready():
    # This test suite will cover drone light show button inputs and R key restart shortcut

    # Test drone show shape selection via ESC menu buttons
    test_drone_show_shape_buttons()

    # Test R key restart shortcut functionality
    test_r_key_restart()

func test_drone_show_shape_buttons():
    var drone_controller_manager = get_node("/root/WorldManager").get_node("DroneControllerManager")
    var menu = get_node("/root/WorldManager").get_node("Menu")

    # Test each show shape button triggers the correct show mode
    var shapes = ["star", "circle", "heart", "diamond", "wave"]
    for shape in shapes:
        menu._on_formation_pressed(shape)
        assert(drone_controller_manager.show_mode_names.has(shape))
        var expected_mode = drone_controller_manager.show_mode_names[shape]
        assert(drone_controller_manager.show_mode == expected_mode)
        print("PASS: Show shape button '" + shape + "' sets show mode correctly.")

func test_r_key_restart():
    var world_manager = get_node("/root/WorldManager")
    var menu = world_manager.menu_instance

    # Simulate pressing R key
    var event = InputEventKey.new()
    event.pressed = true
    event.keycode = KEY_R

    # Before pressing R, record current scene
    var current_scene = get_tree().current_scene

    # Send input event to world_manager
    world_manager._input(event)

    # After pressing R, the scene should be reloaded (different instance)
    var new_scene = get_tree().current_scene
    assert(new_scene != current_scene)
    print("PASS: Pressing R key restarts the simulation.")