class_name EnvironmentObject
extends Node3D

# Base class for all objects that can be placed in an environment
# Provides common functionality like interaction, sounds, etc.

@export var object_name: String = "Environment Object"

func _ready():
	setup_object()

func setup_object():
	# To be overridden by subclasses
	pass
