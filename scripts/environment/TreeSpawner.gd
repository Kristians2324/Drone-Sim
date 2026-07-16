extends MultiMeshInstance3D

@export var tree_scene: PackedScene = preload("res://assets/models/tree_pine.gltf")
@export var tree_count: int = 300
@export var area_size: Vector2 = Vector2(1800.0, 1800.0)
@export var area_center: Vector3 = Vector3.ZERO
@export var terrain_root_path: NodePath
@export var ground_raycast_height: float = 500.0
@export var ground_raycast_depth: float = 1200.0
@export var min_scale: float = 0.8
@export var max_scale: float = 1.2
@export var collision_radius: float = 1.2
@export var collision_height: float = 10.0
@export var collision_parent_path: NodePath

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if tree_scene == null:
		push_warning("TreeSpawner: tree_scene is not assigned.")
		return

	if multimesh == null:
		multimesh = MultiMesh.new()

	var prototype := tree_scene.instantiate()
	if prototype is Node3D:
		var base_transform := (prototype as Node3D).transform
		var mesh_instance := _find_mesh_instance(prototype)
		if mesh_instance == null or mesh_instance.mesh == null:
			push_warning("TreeSpawner: Could not find a mesh inside the tree scene.")
			prototype.queue_free()
			return

		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.instance_count = tree_count
		multimesh.mesh = mesh_instance.mesh

		var collision_parent := _get_collision_parent()
		var terrain_root := _get_terrain_root()
		for i in range(tree_count):
			var x := _rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5)
			var z := _rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5)
			var sampled_pos := _sample_ground_position(Vector3(area_center.x + x, area_center.y, area_center.z + z), terrain_root)
			if sampled_pos == null:
				continue
			var world_pos: Vector3 = sampled_pos

			var yaw := _rng.randf_range(0.0, TAU)
			var scale := _rng.randf_range(min_scale, max_scale)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
			var transform := Transform3D(basis * base_transform.basis, world_pos + base_transform.origin * scale)
			multimesh.set_instance_transform(i, transform)
			_create_tree_collision(collision_parent, world_pos, yaw, scale)

	prototype.queue_free()


func _sample_ground_position(world_pos: Vector3, terrain_root: Node = null) -> Variant:
	var space_state := get_world_3d().direct_space_state
	var from := world_pos + Vector3.UP * ground_raycast_height
	var to := world_pos - Vector3.UP * ground_raycast_depth
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if terrain_root != null:
		query.exclude = [terrain_root]
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"]


func _create_tree_collision(parent: Node, position: Vector3, yaw: float, scale: float) -> void:
	if parent == null:
		return

	var body := StaticBody3D.new()
	body.name = "TreeCollision_%s" % str(parent.get_child_count())
	body.transform = Transform3D(Basis(Vector3.UP, yaw), position)
	parent.add_child(body)
	body.owner = get_tree().current_scene

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = collision_radius * scale
	cylinder.height = collision_height * scale
	shape.shape = cylinder
	shape.position = Vector3(0.0, cylinder.height * 0.5, 0.0)
	body.add_child(shape)
	shape.owner = get_tree().current_scene


func _get_collision_parent() -> Node:
	if collision_parent_path != NodePath():
		var node := get_node_or_null(collision_parent_path)
		if node != null:
			return node
	return get_parent()


func _get_terrain_root() -> Node:
	if terrain_root_path != NodePath():
		var node := get_node_or_null(terrain_root_path)
		if node != null:
			return node
	if get_parent() != null:
		return get_parent()
	return self


func _find_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null
