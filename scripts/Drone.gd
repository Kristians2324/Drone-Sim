extends RigidBody3D

# --- POWERFUL SMOOTH FLIGHT CONFIG ---
const THROTTLE_POWER = 180.0   
const FORWARD_POWER = 120.0    
const TURN_POWER = 18.0
const STABILIZE_FORCE = 45.0
const INPUT_SMOOTHING = 3.5

var smoothed_input = Vector4.ZERO # throttle, yaw, pitch, roll

# Camera toggle
var is_first_person = true
var third_person_camera: Camera3D
var first_person_camera: Camera3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var camera_toggle_cooldown = 0.0

# Audio Variables
var motor_audio: AudioStreamPlayer3D
var motor_playback: AudioStreamGeneratorPlayback
var crash_audio: AudioStreamPlayer3D
var crash_playback: AudioStreamGeneratorPlayback
var audio_hz = 44100.0
var motor_phase = 0.0

@onready var design = $Design
@onready var collision_shape: CollisionShape3D = $Collision

func _ready():
	# Professional heavy physics for maximum stability
	mass = 5.0
	gravity_scale = 1.0
	linear_damp = 2.0
	angular_damp = 8.0
	
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# Enable collision detection for sound
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_drone_collision)
	
	# Ensure collision shape is properly set on the body
	collision_shape.shape = BoxShape3D.new()
	collision_shape.shape.size = Vector3(1.2, 0.2, 1.2)
	collision_shape.transform = Transform3D.IDENTITY
	
	# Setup standard cameras
	third_person_camera = $SpringArm3D/Camera3D
	first_person_camera = Camera3D.new()
	design.add_child(first_person_camera)
	first_person_camera.position = Vector3(0, 0.15, -0.35)
	first_person_camera.rotation_degrees = Vector3(15, 0, 0)
	
	# Setup VR nodes (Optional)
	setup_vr()
	
	# Initial camera state
	update_camera_views()
	
	# Setup procedural audio
	setup_drone_audio()

func setup_vr():
	# Create VR rig at the FPV position
	xr_origin = XROrigin3D.new()
	design.add_child(xr_origin)
	xr_origin.position = first_person_camera.position
	xr_origin.rotation = first_person_camera.rotation
	
	xr_camera = XRCamera3D.new()
	xr_origin.add_child(xr_camera)
	
	# Check if VR is actually active
	var main = get_tree().root.find_child("Main", true, false)
	var vr_manager = null
	if main: vr_manager = main.get_node_or_null("VRManager")
	
	if vr_manager and vr_manager.has_method("is_vr_active") and vr_manager.is_vr_active():
		print("Drone: VR Mode detected, configuring headset view.")
		is_first_person = true # Force FPV in VR
	else:
		xr_origin.visible = false

func update_camera_views():
	var main = get_tree().root.find_child("Main", true, false)
	var vr_manager = null
	if main: vr_manager = main.get_node_or_null("VRManager")
	var is_vr = vr_manager and vr_manager.has_method("is_vr_active") and vr_manager.is_vr_active()

	if is_vr:
		# In VR, we always use the XR Camera when in FPV
		third_person_camera.current = false
		first_person_camera.current = false
		# Note: XRCamera3D doesn't need 'current = true' as much as use_xr = true handles it,
		# but we hide the standard ones.
	else:
		third_person_camera.current = !is_first_person
		first_person_camera.current = is_first_person

func _physics_process(delta):
	if get_tree().paused: return
	
	# 1. Inputs (Works for Keyboard + Xbox natively via Action Map)
	var target = Vector4(
		Input.get_axis("throttle_down", "throttle_up"),
		Input.get_axis("turn_left", "turn_right"),
		Input.get_axis("move_back", "move_forward"),
		Input.get_axis("move_left", "move_right")
	)
	
	smoothed_input = smoothed_input.lerp(target, delta * INPUT_SMOOTHING)

	# Fill audio buffer
	fill_motor_buffer()

	# 2. MOVEMENT
	var local_up = global_transform.basis.y
	var vertical_thrust = local_up * smoothed_input.x * THROTTLE_POWER
	var forward_force = -global_transform.basis.z * smoothed_input.z * FORWARD_POWER
	var strafe_force = global_transform.basis.x * smoothed_input.w * FORWARD_POWER
	
	apply_central_force(vertical_thrust + forward_force + strafe_force)

	# 3. Rotation
	apply_torque(global_transform.basis.x * -smoothed_input.z * TURN_POWER)
	apply_torque(global_transform.basis.z * -smoothed_input.w * TURN_POWER)
	apply_torque(global_transform.basis.y * -smoothed_input.y * TURN_POWER)
	
	# 4. Stabilization
	var up = global_transform.basis.y
	var correction = up.cross(Vector3.UP)
	apply_torque(correction * STABILIZE_FORCE)
	
	# Props
	for prop in $Design/Props.get_children():
		prop.rotate_y(delta * 30.0)

func _process(_delta):
	if get_tree().paused: return
	
	if camera_toggle_cooldown > 0:
		camera_toggle_cooldown -= _delta
	
	if Input.is_key_pressed(KEY_C) and camera_toggle_cooldown <= 0:
		is_first_person = !is_first_person
		update_camera_views()
		camera_toggle_cooldown = 0.2
	
	if Input.is_key_pressed(KEY_R): get_tree().reload_current_scene()

func setup_drone_audio():
	# 1. Continuous Motor Sound
	motor_audio = AudioStreamPlayer3D.new()
	var generator = AudioStreamGenerator.new()
	generator.buffer_length = 0.1
	motor_audio.stream = generator
	motor_audio.unit_size = 5.0
	motor_audio.max_distance = 100.0
	add_child(motor_audio)
	motor_audio.play()
	motor_playback = motor_audio.get_stream_playback()
	
	# 2. Crash Sound Generator
	crash_audio = AudioStreamPlayer3D.new()
	var crash_gen = AudioStreamGenerator.new()
	crash_gen.buffer_length = 0.05
	crash_audio.stream = crash_gen
	add_child(crash_audio)
	crash_playback = crash_audio.get_stream_playback()

func _on_drone_collision(_body):
	# Calculate impact intensity based on velocity
	var impact = linear_velocity.length()
	if impact > 1.5: # Lower threshold to catch more bumps
		play_crash_sound(impact)

func play_crash_sound(intensity: float):
	if crash_playback == null: return
	
	# Push a short, sharp burst of noise for the 'thud'
	var vol = clamp(intensity / 10.0, 0.2, 0.5) 
	var frames_to_push = 2205 # ~50ms of sound
	
	for i in range(frames_to_push):
		var sample = (randf() * 2.0 - 1.0) * vol
		# Rapid decay for the thud effect
		sample *= (1.0 - float(i) / frames_to_push)
		crash_playback.push_frame(Vector2(sample, sample))
	
	if not crash_audio.playing:
		crash_audio.play()

func fill_motor_buffer():
	if motor_playback == null: return
	
	var n = motor_playback.get_frames_available()
	# Gentle hum range
	var throttle = clamp(smoothed_input.x, 0.0, 1.0)
	var freq = 60.0 + (throttle * 120.0) 
	var volume = 0.005 + (throttle * 0.015) # Near-silent base volume
	
	while n > 0:
		# Very soft layered sines
		var sample = sin(motor_phase * TAU)
		sample += sin(motor_phase * 2.0 * TAU) * 0.3
		sample *= volume
		
		# Prevent clipping and filter out peaks
		if not is_inf(sample) and not is_nan(sample):
			motor_playback.push_frame(Vector2(sample, sample))
		
		motor_phase = fmod(motor_phase + freq / audio_hz, 1.0)
		n -= 1
