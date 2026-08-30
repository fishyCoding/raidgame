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

## And what it turns while a rail bomb is on it.
##
## Yellow rather than the amber above, and a harder yellow than that one is: the
## two states mean different things and the difference has to survive being seen
## out of the corner of an eye. Amber is "somebody is coming up this"; this is
## "do not get on this at all".
##
## Unconditional, unlike the amber. That one is a courtesy shown to a man
## standing at an end who could actually see the rider, and it is deliberately
## withheld through a wall. This is not a courtesy - it is the hazard itself,
## visible to anyone who can see the rope, because a bomb you only find out
## about by grabbing the cable is a bomb the rope lied about.
const BOMBED_COLOUR := Color(1.0, 0.92, 0.15, 1.0)
const BOMBED_WIDTH := 4.5

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

## The Rail Bomb ultimate, read for the numbers the bomb runs on so they live in
## the resource with the rest of the gadget's numbers rather than being typed
## twice. The bomb's own behaviour is in RailBomb; this file only carries it.
const BOMB: GadgetData = preload("res://resources/gadgets/rail_bomb.tres")

## How near a cable Player.arc_at has to fall for the bomb to be this cable's.
## Generous on purpose: arc_at is the midpoint of whatever cable was in reach
## when it was cast, so an exact match is the normal case and this only has to
## survive the two ends being dragged since.
const ARC_MATCH := 24.0

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

## The rail bomb riding this cable, if there is one. Built and freed locally on
## every machine off replicated numbers - see _carry_the_bomb - so it is not a
## thing that is spawned or despawned across the wire.
var _bomb: RailBomb = null

## True while that bomb is actually on the rope, which is what turns the cable
## yellow. Goes false again the moment it runs out of rope and lets go: at that
## point the cable is just a cable and the danger is the thing in the air above
## it, which is drawing plenty of attention to itself.
var _bombed := false


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


## Watching for riders, and carrying whatever is clamped to the rope.
##
## Nothing is sent for either. A rider's `riding` flag is already replicated and
## so is their position, so every machine can work out for itself that somebody
## is on this particular cable - which is the whole trick, because the cable
## they are on is not replicated and does not need to be. The bomb is the same
## idea applied to a thing that moves.
func _process(_delta: float) -> void:
	# Every frame, not on the watch interval. A bomb whose position is only
	# refreshed ten times a second is a bomb that visibly stutters up the rope,
	# and one that jolts a rider it passed a tenth of a second ago is one that
	# plainly is not doing what it looks like it is doing.
	#
	# Cheap anyway, because the scan of who has a bomb out happens once per
	# frame for the whole level rather than once per cable - see
	# Net.rail_bombs. A hundred cables asking it is a hundred walks of a list
	# that is empty almost all of the time.
	_carry_the_bomb()
	var lit := _someone_is_riding() and _at_an_end(Net.local_player)
	if lit != _warning_lit:
		_warning_lit = lit
		queue_redraw()


## The rail bomb clamped to this cable, if there is one, kept in step with the
## five numbers it is derived from.
##
## Every machine runs this and every machine reaches the same answer, because
## the five numbers are replicated and the arithmetic is the same everywhere -
## see RailBomb for what they are and why none of it is sent. The cable owns the
## local copy because the cable is the thing the bomb is attached to and the
## thing that knows where its own ends are; when the cell runs flat the bomb is
## freed here, on every machine at once, without anybody being told.
func _carry_the_bomb() -> void:
	var mine := _bomb_on_me()
	if mine.is_empty():
		if _bomb != null:
			if is_instance_valid(_bomb):
				_bomb.queue_free()
			_bomb = null
		_set_bombed(false)
		return

	if _bomb == null or not is_instance_valid(_bomb):
		_bomb = RailBomb.new()
		# Deliberately *not* a child of this cable. A zipline is lifted onto the
		# overlay that the ambient dark cannot reach, because a route is map
		# knowledge you were already shown on the briefing - see
		# _lift_above_the_dark. A bomb is the opposite of map knowledge: it is
		# news about somebody, it is somewhere different every raid, and hung off
		# the rope it inherited a permanent floodlight and could be read across a
		# blacked-out yard through two walls.
		#
		# So it lives in the ordinary world with the grenades, where the dark
		# tints it, and it carries the "shadowed" group so line of sight decides
		# whether you see it at all. Its position is set in global coordinates
		# either way, so nothing about the climb depends on who its parent is.
		var into := Net.effect_root()
		if into == null:
			_bomb = null
			return
		into.add_child(_bomb)
		_bomb.arm(self, int(mine["by"]), BOMB.damage, BOMB.sight_range, BOMB.hit_points)

	var length := cable_length()
	var way := int(mine["way"])
	var at := float(mine["from"])
	var stopped := float(mine["stop"])
	if way != 0 and length >= 1.0:
		# How far it has climbed since it was pointed, worked out from the clock
		# rather than accumulated - a position that is integrated frame by frame
		# drifts apart between machines, and one that is a function of a
		# replicated number cannot.
		#
		# The clock stops where it got off. Once arc_stop is set the position
		# stops being a function of the running clock and becomes a function of
		# that one frozen reading, which is how a bomb that broke off early sits
		# in the same spot on every screen - and, just as importantly, why the
		# cell can be reset underneath it without the thing sliding.
		var clock: float = stopped if stopped > 0.0 else float(mine["left"])
		var travelled: float = (float(mine["launch"]) - clock) * BOMB.travel_speed
		at = clampf(at + float(way) * travelled / length, 0.0, 1.0)
	var end_of_rope := way != 0 and (at <= 0.0 or at >= 1.0)
	var off_the_rope := way != 0 and (stopped > 0.0 or end_of_rope)
	_bomb.place(at, way, off_the_rope)
	_set_bombed(not off_the_rope)

	# Getting off, decided once and on one machine.
	#
	# This is the owner's copy of the bomb, so this is the machine whose sight
	# lines count and whose numbers these are; every other machine reads the
	# answer off arc_stop rather than reaching it - see RailBomb, which explains
	# why a decision about what can be seen must not be made twice.
	if way == 0 or stopped > 0.0:
		return
	if not (end_of_rope or _bomb.wants_off):
		return
	var owner := Net.local_player
	if owner == null or owner.get_multiplayer_authority() != int(mine["by"]):
		return
	owner.arc_stop = float(mine["left"])
	# And the cell is re-cut to the hover: ten seconds of holding station,
	# however long the climb took to get here. Set rather than subtracted - a
	# bomb that spent most of its charge getting up a long rope would otherwise
	# arrive with nothing left to do at the top, which is the half of the gadget
	# that matters.
	owner.arc_left = BOMB.hover_time


## Only redraws on the edge. The cable is static scenery for the whole raid and
## a queue_redraw every frame on every rope in the level is a hundred redraws a
## frame for a picture that changes twice.
func _set_bombed(now: bool) -> void:
	if now == _bombed:
		return
	_bombed = now
	queue_redraw()


## The bomb belonging to this cable, or an empty dictionary.
##
## Matched on the cable's midpoint, which is what arc_at holds: either end of a
## rope is a place a second rope can also end, and the middle of one belongs to
## one rope only.
func _bomb_on_me() -> Dictionary:
	# Net gathers these once a frame for the whole level, so a hundred cables
	# asking is a hundred walks of a list that is almost always empty.
	for bomb in Net.rail_bombs:
		var at: Vector2 = bomb["at"]
		if closest_point(at).distance_to(at) <= ARC_MATCH:
			return bomb
	return {}


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
	#
	# The bomb outranks the rider warning when both are true, and that is the
	# right way round: one of them is telling you somebody is coming and the
	# other is telling you the rope itself will kill you, and there is no reading
	# of a fight in which the first is the more useful thing to know.
	var line := colour
	var width := 2.0
	var anchor := 5.0
	if _bombed:
		line = BOMBED_COLOUR
		width = BOMBED_WIDTH
		anchor = 7.0
	elif _warning_lit:
		line = OCCUPIED_COLOUR
		width = OCCUPIED_WIDTH
		anchor = 6.0
	draw_line(bottom, top, line, width, true)
	# Anchors at both ends, so it reads as fixed to the structure.
	for point in [top, bottom]:
		draw_circle(point, anchor, Color(line.r, line.g, line.b, 0.9))
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
