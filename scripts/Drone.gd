extends RigidBody3D

const THRUST_FORCE = 15.0
const ROTATION_FORCE = 3.0
const STABILIZATION_FORCE = 2.0

@onready var left_controller: XRController3D
@onready var right_controller: XRController3D

func _ready():
	# Find VR controllers in the scene
	var xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		left_controller = xr_origin.get_node("LeftHand")
		right_controller = xr_origin.get_node("RightHand")

func _physics_process(delta):
	if not left_controller or not right_controller:
		return
	
	# Left controller thumbstick for thrust and basic movement
	var left_stick = left_controller.get_vector2("primary")
	
	# Right controller thumbstick for rotation
	var right_stick = right_controller.get_vector2("primary")
	
	# Thrust control (left stick Y axis)
	if abs(left_stick.y) > 0.1:
		apply_central_force(Vector3.UP * THRUST_FORCE * left_stick.y)
	
	# Forward/backward movement (left stick X axis)
	if abs(left_stick.x) > 0.1:
		var forward_force = global_transform.basis.z * ROTATION_FORCE * left_stick.x
		apply_central_force(forward_force)
	
	# Rotation controls (right stick)
	if abs(right_stick.x) > 0.1:
		apply_torque(Vector3.UP * ROTATION_FORCE * right_stick.x)
	
	if abs(right_stick.y) > 0.1:
		apply_torque(Vector3.RIGHT * ROTATION_FORCE * right_stick.y)
	
	# Basic stabilization - try to keep level when not actively rotating
	if abs(right_stick.x) < 0.1 and abs(right_stick.y) < 0.1:
		var current_rotation = global_transform.basis.get_euler()
		# Apply small counter-torques to stabilize
		apply_torque(Vector3(-current_rotation.x, -current_rotation.y, -current_rotation.z) * STABILIZATION_FORCE)