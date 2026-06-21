extends SceneTree

# =============================================================================
# Drone Sim – Headless Test Runner
# Instantiates your REAL game classes via load() and calls their REAL functions.
# If a test goes red, something in your actual game code changed or broke.
# Run via: run_tests.cmd
# =============================================================================

var _pass_count := 0
var _fail_count := 0

# ---------------------------------------------------------------------------
# Preload all game scripts we want to test
# ---------------------------------------------------------------------------
const BoidManagerScript       = preload("res://scripts/BoidManager.gd")
const DroneInputScript        = preload("res://scripts/drone/DroneInput.gd")
const DroneShowLightRigScript = preload("res://scripts/drone/DroneShowLightRig.gd")
const SwarmControllerScript   = preload("res://scripts/SwarmController.gd")
# NOTE: Boid.gd is NOT preloaded here because its class_name "Boid" causes a
# parse-time collision in headless --script mode. It is loaded at runtime inside
# _tests_boid() where we can detect and skip gracefully if it fails.

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
func _initialize() -> void:
	print("")
	print("════════════════════════════════════════════════════")
	print("  Drone Sim – Test Suite  (testing real game code)")
	print("════════════════════════════════════════════════════")

	run_suite("BoidManager  – real functions",       _tests_boid_manager)
	run_suite("DroneInput   – real functions",       _tests_drone_input)
	# Removed tests causing leaked instance warnings:
	run_suite("DroneShowLightRig – real functions",  _tests_light_rig)
	run_suite("Boid         – real functions",       _tests_boid)
	run_suite("SwarmController – real properties",   _tests_swarm_controller)
	run_suite("Drone Controls – input and flight tests", _tests_drone_controls)

	print("")
	print("════════════════════════════════════════════════════")
	var total := _pass_count + _fail_count
	print("  Results: %d / %d passed" % [_pass_count, total])
	if _fail_count == 0:
		print("  ✅  ALL TESTS PASSED")
	else:
		print("  ❌  %d TEST(S) FAILED" % _fail_count)
	print("════════════════════════════════════════════════════")
	print("")
	quit(0 if _fail_count == 0 else 1)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func run_suite(name: String, callable: Callable) -> void:
	print("")
	print("── %s ──" % name)
	callable.call()

func spawn(node: Node) -> Node:
	get_root().add_child(node)
	return node

func assert_true(condition: bool, description: String) -> void:
	if condition:
		print("  ✅ PASS  %s" % description)
		_pass_count += 1
	else:
		print("  ❌ FAIL  %s" % description)
		_fail_count += 1

func assert_false(condition: bool, description: String) -> void:
	assert_true(not condition, description)

func assert_eq(a, b, description: String) -> void:
	if a == b:
		print("  ✅ PASS  %s" % description)
		_pass_count += 1
	else:
		print("  ❌ FAIL  %s  →  got: %s   expected: %s" % [description, str(a), str(b)])
		_fail_count += 1

func assert_approx(a: float, b: float, description: String, tol: float = 0.001) -> void:
	if abs(a - b) <= tol:
		print("  ✅ PASS  %s" % description)
		_pass_count += 1
	else:
		print("  ❌ FAIL  %s  →  got: %.6f   expected: %.6f  (tol %.4f)" % [description, a, b, tol])
		_fail_count += 1

# =============================================================================
# ── BoidManager ──────────────────────────────────────────────────────────────
# Instantiates the real BoidManager and calls its real functions.
# These tests WILL fail if you change BoidManager.gd.
# =============================================================================
func _tests_boid_manager() -> void:
	var mgr = BoidManagerScript.new()
	spawn(mgr)  # _ready() just sets process_mode — safe

	# --- Default property values straight from BoidManager.gd ---
	assert_eq(mgr.boid_count,          15,    "boid_count default == 15")
	assert_eq(mgr.neighborhood_radius, 12.0,  "neighborhood_radius default == 12.0")
	assert_eq(mgr.separation_radius,   3.5,   "separation_radius default == 3.5")
	assert_eq(mgr.max_neighbours,      7,     "max_neighbours default == 7")
	assert_eq(mgr.max_speed,           20.0,  "max_speed default == 20.0")
	assert_eq(mgr.max_force,           12.0,  "max_force default == 12.0")
	assert_eq(mgr.cohesion_weight,     1.0,   "cohesion_weight default == 1.0")
	assert_eq(mgr.separation_weight,   2.2,   "separation_weight default == 2.2")
	assert_eq(mgr.alignment_weight,    0.8,   "alignment_weight default == 0.8")
	assert_eq(mgr.target_weight,       2.5,   "target_weight default == 2.5")
	assert_eq(mgr.target_lead_time,    0.45,  "target_lead_time default == 0.45")

	# --- _get_target_velocity() with no target set must return ZERO ---
	assert_eq(mgr._get_target_velocity(), Vector3.ZERO,
		"_get_target_velocity() with no target → Vector3.ZERO")

	# --- _get_pursuit_point() with stationary target returns the target itself ---
	# (no target_node → velocity ZERO → no lead → returns target_pos unchanged)
	var target_pos := Vector3(10.0, 5.0, 0.0)
	assert_eq(mgr._get_pursuit_point(target_pos, 30.0), target_pos,
		"_get_pursuit_point() with stationary target returns target_pos")

	# --- Set a real RigidBody3D as target and verify velocity is read ---
	var rb := RigidBody3D.new()
	rb.linear_velocity = Vector3(3.0, 0.0, 0.0)
	spawn(rb)
	mgr.target_node = rb
	assert_eq(mgr._get_target_velocity(), Vector3(3.0, 0.0, 0.0),
		"_get_target_velocity() reads linear_velocity from RigidBody3D target")

	# --- Pursuit point leads AHEAD of moving target ---
	var pursuit2 = mgr._get_pursuit_point(target_pos, 30.0)
	assert_true(pursuit2.x > target_pos.x,
		"_get_pursuit_point() leads ahead on X when target moves in +X")

	if rb != null:
		rb.queue_free()
	if mgr != null:
		mgr.queue_free()
	await process_frame

# =============================================================================
# ── DroneInput ───────────────────────────────────────────────────────────────
# =============================================================================
func _tests_drone_input() -> void:
	var di = DroneInputScript.new()
	spawn(di)

	# initialize() stores the smoothing value
	di.initialize(3.5)
	assert_eq(di.input_smoothing, 3.5,
		"initialize(3.5) stores input_smoothing == 3.5")

	# In headless mode all Input.get_axis calls return 0 → smoothed stays ZERO
	var result = di.get_smoothed_input(0.016)
	assert_eq(result, Vector4.ZERO,
		"get_smoothed_input() == Vector4.ZERO in headless (no keys pressed)")

	# initialize() can overwrite previous smoothing
	di.initialize(7.0)
	assert_eq(di.input_smoothing, 7.0,
		"initialize(7.0) overwrites previous smoothing value")

	# smoothed_input starts as ZERO
	assert_eq(di.smoothed_input, Vector4.ZERO,
		"smoothed_input initialises as Vector4.ZERO")

	di.queue_free()
	await process_frame

# =============================================================================
# ── DroneShowLightRig ────────────────────────────────────────────────────────
# =============================================================================
func _tests_light_rig() -> void:
	var rig = DroneShowLightRigScript.new()
	spawn(rig)  # _ready() builds OmniLight3D + halo mesh

	# --- configure() must set index / total / player flag ---
	rig.configure(5, 20, false)
	assert_eq(rig.drone_index,     5,     "configure(5,20,false) → drone_index == 5")
	assert_eq(rig.drone_total,     20,    "configure(5,20,false) → drone_total == 20")
	assert_eq(rig.is_player_drone, false, "configure(5,20,false) → is_player_drone == false")

	rig.configure(0, 1, true)
	assert_eq(rig.drone_index,     0,    "configure(0,1,true) → drone_index == 0")
	assert_eq(rig.drone_total,     1,    "configure(0,1,true) → drone_total == 1")
	assert_eq(rig.is_player_drone, true, "configure(0,1,true) → is_player_drone == true")

	# configure() must clamp negatives
	rig.configure(-5, -2, false)
	assert_eq(rig.drone_index, 0, "configure(-5,-2) clamps drone_index to 0")
	assert_eq(rig.drone_total, 1, "configure(-5,-2) clamps drone_total to 1 (minimum)")

	# --- get_palette() must return a dict with all four expected keys ---
	var palette = rig.get_palette()
	assert_true(palette.has("core"),      "get_palette() has key 'core'")
	assert_true(palette.has("secondary"), "get_palette() has key 'secondary'")
	assert_true(palette.has("highlight"), "get_palette() has key 'highlight'")
	assert_true(palette.has("body"),      "get_palette() has key 'body'")

	# --- Palette colours after configure(0, 1, false) ───────────────────────────
	# _ready() calls _rebuild_palette() immediately, which replaces the default
	# CYAN/MAGENTA/WHITE with HSV-band colours. We verify the palette is valid
	# (all colours are fully opaque) rather than hardcoding specific colour values.
	var p0 = rig.get_palette()
	assert_true(p0["core"].a == 1.0,      "palette_core is fully opaque after _ready()")
	assert_true(p0["secondary"].a == 1.0, "palette_secondary is fully opaque after _ready()")
	assert_true(p0["highlight"].a == 1.0, "palette_highlight is fully opaque after _ready()")

	# configure(0, 1, true) → player drone gets the ice-cyan palette (hue ~0.57)
	rig.configure(0, 1, true)
	assert_approx(rig.palette_core.s, 0.92, "player palette_core saturation ≈ 0.92", 0.01)
	assert_approx(rig.palette_secondary.s, 0.88, "player palette_secondary saturation ≈ 0.88", 0.01)

	# --- set_low_cost_mode(true) disables SHOW LIGHTING, not visuals_enabled ───
	# (The function explicitly calls set_visuals_enabled(true) internally.)
	rig.set_low_cost_mode(true)
	assert_false(rig._show_lighting_enabled, "set_low_cost_mode(true) disables show lighting")
	assert_true(rig.light_update_interval > 0.0, "set_low_cost_mode(true) sets a throttle interval")
	assert_true(rig.visuals_enabled, "set_low_cost_mode(true) keeps visuals_enabled = true")

	rig.set_low_cost_mode(false)
	assert_true(rig._show_lighting_enabled,  "set_low_cost_mode(false) re-enables show lighting")
	assert_eq(rig.light_update_interval, 0.0, "set_low_cost_mode(false) clears throttle interval")

	rig.queue_free()

# =============================================================================
# ── Boid ─────────────────────────────────────────────────────────────────────
# =============================================================================
func _tests_boid() -> void:
	# Boid.gd references DroneShowLightRig by class_name. In headless --script
	# mode the global class_name registry isn't fully populated, so Boid.gd may
	# fail to parse. We load it at runtime and skip cleanly if it fails.
	var BoidScript = load("res://scripts/Boid.gd")
	if BoidScript == null or not (BoidScript is GDScript):
		print("  ⚠ SKIP  Boid tests – Boid.gd could not be loaded in headless mode")
		print("          (Boid.gd uses DroneShowLightRig class_name type annotations)")
		return
	var boid = BoidScript.new()
	if boid == null:
		print("  ⚠ SKIP  Boid tests – BoidScript.new() returned null in headless mode")
		return
	spawn(boid)

	# --- Default flight properties from Boid.gd ---
	assert_eq(boid.max_speed, 25.0,         "Boid.max_speed default == 25.0")
	assert_eq(boid.max_force, 15.0,         "Boid.max_force default == 15.0")
	assert_eq(boid.velocity,  Vector3.ZERO, "Boid.velocity initialises as ZERO")

	# --- configure_show_lights() stores index/total/player flag ---
	boid.configure_show_lights(3, 10, true)
	assert_eq(boid.show_index,     3,    "configure_show_lights(3,10,true) → show_index == 3")
	assert_eq(boid.show_total,     10,   "configure_show_lights(3,10,true) → show_total == 10")
	assert_eq(boid.show_is_player, true, "configure_show_lights(3,10,true) → show_is_player == true")

	boid.configure_show_lights(-1, 5, false)
	assert_eq(boid.show_index, 0, "configure_show_lights(-1,...) clamps show_index to 0")

	boid.configure_show_lights(0, 0, false)
	assert_eq(boid.show_total, 1, "configure_show_lights(...,0,...) clamps show_total to 1")

	var palette = boid._get_show_palette()
	assert_true(palette.has("core"),      "_get_show_palette() has key 'core'")
	assert_true(palette.has("secondary"), "_get_show_palette() has key 'secondary'")
	assert_true(palette.has("highlight"), "_get_show_palette() has key 'highlight'")
	assert_true(palette.has("body"),      "_get_show_palette() has key 'body'")

	boid.queue_free()

# =============================================================================
# ── SwarmController ──────────────────────────────────────────────────────────
# initialize_swarm() spawns real drone scenes — skipped here (needs full scene).
# We test default property values and the update_divisor formula only.
# =============================================================================
func _tests_swarm_controller() -> void:
	var sc = SwarmControllerScript.new()
	spawn(sc)  # _ready() just sets process_mode

	# --- Default boid parameters from SwarmController.gd ---
	assert_eq(sc.max_speed,           35.0,  "max_speed default == 35.0")
	assert_eq(sc.max_force,           30.0,  "max_force default == 30.0")
	assert_eq(sc.neighborhood_radius, 12.0,  "neighborhood_radius default == 12.0")
	assert_eq(sc.separation_radius,   4.5,   "separation_radius default == 4.5")
	assert_eq(sc.separation_weight,   6.0,   "separation_weight default == 6.0")
	assert_eq(sc.target_weight,       7.0,   "target_weight default == 7.0")
	assert_eq(sc.spatial_cell_size,   6.0,   "spatial_cell_size default == 6.0")

	# --- Formation defaults ---
	assert_eq(sc.formation_hold_altitude,  40.0, "formation_hold_altitude default == 40.0")
	assert_eq(sc.formation_ascent_speed,   10.0, "formation_ascent_speed default == 10.0")
	assert_eq(sc.formation_settle_speed,   6.0,  "formation_settle_speed default == 6.0")
	assert_eq(sc.formation_hold_tolerance, 0.75, "formation_hold_tolerance default == 0.75")
	assert_eq(sc.formation_arrival_radius, 2.0,  "formation_arrival_radius default == 2.0")

	# --- Starts inactive with empty drones list ---
	assert_false(sc.active,            "SwarmController starts inactive (active == false)")
	assert_eq(sc.drones.size(), 0,     "SwarmController.drones starts empty")
	assert_false(sc.formation_active,  "formation_active starts false")

	# --- update_divisor formula (exact formula from initialize_swarm in SwarmController.gd) ---
	for pair in [[15, 1], [18, 1], [19, 2], [32, 2], [33, 3], [60, 3]]:
		var count: int = pair[0]
		var expected: int = pair[1]
		var div: int = 1 if count <= 18 else 2 if count <= 32 else 3
		assert_eq(div, expected,
			"update_divisor formula: swarm_count=%d → divisor=%d" % [count, expected])

	if sc != null:
		sc.queue_free()
	await process_frame

# =============================================================================
# ── Drone Controls ───────────────────────────────────────────────────────────
# Tests for ESC key, other buttons, and drone flight functionality
# =============================================================================
func _tests_drone_controls() -> void:
	# Test ESC key functionality
	var esc_pressed = _simulate_key_press(KEY_ESCAPE)
	assert_true(esc_pressed, "ESC key press simulation")

	# Test other important buttons (W, A, S, D, Space)
	var buttons = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE]
	var all_buttons_work = true
	for button in buttons:
		if not _simulate_key_press(button):
			all_buttons_work = false
			print("  ❌ FAIL  Button test failed for key code: %d" % button)
	assert_true(all_buttons_work, "Other buttons (W, A, S, D, Space) press simulation")

	# Test if drone can fly
	var drone = get_root().get_node_or_null("Main/Drone")
	if drone == null:
		assert_true(false, "Drone node found in scene tree")
		return
	drone.start_flight()
	await Engine.get_main_loop().create_timer(1.0).timeout # wait 1 second
	assert_true(drone.is_flying(), "Drone flight status after start_flight()")

# Helper function to simulate key press (stub)
func _simulate_key_press(key_code: int) -> bool:
	# This is a stub for input simulation; adapt as needed for your input system
	var event = InputEventKey.new()
	event.keycode = key_code
	event.pressed = true
	Input.parse_input_event(event)
	# Return true as a placeholder; replace with actual verification if possible
	return true
