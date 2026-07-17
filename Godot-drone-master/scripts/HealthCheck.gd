extends Node

func _ready():
	# Wait a frame for everything to initialize
	await get_tree().process_frame
	run_diagnostics()

func run_diagnostics():
	print("\n=== SYSTEM DIAGNOSTICS ===")
	
	# 1. Check Drone
	var drone = get_tree().root.find_child("Drone", true, false)
	if drone:
		print("[OK] Drone node found.")
		if drone.has_method("get_propeller_count"):
			var count = drone.get_propeller_count()
			if count > 0:
				print("[OK] Drone has ", count, " propellers.")
			else:
				print("[WARN] Drone has 0 propellers found.")
		
		# Check visibility
		if not drone.visible:
			print("[ERROR] Drone node is INVISIBLE.")
	else:
		print("[ERROR] Drone node NOT FOUND in scene.")

	# 2. Check Environment
	var terrain = get_tree().root.find_child("Terrain", true, false)
	if terrain:
		print("[OK] Terrain found.")
	else:
		print("[WARN] Terrain missing.")

	# 3. Check for GLTF Model
	if FileAccess.file_exists("res://Drone.gltf"):
		print("[OK] Drone.gltf exists in project folder.")
	else:
		print("[ERROR] Drone.gltf MISSING from folder.")

	print("=== DIAGNOSTICS COMPLETE ===\n")
