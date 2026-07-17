extends Node3D
class_name EnvironmentController

# References to components
@onready var terrain: Node3D = $Terrain
@onready var sky: Node3D = $SkyEnvironment
@onready var town: Node3D = $Town
@onready var world_details: Node3D = $WorldDetails
@onready var mountains: Node3D = $Mountains

func _ready():
	initialize_components()

func initialize_components():
	if terrain and terrain.has_method("generate"):
		terrain.generate()
	if sky and sky.has_method("setup"):
		sky.setup()
	if town and town.has_method("generate"):
		town.generate()
	if world_details and world_details.has_method("generate"):
		world_details.generate()
	if mountains and mountains.has_method("setup"):
		mountains.setup()

# Public methods
func set_config(config: Dictionary):
	if "terrain_size" in config and terrain:
		terrain.size = config.terrain_size
	if "town_grid" in config and town:
		town.grid_size = config.town_grid
	if "tree_count" in config and world_details:
		world_details.tree_count = config.tree_count