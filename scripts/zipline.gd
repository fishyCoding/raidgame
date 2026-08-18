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
## addons/zipline_tools.

## Amber marks the top end, blue the bottom, in the editor and on the drag
## handles, so which end is which is never a guess.
const TOP_COLOUR := Color(1.0, 0.72, 0.28)
const BOTTOM_COLOUR := Color(0.36, 0.72, 1.0)

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


func _ready() -> void:
	add_to_group(&"zipline")


func _draw() -> void:
	draw_line(bottom, top, colour, 2.0, true)
	# Anchors at both ends, so it reads as fixed to the structure.
	for point in [top, bottom]:
		draw_circle(point, 5.0, Color(colour.r, colour.g, colour.b, 0.9))
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
