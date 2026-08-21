extends Node2D

## The blue line around a body with its plates up.
##
## Everything else about the shield is invisible: it changes how fast you move
## and whether the next round kills you, and neither of those can be read off a
## character at a distance. So the state has to be worn, and worn in a colour the
## level does not otherwise use - nothing in the yard is blue, so a blue body is
## a shielded body and there is nothing else it could be.
##
## Drawn rather than tinted. Recolouring the torso would fight the hit flash,
## which turns it red and tweens back to a hardcoded grey (see
## Player.take_damage), and the two would end up overwriting each other.
##
## A child of Body on purpose: Body squashes and shifts as its owner crouches and
## crawls, and an outline that did not follow would float off a prone character.

## Traced from this sibling, so a change to the character art is not also a
## change to the outline. Torso is the whole silhouette - the head and face
## polygons sit inside it.
const SILHOUETTE := ^"../Torso"

## Pixels outside the body. Enough to read as a rim rather than an edge on the
## polygon, not so far that two people standing together merge into one shape.
const SPREAD := 3.0

## Full-strength colour. Alpha rides the ramp on top of this.
const OUTLINE := Color(0.36, 0.72, 1.0)
## The wider, fainter line under it. One line reads as a drawing error at small
## sizes; two reads as a field around the body.
const GLOW := Color(0.36, 0.72, 1.0, 0.28)

var _player: Node2D
var _shape: Polygon2D
## What the outline was drawn at, so a body standing still is not redrawn every
## frame for a value that has not moved.
var _drawn := -1.0


func _ready() -> void:
	# Above the body it outlines: siblings draw in tree order, and this node sits
	# after the last of the polygons.
	z_index = 1
	_shape = get_node_or_null(SILHOUETTE) as Polygon2D
	_player = get_parent().get_parent() as Node2D


func _process(_delta: float) -> void:
	if _player == null:
		return
	var lit: float = _player.shield
	if is_equal_approx(lit, _drawn):
		return
	_drawn = lit
	queue_redraw()


func _draw() -> void:
	if _shape == null or _drawn <= 0.001:
		return
	var edge := _expanded()
	if edge.is_empty():
		return
	# Half up is half there. The line fades and thickens into place rather than
	# appearing, so the 0.3s the plates take is something you can watch happen -
	# on your own body and, more usefully, on somebody else's.
	var strength := clampf(_drawn, 0.0, 1.0)
	draw_polyline(edge, Color(GLOW, GLOW.a * strength), 6.0 * strength, true)
	draw_polyline(edge, Color(OUTLINE, strength), 2.0, true)


## The silhouette pushed outwards, closed back on itself so the polyline has no
## gap at the seam.
func _expanded() -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(_shape.polygon, SPREAD)
	if grown.is_empty():
		return PackedVector2Array()
	var ring: PackedVector2Array = grown[0]
	if ring.size() > 1:
		ring.append(ring[0])
	return ring
