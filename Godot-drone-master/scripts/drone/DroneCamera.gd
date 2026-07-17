extends Node
class_name DroneCamera

@onready var design: Node3D = get_parent().get_parent()

var is_first_person = true
var third_person_camera: Camera3D
var first_person_camera: Camera3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var camera_toggle_cooldown = 0.0

func initialize():
	setup_cameras()
	update_camera_views()

func setup_cameras():
	# Third person camera
	var spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.spring_length = 5.0
	spring_arm.collision_mask = 1
	third_person_camera = Camera3D.new()
	third_person_camera.name = "Camera3D"
	spring_arm.add_child(third_person_camera)
	design.add_child(spring_arm)
	
	# First person camera
	first_person_camera = Camera3D.new()
	first_person_camera.name = "FirstPersonCamera"
	design.add_child(first_person_camera)
	first_person_camera.position = Vector3(0, 0.15, -0.35)
	first_person_camera.rotation_degrees = Vector3(15, 0, 0)
	
	# VR setup
	setup_vr()

func setup_vr():
	xr_origin = XROrigin3D.new()
	design.add_child(xr_origin)
	xr_origin.position = first_person_camera.position
	xr_origin.rotation = first_person_camera.rotation
	
	xr_camera = XRCamera3D.new()
	xr_origin.add_child(xr_camera)
	
	var main = get_tree().root.find_child("Main", true, false)
	var vr_manager = null
	if main:
		vr_manager = main.get_node_or_null("VRManager")
	
	if vr_manager and vr_manager.has_method("is_vr_active") and vr_manager.is_vr_active():
		print("DroneCamera: VR Mode detected")
	else:
		xr_origin.visible = false

func update_camera_views():
	var main = get_tree().root.find_child("Main", true, false)
	var vr_manager = null
	if main:
		vr_manager = main.get_node_or_null("VRManager")
	var is_vr = vr_manager and vr_manager.has_method("is_vr_active") and vr_manager.is_vr_active()

	if is_vr:
		third_person_camera.current = false
		first_person_camera.current = false
	else:
		third_person_camera.current = not is_first_person
		first_person_camera.current = is_first_person

func toggle_view():
	is_first_person = not is_first_person
	update_camera_views()
	camera_toggle_cooldown = 0.2

func is_cooldown_active() -> bool:
	return camera_toggle_cooldown > 0

func _process(delta):
	if camera_toggle_cooldown > 0:
		camera_toggle_cooldown -= delta