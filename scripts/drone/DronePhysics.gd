extends Node
class_name DronePhysics

var throttle_power: float
var forward_power: float
var turn_power: float
var stabilize_force: float

func initialize(throttle: float, forward: float, turn: float, stabilize: float):
	throttle_power = throttle
	forward_power = forward
	turn_power = turn
	stabilize_force = stabilize

func apply_forces(body: RigidBody3D, input: Vector4, delta: float):
	var local_up = body.global_transform.basis.y
	
	# Throttle
	var vertical_thrust = local_up * input.x * throttle_power
	
	# Movement
	var forward_force = -body.global_transform.basis.z * input.z * forward_power
	var strafe_force = body.global_transform.basis.x * input.w * forward_power
	
	body.apply_central_force(vertical_thrust + forward_force + strafe_force)
	
	# Rotation
	body.apply_torque(body.global_transform.basis.x * -input.z * turn_power)
	body.apply_torque(body.global_transform.basis.z * -input.w * turn_power)
	body.apply_torque(body.global_transform.basis.y * -input.y * turn_power)
	
	# Stabilization
	var up = body.global_transform.basis.y
	var correction = up.cross(Vector3.UP)
	body.apply_torque(correction * stabilize_force)