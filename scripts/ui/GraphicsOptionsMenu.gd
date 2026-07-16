extends Control

enum AAOption { DISABLED, MSAA_2X, MSAA_4X }
enum ShadowMapOption { SHADOW_1024, SHADOW_2048 }

@export var directional_light_path: NodePath

@export var low_shadow_size: int = 1024
@export var medium_shadow_size: int = 2048


func set_vsync_enabled(enabled: bool) -> void:
	var mode := DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


func set_msaa(option: int) -> void:
	match option:
		AAOption.DISABLED:
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		AAOption.MSAA_2X:
			get_viewport().msaa_3d = Viewport.MSAA_2X
		AAOption.MSAA_4X:
			get_viewport().msaa_3d = Viewport.MSAA_4X
		_:
			push_warning("GraphicsOptionsMenu: Unknown MSAA option: %s" % option)


func toggle_shadow_quality() -> void:
	var light := _get_directional_light()
	if light == null:
		push_warning("GraphicsOptionsMenu: DirectionalLight3D not found.")
		return

	if light.shadow_atlas_size == low_shadow_size:
		light.shadow_atlas_size = medium_shadow_size
	else:
		light.shadow_atlas_size = low_shadow_size


func set_shadow_quality(low: bool) -> void:
	var light := _get_directional_light()
	if light == null:
		push_warning("GraphicsOptionsMenu: DirectionalLight3D not found.")
		return
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = low_shadow_size if low else medium_shadow_size


func set_shadow_map_resolution(option: int) -> void:
	var light := _get_directional_light()
	if light == null:
		push_warning("GraphicsOptionsMenu: DirectionalLight3D not found.")
		return

	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	match option:
		ShadowMapOption.SHADOW_1024:
			light.directional_shadow_max_distance = float(low_shadow_size)
		ShadowMapOption.SHADOW_2048:
			light.directional_shadow_max_distance = float(medium_shadow_size)
		_:
			push_warning("GraphicsOptionsMenu: Unknown shadow map option: %s" % option)


func _get_directional_light() -> DirectionalLight3D:
	if directional_light_path != NodePath():
		var node := get_node_or_null(directional_light_path)
		if node is DirectionalLight3D:
			return node as DirectionalLight3D
	return get_tree().current_scene.find_child("DirectionalLight3D", true, false) as DirectionalLight3D