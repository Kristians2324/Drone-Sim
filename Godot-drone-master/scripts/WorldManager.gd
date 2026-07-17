extends Node3D

# Minimal stub WorldManager to avoid script compilation/runtime failures
# inside the container. This keeps the main scene loadable while other
# imports and assets are being repaired. Restoring original behavior is
# safe once the import/cache errors are fixed.

func _ready() -> void:
	# No-op: environment and menu loading disabled in container mode.
	pass
