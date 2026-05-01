class_name ChargingStation
extends EnvironmentObject

func setup_object():
	object_name = "Drone Charging Station"
	
	# Create a simple visual representation
	var base = CSGBox3D.new()
	base.size = Vector3(2, 0.2, 2)
	add_child(base)
	
	var pillar = CSGBox3D.new()
	pillar.size = Vector3(0.5, 1.5, 0.5)
	pillar.position = Vector3(0, 0.75, 0)
	add_child(pillar)
	
	var light = OmniLight3D.new()
	light.position = Vector3(0, 1.5, 0)
	light.light_color = Color(0, 1, 0) # Green light
	light.omni_range = 5.0
	add_child(light)
