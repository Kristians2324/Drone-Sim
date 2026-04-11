extends RigidBody3D

const THRUST_FORCE = 120.0
const ROTATION_FORCE = 25.0
const MOUSE_SENSITIVITY = 0.002
const STABILIZATION_FORCE = 40.0
const MAX_ANGULAR_VELOCITY = 8.0
const INPUT_SMOOTHING = 8.0

var smoothed_input = Vector4.ZERO # x:thrust, y:yaw, z:pitch, w:roll
var mouse_input = Vector2.ZERO

@onready var label: Label
@onready var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	mass = 1.0
	gravity_scale = 1.0
	linear_damp = 0.5
	angular_damp = 6.0
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	var canvas = CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	canvas.add_child(label)
	label.text = "ALPHASIM DRONE SIMULATOR\nMOUSE: Pitch/Roll | Q/E: Yaw\nSpace/Shift: Throttle | ESC: Unlock Mouse"
	label.set("theme_override_font_sizes/font_size", 24)
	label.position = Vector2(20, 20)

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input.x += event.relative.x * MOUSE_SENSITIVITY
		mouse_input.y += event.relative.y * MOUSE_SENSITIVITY
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	# --- 1. Get Inputs ---
	var throttle = Input.get_axis("throttle_down", "throttle_up")
	if Input.is_key_pressed(KEY_SPACE): throttle = 1.0
	if Input.is_key_pressed(KEY_SHIFT): throttle = -1.0
	
	var yaw_input = Input.get_axis("turn_right", "turn_left")
	if Input.is_key_pressed(KEY_Q): yaw_input = 1.0
	if Input.is_key_pressed(KEY_E): yaw_input = -1.0

	# Mouse/Keyboard hybrid for Pitch/Roll
	var pitch_input = mouse_input.y + Input.get_axis("move_back", "move_forward")
	var roll_input = -mouse_input.x + Input.get_axis("move_right", "move_left") # Negative to fix "barrel roll" direction
	
	# Clamp and decay mouse input for smoothness
	mouse_input = mouse_input.lerp(Vector2.ZERO, delta * 10.0)

	var target_input = Vector4(throttle, yaw_input, pitch_input, roll_input)
	smoothed_input = smoothed_input.lerp(target_input, delta * INPUT_SMOOTHING)

	# --- 2. Advanced Hover & Movement ---
	var weight_force = Vector3.UP * (mass * gravity)
	# Thrust is applied in the LOCAL up direction. 
	# Tilted drone = horizontal component of thrust = MOVEMENT.
	var thrust_direction = global_transform.basis.y
	var thrust_force = thrust_direction * (smoothed_input.x + 0.1) * THRUST_FORCE
	
	apply_central_force(weight_force + thrust_force)

	# --- 3. Torque Controls (AXIS CORRECTED) ---
	# Pitch: Rotate around LOCAL X
	apply_torque(global_transform.basis.x * smoothed_input.z * ROTATION_FORCE)
	# Roll: Rotate around LOCAL Z
	apply_torque(global_transform.basis.z * smoothed_input.w * ROTATION_FORCE)
	# Yaw: Rotate around WORLD UP (for cleaner turning)
	apply_torque(Vector3.UP * smoothed_input.y * ROTATION_FORCE)
	
	# --- 4. Dynamic Stabilization ---
	stabilize(delta)

func stabilize(_delta):
	var up = global_transform.basis.y
	var tilt_correction = up.cross(Vector3.UP)
	
	# Only stabilize if no active pitch/roll input
	var s_mult = 1.0
	if abs(smoothed_input.z) > 0.05 or abs(smoothed_input.w) > 0.05:
		s_mult = 0.05 # Let the user lean!
	
	apply_torque(tilt_correction * STABILIZATION_FORCE * s_mult)
	
	if angular_velocity.length() > MAX_ANGULAR_VELOCITY:
		angular_velocity = angular_velocity.normalized() * MAX_ANGULAR_VELOCITY

func _process(_delta):
	if Input.is_key_pressed(KEY_R):
		get_tree().reload_current_scene()
