extends CanvasLayer
class_name WindHud

const PADDING := 12

var _panel: PanelContainer
var _label: Label
var _meter: Control

func _ready() -> void:
	layer = 120
	_build()

func _process(_delta: float) -> void:
	_update()

func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.08, 0.65)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = PADDING
	_panel.offset_top = PADDING + 58
	_panel.offset_right = 250
	_panel.offset_bottom = 150

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_label.text = "Wind: --"
	vbox.add_child(_label)

	_meter = Control.new()
	_meter.custom_minimum_size = Vector2(220, 44)
	_meter.draw.connect(_draw_meter)
	vbox.add_child(_meter)
	add_child(_panel)

func _update() -> void:
	if not is_instance_valid(_label):
		return
	var wm := _get_wind_manager()
	if wm == null:
		_label.text = "Wind: --"
		_meter.queue_redraw()
		return
	_label.text = "Wind: %s  %.1f m/s" % [wm.get_state_name(), wm.get_wind_strength()]
	_meter.queue_redraw()

func _draw_meter() -> void:
	var wm := _get_wind_manager()
	var strength: float = wm.get_wind_strength() if wm else 0.0
	var fill := clampf(strength / 7.0, 0.0, 1.0)
	var rect := _meter.get_rect()
	var base := Rect2(Vector2(0, 8), Vector2(rect.size.x, 12))
	var fill_rect := Rect2(base.position, Vector2(base.size.x * fill, base.size.y))
	_meter.draw_rect(base, Color(0.1, 0.1, 0.12, 0.9), true)
	_meter.draw_rect(base, Color(0.7, 0.8, 0.9, 0.8), false, 2.0)
	_meter.draw_rect(fill_rect, Color(0.35, 0.75, 1.0, 0.95), true)
	for i in range(5):
		var x := base.position.x + (base.size.x / 5.0) * float(i)
		_meter.draw_line(Vector2(x, 0), Vector2(x + 8, 6), Color(0.7, 0.9, 1.0, 0.5), 1.0)

func _get_wind_manager() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var direct := scene.get_node_or_null("WindManager")
	if direct != null:
		return direct
	for child in scene.get_children():
		if child is WindManager:
			return child
		var nested := child.find_child("WindManager", true, false)
		if nested != null and nested is WindManager:
			return nested
	return null