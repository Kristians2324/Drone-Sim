extends CanvasLayer

# Minimal no-op DebugOverlay to avoid runtime errors in the container.
func _ready() -> void:
	set_process(false)
	pass

