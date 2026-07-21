## WindHud.gd — replaced by WindCompass.gd
## This file is kept as a stub so any stale scene references don't break.
## The actual wind visualizer is now res://scripts/ui/WindCompass.gd
extends CanvasLayer

func _ready() -> void:
	# Old WindHud replaced — nothing to do here.
	# Remove this node from the scene if it somehow gets added.
	queue_free()
