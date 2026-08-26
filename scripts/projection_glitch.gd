extends Node2D

## The tear that runs through a projection when a round goes through it.
##
## Drawn rather than animated, for the same reason ShieldOutline is: the
## character is four flat polygons with no texture and no frames, so there is
## nothing to swap. What a hit has to read as is "that body is not made of
## anything" - so the silhouette is sliced into horizontal bands, each shoved
## sideways by a different amount, with the red and blue channels pulled apart
## either side of the tear. Nothing else on the map does that, so one frame of
## it is enough to tell you what you just shot at.
##
## A child of Body on purpose, exactly like the outline: Body squashes and
## shifts as its owner crouches, and a tear that did not follow would hang in
## the air beside a crouching ghost.

## Traced from this sibling so a change to the character art is not also a
## change to the tear. Torso is the whole silhouette - head and face sit inside
## it - and it is what the outline measures itself against too.
const SILHOUETTE := ^"../Torso"

## How many bands the body is cut into. Few enough that each one is a slab you
## can see move, rather than a dither.
const BANDS := 7

## Furthest a band is thrown sideways at full strength, in pixels. Wider than
## the body is, so a hard hit genuinely comes apart rather than shivering.
const THROW := 22.0

## The two halves of the channel split. Not the shield's blue: that colour
## already means "plates up" on this exact silhouette, and a hit must not read
## as armour going on.
const CHANNEL_A := Color(1.0, 0.24, 0.42)
const CHANNEL_B := Color(0.3, 0.95, 1.0)

## Redrawn from a seed that changes per hit rather than per frame, so a single
## tear holds its shape while it fades instead of boiling. See Projection.hit().
var _rng := RandomNumberGenerator.new()

var _ghost: Node2D
var _shape: Polygon2D
## What the tear was last drawn at, so a projection standing quietly is not
## redrawn every frame for a value that has not moved.
var _drawn := -1.0
var _seed := 0


func _ready() -> void:
	# Above the body and above the shield outline, which sits at 1.
	z_index = 2
	_shape = get_node_or_null(SILHOUETTE) as Polygon2D
	_ghost = get_parent().get_parent() as Node2D


func _process(_delta: float) -> void:
	if _ghost == null:
		return
	var torn: float = _ghost.glitch
	var seed_now: int = _ghost.glitch_seed
	if is_equal_approx(torn, _drawn) and seed_now == _seed:
		return
	_drawn = torn
	_seed = seed_now
	queue_redraw()


func _draw() -> void:
	if _shape == null or _drawn <= 0.001:
		return
	var box := _bounds()
	if box.size.y <= 0.0:
		return

	# Seeded per hit, so the bands are in the same places for the whole life of
	# one tear. A fresh number every frame makes it a static field, which reads
	# as noise on the lens rather than damage to the thing.
	_rng.seed = _seed
	var strength := clampf(_drawn, 0.0, 1.0)
	var height := box.size.y / float(BANDS)

	for i in BANDS:
		var band := Rect2(box.position + Vector2(0.0, height * i),
			Vector2(box.size.x, height))
		# Some bands stay put. A tear where every slice has moved is a blur; one
		# where three of seven have moved is a broken picture.
		if _rng.randf() < 0.35:
			continue
		var shove := _rng.randf_range(-THROW, THROW) * strength
		# The gap the band was lifted out of goes down first, so the body reads
		# as cut and the pieces as laid back over it. Painted the other way round
		# the slices are buried under their own hole whenever the shove is small,
		# which is most of the time as the tear fades.
		draw_rect(band, Color(0.02, 0.03, 0.05, 0.55 * strength))
		var a := band
		a.position.x += shove
		var b := band
		b.position.x -= shove * 0.6
		draw_rect(a, Color(CHANNEL_A, 0.5 * strength))
		draw_rect(b, Color(CHANNEL_B, 0.42 * strength))


## The silhouette's own extent, so the bands cover exactly the body and not a
## guessed rectangle around it.
func _bounds() -> Rect2:
	var points := _shape.polygon
	if points.is_empty():
		return Rect2()
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	return box
