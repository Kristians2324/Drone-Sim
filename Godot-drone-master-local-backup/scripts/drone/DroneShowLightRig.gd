extends Node3D

class_name DroneShowLightRig

# Minimal placeholder for DroneShowLightRig used by Drone.
func _ready() -> void:
	set_process(false)
	pass
	light_update_interval = 0.25 if enabled else 0.0
	set_visuals_enabled(true)
	_show_lighting_enabled = not enabled
	if enabled:
		_saved_visual_state = visuals_enabled
	_apply_light_output_state()
	if not enabled:
		_apply_palette_to_visuals()

func set_high_performance_mode(enabled: bool) -> void:
	# In performance mode we still keep visuals, but we slow the modulation a bit.
	light_update_interval = 0.0 if enabled else light_update_interval

func set_show_lighting_enabled(enabled: bool) -> void:
	_show_lighting_enabled = enabled
	set_visuals_enabled(true)
	_apply_light_output_state()

func _apply_light_output_state() -> void:
	if halo_light:
		halo_light.light_energy = (2.6 if is_player_drone else 2.0) if _show_lighting_enabled else 0.0
	if down_light:
		down_light.light_energy = (3.6 if is_player_drone else 2.8) if _show_lighting_enabled else 0.0
	if halo_material:
		halo_material.emission_energy_multiplier = halo_material.emission_energy_multiplier if _show_lighting_enabled else 0.6
