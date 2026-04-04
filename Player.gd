extends XROrigin3D

@onready var camera = $XRCamera3D
@onready var left_target = $LeftHand
@onready var right_target = $RightHand

@onready var left_phys_hand = $LeftPhysicalHand
@onready var right_phys_hand = $RightPhysicalHand

@onready var left_grab_area = $LeftPhysicalHand/GrabArea
@onready var right_grab_area = $RightPhysicalHand/GrabArea

@onready var left_joint = $LeftPhysicalHand/Generic6DOFJoint3D
@onready var right_joint = $RightPhysicalHand/Generic6DOFJoint3D

const SPEED = 3.0
const SNAP_TURN_ANGLE = 45.0

var held_object_left: RigidBody3D = null
var held_object_right: RigidBody3D = null
var can_snap_turn = true

func _ready():
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

func _physics_process(delta):
	# 1. Physical Hand Following (Direct Position + Physics Move)
	update_phys_hand(left_phys_hand, left_target, delta)
	update_phys_hand(right_phys_hand, right_target, delta)

	# 2. Movement (Left Thumbstick)
	handle_movement(delta)

	# 3. Snap Turning (Right Thumbstick)
	handle_rotation(delta)

	# 4. Grabbing Logic (Using Joints for Stability)
	handle_grabbing(left_target, left_phys_hand, left_grab_area, left_joint, "held_object_left")
	handle_grabbing(right_target, right_phys_hand, right_grab_area, right_joint, "held_object_right")

func update_phys_hand(phys_hand: CharacterBody3D, target: XRController3D, delta: float):
	var target_pos = target.global_transform.origin
	var current_pos = phys_hand.global_transform.origin
	var diff = target_pos - current_pos
	
	# Use move_and_collide for solid feel
	phys_hand.velocity = diff / delta
	phys_hand.global_transform.basis = target.global_transform.basis
	phys_hand.move_and_slide()
	
	# Impulse physics for knocking things around
	for i in phys_hand.get_slide_collision_count():
		var collision = phys_hand.get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is RigidBody3D:
			var push_dir = -collision.get_normal()
			collider.apply_impulse(push_dir * phys_hand.velocity.length() * 0.15, collision.get_position() - collider.global_position)

func handle_movement(delta):
	var move_input = left_target.get_vector2("primary")
	if move_input.length() > 0.1:
		var forward = -camera.global_transform.basis.z
		var right_dir = camera.global_transform.basis.x
		forward.y = 0
		right_dir.y = 0
		forward = forward.normalized()
		right_dir = right_dir.normalized()
		
		# "Up" on stick moves you forward
		var move_dir = (forward * move_input.y + right_dir * move_input.x).normalized()
		global_translate(move_dir * SPEED * delta)

func handle_rotation(_delta):
	var rot_input = right_target.get_vector2("primary")
	if abs(rot_input.x) > 0.5:
		if can_snap_turn:
			var turn_dir = -1.0 if rot_input.x > 0 else 1.0
			rotate_y(deg_to_rad(SNAP_TURN_ANGLE * turn_dir))
			can_snap_turn = false
	else:
		can_snap_turn = true

func handle_grabbing(target: XRController3D, phys_hand: CharacterBody3D, area: Area3D, joint: Generic6DOFJoint3D, held_var_name: String):
	var is_gripping = target.is_button_pressed("grip_click") or target.is_button_pressed("trigger_click")
	var held_object = get(held_var_name)

	if is_gripping:
		if not held_object:
			for body in area.get_overlapping_bodies():
				if body is RigidBody3D:
					# Grab detected!
					set(held_var_name, body)
					
					# Prevent hand from colliding with held object
					phys_hand.add_collision_exception_with(body)
					
					# Attach joint at current relative position for stability
					joint.node_a = phys_hand.get_path()
					joint.node_b = body.get_path()
					
					# Configure joint (lock all axes for stiff grab)
					joint.set("linear_limit_x/enabled", true)
					joint.set("linear_limit_y/enabled", true)
					joint.set("linear_limit_z/enabled", true)
					joint.set("angular_limit_x/enabled", true)
					joint.set("angular_limit_y/enabled", true)
					joint.set("angular_limit_z/enabled", true)
					
					target.trigger_haptic_pulse("haptic", 30.0, 1.0, 0.1, 0)
					break
	else:
		if held_object:
			# Release!
			phys_hand.remove_collision_exception_with(held_object)
			joint.node_a = NodePath("")
			joint.node_b = NodePath("")
			
			# Apply hand's velocity to the released object for throwing
			held_object.linear_velocity = phys_hand.velocity
			
			set(held_var_name, null)
