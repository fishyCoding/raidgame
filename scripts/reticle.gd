class_name Reticle
extends Node2D

## Floats at a fixed radius from the player along the aim line, mouse or stick.
##
## The gap between the ticks is not decorative: it is the actual cone half-width
## at this distance (radius * tan(spread)), so what you see is where rounds can
## land. Bloom from firing widens it live.

@export var radius := 220.0
@export var min_gap := 3.0
@export var tick_length := 9.0
@export var thickness := 2.0
@export var color := Color(0.85, 0.93, 1.0, 0.9)
@export var empty_color := Color(1.0, 0.36, 0.36, 0.95)
@export var reload_color := Color(1.0, 0.78, 0.35, 0.95)

## Hit confirmation. Four diagonal ticks that snap in and fade - the classic
## shape, because it is instantly readable and never mistaken for the aim ticks,
## which are axis-aligned. Colour carries the rest: white for a hit, amber for a
## headshot, red for a kill.
enum Mark { NONE, HIT, HEADSHOT, KILL }

@export var marker_color := Color(1.0, 1.0, 1.0, 0.95)
@export var marker_headshot_color := Color(1.0, 0.82, 0.35, 0.98)
@export var marker_kill_color := Color(1.0, 0.35, 0.32, 1.0)
## How long a marker stays up. Short: it has to keep up with a fast weapon.
@export var marker_time := 0.32

## Cone half-angle in radians, written by the player each frame.
var spread := 0.0
var reload_progress := 0.0
var is_reloading := false
var is_empty := false

var _mark := Mark.NONE
var _mark_age := 0.0


## Called when a round of yours lands. A kill overrides a plain hit already on
## screen; a plain hit never overwrites a kill, so the last thing you see from a
## burst that killed someone is the kill.
func flash(mark: Mark) -> void:
	if mark == Mark.NONE:
		return
	if _mark == Mark.KILL and _mark_age < marker_time and mark != Mark.KILL:
		return
	_mark = mark
	_mark_age = 0.0


func _process(delta: float) -> void:
	if _mark != Mark.NONE:
		_mark_age += delta
		if _mark_age >= marker_time:
			_mark = Mark.NONE
	queue_redraw()


func _draw() -> void:
	var gap := maxf(radius * tan(spread), min_gap)
	var tint := color
	if is_reloading:
		tint = reload_color
	elif is_empty:
		tint = empty_color

	# Ticks are drawn in local space; the node is rotated to the aim angle, so
	# "up/down" here means perpendicular to the shot line.
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(dir * gap, dir * (gap + tick_length), tint, thickness, true)

	draw_circle(Vector2.ZERO, 1.5, tint)

	if is_reloading:
		var r := gap + tick_length + 6.0
		draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * reload_progress,
			24, reload_color, 2.0, true)

	if _mark != Mark.NONE:
		_draw_marker(gap)


## The marker punches outward from the centre and fades. It is drawn in the
## node's own rotated space like everything else here, but the diagonals stay
## legible at any aim angle, which is why they read as separate from the ticks.
func _draw_marker(gap: float) -> void:
	var t := clampf(_mark_age / maxf(marker_time, 0.01), 0.0, 1.0)
	# Snap out over the first fifth, then hold and fade.
	var punch := 1.0 - pow(1.0 - clampf(t / 0.2, 0.0, 1.0), 3.0)
	var fade := 1.0 - pow(t, 2.0)

	var tint := marker_color
	var length := 7.0
	var width := 2.0
	match _mark:
		Mark.HEADSHOT:
			tint = marker_headshot_color
			length = 9.0
		Mark.KILL:
			tint = marker_kill_color
			length = 11.0
			width = 2.5

	var inner := gap * 0.55 + 3.0 + punch * 4.0
	tint.a *= fade
	for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var dir := (corner as Vector2).normalized()
		draw_line(dir * inner, dir * (inner + length), tint, width, true)

	# A kill gets a ring as well: the difference between hurting someone and
	# finishing them should not be a shade of colour you have to look at.
	if _mark == Mark.KILL:
		draw_arc(Vector2.ZERO, inner + length + 4.0, 0.0, TAU, 28,
			Color(tint, tint.a * 0.5), 1.5, true)
