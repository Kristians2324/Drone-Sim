extends Node3D
class_name Terrain

@export var size: Vector2 = Vector2(2000, 2000)

const FLOOR_ALBEDO := preload("res://assets/textures/wall_albedo.png")
const FLOOR_NORMAL := preload("res://assets/textures/wall_normal.png")

func _build_ground_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = FLOOR_ALBEDO
	material.normal_texture = FLOOR_NORMAL
	material.normal_enabled = true
	material.roughness = 1.0
	material.albedo_color = Color(0.58, 0.56, 0.5)
	material.metallic = 0.0
	material.uv1_scale = Vector3(48, 48, 48)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.detail_enabled = true
	material.detail_uv_layer = 0
	material.detail_blend_mode = BaseMaterial3D.DETAIL_BLEND_MODE_MIX
	return material

func generate():
	# Fallback floor
	var floor_body = StaticBody3D.new()
	floor_body.name = "FallbackFloor"
	add_child(floor_body)
	
	var collision = CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	
	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size
	var material = _build_ground_material()
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = material
	floor_body.add_child(mesh_instance)
	
	# Landform
	var landform = CSGCombiner3D.new()
	landform.name = "Landform"
	landform.use_collision = true
	add_child(landform)
	
	# Add some hills and terrain variation
	var hill1 = CSGSphere3D.new()
	hill1.name = "Hill1"
	hill1.transform.origin = Vector3(50, -30, -80)
	hill1.radius = 60.0
	hill1.radial_segments = 24
	landform.add_child(hill1)

	var hill4 = CSGSphere3D.new()
	hill4.name = "Hill4"
	hill4.transform.origin = Vector3(-220, -35, -170)
	hill4.radius = 120.0
	hill4.radial_segments = 24
	landform.add_child(hill4)
	
	var hill2 = CSGSphere3D.new()
	hill2.name = "Hill2"
	hill2.transform.origin = Vector3(-120, -20, 40)
	hill2.radius = 80.0
	hill2.radial_segments = 24
	landform.add_child(hill2)
	
	var valley = CSGSphere3D.new()
	valley.name = "Valley"
	valley.transform.origin = Vector3(0, -5, 0)
	valley.operation = CSGShape3D.OPERATION_SUBTRACTION
	valley.radius = 30.0
	valley.radial_segments = 24
	landform.add_child(valley)
	
	var hill3 = CSGSphere3D.new()
	hill3.name = "Hill3"
	hill3.transform.origin = Vector3(200, -25, 150)
	hill3.radius = 100.0
	hill3.radial_segments = 24
	landform.add_child(hill3)