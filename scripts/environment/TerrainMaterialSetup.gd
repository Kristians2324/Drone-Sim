extends Node

@export var terrain_material_path: NodePath

@export var ground_texture: Texture2D = preload("res://assets/textures/real_ground_albedo.png")


func _ready() -> void:
	var terrain := _get_terrain_node()
	if terrain == null:
		push_warning("TerrainMaterialSetup: terrain node not found.")
		return

	if terrain.has_method("set_material"):
		var material := StandardMaterial3D.new()
		material.albedo_texture = ground_texture
		material.roughness = 1.0
		material.metallic = 0.0
		material.normal_enabled = false
		terrain.call("set_material", material)


func _get_terrain_node() -> Node:
	if terrain_material_path != NodePath():
		return get_node_or_null(terrain_material_path)
	return get_tree().current_scene.find_child("Terrain3D", true, false)
