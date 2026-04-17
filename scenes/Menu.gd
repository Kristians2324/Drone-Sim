extends CanvasLayer

@onready var controls_label = $Center/Panel/Margin/Layout/Controls
var last_input_was_controller: bool = false

const KEYBOARD_TEXT = "--- KEYBOARD CONTROLS ---
SPACE / SHIFT : Thrust Up/Down
W / S : Pitch Forward/Back
A / D : Roll Left/Right
Q / E : Yaw Rotate
C : Switch Camera View
R : Reset Level"

const CONTROLLER_TEXT = "--- XBOX CONTROLLER ---
LS Vertical : Thrust Up/Down
LS Horizontal : Yaw (Turn)
RS Vertical : Pitch Forward/Back
RS Horizontal : Roll Left/Right
START : Toggle Camera
BACK : Restart Level"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	update_controls_display()

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
