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

## How long the sheet takes to come apart once it has been shot. Long enough to
## be read as an event, short enough that it is over before anybody could use it
## as cover - it stops being a wall the instant it is hit, not when the last
## piece has fallen.
const BREAK_TIME := 0.55
## How many pieces it goes into. More than this and they are slivers nobody can
## see; fewer and it reads as a plank snapping rather than a picture failing.
const SHARDS := 9
## How hard the pieces fall, in pixels per second squared. Not the world's
## gravity - they are lighter than that, because they are supposed to look like
## a picture blowing away rather than a wall collapsing.
const FALL := 240.0

## Who put it up. Only they can see it - see _draw.
var caster := 0
## The host's name for this sheet. Every machine holding a copy uses the same
## one, which is what lets a bullet on the host take it down everywhere.
var id := 0

var _span := 0.0
var _life := 0.0
## Seconds left of the break animation, or 0 while it is still standing.
var _breaking := 0.0
## The pieces, once it has been hit. Each is where along the sheet it started,
## how long it is, which way it is going in world space and how fast it turns.
var _shards: Array[Dictionary] = []
## The sheet in world space, for the sight test.
var _from := Vector2.ZERO
var _to := Vector2.ZERO


func setup(from: Vector2, to: Vector2, by: int, name_from_host := 0) -> void:
	caster = by
	id = name_from_host
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
	if _breaking > 0.0:
		# From here it is an animation and nothing else, so it redraws for
		# everybody and frees itself once the last piece has gone.
		_breaking -= delta
		queue_redraw()
		if _breaking <= 0.0:
			queue_free()
		return
	if caster == Net.peer_id():
		queue_redraw()


## Anything that reaches it takes it down. The damage is thrown away - a screen
## has no health to whittle, it either stands or it does not.
func take_damage(_amount: float, at: Vector2, _from: Vector2) -> void:
	# Through Net, so it comes down on every machine rather than only on the one
	# where the round happened to be resolved. Bullets have consequences on the
	# host alone; a screen that only died there would live on as an invisible
	# wall for everybody else. The sound and the pieces are not started here
	# either, and for the same reason: they belong to the sheet coming down,
	# which happens everywhere, not to the round landing, which happens once.
	Net.break_screen(id, at)


## The sheet stops being a sheet and becomes an animation.
##
## Called on every machine holding a copy, which is what makes this the right
## place for the noise and the pieces - the one machine that resolved the round
## is not the only one that needs to know the lie is over.
##
## It stops working the instant it is hit rather than when the animation ends:
## out of the group before anything else, so the sight test lets bodies through
## again the same frame, and off its collision layer so nobody can take cover
## behind a picture that is already falling.
func shatter(at: Vector2) -> void:
	if _breaking > 0.0:
		return
	_breaking = BREAK_TIME
	remove_from_group(&"screen")
	collision_layer = 0
	collision_mask = 0
	_break_up(at)
	_burst(at)
	queue_redraw()


## Cuts the sheet into pieces and throws them.
##
## Cut at uneven places on purpose. A row of identical bars reads as a fence
## being dismantled; pieces of different lengths read as something brittle that
## broke where it was struck. Which is the same reason the pieces nearest the
## round go furthest and spin fastest - it says where the bullet went in without
## having to draw the bullet.
func _break_up(at: Vector2) -> void:
	var half := _span * 0.5
	# The round in the sheet's own terms: how far along it the hit landed. A
	# screen dropped by something that did not say where breaks from the middle,
	# which is the honest answer rather than a guessed one.
	var here := clampf(to_local(at).y, -half, half) if at.is_finite() else 0.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_shards.clear()
	var step := _span / float(SHARDS)
	var edge := -half
	for i in SHARDS:
		var cut := -half + step * float(i + 1)
		if i < SHARDS - 1:
			cut += rng.randf_range(-0.3, 0.3) * step
		var centre := (edge + cut) * 0.5
		# 1 at the hit, 0 at the far end.
		var near := 1.0 - clampf(absf(centre - here) / maxf(half, 1.0), 0.0, 1.0)
		var push := 30.0 + 90.0 * near
		_shards.append({
			# Thrown in world space and rotated back into the sheet's frame when
			# it is drawn. Falling is something the world does, not something the
			# sheet does, and the pieces of a sheet lying on its side have to
			# come down the same way the pieces of an upright one do.
			"drift": Vector2(rng.randf_range(-1.0, 1.0) * push,
				rng.randf_range(-0.45, 0.9) * push),
			"at": centre,
			"half": maxf((cut - edge) * 0.5, 1.0),
			"turn": rng.randf_range(-2.6, 2.6) * (0.4 + near),
		})
		edge = cut


func _burst(at: Vector2) -> void:
	if not is_inside_tree():
		return
	# Loud on purpose. Whoever was hiding needs to know their cover has gone, and
	# whoever shot it needs to know they were right to. Borrowed from the
	# explosion rather than given a sound of its own, quietly and at a fraction
	# of the size - a new sample is a separate job from making the thing work.
	Audio.explosion(at if at.is_finite() else global_position, 0.25)


## Drawn only for whoever deployed it, and faintly - until it breaks, which
## everybody sees.
##
## Invisible to everybody else is the whole gadget. Visible to its owner is what
## stops it being a trap for them as well - a sheet you cannot see is one you
## forget you are standing behind, and one you will try to shoot through.
func _draw() -> void:
	if _breaking > 0.0:
		_draw_break()
		return
	if caster != Net.peer_id():
		return
	var half := _span * 0.5
	var shimmer := 0.10 + 0.05 * sin(_life * 3.0)
	draw_line(Vector2(0.0, -half), Vector2(0.0, half),
		Color(0.62, 0.86, 1.0, shimmer + 0.12), THICK)
	draw_line(Vector2(0.0, -half), Vector2(0.0, half),
		Color(0.86, 0.96, 1.0, shimmer), 2.0)


## Coming apart, and drawn for the whole room.
##
## The one moment a screen is not a secret. Standing, it is a lie that only works
## while nobody knows it is there, so nobody but its caster gets to see it. Shot,
## the lie is already over - somebody is looking at a corridor that has just
## stopped being empty - and the picture failing in front of them is the account
## of why. Hiding the break as well would leave the shooter with a bang, a body
## that appeared out of nothing, and no explanation for either.
##
## Two stages. The whole sheet blows out white first, because a picture losing
## its hold goes bright before it goes at all; then it is in pieces, tumbling and
## falling and fading, lit brightest along their edges the way something with no
## substance is.
func _draw_break() -> void:
	var through := 1.0 - clampf(_breaking / BREAK_TIME, 0.0, 1.0)
	var half := _span * 0.5

	if through < 0.18:
		var flare := 1.0 - through / 0.18
		draw_line(Vector2(0.0, -half), Vector2(0.0, half),
			Color(0.90, 0.97, 1.0, 0.75 * flare), THICK * (1.0 + flare))

	var t := through * BREAK_TIME
	var fade := pow(1.0 - through, 1.6)
	# Back out of the world's frame into this node's. Drawing happens in local
	# space, and the pieces were thrown in world space so that they fall whichever
	# way the sheet happens to be lying.
	var lean := -global_rotation
	for shard in _shards:
		var thrown: Vector2 = shard.drift * t + Vector2(0.0, FALL * t * t)
		var centre := Vector2(0.0, float(shard.at)) + thrown.rotated(lean)
		var turn: float = shard.turn * t
		var arm := Vector2(-sin(turn), cos(turn)) * float(shard.half)
		draw_line(centre - arm, centre + arm,
			Color(0.62, 0.86, 1.0, 0.45 * fade), THICK * 0.7)
		draw_line(centre - arm, centre + arm,
			Color(0.92, 0.98, 1.0, 0.85 * fade), 1.5)
