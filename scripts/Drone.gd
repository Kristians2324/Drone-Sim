extends RigidBody3D

# --- POWERFUL SMOOTH FLIGHT CONFIG ---
const THROTTLE_POWER = 180.0   
const FORWARD_POWER = 120.0    
const TURN_POWER = 18.0
const STABILIZE_FORCE = 45.0
const INPUT_SMOOTHING = 3.5
const HOVER_MIN_CLEARANCE = 2.0
const HOVER_HOLD_FORCE = 55.0
const HOVER_HOLD_DAMPING = 12.0
const HOVER_MAX_HOLD_FORCE = 90.0
const MAX_PITCH_DEGREES = 30.0
const MAX_TILT_DEGREES = 35.0
const WIND_FORCE_SCALE = 18.0
const WIND_LIFT_SCALE = 2.4
const WIND_DRAG_SCALE = 0.45
const WIND_HOVER_BOBBLE_SCALE = 1.35
const WIND_ROTATION_SCALE = 0.28

# DJI Mini 4K-inspired battery behavior:
# - About 20 minutes of flight under normal use
# - Drain rate increases with aggressive maneuvering / high thrust
# - Low battery warning and automatic landing reserve near the end
const BATTERY_CAPACITY_MINUTES := 20.0
const BATTERY_DRAIN_PER_SECOND := 100.0 / (BATTERY_CAPACITY_MINUTES * 60.0)
const BATTERY_AGGRESSIVE_DRAIN_MULTIPLIER := 1.85
const BATTERY_HOVER_DRAIN_MULTIPLIER := 0.72
const BATTERY_LOW_WARNING_PERCENT := 20.0
const BATTERY_CRITICAL_PERCENT := 8.0
const BATTERY_AUTO_LAND_PERCENT := 3.0
const BATTERY_CONTROL_SLOWDOWN_START_PERCENT := 12.0

var smoothed_input = Vector4.ZERO # throttle, yaw, pitch, roll
var hover_enabled = false
var speed_multiplier: float = 1.0
var wind_velocity: Vector3 = Vector3.ZERO
var wind_strength: float = 0.0
var wind_gust_factor: float = 0.25
var wind_state_name: String = "Normal"
var wind_phase: float = 0.0

var low_cost_mode: bool = false
var battery_percent: float = 100.0
var battery_low_warning: bool = false
var battery_critical: bool = false
var battery_auto_landing: bool = false
var battery_failed: bool = false
var battery_exhausted: bool = false
var battery_recharging: bool = false

func set_swarm_mode_active(active: bool):
	speed_multiplier = 1.6 if active else 1.0
	if active:
		set_low_cost_mode(true)
	else:
		set_low_cost_mode(low_cost_mode)
	if is_instance_valid(design):
		design.visible = !active
	if is_instance_valid(show_rig):
		show_rig.visible = true
		show_rig.set_show_lighting_enabled(not active and not low_cost_mode)

func set_low_cost_mode(enabled: bool) -> void:
	low_cost_mode = enabled
	if is_instance_valid(show_rig):
		show_rig.set_low_cost_mode(enabled)
		show_rig.visible = true
		if speed_multiplier > 1.0:
			show_rig.set_show_lighting_enabled(false)
	if is_instance_valid(design) and speed_multiplier <= 1.0:
		design.visible = true

func set_low_detail_visuals(enabled: bool) -> void:
	low_detail_visuals = enabled
	if is_instance_valid(show_rig):
		show_rig.visible = true

func set_show_lighting_enabled(enabled: bool) -> void:
	if is_instance_valid(show_rig):
		show_rig.set_show_lighting_enabled(enabled)

@onready var design = $Design
@onready var collision_shape: CollisionShape3D = $Collision
var drone_model: Node3D
var propellers: Array[Node3D] = []
var show_rig: DroneShowLightRig
var low_detail_visuals: bool = false
const CAMERA_COLLISION_LAYER := 1 << 31

func _ready():
	add_to_group("drone_quality_targets")
	# Prevent drones from colliding with the swarm camera rig.
	# The camera controller assigns the camera to a dedicated collision layer.
	collision_layer = 1
	collision_mask = collision_mask & ~CAMERA_COLLISION_LAYER
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
	
	# Find and initialize propellers from the built-in Godot scene model
	propellers.clear()
	var props_node = design.get_node_or_null("Props")
	if props_node:
		for prop in props_node.get_children():
			if prop is Node3D:
				propellers.append(prop)
		print("Drone: Found ", propellers.size(), " procedural propellers in the Godot model.")

	setup_show_lights()
	apply_hover_mode()

func replace_drone_model():
	print("Drone: Starting model replacement...")
	# Hide/Remove old procedural parts
	for child in design.get_children():
		if not child is Camera3D and not child is XROrigin3D:
			if child == show_rig:
				show_rig = null
			child.queue_free()
	
	# Load and instance the new model
	if not FileAccess.file_exists("res://Drone.gltf"):
		push_error("Drone: Drone.gltf NOT FOUND in res://")
		return
		
	var model_scene: PackedScene = load("res://Drone.gltf")
	if model_scene:
		drone_model = model_scene.instantiate()
		design.add_child(drone_model)
		design.visible = true
		
		# Center the model
		var model_aabb: AABB = _center_spline_model(drone_model)
		
		# Auto-scale to a reasonable 3.5m wingspan
		var max_dim: float = max(model_aabb.size.x, model_aabb.size.z)
		if max_dim > 0:
			var target_scale = 3.5 / max_dim 
			drone_model.scale = Vector3(target_scale, target_scale, target_scale)
			print("Drone: Applied reasonable scale: ", target_scale)
		else:
			drone_model.scale = Vector3(2.5, 2.5, 2.5)
			
		# Shrink the central body block
		var central_cube: Node3D = drone_model.find_child("Cube*", true, false)
		if not central_cube: central_cube = drone_model.find_child("*Cube*", true, false)
		if central_cube:
			central_cube.scale *= 0.4 
			print("Drone: Shrunk central body node: ", central_cube.name)
			
		drone_model.rotation_degrees.y = 180 
		
		# Find propellers
		propellers.clear()
		_find_propellers(drone_model)
		print("Drone: Model loaded successfully. Found ", propellers.size(), " propellers.")

		if propellers.size() == 0:
			print("Drone: No propellers found by name, attempting fallback by height...")
			_find_propellers_fallback(drone_model)
			print("Drone: Fallback found ", propellers.size(), " potential propellers.")

		setup_show_lights()
	else:
		push_error("Drone: Failed to load Drone.gltf as a scene.")

func _center_spline_model(model: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_get_all_meshes(model, meshes)
	
	var aabb = AABB()
	var first = true
	
	for mesh in meshes:
		var mesh_transform = model.global_transform.affine_inverse() * mesh.global_transform
		var mesh_aabb = mesh_transform * mesh.get_aabb()
		
		if first:
			aabb = mesh_aabb
			first = false
		else:
			aabb = aabb.merge(mesh_aabb)
	
	if not first:
		var center = aabb.get_center()
		for child in model.get_children():
			if child is Node3D:
				child.position -= center
		print("Drone: Auto-centered Spline model. Offset by: ", -center)
		aabb.position -= center
		return aabb
		
	return AABB()

func _get_all_meshes(node: Node, meshes: Array[MeshInstance3D]):
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_get_all_meshes(child, meshes)

func _find_propellers_fallback(node):
	if node is MeshInstance3D:
		var name_lower = node.name.to_lower()
		if "cylinder" in name_lower:
			propellers.append(node)
	
	for child in node.get_children():
		_find_propellers_fallback(child)

func _find_propellers(node):
	var name_lower = node.name.to_lower()
	var is_prop = "prop" in name_lower or "blade" in name_lower or "rotor" in name_lower or "helix" in name_lower or "fan" in name_lower
	
	if is_prop and node is Node3D:
		propellers.append(node)
	
	for child in node.get_children():
		_find_propellers(child)

func _physics_process(delta):
	if get_tree().paused: return
	if battery_exhausted:
		_apply_battery_lockout()
		return

	wind_phase += delta * (1.2 + wind_strength * 0.08)
	_update_battery(delta)

	_apply_input_forces(delta, smoothed_input)

	if battery_auto_landing:
		# Simulate DJI-style reserve behavior by softening control response as battery gets extremely low.
		smoothed_input.y = 0.0
		smoothed_input.z = 0.0
		smoothed_input.w = 0.0

var smoothed_input_internal = Vector4.ZERO

func _apply_input_forces(delta, input_vec: Vector4):
	smoothed_input_internal = smoothed_input_internal.lerp(input_vec, delta * INPUT_SMOOTHING)

	var local_up = Vector3.UP if hover_enabled else global_transform.basis.y
	var forward_dir = -global_transform.basis.z
	var strafe_dir = global_transform.basis.x
	if hover_enabled:
		forward_dir.y = 0.0
		strafe_dir.y = 0.0
		if not forward_dir.is_zero_approx():
			forward_dir = forward_dir.normalized()
		if not strafe_dir.is_zero_approx():
			strafe_dir = strafe_dir.normalized()

	var vertical_thrust = local_up * smoothed_input_internal.x * THROTTLE_POWER * speed_multiplier
	var forward_force = forward_dir * smoothed_input_internal.z * FORWARD_POWER * speed_multiplier
	var strafe_force = strafe_dir * smoothed_input_internal.w * FORWARD_POWER * speed_multiplier
	var wind_force := Vector3.ZERO
	var wind_bobble := Vector3.ZERO
	var wind_drag_factor := 1.0

	if wind_strength > 0.0:
		var wind_dir := wind_velocity.normalized() if not wind_velocity.is_zero_approx() else Vector3.ZERO
		if not wind_dir.is_zero_approx():
			var forward_component := -forward_dir.dot(wind_dir)
			var right_component := strafe_dir.dot(wind_dir)
			var up_component := Vector3.UP.dot(wind_dir)
			wind_drag_factor = clamp(1.0 - forward_component * WIND_DRAG_SCALE, 0.55, 1.35)
			var gust := 0.65 + (wind_gust_factor * 0.9) + (sin(wind_phase * 1.7) * 0.15)
			wind_force = wind_dir * (wind_strength * WIND_FORCE_SCALE * gust)
			wind_force += Vector3.UP * (wind_strength * WIND_LIFT_SCALE * (0.35 + wind_gust_factor * 0.65) * sin(wind_phase * 2.6))
			wind_force += strafe_dir * (wind_strength * right_component * 2.0 * gust)
			wind_force += forward_dir * (wind_strength * forward_component * 1.2 * gust)
			if hover_enabled:
				wind_bobble = Vector3(
					wind_strength * right_component * WIND_HOVER_BOBBLE_SCALE * sin(wind_phase * 2.2),
					wind_strength * WIND_HOVER_BOBBLE_SCALE * 0.45 * sin(wind_phase * 3.4),
					wind_strength * forward_component * WIND_HOVER_BOBBLE_SCALE * cos(wind_phase * 1.8)
				)

	forward_force *= wind_drag_factor
	strafe_force *= lerp(wind_drag_factor, 1.0, 0.2)
	vertical_thrust += wind_force * 0.12

	apply_central_force(vertical_thrust + forward_force + strafe_force + wind_force + wind_bobble)

	if hover_enabled:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var from = global_position + Vector3.UP * 0.1
			var to = global_position + Vector3.DOWN * 20.0
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.exclude = [get_rid()]
			var result = space_state.intersect_ray(query)
			if result.has("position"):
				var ground_distance = global_position.y - result.position.y
				if ground_distance < HOVER_MIN_CLEARANCE:
					var hover_force = (HOVER_MIN_CLEARANCE - ground_distance) * HOVER_HOLD_FORCE
					hover_force -= linear_velocity.y * HOVER_HOLD_DAMPING
					hover_force = clamp(hover_force, 0.0, HOVER_MAX_HOLD_FORCE)
					apply_central_force(Vector3.UP * hover_force)

	apply_torque(global_transform.basis.x * (-smoothed_input_internal.z * TURN_POWER * speed_multiplier + wind_force.z * WIND_ROTATION_SCALE))
	apply_torque(global_transform.basis.z * (-smoothed_input_internal.w * TURN_POWER * speed_multiplier + wind_force.x * WIND_ROTATION_SCALE))
	apply_torque(global_transform.basis.y * -smoothed_input_internal.y * TURN_POWER * speed_multiplier)

	var up = global_transform.basis.y
	var correction = up.cross(Vector3.UP)
	
	var current_stabilize = STABILIZE_FORCE
	if abs(smoothed_input_internal.z) < 0.05 and abs(smoothed_input_internal.w) < 0.05:
		current_stabilize = STABILIZE_FORCE * 3.0
		
	apply_torque(correction * current_stabilize)

	# Keep the drone within the configured attitude limits.
	var current_pitch = rad_to_deg(get_rotation().x)
	var current_tilt = max(abs(rad_to_deg(get_rotation().z)), abs(rad_to_deg(get_rotation().x)))
	if abs(current_pitch) > MAX_PITCH_DEGREES:
		var pitch_correction = clamp(-current_pitch * 0.05, -1.0, 1.0)
		apply_torque(global_transform.basis.x * pitch_correction * TURN_POWER * speed_multiplier)
	if current_tilt > MAX_TILT_DEGREES:
		var tilt_error = current_tilt - MAX_TILT_DEGREES
		var tilt_correction = clamp(tilt_error * 0.05, 0.0, 1.0)
		apply_torque(global_transform.basis.z * tilt_correction * TURN_POWER * speed_multiplier)

	# Keep hover mode visibly alive in the wind without making it uncontrollable.
	if hover_enabled and wind_strength > 0.0:
		apply_torque(global_transform.basis.x * sin(wind_phase * 2.0) * wind_strength * 0.9)
		apply_torque(global_transform.basis.z * cos(wind_phase * 1.6) * wind_strength * 0.9)

	var prop_speed = 30.0 + (smoothed_input_internal.x * 60.0)
	for prop in propellers:
		prop.rotate_y(delta * prop_speed)

	var legacy_props = design.get_node_or_null("Props")
	if legacy_props:
		for prop in legacy_props.get_children():
			prop.rotate_y(delta * prop_speed)

func set_input_vector(input_vec: Vector4) -> void:
	if battery_exhausted:
		smoothed_input = Vector4.ZERO
		return
	smoothed_input = input_vec

func get_battery_percent() -> float:
	return battery_percent

func is_battery_low_warning() -> bool:
	return battery_low_warning

func is_battery_critical() -> bool:
	return battery_critical

func is_battery_auto_landing() -> bool:
	return battery_auto_landing

func is_battery_empty() -> bool:
	return battery_exhausted

func recharge_battery() -> void:
	battery_percent = 100.0
	battery_low_warning = false
	battery_critical = false
	battery_auto_landing = false
	battery_failed = false
	battery_exhausted = false
	battery_recharging = false
	print("Drone: Battery recharged to 100%.")

func start_battery_recharge() -> void:
	battery_recharging = true
	battery_auto_landing = true
	battery_low_warning = true
	battery_critical = true
	battery_exhausted = false
	set_sleeping(false)
	gravity_scale = 0.0 if hover_enabled else 1.0
	print("Drone: Recharge sequence started.")

func set_battery_percent(value: float) -> void:
	battery_percent = clamp(value, 0.0, 100.0)
	battery_low_warning = battery_percent <= BATTERY_LOW_WARNING_PERCENT
	battery_critical = battery_percent <= BATTERY_CRITICAL_PERCENT
	battery_auto_landing = battery_percent <= BATTERY_AUTO_LAND_PERCENT
	battery_exhausted = battery_percent <= 0.01
	if battery_exhausted:
		_apply_battery_lockout()

func _update_battery(delta: float) -> void:
	if battery_exhausted:
		return

	if battery_recharging:
		battery_percent = min(100.0, battery_percent + (delta * 30.0))
		if battery_percent >= 100.0:
			recharge_battery()
		return

	var throttle_use: float = absf(smoothed_input.x)
	var maneuver_use: float = absf(smoothed_input.y) + absf(smoothed_input.z) + absf(smoothed_input.w)
	var drain_multiplier: float = 1.0

	# Hovering and gentle flight are a little more efficient, aggressive movement drains faster.
	if hover_enabled:
		drain_multiplier *= BATTERY_HOVER_DRAIN_MULTIPLIER
	if maneuver_use > 0.15 or throttle_use > 0.15:
		drain_multiplier *= lerp(1.0, BATTERY_AGGRESSIVE_DRAIN_MULTIPLIER, clamp(max(throttle_use, maneuver_use) / 2.0, 0.0, 1.0))

	# Higher speed multipliers represent heavier workloads and slightly faster battery loss.
	drain_multiplier *= lerp(1.0, 1.12, clamp(speed_multiplier - 1.0, 0.0, 1.0))

	battery_percent = max(0.0, battery_percent - (BATTERY_DRAIN_PER_SECOND * drain_multiplier * delta))

	var was_low_warning = battery_low_warning
	var was_critical = battery_critical
	var was_auto_landing = battery_auto_landing

	battery_low_warning = battery_percent <= BATTERY_LOW_WARNING_PERCENT
	battery_critical = battery_percent <= BATTERY_CRITICAL_PERCENT
	battery_auto_landing = battery_percent <= BATTERY_AUTO_LAND_PERCENT
	if battery_percent <= 0.01:
		battery_exhausted = true
		battery_failed = true
		battery_percent = 0.0

	if battery_low_warning and not was_low_warning:
		print("Drone: Battery low (", snappedf(battery_percent, 0.1), "%)")
	if battery_critical and not was_critical:
		print("Drone: Battery critical (", snappedf(battery_percent, 0.1), "%)")
	if battery_auto_landing and not was_auto_landing:
		print("Drone: Battery reserve reached - auto landing recommended.")

	if battery_auto_landing:
		# Reduce available power to mimic the final reserve behavior of consumer drones.
		var low_battery_scale := _get_low_battery_control_scale()
		speed_multiplier = min(speed_multiplier, low_battery_scale)
		gravity_scale = 1.0
		if not hover_enabled:
			hover_enabled = true
			apply_hover_mode()
		# Keep the drone from drifting into a hard crash when the battery is nearly empty.
		linear_velocity *= low_battery_scale
		angular_velocity *= low_battery_scale

	if battery_exhausted:
		_apply_battery_lockout()

func _get_low_battery_control_scale() -> float:
	if battery_percent <= BATTERY_CONTROL_SLOWDOWN_START_PERCENT:
		var t := clampf(battery_percent / BATTERY_CONTROL_SLOWDOWN_START_PERCENT, 0.0, 1.0)
		return lerp(0.55, 1.0, t)
	return 1.0

func _apply_battery_lockout() -> void:
	smoothed_input = Vector4.ZERO
	smoothed_input_internal = Vector4.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gravity_scale = 0.0
	hover_enabled = false
	set_sleeping(true)


func apply_hover_mode():
	gravity_scale = 0.0 if hover_enabled else 1.0

func set_wind_profile(direction: Vector3, strength: float, gust_factor: float, state_name: String) -> void:
	wind_velocity = direction.normalized() if not direction.is_zero_approx() else Vector3.ZERO
	wind_strength = maxf(strength, 0.0)
	wind_gust_factor = clampf(gust_factor, 0.0, 1.0)
	wind_state_name = state_name

func set_wind(direction: Vector3, strength: float) -> void:
	set_wind_profile(direction, strength, wind_gust_factor, wind_state_name)

func get_propeller_count() -> int:
	return propellers.size()

func setup_show_lights():
	if show_rig != null:
		return

	show_rig = DroneShowLightRig.new()
	show_rig.name = "ShowLights"
	show_rig.position = Vector3(0, -0.18, 0)
	add_child(show_rig)
	show_rig.configure(0, 1, true)
	show_rig.set_low_cost_mode(low_cost_mode or speed_multiplier > 1.0)

func _on_drone_collision(_body):
	if _body and _body.has_method("set_input_vector"):
		return
	var impact = linear_velocity.length()
	# Audio intentionally disabled: drone is silent.
