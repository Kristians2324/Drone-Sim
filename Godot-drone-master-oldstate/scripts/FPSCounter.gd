## DEPRECATED — FPS display is now handled by DebugOverlay.gd
## Press V in-game to toggle the full debug panel (FPS is always visible top-right).
extends CanvasLayer

func _ready() -> void:
	push_warning("FPSCounter is deprecated. Use DebugOverlay instead (already in Main.tscn).")
	queue_free()
