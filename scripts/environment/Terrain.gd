extends Node3D
class_name Terrain

@export var size: Vector2 = Vector2(2000, 2000)

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
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.22, 0.08, 1)
	material.roughness = 0.8
	material.normal_enabled = true
	material.uv1_scale = Vector3(100, 100, 100)
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = material
	floor_body.add_child(mesh_instance)
	
	# Landform
	var landform = CSGCombiner3D.new()
	landform.name = "Landform"
	landform.use_collision = true
	add_child(landform)
	
	# Add some hills
	var hill1 = CSGSphere3D.new()
	hill1.name = "Hill1"
	hill1.transform.origin = Vector3(50, -30, -80)
	hill1.radius = 60.0
	hill1.radial_segments = 24
	landform.add_child(hill1)
	
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