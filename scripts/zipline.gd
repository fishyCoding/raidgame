@tool
class_name Zipline
extends Node2D

## A cable you can ride up or down, and the only way to reach the high ground
## quickly.
##
## Vertical on purpose: the level is wide and flat without them, and a fight you
## can only leave sideways is a fight you are stuck in. A zipline is a commitment
## - riding one puts you in the open, moving predictably, which is exactly when
## someone shoots you.
##
## Runs as @tool so the cable, its ends and its reach are visible while you are
## placing it. The endpoints can be dragged in the 2D viewport - see
## addons/endpoint_tools, which does the same for a Platform.

## Amber marks the top end, blue the bottom, in the editor and on the drag
## handles, so which end is which is never a guess.
const TOP_COLOUR := Color(1.0, 0.72, 0.28)
const BOTTOM_COLOUR := Color(0.36, 0.72, 1.0)

## What the cable turns while somebody is riding it - but only for a player
## standing at one of its ends. See _warning_lit.
const OCCUPIED_COLOUR := Color(1.0, 0.78, 0.2, 0.95)
const OCCUPIED_WIDTH := 3.5

## How close to an end you have to be standing for the cable to warn you.
##
## Two seconds of travel on a default cable, not one. 340 px was the distance a
## rider covers in the second before they land, which turned out to be the wrong
## thing to measure: a warning that arrives a second out is a warning you react
## to after the fact. This is long enough to look up and decide.
##
## It is longer than plenty of cables in the level are, which is fine and not an
## accident - on a short hop the whole rope is inside the warning and anyone near
## either end sees it, which is exactly who is at risk on a rope that short.
const WARN_RANGE := 680.0

## What the sight check for the warning is cast against, and how far short of
## the cable it stops. Same mask as vision_system: solid geometry only, so a
## one-way catwalk and another player are both see-through for this.
const SIGHT_MASK := Layers.WORLD
const SIGHT_INSET := 8.0

## The Live Rail ultimate, read for its damage so the number lives in the
## resource with the rest of the gadget's numbers rather than being typed twice.
const RAIL: GadgetData = preload("res://resources/gadgets/live_rail.tres")

## How near a cable Player.arc_at has to fall for the current to be this cable's.
## Generous on purpose: arc_at is the midpoint of whatever cable was in reach
## when it was cast, so an exact match is the normal case and this only has to
## survive the two ends being dragged since.
const ARC_MATCH := 24.0

## What a hot cable looks like, and how fast it crawls.
const LIVE_COLOUR := Color(0.62, 0.92, 1.0, 1.0)
const LIVE_CORE := Color(1.0, 1.0, 1.0, 0.9)
const LIVE_WIDTH := 4.0
const ARC_SEGMENTS := 14
const ARC_SPREAD := 5.0
const ARC_HZ := 18.0

## How often the cable checks whether anyone is on it. Cheap either way - a
## handful of players against one segment - but this runs on every cable in the
## level and there is nothing to be gained from doing it at the frame rate.
const WATCH_INTERVAL := 0.1

## Ends of the cable, relative to this node.
@export var top := Vector2(0, -300):
	set(value):
		top = value
		_refresh()

@export var bottom := Vector2(0, 0):
	set(value):
		bottom = value
		_refresh()

## How fast a rider travels, pixels per second along the cable. This is the
## cable's own number, not the rider's: a long haul across the yard can be quick
## while a short lift up a tower is a slow, exposed climb.
@export_range(40.0, 1200.0, 1.0, "or_greater") var speed := 330.0:
	set(value):
		speed = value
		_refresh()

## How close you have to be to grab it.
@export_range(8.0, 200.0, 1.0, "or_greater") var grab_range := 46.0:
	set(value):
		grab_range = value
		_refresh()

@export var colour := Color(0.62, 0.68, 0.76, 0.7):
	set(value):
		colour = value
		_refresh()

## Labels, reach envelope and ride time, drawn in the editor only. Turn off for
## a cable you have finished placing and no longer want to look at.
@export var show_guides := true:
	set(value):
		show_guides = value
		_refresh()


## True while somebody is riding this cable and the local player is standing at
## one end of it. Drives the colour and nothing else.
var _warning_lit := false
var _watch_timer := 0.0

## True while somebody's Live Rail is running through this cable. Worked out on
## every machine rather than sent - see _current_through_me.
var _live := false
var _was_live := false
var _powered_by := 0
var _arc_phase := 0.0


func _ready() -> void:
	add_to_group(&"zipline")
	# The editor draws a cable nobody is riding, so it has no reason to look.
	set_process(not Engine.is_editor_hint())
	if not Engine.is_editor_hint():
		# Deferred: the level is still being built around us, and this moves the
		# node to a different branch of it.
		_lift_above_the_dark.call_deferred()


## Puts the cable on the layer the ambient dark does not reach.
##
## A zipline is map knowledge, not news about anybody. It is in the same place
## every raid, it was on the briefing map you were shown on the way in, and a
## route you have already been told about is not worth hiding - a cable you
## cannot see in an unlit room is a way up you have to walk over to find.
##
## A grapple line is the opposite of this and stays where it is: somebody else's
## rope drawn across a dark room says where they are, which way they are going
## and roughly how fast, none of it earned by looking. That one is in the
## "shadowed" group and the dark takes it - see GrappleHook.
##
## The overlay is a CanvasLayer that follows the viewport, so world coordinates
## still mean what they meant and the cable does not move a pixel; what stops
## applying is the CanvasModulate on the layer below it. The cost is that a cable
## now draws in front of the wall it used to pass behind, which is the same trade
## every other thing on that layer has already made.
func _lift_above_the_dark() -> void:
	var overlay := get_tree().get_first_node_in_group(&"world_overlay") as CanvasLayer
	var parent := get_parent()
	if overlay == null or parent == null or parent == overlay:
		return
	# Kept as a transform rather than a position: the container a cable is filed
	# under is not guaranteed to sit at the origin, and a level where it does not
	# would otherwise slide every cable in it.
	var was := global_transform
	parent.remove_child(self)
	overlay.add_child(self)
	global_transform = was


## Watching for riders.
##
## Nothing is sent for this. A rider's `riding` flag is already replicated and so
## is their position, so every machine can work out for itself that somebody is
## on this particular cable - which is the whole trick, because the cable they
## are on is not replicated and does not need to be.
func _process(delta: float) -> void:
	# Damage every frame, but only once we already know the cable is hot. Who is
	# powering it is re-asked on the watch interval below with everything else -
	# scanning every player from every cable in the level sixty times a second
	# is a lot of work to keep answering "nobody", and there are a hundred
	# cables on the quarry. The cost of asking at 10Hz is up to a tenth of a
	# second of grace at either end of the effect, which is the same tolerance
	# the warning colour has always had.
	if _live:
		_arc_phase += delta
		_electrocute(delta, _powered_by)
		queue_redraw()

	_watch_timer -= delta
	if _watch_timer > 0.0:
		return
	_watch_timer = WATCH_INTERVAL

	_powered_by = _current_through_me()
	_live = _powered_by != 0
	if _live != _was_live:
		queue_redraw()
	_was_live = _live
	var lit := _someone_is_riding() and _at_an_end(Net.local_player)
	if lit != _warning_lit:
		_warning_lit = lit
		queue_redraw()


## Whether somebody has put current through this particular cable.
##
## Read off the players rather than told to us, the same way riders are. Every
## machine has every player's arc_at and arc_left, so every machine reaches this
## answer on its own and the effect needs no message of its own - see
## Player.arc_at.
## Returns the peer id of whoever is powering it, or 0 for a dead cable - so the
## kill goes to the person who threw the switch rather than to nobody.
func _current_through_me() -> int:
	for body in Net.players():
		if body == null or not is_instance_valid(body):
			continue
		var left: Variant = body.get(&"arc_left")
		if typeof(left) != TYPE_FLOAT or left <= 0.0:
			continue
		var at: Variant = body.get(&"arc_at")
		if typeof(at) != TYPE_VECTOR2:
			continue
		if closest_point(at).distance_to(at) <= ARC_MATCH:
			return (body as Node).get_multiplayer_authority()
	return 0


## Hurts whoever is hanging off a live cable.
##
## Host only, like every other source of damage in the game - see
## Net.deals_damage. Every machine draws the sparks; one of them decides what
## they cost.
##
## Riders only. Standing at either end of a hot cable is safe, and that is the
## point of it: the gadget does not deny the ledge, it denies the rope. A ride
## is already a commitment you cannot break off halfway, so what this really
## does is turn one that is already underway into a mistake.
func _electrocute(delta: float, powered_by: int) -> void:
	if not Net.deals_damage():
		return
	for body in Net.players():
		if body == null or not is_instance_valid(body):
			continue
		if (body as Node).get_multiplayer_authority() == powered_by:
			continue   # your own rail does not bite you
		var rides: Variant = body.get(&"riding")
		if typeof(rides) != TYPE_BOOL or not rides:
			continue
		if not in_reach(body.global_position):
			continue
		if not body.has_method(&"take_damage"):
			continue
		# Aimed at the body's own centre, which Damage.resolve reads as a body
		# shot: current is not a projectile and should not be rolling headshots.
		# Along the rope for a direction, because that is the way it is running.
		Net.attributing_to = powered_by
		body.take_damage(RAIL.damage * delta, body.global_position, direction())
		Net.attributing_to = 0


## Whether somebody *other than you* is hanging off this cable.
##
## Matched on position rather than on the cable itself: `riding` travels between
## machines and the Zipline reference cannot, so a rider is somebody in the air
## on this segment. Two cables would have to overlap for that to be wrong, and
## then both lighting up is the right answer anyway.
##
## You do not count as a rider on your own screen. A ride starts at an end of
## the cable, so counting yourself would flash the warning in your face every
## time you grabbed one - telling you a thing you had just done.
func _someone_is_riding() -> bool:
	var me := Net.local_player
	var riders: Array = Net.players()
	# Ghosts count, and have to. A projection is a lie told to the eye, and a
	# cable that lit up for a person and stayed grey for a decoy would be the
	# level itself giving the lie away - somebody at the top of a rope would
	# learn to read "no warning" as "that is not a man". See Projection.
	riders.append_array(get_tree().get_nodes_in_group(&"projection"))
	for body in riders:
		if body == me or body == null or not is_instance_valid(body):
			continue
		var rides: Variant = body.get(&"riding")
		if typeof(rides) != TYPE_BOOL or not rides:
			continue
		if in_reach(body.global_position):
			return true
	return false


## Whether a body is stood at either end of the cable, which is where a rider
## arriving would be on top of them.
##
## Both ends, not just the far one: the danger is somebody appearing next to you,
## and that happens at whichever end you are standing at.
func _at_an_end(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var at := body.global_position
	var to_top := at.distance_to(world_top())
	var to_bottom := at.distance_to(world_bottom())
	if minf(to_top, to_bottom) > WARN_RANGE:
		return false
	return _in_sight_of(at)


## Whether the cable can actually be seen from a point.
##
## The warning is a thing you notice, and you cannot notice a rope through a
## wall. Standing at the top of a shaft with a floor between you and the cable
## used to light it amber anyway - which told you somebody was coming, from a
## direction you had no way of watching, through geometry that was the whole
## reason you felt safe standing there.
##
## Aimed at the nearest point of the cable rather than at either end, because
## the end you are near is the end you might be standing on the far side of, and
## what matters is whether any of the rope is visible from here.
##
## WORLD only, the same mask vision_system uses. A one-way catwalk you can see
## through does not hide the cable, and neither does another player.
func _in_sight_of(from: Vector2) -> bool:
	var world := get_world_2d()
	if world == null:
		return true
	var to := closest_point(from)
	# Pulled back off the cable so the ray does not start inside whatever the
	# cable is bolted to and report the anchor as the thing in the way.
	var span := to - from
	if span.length() <= SIGHT_INSET:
		return true
	to -= span.normalized() * SIGHT_INSET
	var query := PhysicsRayQueryParameters2D.create(from, to, SIGHT_MASK)
	query.hit_from_inside = false
	return world.direct_space_state.intersect_ray(query).is_empty()


func _draw() -> void:
	# A rope with somebody on it, seen from the end they are heading for. The
	# cable is scenery for the whole raid until this moment, which is exactly why
	# a colour is enough - nothing else about it ever changes.
	if _live:
		_draw_live()
		return
	var line := OCCUPIED_COLOUR if _warning_lit else colour
	var width := OCCUPIED_WIDTH if _warning_lit else 2.0
	draw_line(bottom, top, line, width, true)
	# Anchors at both ends, so it reads as fixed to the structure.
	for point in [top, bottom]:
		draw_circle(point, 6.0 if _warning_lit else 5.0,
			Color(line.r, line.g, line.b, 0.9))
	if Engine.is_editor_hint() and show_guides:
		_draw_guides()


## A hot cable, drawn as a rope with something wrong with it.
##
## Deliberately unmissable and deliberately not the amber warning. Amber means
## somebody is on this rope; this means the rope will kill you, and reading one
## as the other in the second you have to decide is the whole cost of the
## gadget being subtle. The zigzag is seeded off a clock so it crawls, because a
## static lightning bolt reads as a decal rather than as current.
func _draw_live() -> void:
	var span := top - bottom
	var length := span.length()
	if length < 1.0:
		return
	var along := span / length
	var side := along.orthogonal()
	var points := PackedVector2Array()
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / float(ARC_SEGMENTS)
		var wobble := 0.0
		if i > 0 and i < ARC_SEGMENTS:
			# Two waves at odds with each other, so it never looks like a sine.
			wobble = (sin(t * 22.0 + _arc_phase * ARC_HZ)
				+ sin(t * 9.0 - _arc_phase * ARC_HZ * 0.6)) * 0.5 * ARC_SPREAD
		points.append(bottom + along * (length * t) + side * wobble)
	draw_polyline(points, LIVE_COLOUR, LIVE_WIDTH, true)
	# A straight white core under the crackle: the rope is still there, and
	# where it runs is still the thing you are judging.
	draw_line(bottom, top, LIVE_CORE, 1.5, true)
	for point in [top, bottom]:
		draw_circle(point, 7.0, LIVE_COLOUR)


func world_top() -> Vector2:
	return to_global(top)


func world_bottom() -> Vector2:
	return to_global(bottom)


func cable_length() -> float:
	return top.distance_to(bottom)


## Which way is up the cable, in world space. Zero for a collapsed cable, which
## leaves a rider stationary rather than sending them somewhere undefined.
func direction() -> Vector2:
	return (world_top() - world_bottom()).normalized()


## Nearest point on the cable to a position, and how far away that is.
func closest_point(to: Vector2) -> Vector2:
	return Geometry2D.get_closest_point_to_segment(to, world_top(), world_bottom())


func in_reach(from: Vector2) -> bool:
	return closest_point(from).distance_to(from) <= grab_range


## Clamps a position to the cable, so a rider cannot slide off the end.
func clamp_to_cable(at: Vector2) -> Vector2:
	return closest_point(at)


## The nearest cable in reach of a point, or null.
static func nearest(tree: SceneTree, from: Vector2) -> Zipline:
	var best: Zipline = null
	var best_distance := INF
	for node in tree.get_nodes_in_group(&"zipline"):
		var line := node as Zipline
		if line == null or not line.in_reach(from):
			continue
		var distance := line.closest_point(from).distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = line
	return best


func _refresh() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		update_configuration_warnings()


## Everything below here is editor decoration and never runs in game.
func _draw_guides() -> void:
	var span := top - bottom
	var length := span.length()
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size

	if length < 1.0:
		# Nothing to draw a direction from - just flag the collapsed cable.
		draw_arc(top, 10.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.3), 2.0, true)
		draw_string(font, top + Vector2(16, 4), "both ends here",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.3, 0.3))
		return

	var along := span / length
	var side := along.orthogonal() * grab_range
	var angle := along.angle()
	# The reach envelope: stand anywhere inside this and the grab prompt appears.
	var reach := Color(colour.r, colour.g, colour.b, 0.35)
	draw_dashed_line(bottom + side, top + side, reach, 1.0, 7.0)
	draw_dashed_line(bottom - side, top - side, reach, 1.0, 7.0)
	draw_arc(top, grab_range, angle - PI * 0.5, angle + PI * 0.5, 24, reach, 1.0, true)
	draw_arc(bottom, grab_range, angle + PI * 0.5, angle + PI * 1.5, 24, reach, 1.0, true)

	# Ends: a ring for the top, a disc for the bottom, so they stay tellable
	# apart even when the cable runs sideways and "up" means nothing.
	draw_arc(top, 9.0, 0.0, TAU, 28, TOP_COLOUR, 2.0, true)
	draw_circle(bottom, 7.0, BOTTOM_COLOUR)

	draw_string(font, top + Vector2(14, -8), "TOP",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TOP_COLOUR)
	draw_string(font, bottom + Vector2(14, 18), "BOTTOM",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BOTTOM_COLOUR)
	# Ride time is the number that actually matters when placing one: how long
	# you are hanging in the open on it.
	var seconds := length / maxf(speed, 1.0)
	draw_string(font, (top + bottom) * 0.5 + Vector2(14, 4),
			"%d px  -  %.1fs ride" % [roundi(length), seconds],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(colour.r, colour.g, colour.b, 0.9))


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var length := cable_length()
	if length < 1.0:
		warnings.append("Top and bottom are in the same place, so there is no cable to ride.")
	elif length <= grab_range:
		warnings.append("The cable is %d px long but grab range is %d px, so a rider is at both ends at once and cannot travel." % [roundi(length), roundi(grab_range)])
	if speed <= 0.0:
		warnings.append("Speed is %d, so a rider would never move." % roundi(speed))
	return warnings
