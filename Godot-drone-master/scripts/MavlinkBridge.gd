extends Node

class_name MavlinkBridge

# Minimal placeholder implementation used during container startup.
var enabled: bool = false
var listen_port: int = 14550
func set_endpoint(host: String, port: int) -> void:
	pass

