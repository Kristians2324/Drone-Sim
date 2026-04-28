extends Node3D
class_name WorldDetails

@export var tree_count: int = 50
@export var rock_count: int = 30
@export var forest_radius: float = 400.0

var tree_colors = [Color(0.1, 0.4, 0.1), Color(0.15, 0.35, 0.1), Color(0.2, 0.4, 0.15)]

func generate():
	seed(42)
	generate_trees()
	generate_rocks()

func generate_trees():
	var tree_multimesh = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = tree_count
	
	var tree_mesh = CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 2.0
	tree_mesh.height = 6.0
	var tree_mat = StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.1, 0.3, 0.1)
	tree_mesh.material = tree_mat
	
	mm.mesh = tree_mesh
	tree_multimesh.multimesh = mm
	add_child(tree_multimesh)

	for i in range(tree_count):
		var pos = Vector3(randf_range(-forest_radius, forest_radius), 0, randf_range(-forest_radius, forest_radius))
		if pos.length() < 20:
			pos *= 2.0
		
		var xform = Transform3D()
		xform = xform.scaled(Vector3(randf_range(0.8, 1.5), randf_range(1.0, 2.0), randf_range(0.8, 1.5)))
		xform.origin = pos + Vector3(0, tree_mesh.height * 0.5 * xform.basis.get_scale().y, 0)
		mm.set_instance_transform(i, xform)
		
		var tree_static = StaticBody3D.new()
		var tree_collision = CollisionShape3D.new()
		var tree_shape = CylinderShape3D.new()
		tree_shape.radius = 1.0
		tree_shape.height = 6.0 * xform.basis.get_scale().y
		
		tree_collision.shape = tree_shape
		tree_collision.position = pos + Vector3(0, tree_shape.height * 0.5, 0)
		
		tree_static.add_child(tree_collision)
		add_child(tree_static)

func generate_rocks():
	for i in range(rock_count):
		var rock = CSGSphere3D.new()
		rock.use_collision = true
		rock.radius = randf_range(2.0, 5.0)
		rock.radial_segments = 6
		rock.rings = 4
		var rock_mat = StandardMaterial3D.new()
		rock_mat.albedo_color = Color(0.4, 0.4, 0.43)
		rock_mat.roughness = 0.9
		rock.material = rock_mat
		
		var rock_pos = Vector3(randf_range(-forest_radius, forest_radius), -1, randf_range(-forest_radius, forest_radius))
		rock.position = rock_pos
		rock.scale = Vector3(randf_range(1.0, 2.0), randf_range(0.5, 1.0), randf_range(1.0, 2.0))
		rock.rotation = Vector3(randf(), randf(), randf()) * PI
		
		add_child(rock)