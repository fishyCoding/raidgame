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
	_watch_timer -= delta
	if _watch_timer > 0.0:
		return
	_watch_timer = WATCH_INTERVAL
	var lit := _someone_is_riding() and _at_an_end(Net.local_player)
	if lit != _warning_lit:
		_warning_lit = lit
		queue_redraw()


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
	return minf(to_top, to_bottom) <= WARN_RANGE


func _draw() -> void:
	# A rope with somebody on it, seen from the end they are heading for. The
	# cable is scenery for the whole raid until this moment, which is exactly why
	# a colour is enough - nothing else about it ever changes.
	var line := OCCUPIED_COLOUR if _warning_lit else colour
	var width := OCCUPIED_WIDTH if _warning_lit else 2.0
	draw_line(bottom, top, line, width, true)
	# Anchors at both ends, so it reads as fixed to the structure.
	for point in [top, bottom]:
		draw_circle(point, 6.0 if _warning_lit else 5.0,
			Color(line.r, line.g, line.b, 0.9))
	if Engine.is_editor_hint() and show_guides:
		_draw_guides()


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
