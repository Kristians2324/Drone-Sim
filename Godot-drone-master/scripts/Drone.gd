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
# Realistic light/moderate wind constants (was 18/2.4/0.45/1.35/0.28)
const WIND_FORCE_SCALE = 5.5
const WIND_LIFT_SCALE = 0.9
const WIND_DRAG_SCALE = 0.30
const WIND_HOVER_BOBBLE_SCALE = 0.55
const WIND_ROTATION_SCALE = 0.14
# Turbulence: independent frequency layers per axis
const WIND_TURB_SCALE = 0.85     # overall turbulence intensity
const WIND_TURB_FREQ_A = 1.90    # fast jitter
const WIND_TURB_FREQ_B = 0.65    # medium sway
const WIND_TURB_FREQ_C = 0.22    # slow drift

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
# Independent per-axis turbulence phases so X/Z wobble are never in sync
var _turb_phase_x: float = 0.0
var _turb_phase_z: float = 0.37
var _turb_phase_y: float = 0.71

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

var propeller_datas: Array[Dictionary] = []
var prop_rotation_angle: float = 0.0

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
	# Collide with everything in the world (obstacles on layer 1, terrain/hills on layer 2)
	collision_mask = 0xFFFFFFFF & ~CAMERA_COLLISION_LAYER
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
	
	# Replace with the new model automatically at startup
	replace_drone_model()
	apply_hover_mode()
	
	# ── Connect to WindManager so ALL drone instances receive live wind data ──
	# Deferred so the scene tree is fully ready when we search.
	call_deferred("_connect_wind_manager")

func _connect_wind_manager() -> void:
	var scene := get_tree().current_scene if get_tree() else null
	if scene == null:
		return
	var wm: WindManager = null
	var direct := scene.get_node_or_null("WindManager")
	if direct is WindManager:
		wm = direct as WindManager
	if wm == null:
		for child in scene.get_children():
			if child is WindManager:
				wm = child as WindManager
				break
			var nested := child.find_child("WindManager", true, false)
			if nested is WindManager:
				wm = nested as WindManager
				break
	if wm and wm.has_signal("wind_changed") and not wm.wind_changed.is_connected(set_wind_profile):
		wm.wind_changed.connect(set_wind_profile)
		# Apply current wind state immediately so there's no startup lag
		set_wind_profile(wm.wind_direction, wm.get_wind_strength(), wm.gust_factor, wm.get_state_name())

func replace_drone_model():
	print("Drone: Starting model replacement with assets/drone_model/scene.gltf...")
	# Hide/Remove old procedural parts
	for child in design.get_children():
		if not child is Camera3D and not child is XROrigin3D:
			if child == show_rig:
				show_rig = null
			child.queue_free()
	
	# Load and instance the model
	if not FileAccess.file_exists("res://assets/drone_model/scene.gltf"):
		push_error("Drone: scene.gltf NOT FOUND")
		return

	var model_scene: PackedScene = load("res://assets/drone_model/scene.gltf")
	if model_scene:
		drone_model = model_scene.instantiate()
		design.add_child(drone_model)
		design.visible = true

		# The GLTF fan blade meshes each contain ALL 4 blades in one mesh.
		# Spinning them individually sends 3 blades flying. Hide them all.
		var nodes_to_hide = ["Circle_16", "Fan_006_20"]
		for node_name in nodes_to_hide:
			var n = drone_model.find_child(node_name, true, false)
			if n:
				n.visible = false

		# Scale model to fit 1.3m wingspan
		var model_aabb: AABB = _center_spline_model(drone_model)
		var max_dim: float = max(model_aabb.size.x, model_aabb.size.z)
		var target_scale := 1.3 / max_dim if max_dim > 0 else 1.0
		drone_model.scale = Vector3(target_scale, target_scale, target_scale)
		print("Drone: Applied scale: ", target_scale)
		drone_model.rotation_degrees.y = 0

		# --- Procedural propeller discs ---
		# Positions from tree_output.txt (GLTF_SceneRootNode local space)
		var arm_positions: Array = [
			Vector3(-0.249101,  0.109929, -0.132448),  # Front-Left
			Vector3( 0.249100,  0.109079, -0.132448),  # Front-Right
			Vector3(-0.249101,  0.109079,  0.134621),  # Back-Left
			Vector3( 0.226978,  0.109079,  0.134621),  # Back-Right
		]

		var blade_mat := StandardMaterial3D.new()
		blade_mat.albedo_color = Color(0.08, 0.08, 0.08, 0.88)
		blade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blade_mat.metallic = 0.15
		blade_mat.roughness = 0.55

		propellers.clear()
		propeller_datas.clear()

		# Parent discs into GLTF_SceneRootNode so they share its coord system
		var scene_root_node = drone_model.find_child("GLTF_SceneRootNode", true, false)
		var disc_parent: Node3D = scene_root_node if scene_root_node else drone_model

		for i in range(4):
			var holder := Node3D.new()
			holder.name = "PropDisc_%d" % i
			holder.position = arm_positions[i]
			disc_parent.add_child(holder)

			# Thin disc base
			var disc := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius    = 0.1
			cyl.bottom_radius = 0.1
			cyl.height        = 0.005
			cyl.radial_segments = 20
			disc.mesh = cyl
			disc.material_override = blade_mat
			holder.add_child(disc)

			# Blade bar 1
			var b1 := MeshInstance3D.new()
			var b1m := BoxMesh.new()
			b1m.size = Vector3(0.185, 0.006, 0.032)
			b1.mesh = b1m
			b1.material_override = blade_mat
			holder.add_child(b1)

			# Blade bar 2 (cross)
			var b2 := MeshInstance3D.new()
			var b2m := BoxMesh.new()
			b2m.size = Vector3(0.032, 0.006, 0.185)
			b2.mesh = b2m
			b2.material_override = blade_mat
			holder.add_child(b2)

			propellers.append(holder)
			var data := {}
			data["node"] = holder
			data["original_transform"] = holder.transform
			propeller_datas.append(data)

		print("Drone: Model loaded. Created 4 procedural propeller discs.")
		setup_show_lights()
	else:
		push_error("Drone: Failed to load scene.gltf.")

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
	var is_prop = ("prop" in name_lower or "blade" in name_lower or "helix" in name_lower or "fan" in name_lower or "circle_16" in name_lower) and not "rotor" in name_lower
	
	if is_prop and node is Node3D:
		propellers.append(node)
	
	for child in node.get_children():
		_find_propellers(child)


func _get_mesh_child_recursively(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh:
		return node
	for child in node.get_children():
		var m = _get_mesh_child_recursively(child)
		if m != null:
			return m
	return null

func _physics_process(delta):
	if get_tree().paused: return
	if battery_exhausted:
		_apply_battery_lockout()
		return

	wind_phase += delta * (1.2 + wind_strength * 0.08)
	# Advance independent turbulence phases at different rates so X/Z never sync
	_turb_phase_x += delta * (WIND_TURB_FREQ_A + wind_strength * 0.06)
	_turb_phase_z += delta * (WIND_TURB_FREQ_B + wind_strength * 0.04)
	_turb_phase_y += delta * (WIND_TURB_FREQ_C + wind_strength * 0.02)
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
			var right_component   := strafe_dir.dot(wind_dir)

			# Drag slightly reduces forward speed into the wind
			wind_drag_factor = clampf(1.0 - forward_component * WIND_DRAG_SCALE, 0.60, 1.25)

			# Gust envelope — peaks when gust_factor is high, adds sine shimmer
			var gust_env := 0.7 + wind_gust_factor * 0.8 + sin(wind_phase * 1.55) * 0.12

			# ── Primary push (base wind direction) ───────────────────────────
			wind_force = wind_dir * (wind_strength * WIND_FORCE_SCALE * gust_env)

			# ── Multi-octave turbulence per axis (independent phases) ────────
			# Each axis gets a blended low+mid+high frequency signal
			var ws := wind_strength * WIND_TURB_SCALE
			var turb_x := (
				sin(_turb_phase_x * WIND_TURB_FREQ_A) * 0.55 +
				sin(_turb_phase_x * WIND_TURB_FREQ_B * 1.3) * 0.30 +
				sin(_turb_phase_x * WIND_TURB_FREQ_C * 0.4) * 0.15
			)
			var turb_z := (
				cos(_turb_phase_z * WIND_TURB_FREQ_A * 0.9) * 0.55 +
				cos(_turb_phase_z * WIND_TURB_FREQ_B * 1.7) * 0.30 +
				cos(_turb_phase_z * WIND_TURB_FREQ_C * 0.5) * 0.15
			)
			# Scale turbulence with gust factor — gusty wind = jitterier flight
			var turb_scale := lerpf(0.5, 1.5, wind_gust_factor)
			wind_force.x += turb_x * ws * turb_scale
			wind_force.z += turb_z * ws * turb_scale

			# ── Lift variation (wind can slightly bounce altitude) ────────────
			var lift_osc := sin(_turb_phase_y * WIND_TURB_FREQ_A * 0.8) * 0.6 + sin(_turb_phase_y * WIND_TURB_FREQ_B) * 0.4
			wind_force.y += wind_strength * WIND_LIFT_SCALE * (0.3 + wind_gust_factor * 0.5) * lift_osc

			# ── Crosswind component ──────────────────────────────────────────
			wind_force += strafe_dir * (wind_strength * right_component * 1.2 * gust_env)

			# ── Hover bobble (extra positional jitter when holding position) ─
			if hover_enabled:
				wind_bobble = Vector3(
					turb_x * wind_strength * WIND_HOVER_BOBBLE_SCALE,
					lift_osc * wind_strength * WIND_HOVER_BOBBLE_SCALE * 0.4,
					turb_z * wind_strength * WIND_HOVER_BOBBLE_SCALE
				)

	forward_force *= wind_drag_factor
	strafe_force  *= lerpf(wind_drag_factor, 1.0, 0.2)
	# Wind force contributes a small fraction to vertical thrust (lift interaction)
	vertical_thrust += Vector3(0.0, wind_force.y * 0.08, 0.0)

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

	# ── Rotation from control inputs ────────────────────────────────────────
	apply_torque(global_transform.basis.x * (-smoothed_input_internal.z * TURN_POWER * speed_multiplier + wind_force.z * WIND_ROTATION_SCALE))
	apply_torque(global_transform.basis.z * (-smoothed_input_internal.w * TURN_POWER * speed_multiplier + wind_force.x * WIND_ROTATION_SCALE))
	apply_torque(global_transform.basis.y * -smoothed_input_internal.y * TURN_POWER * speed_multiplier)

	# ── Wind tilt torque (multi-axis turbulent wobble) ───────────────────────
	if wind_strength > 0.0:
		# Pitch and roll wobble use independent turbulence phases
		var tilt_x := sin(_turb_phase_x * WIND_TURB_FREQ_A * 0.7) * 0.65 + sin(_turb_phase_x * WIND_TURB_FREQ_B) * 0.35
		var tilt_z := cos(_turb_phase_z * WIND_TURB_FREQ_A * 0.8) * 0.65 + cos(_turb_phase_z * WIND_TURB_FREQ_B * 1.2) * 0.35
		var tilt_scale := wind_strength * WIND_ROTATION_SCALE * lerpf(0.6, 1.4, wind_gust_factor)
		apply_torque(global_transform.basis.x * tilt_x * tilt_scale)
		apply_torque(global_transform.basis.z * tilt_z * tilt_scale)

	var up = global_transform.basis.y
	var correction = up.cross(Vector3.UP)
	
	var current_stabilize = STABILIZE_FORCE
	if abs(smoothed_input_internal.z) < 0.05 and abs(smoothed_input_internal.w) < 0.05:
		current_stabilize = STABILIZE_FORCE * 3.0
	# Wind reduces stabilization — harder to hold level in heavier gusts
	if wind_strength > 0.0:
		var stab_reduction := clampf(wind_strength * 0.06, 0.0, 0.40)
		current_stabilize *= (1.0 - stab_reduction)
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

	var prop_speed = 30.0 + (smoothed_input_internal.x * 60.0)
	prop_rotation_angle = fmod(prop_rotation_angle + delta * prop_speed, PI * 2.0)
	
	# Spin the procedural propeller disc holders around their local Y axis
	for data in propeller_datas:
		var prop = data["node"]
		if is_instance_valid(prop):
			var orig: Transform3D = data["original_transform"]
			var t := orig
			t.basis = orig.basis.rotated(Vector3.UP, prop_rotation_angle)
			prop.transform = t

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

func _write_debug_hierarchy(node: Node, indent: String, file: FileAccess):
	var line = indent + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		line += " pos=" + str(node.position) + " rot=" + str(node.rotation) + " scale=" + str(node.scale)
	if node is MeshInstance3D:
		line += " MESH aabb_center=" + str(node.get_aabb().get_center()) + " aabb_size=" + str(node.get_aabb().size)
	file.store_line(line)
	for child in node.get_children():
		_write_debug_hierarchy(child, indent + "  ", file)
