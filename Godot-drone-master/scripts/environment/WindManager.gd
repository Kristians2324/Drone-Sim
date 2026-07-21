extends Node3D
class_name WindManager

signal wind_changed(direction: Vector3, strength: float, gust_factor: float, state_name: String)

enum WindState { CALM, NORMAL, HEAVY }

@export var wind_enabled: bool = true
@export var calm_speed_range: Vector2 = Vector2(0.0, 0.8)
@export var normal_speed_range: Vector2 = Vector2(0.8, 2.8)
@export var heavy_speed_range: Vector2 = Vector2(2.8, 7.0)
@export var state_min_duration: Vector2 = Vector2(8.0, 20.0)
@export var gust_strength_range: Vector2 = Vector2(0.15, 0.65)
@export var gust_interval_range: Vector2 = Vector2(3.0, 9.0)

var current_state: int = WindState.NORMAL
var wind_direction: Vector3 = Vector3(1, 0, 0)
var wind_speed_mps: float = 1.4
var gust_factor: float = 0.25

# Smooth direction tracking — we lerp toward a target direction over time
var _target_direction: Vector3 = Vector3(1, 0, 0)
var _direction_change_speed: float = 0.08  # radians-equivalent blend speed

# Turbulence state — two independent noise phases for X and Z axes
var _turb_phase_x: float = 0.0
var _turb_phase_z: float = 0.0
var _turb_speed_x: float = 0.73
var _turb_speed_z: float = 0.51
var _turb_amplitude: float = 0.12   # how much turbulence shifts the direction

var _state_timer: float = 0.0
var _gust_timer: float = 0.0
var _gust_duration: float = 0.0
var _gust_active: bool = false
var _gust_peak: float = 0.0
var _gust_phase: float = 0.0   # 0→1 across the gust envelope

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_pick_new_state(true)
	call_deferred("_emit_current_state")

func _physics_process(delta: float) -> void:
	if not wind_enabled:
		return

	_state_timer -= delta
	_gust_timer  -= delta

	# ── Turbulence noise (independent per axis) ──────────────────────────
	_turb_phase_x += delta * _turb_speed_x
	_turb_phase_z += delta * _turb_speed_z
	var turb_x := sin(_turb_phase_x * 1.0) * 0.6 + sin(_turb_phase_x * 2.7) * 0.25 + sin(_turb_phase_x * 5.1) * 0.15
	var turb_z := sin(_turb_phase_z * 1.0) * 0.6 + cos(_turb_phase_z * 2.3) * 0.25 + sin(_turb_phase_z * 4.9) * 0.15

	# ── Smoothly lerp wind direction toward target ────────────────────────
	# Add small turbulence perturbation on top of base target direction
	var perturbed := _target_direction + Vector3(turb_x * _turb_amplitude, 0.0, turb_z * _turb_amplitude)
	if not perturbed.is_zero_approx():
		perturbed = perturbed.normalized()
	wind_direction = wind_direction.lerp(perturbed, _direction_change_speed).normalized()

	# ── Gust envelope (bell-curve shaped) ───────────────────────────────
	if _gust_timer <= 0.0:
		_start_gust()

	if _gust_active:
		_gust_phase += delta / maxf(_gust_duration, 0.01)
		if _gust_phase >= 1.0:
			_gust_active = false
			_gust_phase = 0.0
			gust_factor = _state_gust_baseline()
		else:
			# Smooth bell: rise quickly, hold, fall slowly
			var env := sin(_gust_phase * PI)
			gust_factor = clampf(_state_gust_baseline() + env * _gust_peak, 0.0, 1.0)
	else:
		# Drift gust factor back to state baseline
		gust_factor = move_toward(gust_factor, _state_gust_baseline(), delta * 0.3)

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
		WindState.CALM:   return "Calm"
		WindState.NORMAL: return "Normal"
		WindState.HEAVY:  return "Heavy"
		_:                return "Unknown"

func set_wind_enabled(enabled: bool) -> void:
	wind_enabled = enabled

func _pick_new_state(force_initial: bool = false) -> void:
	var roll := _rng.randf()

	var new_dir := Vector3(
		_rng.randf_range(-1.0, 1.0),
		0.0,
		_rng.randf_range(-1.0, 1.0)
	).normalized()

	if roll < 0.28:
		current_state = WindState.CALM
		wind_speed_mps  = _rng.randf_range(calm_speed_range.x, calm_speed_range.y)
		_direction_change_speed = 0.04   # Calm = very slow drift
		_turb_amplitude = 0.05
	elif roll < 0.82:
		current_state = WindState.NORMAL
		wind_speed_mps  = _rng.randf_range(normal_speed_range.x, normal_speed_range.y)
		_direction_change_speed = 0.08
		_turb_amplitude = 0.12
	else:
		current_state = WindState.HEAVY
		wind_speed_mps  = _rng.randf_range(heavy_speed_range.x, heavy_speed_range.y)
		_direction_change_speed = 0.15   # Heavy = quicker direction shifts
		_turb_amplitude = 0.22

	_target_direction = new_dir
	_state_timer  = _rng.randf_range(state_min_duration.x, state_min_duration.y) * (0.6 if force_initial else 1.0)
	_gust_timer   = _rng.randf_range(gust_interval_range.x, gust_interval_range.y)
	_gust_active  = false
	_gust_phase   = 0.0
	gust_factor   = _state_gust_baseline()
	wind_changed.emit(wind_direction, get_wind_strength(), gust_factor, get_state_name())

func _emit_current_state() -> void:
	wind_changed.emit(wind_direction, get_wind_strength(), gust_factor, get_state_name())

func _start_gust() -> void:
	_gust_timer    = _rng.randf_range(gust_interval_range.x, gust_interval_range.y)
	_gust_duration = _rng.randf_range(1.5, 4.0)
	_gust_peak     = _rng.randf_range(0.12, 0.45)
	_gust_phase    = 0.0
	_gust_active   = true
	# Gusts can slightly shift direction target
	var gust_dir_nudge := Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
	_target_direction = (_target_direction + gust_dir_nudge).normalized()

func _gust_strength() -> float:
	match current_state:
		WindState.CALM:   return lerp(gust_strength_range.x, gust_strength_range.y * 0.5, 0.2)
		WindState.NORMAL: return lerp(gust_strength_range.x, gust_strength_range.y, 0.6)
		WindState.HEAVY:  return gust_strength_range.y * 1.25
		_:                return gust_strength_range.y

func _state_gust_baseline() -> float:
	match current_state:
		WindState.CALM:   return 0.06
		WindState.NORMAL: return 0.22
		WindState.HEAVY:  return 0.50
		_:                return 0.22