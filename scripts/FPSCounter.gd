extends CanvasLayer

var fps_label: Label

func _ready():
	fps_label = Label.new()
	fps_label.position = Vector2(10, 10)
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.0))
	fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	fps_label.add_theme_constant_override("shadow_offset_x", 1)
	fps_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(fps_label)

func _process(_delta):
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
