class_name BaseEnvironment
extends Node3D

# Common objects that can be added to any environment
var foosball_table: FoosballTable = null

func _ready():
	setup_environment()

func setup_environment():
	# To be overridden by subclasses
	pass

func add_foosball_table(pos: Vector3, rot: Vector3 = Vector3.ZERO, sca: Vector3 = Vector3.ONE):
	var obj = FoosballTable.new()
	obj.position = pos
	obj.rotation_degrees = rot
	obj.scale = sca
	add_child(obj)
	return obj

func add_charging_station(pos: Vector3, rot: Vector3 = Vector3.ZERO, sca: Vector3 = Vector3.ONE):
	var obj = ChargingStation.new()
	obj.position = pos
	obj.rotation_degrees = rot
	obj.scale = sca
	add_child(obj)
	return obj
