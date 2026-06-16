extends RigidBody3D
class_name DroneController

# References to component nodes
@onready var design: Node3D = $Design
@onready var model_component: Node3D = $Design/Model
@onready var camera_component: Node3D = $Design/Cameras
@onready var physics_component: Node3D = $Physics
@onready var input_component: Node3D = $InputHandler
@onready var audio_component: Node3D = $Audio

# Configuration
@export var throttle_power: float = 180.0
@export var forward_power: float = 120.0
@export var turn_power: float = 18.0
@export var stabilize_force: float = 45.0
@export var input_smoothing: float = 3.5
@export var audio_enabled: bool = true

var collision_shape: CollisionShape3D

func _ready():
	# Physics setup
	mass = 5.0
	gravity_scale = 1.0
	linear_damp = 2.0
	angular_damp = 8.0
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# Collision
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_collision)
	
	collision_shape = CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	collision_shape.shape.size = Vector3(1.2, 0.2, 1.2)
	add_child(collision_shape)
	
	# Initialize components
	if model_component and model_component.has_method("initialize"):
		model_component.initialize()
	if camera_component and camera_component.has_method("initialize"):
		camera_component.initialize()
	if physics_component and physics_component.has_method("initialize"):
		physics_component.initialize(throttle_power, forward_power, turn_power, stabilize_force)
	if input_component and input_component.has_method("initialize"):
		input_component.initialize(input_smoothing)
	if audio_component and audio_component.has_method("initialize"):
		audio_component.initialize()
	if audio_component and audio_component.has_method("set_audio_enabled"):
		audio_component.set_audio_enabled(audio_enabled)

func _physics_process(delta):
	if get_tree().paused:
		return
	
	# Get smoothed input from input component
	var smoothed_input = input_component.get_smoothed_input(delta) if input_component else Vector4.ZERO
	
	# Apply physics
	if physics_component:
		physics_component.apply_forces(self, smoothed_input, delta)
	
	# Animate propellers
	if model_component:
		var prop_speed = 30.0 + (smoothed_input.x * 60.0)
		model_component.animate_propellers(delta, prop_speed)
	
	# Handle audio
	if audio_enabled and audio_component:
		audio_component.update_audio(smoothed_input.x)

func _process(delta):
	if get_tree().paused:
		return
	
	# Camera toggle
	if Input.is_key_pressed(KEY_C) and not camera_component.is_cooldown_active():
		camera_component.toggle_view()
	
	# Reload scene
	if Input.is_key_pressed(KEY_R):
		get_tree().reload_current_scene()

func _on_collision(body):
	if audio_enabled and audio_component and audio_component.has_method("play_crash"):
		var impact = linear_velocity.length()
		if impact > 1.5:
			audio_component.play_crash(impact)

# Public methods for configuration
func set_initial_position(pos: Vector3):
	global_position = pos

func set_config(config: Dictionary):
	if "throttle_power" in config:
		throttle_power = config.throttle_power
	if "forward_power" in config:
		forward_power = config.forward_power
	if "turn_power" in config:
		turn_power = config.turn_power
	if "stabilize_force" in config:
		stabilize_force = config.stabilize_force
	if "input_smoothing" in config:
		input_smoothing = config.input_smoothing
	if "audio_enabled" in config:
		audio_enabled = config.audio_enabled
		if audio_component and audio_component.has_method("set_audio_enabled"):
			audio_component.set_audio_enabled(audio_enabled)

func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled
	if audio_component and audio_component.has_method("set_audio_enabled"):
		audio_component.set_audio_enabled(enabled)
