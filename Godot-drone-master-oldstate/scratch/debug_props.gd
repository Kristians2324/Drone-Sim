extends SceneTree

func _init():
	var drone_scene = load("res://Drone.gltf")
	if not drone_scene:
		print("Failed to load drone scene")
		quit()
		return
		
	var drone_model = drone_scene.instantiate()
	
	var candidates = []
	for pattern in ["*Prop*", "*Blade*", "*Rotor*", "*Helix*", "*Fan*"]:
		var found = drone_model.find_children(pattern, "Node3D", true, false)
		for p in found:
			if not p in candidates:
				candidates.append(p)
	
	print("CANDIDATES:")
	for c in candidates:
		print("- " + c.name + " (Parent: " + (c.get_parent().name if c.get_parent() else "None") + ")")

	var preliminary_filtered = []
	for c in candidates:
		var name_lower = c.name.to_lower()
		var is_static = "arm" in name_lower or "pole" in name_lower or "mount" in name_lower or "frame" in name_lower or "body" in name_lower or "static" in name_lower
		if is_static:
			continue
		preliminary_filtered.append(c)

	var final_props = []
	var processed_nodes = []
	
	for c in preliminary_filtered:
		if c in processed_nodes: continue
		var best_target = c
		var p = c.get_parent()
		while p and p != drone_model:
			var p_name = p.name.to_lower()
			var p_is_static = "arm" in p_name or "pole" in p_name or "mount" in p_name or "frame" in p_name or "body" in p_name
			if p_is_static:
				break
			var rotating_children = 0
			for child in p.get_children():
				if child in candidates:
					rotating_children += 1
			if p in candidates or rotating_children > 1:
				best_target = p
			p = p.get_parent()
		if not best_target in final_props:
			final_props.append(best_target)
			mark_processed(best_target, processed_nodes, candidates)
	
	print("\nFINAL PROPELLERS:")
	for f in final_props:
		print("- " + f.name)
		
	quit()

func mark_processed(node, processed, candidates):
	if node in candidates:
		processed.append(node)
	for child in node.get_children():
		mark_processed(child, processed, candidates)
