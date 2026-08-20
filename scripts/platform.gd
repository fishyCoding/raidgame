@tool
class_name Platform
extends StaticBody2D

## Prototype block that resizes its own collision and visual, so levels can be
## blocked out by duplicating it in the editor and dragging the size around.

## The wall panelling. One tile spans the block's thickness - the artwork is a
## cross-section, light edge bands and all - and repeats square along its
## length, so a 24px catwalk and a 3000px wall are made of the same panel at the
## same scale. The end tile caps both ends of the run.
const BASE_TILE: Texture2D = preload("res://resources/pixil-frame-0.png")
const END_TILE: Texture2D = preload("res://resources/pixil-frame-1.png")

@export var size := Vector2(256, 32):
	set(value):
		size = value
		_apply()

## The two ends of the block's long axis, in the parent's space - the same idea
## as a Zipline's top and bottom, and dragged in the viewport the same way (see
## addons/endpoint_tools).
##
## Neither is stored. A block is still authored as a position, a rotation and a
## size, because that is what the collision shape wants; these read and write
## that. Setting one end pins the other, turns the block to face it and
## stretches it to reach - which also flattens any scale on the node into the
## size, so a block that has been dragged is always a clean 1:1 rectangle.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR) var start := Vector2.ZERO:
	get:
		return _end_at(-1.0)
	set(value):
		_span(value, _end_at(1.0))

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR) var finish := Vector2.ZERO:
	get:
		return _end_at(1.0)
	set(value):
		_span(_end_at(-1.0), value)

@export var color := Color(0.38, 0.45, 0.53):
	set(value):
		color = value
		_apply()

## Off falls back to the old flat [param color] fill - handy for blocks that are
## props rather than architecture.
@export var textured := true:
	set(value):
		textured = value
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
	# draw_texture_rect(tile) samples past the texture edge, so the block has to
	# be set to wrap or every tile after the first comes out clamped.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# The tile is 128px of pixel art squeezed into as little as 24px of block.
	# Mipmaps (turned on in the .import) are what keep that from shimmering as
	# the camera moves.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Blocks are stretched with the scale handles as often as with `size`, and
	# scale feeds the texel density, so a redraw has to follow it.
	set_notify_local_transform(true)
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		queue_redraw()


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
	# The panelling is drawn by _draw() on the body itself, so the flat polygon
	# is only in play as the untextured fallback.
	_visual.visible = not textured
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
	queue_redraw()


## Which way the block runs, in its own local space. Everything here has to
## agree on this: the panelling runs along it, and the ends sit at either
## extreme of it.
func long_axis_is_x() -> bool:
	return absf(size.x * scale.x) >= absf(size.y * scale.y)


## How thick the block is on screen, across its length, scale included.
func world_thickness() -> float:
	return minf(absf(size.x * scale.x), absf(size.y * scale.y))


## How long the block is on screen, scale included.
func world_length() -> float:
	return maxf(absf(size.x * scale.x), absf(size.y * scale.y))


## One end of the long axis in the parent's space. -1 is the start, +1 the end.
func _end_at(direction: float) -> Vector2:
	var half := Vector2(size.x * 0.5 * direction, 0.0) if long_axis_is_x() 			else Vector2(0.0, size.y * 0.5 * direction)
	return transform * half


## Rebuilds the block to run between two points in the parent's space.
func _span(from: Vector2, to: Vector2) -> void:
	var thickness := world_thickness()
	var offset := to - from
	var length := offset.length()
	if length > 0.001:
		rotation = offset.angle()
	position = (from + to) * 0.5
	# Any scale on the node is folded into the size here rather than kept, so
	# the two ends stay where they were put and the panelling keeps its density.
	scale = Vector2.ONE
	# A block shorter than it is thick has no long axis left to speak of, so the
	# ends stop at a square instead of quietly swapping which way it runs.
	size = Vector2(maxf(length, thickness), thickness)


func _draw() -> void:
	if not textured or size.x <= 0.0 or size.y <= 0.0:
		return

	# Half the level is blocked out with the scale handles rather than `size`,
	# so measure the block as it actually lands on screen. Feeding the node's
	# own scale back out of the draw transform is what stops a block stretched
	# 5.9x wide from getting tiles 5.9x wide with it.
	var sx: float = scale.x if absf(scale.x) > 0.0001 else 1.0
	var sy: float = scale.y if absf(scale.y) > 0.0001 else 1.0
	var world := Vector2(absf(size.x * sx), absf(size.y * sy))

	var along_x := long_axis_is_x()
	var length := maxf(world.x, world.y)
	var thickness := minf(world.x, world.y)
	# One tile is the block's thickness square. The artwork is a cross-section,
	# light edge bands and all, so spanning the thickness with it is what makes
	# a 24px catwalk and a 3000px wall read as the same panel.
	var tile := maxf(thickness, 1.0)
	var tex := BASE_TILE.get_size()

	# Whole panels only: round the run between the two caps to a whole number of
	# tiles and stretch them the last few percent to fit, rather than leaving a
	# tile sliced through where it meets the cap.
	var cap := minf(tile, length * 0.5)
	var tiles := roundi((length - cap * 2.0) / tile)
	if tiles < 1:
		# Too short to hold a panel: two end pieces butted together.
		tiles = 0
		cap = length * 0.5
	var run := length - cap * 2.0

	# Draw in texture pixels, because draw_texture_rect() repeats at the
	# texture's own size - one texture is one tile only if a texture-sized step
	# of the draw space measures a tile of world pixels.
	var unit_along := (run / tiles if tiles > 0 else tile) / tex.x
	var unit_across := tile / tex.y
	var along := Vector2(unit_along / sx, 0.0)
	var across := Vector2(0.0, unit_across / sy)
	if not along_x:
		# Long axis is the block's Y. Swapping the basis vectors turns the
		# artwork with the block, so the panel lines always run lengthwise -
		# a tower reads as the same wall as the floor it stands on.
		along = Vector2(0.0, unit_along / sy)
		across = Vector2(unit_across / sx, 0.0)
	draw_set_transform_matrix(Transform2D(along, across, Vector2.ZERO))

	var half_thick := tex.y * 0.5
	var half_run := tiles * tex.x * 0.5
	var cap_draw := cap / unit_along
	if tiles > 0:
		draw_texture_rect(BASE_TILE, Rect2(-half_run, -half_thick, tiles * tex.x, tex.y), true)
	draw_texture_rect(END_TILE, Rect2(-half_run - cap_draw, -half_thick, cap_draw, tex.y), false)
	draw_texture_rect(END_TILE, Rect2(half_run, -half_thick, cap_draw, tex.y), false)
