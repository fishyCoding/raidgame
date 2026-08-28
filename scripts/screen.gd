class_name Screen
extends StaticBody2D

## A sheet that shows you the room with nobody in it.
##
## Not an opaque wall - that is the whole distinction. The level behind it draws
## exactly as it always did, so looking at one you see an empty corridor rather
## than a barrier telling you something is being hidden. What goes missing is
## anything alive back there. It is the projection screen out of a heist film:
## the picture is of the room, and the picture does not include you.
##
## Which makes it a lie rather than a hiding place, and it fails the way a lie
## does. Sound goes straight through, so somebody on the far side hears the
## footsteps and the reload coming out of an empty room. Occlusion in this game
## is not raycast at all, so audio is left alone by construction - and if that
## ever changes, screens must stay out of it.
##
## Bullets do not go through, and one is all it takes. The moment somebody shoots
## the empty room, the empty room stops being empty.
##
## Bodies do not go through either. It is a real sheet with a real edge, so it is
## cover you can put your back against - and a thing you can be pinned behind,
## since the only way out through it is to break it and announce yourself.

## How thick the sheet is. Only wide enough that a bullet cannot tunnel through
## it between two physics steps at close range.
const THICK := 10.0

## Who put it up. Only they can see it - see _draw.
var caster := 0

var _span := 0.0
var _life := 0.0
## The sheet in world space, for the sight test.
var _from := Vector2.ZERO
var _to := Vector2.ZERO


func setup(from: Vector2, to: Vector2, by: int) -> void:
	caster = by
	_from = from
	_to = to
	global_position = (from + to) * 0.5
	_span = from.distance_to(to)
	rotation = (to - from).angle() - PI * 0.5
	var box := RectangleShape2D.new()
	box.size = Vector2(THICK, _span)
	($Shape as CollisionShape2D).shape = box
	add_to_group(&"screen")


## Whether a screen stands between these two points.
##
## Asked about bodies, never about the world. A screen hides who is in a room; it
## does not change what the room looks like, and anything that treated it as
## geometry would give it away by the shadow it cast.
static func blocks_sight(tree: SceneTree, from: Vector2, to: Vector2) -> bool:
	for node in tree.get_nodes_in_group(&"screen"):
		var sheet := node as Screen
		if sheet == null or not is_instance_valid(sheet):
			continue
		if Geometry2D.segment_intersects_segment(from, to, sheet._from, sheet._to) != null:
			return true
	return false


func _process(delta: float) -> void:
	_life += delta
	if caster == Net.peer_id():
		queue_redraw()


## Anything that reaches it takes it down. The damage is thrown away - a screen
## has no health to whittle, it either stands or it does not.
func take_damage(_amount: float, at: Vector2, _from: Vector2) -> void:
	shatter(at)


func shatter(at: Vector2) -> void:
	if not is_inside_tree():
		return
	# Loud on purpose. Whoever was hiding needs to know their cover has gone, and
	# whoever shot it needs to know they were right to. Borrowed from the
	# explosion rather than given a sound of its own, quietly and at a fraction
	# of the size - a new sample is a separate job from making the thing work.
	Audio.explosion(at if at.is_finite() else global_position, 0.25)
	queue_free()


## Drawn only for whoever deployed it, and faintly.
##
## Invisible to everybody else is the whole gadget. Visible to its owner is what
## stops it being a trap for them as well - a sheet you cannot see is one you
## forget you are standing behind, and one you will try to shoot through.
func _draw() -> void:
	if caster != Net.peer_id():
		return
	var half := _span * 0.5
	var shimmer := 0.10 + 0.05 * sin(_life * 3.0)
	draw_line(Vector2(0.0, -half), Vector2(0.0, half),
		Color(0.62, 0.86, 1.0, shimmer + 0.12), THICK)
	draw_line(Vector2(0.0, -half), Vector2(0.0, half),
		Color(0.86, 0.96, 1.0, shimmer), 2.0)
