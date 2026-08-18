@tool
class_name Platform
extends StaticBody2D

## Prototype block that resizes its own collision and visual, so levels can be
## blocked out by duplicating it in the editor and dragging the size around.

@export var size := Vector2(256, 32):
	set(value):
		size = value
		_apply()

@export var color := Color(0.38, 0.45, 0.53):
	set(value):
		color = value
		_apply()

## One-way blocks are solid from above only, and can be dropped through
## with down + jump (see player.gd).
@export var one_way := false:
	set(value):
		one_way = value
		_apply()

## Which faces of the block cast shadow. Culling one side lets the block light
## its own face instead of sitting inside its own shadow. Purely cosmetic:
## entity concealment raycasts against the collision shape, never this.
@export var cull_mode: OccluderPolygon2D.CullMode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE:
	set(value):
		cull_mode = value
		_apply()

@onready var _visual: Polygon2D = $Visual
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _occluder: LightOccluder2D = $LightOccluder2D


func _ready() -> void:
	_apply()


func _apply() -> void:
	# Setters fire during scene load, before children are available.
	if not is_node_ready():
		return

	var half := size * 0.5
	var corners := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	_visual.polygon = corners
	_visual.color = color
	# The same outline again as a light occluder: solid cover blocks sight.
	# Culling back faces means the side facing the light is lit and the shadow
	# starts at the silhouette, instead of the block sitting in its own shadow.
	var occluder_polygon := _occluder.occluder as OccluderPolygon2D
	occluder_polygon.polygon = corners
	occluder_polygon.cull_mode = cull_mode
	# One-way blocks cast no shadow, so you can see what is underneath the
	# catwalk you are standing on. They still stop bullets - see Layers.ONE_WAY
	# in the shot masks - so a floor you can see through is not one you can
	# shoot through. Kept in step with vision_system.gd's SIGHT_MASK.
	_occluder.visible = not one_way

	var rect := _shape.shape as RectangleShape2D
	rect.size = size
	_shape.one_way_collision = one_way
	_shape.position = Vector2.ZERO

	collision_layer = Layers.ONE_WAY if one_way else Layers.WORLD
