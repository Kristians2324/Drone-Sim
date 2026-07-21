extends Node

@export var terrain_material_path: NodePath
@export var ground_texture_path: String = "res://assets/textures/wall_albedo.png"

const GROUND_TEXTURE_FALLBACK: String = "res://assets/textures/metal_albedo.png"
var ground_texture: Texture2D


func _ready() -> void:
	var terrain := _get_terrain_node()
	if terrain == null:
		push_warning("TerrainMaterialSetup: terrain node not found.")
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.58, 0.53)
	material.roughness = 1.0
	material.metallic = 0.0
	material.normal_enabled = false
	if terrain.has_method("set_material"):
		terrain.call("set_material", material)


func _get_terrain_node() -> Node:
	if terrain_material_path != NodePath():
		return get_node_or_null(terrain_material_path)
	return get_tree().current_scene.find_child("Terrain3D", true, false)
