extends Node3D
class_name WorldDetails

@export var tree_count: int = 50
@export var rock_count: int = 30
@export var forest_radius: float = 400.0

var tree_colors = [Color(0.1, 0.4, 0.1), Color(0.15, 0.35, 0.1), Color(0.2, 0.4, 0.15)]

const WALL_ALBEDO := preload("res://assets/textures/real_bark_albedo.png")
const WALL_NORMAL := preload("res://assets/textures/wall_normal.png")
const METAL_ALBEDO := preload("res://assets/textures/real_rock_albedo.png")
const METAL_NORMAL := preload("res://assets/textures/metal_normal.png")

func _build_tree_material() -> StandardMaterial3D:
	var tree_mat := StandardMaterial3D.new()
	tree_mat.albedo_texture = WALL_ALBEDO
	tree_mat.normal_texture = WALL_NORMAL
	tree_mat.normal_enabled = true
	tree_mat.roughness = 0.96
	tree_mat.uv1_scale = Vector3(1.75, 1.75, 1.75)
	tree_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return tree_mat

func _build_rock_material() -> StandardMaterial3D:
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_texture = METAL_ALBEDO
	rock_mat.normal_texture = METAL_NORMAL
	rock_mat.normal_enabled = true
	rock_mat.roughness = 1.0
	rock_mat.metallic = 0.0
	rock_mat.albedo_color = Color(0.72, 0.72, 0.75)
	rock_mat.uv1_scale = Vector3(1.1, 1.1, 1.1)
	rock_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return rock_mat

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
	tree_mesh.material = _build_tree_material()
	
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
		rock.material = _build_rock_material()
		
		var rock_pos = Vector3(randf_range(-forest_radius, forest_radius), -1, randf_range(-forest_radius, forest_radius))
		rock.position = rock_pos
		rock.scale = Vector3(randf_range(1.0, 2.0), randf_range(0.5, 1.0), randf_range(1.0, 2.0))
		rock.rotation = Vector3(randf(), randf(), randf()) * PI
		
		add_child(rock)