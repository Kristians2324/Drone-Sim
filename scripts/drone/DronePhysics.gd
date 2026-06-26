extends Node
class_name DronePhysics

var throttle_power: float
var forward_power: float
var turn_power: float
var stabilize_force: float
var max_acceleration: float = 6.0
var max_deceleration: float = 4.0
var wind_velocity: Vector3 = Vector3.ZERO
var wind_strength: float = 0.0
var wind_gust_phase: float = 0.0

func initialize(throttle: float, forward: float, turn: float, stabilize: float, accel: float = 6.0, decel: float = 4.0):
	throttle_power = throttle
	forward_power = forward
	turn_power = turn
	stabilize_force = stabilize
	max_acceleration = accel
	max_deceleration = decel

func set_wind(direction: Vector3, strength: float) -> void:
	wind_velocity = direction.normalized() if not direction.is_zero_approx() else Vector3.ZERO
	wind_strength = maxf(strength, 0.0)

func apply_forces(body: RigidBody3D, input: Vector4, delta: float):
	var local_up: Vector3 = body.global_transform.basis.y
	wind_gust_phase += delta * 0.85
	
	# Throttle
	var throttle_input: float = clamp(input.x, -1.0, 1.0)
	var vertical_thrust: Vector3 = local_up * throttle_input * throttle_power
	
	# Movement
	var forward_input: float = clamp(input.z, -1.0, 1.0)
	var strafe_input: float = clamp(input.w, -1.0, 1.0)
	var accel_limit: float = max_acceleration if throttle_input >= 0.0 else max_deceleration
	var forward_force: Vector3 = -body.global_transform.basis.z * forward_input * minf(forward_power, accel_limit)
	var strafe_force: Vector3 = body.global_transform.basis.x * strafe_input * minf(forward_power, accel_limit)

	# Wind influence: makes the drone feel faster/slower depending on direction.
	# When hovering, wind also nudges the drone slightly.
	var wind_force: Vector3 = Vector3.ZERO
	if wind_strength > 0.0:
		var wind_dir: Vector3 = wind_velocity
		var forward_component: float = -body.global_transform.basis.z.dot(wind_dir)
		var right_component: float = body.global_transform.basis.x.dot(wind_dir)
		var wind_scale: float = clamp(1.0 + forward_component * 1.0, 0.35, 1.65)
		var crosswind_scale: float = clamp(1.0 + abs(right_component) * 0.6, 0.75, 1.35)
		forward_force *= wind_scale
		strafe_force *= crosswind_scale
		var gust: float = 0.6 + 0.4 * sin(wind_gust_phase)
		wind_force = wind_dir * (wind_strength * 10.0 * gust)
		if body.has_method("get") and body.get("hover_enabled"):
			wind_force += wind_dir * (wind_strength * 4.0 * gust)
			wind_force += body.global_transform.basis.x * (wind_strength * 1.5 * sin(wind_gust_phase * 1.8))
	
	body.apply_central_force(vertical_thrust + forward_force + strafe_force + wind_force)
	
	# Rotation
	body.apply_torque(body.global_transform.basis.x * -input.z * turn_power)
	body.apply_torque(body.global_transform.basis.z * -input.w * turn_power)
	body.apply_torque(body.global_transform.basis.y * -input.y * turn_power)
	
	# Stabilization
	var up: Vector3 = body.global_transform.basis.y
	var correction: Vector3 = up.cross(Vector3.UP)
	body.apply_torque(correction * stabilize_force)