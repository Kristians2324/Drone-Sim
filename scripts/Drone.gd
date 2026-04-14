extends RigidBody3D

# --- POWERFUL SMOOTH FLIGHT CONFIG ---
const THROTTLE_POWER = 150.0   # Vertical strength
const FORWARD_POWER = 100.0    # Directional strength (THE FIX)
const TURN_POWER = 15.0
const STABILIZE_FORCE = 40.0 
const INPUT_SMOOTHING = 4.0    # Smooth but responsive

var smoothed_input = Vector4.ZERO # throttle, yaw, pitch, roll

@onready var label: Label
@onready var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var design = $Design

func _ready():
	# Professional heavy physics for maximum stability
	mass = 1.0
	gravity_scale = 1.0
	linear_damp = 2.5     # Prevents jitter / spastic movement
	angular_damp = 10.0   # Buttery smooth rotations
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Detailed UI Instructions
	var canvas = CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	canvas.add_child(label)
	label.text = "ALPHASIM DRONE PRO-SIMULATOR v2.0\n" + \
				 "--------------------------------\n" + \
				 "W / S      : Pitch Forward / Back\n" + \
				 "A / D      : Roll Left / Right\n" + \
				 "Q / E      : Yaw (Rotate) Left / Right\n" + \
				 "SPACE      : Increase Thrust (Go Up)\n" + \
				 "SHIFT      : Decrease Thrust (Go Down)\n" + \
				 "T          : Toggle Day / Night Cycle\n" + \
				 "R          : Reset Simulation\n" + \
				 "ESC        : Quit Game"
	label.set("theme_override_font_sizes/font_size", 20)
	label.position = Vector2(30, 30)

func _physics_process(delta):
	# 1. Inputs
	var target = Vector4(
		Input.get_axis("throttle_down", "throttle_up"),
		Input.get_axis("turn_right", "turn_left"),
		Input.get_axis("move_back", "move_forward"),
		Input.get_axis("move_right", "move_left")
	)
	
	# Full Key Fallback
	if target.length() == 0:
		if Input.is_key_pressed(KEY_SPACE): target.x = 1.0
		if Input.is_key_pressed(KEY_SHIFT): target.x = -1.0
		if Input.is_key_pressed(KEY_Q): target.y = 1.0
		if Input.is_key_pressed(KEY_E): target.y = -1.0
		if Input.is_key_pressed(KEY_W): target.z = 1.0
		if Input.is_key_pressed(KEY_S): target.z = -1.0
		if Input.is_key_pressed(KEY_A): target.w = -1.0
		if Input.is_key_pressed(KEY_D): target.w = 1.0

	smoothed_input = smoothed_input.lerp(target, delta * INPUT_SMOOTHING)

	# 2. POWERFUL MOVEMENT ENGINE
	# We combine physical local-up thrust with high-torque directional push
	var local_up = global_transform.basis.y
	
	# Base vertical force
	var vertical_thrust = local_up * smoothed_input.x * THROTTLE_POWER
	
	# Horizontal directional force (High-Torque for definite movement)
	var forward_force = -global_transform.basis.z * smoothed_input.z * FORWARD_POWER
	var strafe_force = -global_transform.basis.x * smoothed_input.w * FORWARD_POWER
	
	# Apply all forces
	apply_central_force(vertical_thrust + forward_force + strafe_force)

	# 3. Rotation
	apply_torque(global_transform.basis.x * -smoothed_input.z * TURN_POWER)
	apply_torque(global_transform.basis.z * smoothed_input.w * TURN_POWER)
	apply_torque(global_transform.basis.y * smoothed_input.y * TURN_POWER)
	
	# 4. Stabilization
	var up = global_transform.basis.y
	var correction = up.cross(Vector3.UP)
	apply_torque(correction * STABILIZE_FORCE)
	
	# Props
	for prop in design.get_node("Props").get_children():
		prop.rotate_y(delta * 30.0)

func _process(_delta):
	if Input.is_key_pressed(KEY_R): get_tree().reload_current_scene()
	if Input.is_key_pressed(KEY_ESCAPE): get_tree().quit()
