extends Node
class_name DroneInput

signal input_sampled(input: Vector4)

var input_smoothing: float
var smoothed_input = Vector4.ZERO

func initialize(smoothing: float):
	input_smoothing = smoothing

func get_smoothed_input(delta: float) -> Vector4:
	var target = Vector4(
		Input.get_axis("throttle_down", "throttle_up"),
		Input.get_axis("turn_left", "turn_right"),
		Input.get_axis("move_back", "move_forward"),
		Input.get_axis("move_left", "move_right")
	)
	
	smoothed_input = smoothed_input.lerp(target, delta * input_smoothing)
	input_sampled.emit(smoothed_input)
	return smoothed_input