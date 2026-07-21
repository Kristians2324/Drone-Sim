extends CanvasLayer

@onready var controls_label = $Center/Panel/Margin/Layout/Controls
@onready var resume_button = $Center/Panel/Margin/Layout/Resume
@onready var formation_buttons = {
	"star": $Center/Panel/Margin/Layout/Formations/Grid/Star,
	"circle": $Center/Panel/Margin/Layout/Formations/Grid/Circle,
	"heart": $Center/Panel/Margin/Layout/Formations/Grid/Heart,
	"diamond": $Center/Panel/Margin/Layout/Formations/Grid/Diamond,
	"wave": $Center/Panel/Margin/Layout/Formations/Grid/Wave,
}

var last_input_was_controller: bool = false


const KEYBOARD_TEXT = "--- KEYBOARD CONTROLS ---
SPACE / SHIFT : Thrust Up/Down
W / S : Pitch Forward/Back
A / D : Roll Left/Right
Q / E : Yaw Rotate
C : Switch Camera View
H : Toggle Hover Mode
V : Toggle Debug Mode
R : Reset Level
1-4 : Switch Environments
5 : Toggle Autopilot (Track Flight)
6 : Trigger Loop-de-Loop Trick
7 : Trigger Barrel Roll Trick
TAB : Toggle Swarm (Boids Mode)"

const CONTROLLER_TEXT = "--- XBOX CONTROLLER ---
LS Vertical : Thrust Up/Down
LS Horizontal : Yaw (Turn)
RS Vertical : Pitch Forward/Back
RS Horizontal : Roll Left/Right
START : Toggle Menu (ESC)
A : Select Menu Option
BACK : Restart Level"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	update_controls_display()
	connect_formation_buttons()

func _input(event):
	# Detect if user is using a controller
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if not last_input_was_controller:
			last_input_was_controller = true
			update_controls_display()
	elif event is InputEventKey or event is InputEventMouse:
		if last_input_was_controller:
			last_input_was_controller = false
			update_controls_display()

func update_controls_display():
	if controls_label:
		controls_label.text = CONTROLLER_TEXT if last_input_was_controller else KEYBOARD_TEXT

func connect_formation_buttons():
	for key in formation_buttons.keys():
		var button = formation_buttons[key]
		if button and not button.pressed.is_connected(_on_formation_pressed.bind(key)):
			button.pressed.connect(_on_formation_pressed.bind(key))

func _on_formation_pressed(shape_name: String) -> void:
	var manager = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if manager and manager.has_method("select_show_shape"):
		manager.select_show_shape(shape_name)
		resume()

func toggle():
	if visible:
		resume()
	else:
		pause()

func pause():
	show()
	update_controls_display()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Enable controller navigation by focusing the first button
	if resume_button:
		resume_button.grab_focus()

func resume():
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_resume_pressed():
	resume()

func _on_restart_pressed():
	resume()
	get_tree().reload_current_scene()

func _on_quit_pressed():
	get_tree().quit()
