extends Node

# No-op DroneControllerManager stub for container stability.
# Reintroduce full behavior when assets/imports are fixed.

var _drone: Node = null

func _ready() -> void:
    set_process(false)

func get_drone() -> Node:
    return _drone

func spawn_drone() -> void:
    pass

func cleanup() -> void:
    pass

func update_camera_views() -> void:
    pass
