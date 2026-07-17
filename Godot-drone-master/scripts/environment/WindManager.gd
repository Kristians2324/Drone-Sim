extends Node3D
class_name WindManager

signal wind_changed(direction: Vector3, strength: float, gust_factor: float, state_name: String)

enum WindState { CALM, NORMAL, HEAVY }

@export var wind_enabled: bool = true
@export var calm_speed_range: Vector2 = Vector2(0.0, 0.8)
@export var normal_speed_range: Vector2 = Vector2(0.8, 2.8)
@export var heavy_speed_range: Vector2 = Vector2(2.8, 7.0)
@export var state_min_duration: Vector2 = Vector2(6.0, 16.0)
@export var gust_strength_range: Vector2 = Vector2(0.15, 0.65)
@export var gust_interval_range: Vector2 = Vector2(3.0, 9.0)

var current_state: int = WindState.NORMAL
var wind_direction: Vector3 = Vector3(1, 0, 0)
var wind_speed_mps: float = 1.4
var gust_factor: float = 0.25
var _state_timer: float = 0.0
var _gust_timer: float = 0.0
var _gust_duration: float = 0.0
var _gust_dir: float = 1.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_pick_new_state(true)
	# Ensure any listeners that connect slightly later still get a first visible update.
	call_deferred("_emit_current_state")

func _physics_process(delta: float) -> void:
	if not wind_enabled:
		return

	_state_timer -= delta
	_gust_timer -= delta
	if _gust_timer <= 0.0:
		_start_gust()

	if _gust_duration > 0.0:
		_gust_duration -= delta
		var gust_wave := sin((1.0 - clampf(_gust_duration / maxf(_gust_duration + delta, 0.01), 0.0, 1.0)) * PI)
		gust_factor = clampf(gust_factor + (_gust_dir * gust_wave * 0.03), 0.0, 1.0)
	else:
		gust_factor = move_toward(gust_factor, _state_gust_baseline(), delta * 0.25)

	wind_direction = wind_direction.rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.00018) * delta * 0.12).normalized()
	wind_speed_mps = maxf(_state_base_speed(), wind_speed_mps)
	var strength := get_wind_strength()
	wind_changed.emit(wind_direction, strength, gust_factor, get_state_name())

	if _state_timer <= 0.0:
		_pick_new_state()

func get_wind_vector() -> Vector3:
	return wind_direction * get_wind_strength()

func get_wind_strength() -> float:
	return wind_speed_mps + (gust_factor * _gust_strength())

func get_state_name() -> String:
	match current_state:
		WindState.CALM:
			return "Calm"
		WindState.NORMAL:
			return "Normal"
		WindState.HEAVY:
			return "Heavy"
		_:
			return "Unknown"

func set_wind_enabled(enabled: bool) -> void:
	wind_enabled = enabled

func _pick_new_state(force_initial: bool = false) -> void:
	var roll := _rng.randf()
	if roll < 0.28:
		current_state = WindState.CALM
		wind_speed_mps = _rng.randf_range(calm_speed_range.x, calm_speed_range.y)
		wind_direction = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
	elif roll < 0.82:
		current_state = WindState.NORMAL
		wind_speed_mps = _rng.randf_range(normal_speed_range.x, normal_speed_range.y)
		wind_direction = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
	else:
		current_state = WindState.HEAVY
		wind_speed_mps = _rng.randf_range(heavy_speed_range.x, heavy_speed_range.y)
		wind_direction = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()

	_state_timer = _rng.randf_range(state_min_duration.x, state_min_duration.y) * (0.6 if force_initial else 1.0)
	_gust_timer = _rng.randf_range(gust_interval_range.x, gust_interval_range.y)
	_gust_duration = 0.0
	gust_factor = _state_gust_baseline()
	wind_changed.emit(wind_direction, get_wind_strength(), gust_factor, get_state_name())

func _emit_current_state() -> void:
	wind_changed.emit(wind_direction, get_wind_strength(), gust_factor, get_state_name())

func _start_gust() -> void:
	_gust_timer = _rng.randf_range(gust_interval_range.x, gust_interval_range.y)
	_gust_duration = _rng.randf_range(1.5, 4.0)
	_gust_dir = -1.0 if _rng.randf() > 0.5 else 1.0
	gust_factor = clampf(_state_gust_baseline() + _rng.randf_range(0.1, 0.35), 0.0, 1.0)

func _state_base_speed() -> float:
	match current_state:
		WindState.CALM:
			return wind_speed_mps
		WindState.NORMAL:
			return wind_speed_mps
		WindState.HEAVY:
			return wind_speed_mps
		_:
			return wind_speed_mps

func _gust_strength() -> float:
	match current_state:
		WindState.CALM:
			return lerp(gust_strength_range.x, gust_strength_range.y * 0.5, 0.2)
		WindState.NORMAL:
			return lerp(gust_strength_range.x, gust_strength_range.y, 0.6)
		WindState.HEAVY:
			return gust_strength_range.y * 1.25
		_:
			return gust_strength_range.y

func _state_gust_baseline() -> float:
	match current_state:
		WindState.CALM:
			return 0.08
		WindState.NORMAL:
			return 0.25
		WindState.HEAVY:
			return 0.55
		_:
			return 0.25