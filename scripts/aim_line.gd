class_name AimLine
extends Node2D

## The sight picture: a straight line from the muzzle through the reticle and on
## down range, with the spread cone drawn either side of it.
##
## The line is exactly the path a perfectly centred round takes, and it carries
## on well past the reticle so a target far beyond aiming distance can still be
## lined up - the reticle marks where the cone is measured, not how far the gun
## reaches. The cone edges run out with it and keep diverging, so at long range
## you can see how much of the distant ground the spread actually covers. The arc
## closes the cone at the reticle's distance.
##
## Purely a readout: nothing here feeds back into aiming or firing.

## Both ends in world space, written by whoever holds the gun.
var from := Vector2.ZERO
var to := Vector2.ZERO
## Cone half-angle in radians, the same value the bullets are jittered by.
var spread := 0.0
## 0 hip-fire, 1 fully aimed. Brightens the whole picture.
var focus := 0.0
## Where a grenade would land, while one is being wound up. Drawn here because
## this node already lives on the overlay layer, above the world's darkness.
##
## The bow uses the same three fields for the same reason: an arrow is a thing
## that flies, drops and lands somewhere, which is exactly what this already
## draws. Two arc renderers that had to be kept looking alike would be two
## chances to drift.
var arc_points: PackedVector2Array = PackedVector2Array()
var arc_power := 0.0
var showing_arc := false
## What the thing does where it lands, in world pixels. A grenade leaves this at
## zero and gets the plain ring; a recon arrow sets it to the sweep it will paint
## so the shot can be placed on a room rather than on a spot. Being able to see
## the circle shrink as the draw comes off is the whole argument for winding the
## bow up at all.
var arc_radius := 0.0
## Overrides the arc's colour. Zero alpha means "use the grenade's amber". The
## bow is blue, the same blue everything recon is drawn in, because a blue circle
## on a wall means one thing in this game and it should keep meaning it.
var arc_tint := Color(0, 0, 0, 0)

@export var color := Color(0.72, 0.85, 1.0, 0.16)
## Colour once fully aimed. Brighter, because by then the line is a sight.
@export var aimed_color := Color(0.85, 0.93, 1.0, 0.5)
## The cone edges and arc are drawn fainter than the centre line, so the shot
## line stays the thing your eye lands on.
@export_range(0.0, 1.0) var cone_alpha_scale := 0.55
@export var width := 1.5
## Gap left at the muzzle so the line does not overlap the arm.
@export var muzzle_gap := 12.0
## Gap left before the reticle so the centre dot stays readable.
@export var reticle_gap := 16.0
## How far the line carries on past the reticle, in pixels, fading as it goes.
## This is the part you aim distant shots with.
@export var overshoot := 900.0
## Below this cone width the arc is not worth drawing.
@export var min_spread_degrees := 0.12

const STEPS := 24


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var muzzle := to_local(from)
	var tip := to_local(to)
	var span := tip - muzzle
	var reach := span.length()
	if reach <= muzzle_gap + reticle_gap:
		return

	var angle := span.angle()
	var tint := color.lerp(aimed_color, focus)
	var far := reach + overshoot

	# Centre line in two pieces, so the reticle's own centre dot stays clear.
	_draw_ray(muzzle, angle, muzzle_gap, reach - reticle_gap, reach, far, tint)
	_draw_ray(muzzle, angle, reach + reticle_gap, far, reach, far, tint)

	if spread > deg_to_rad(min_spread_degrees):
		_draw_cone(muzzle, reach, far, angle, tint)

	if showing_arc:
		_draw_throw_arc()


## The grenade arc: dots along the flight and a ring where it lands.
func _draw_throw_arc() -> void:
	if arc_points.size() < 2:
		return
	var tint := Color(0.7, 0.78, 0.86, 0.6).lerp(Color(1.0, 0.72, 0.34, 0.95), arc_power)
	if arc_tint.a > 0.0:
		tint = Color(arc_tint, lerpf(arc_tint.a * 0.45, arc_tint.a, arc_power))
	for i in arc_points.size():
		if i % 3 != 0:
			continue
		var fade := 1.0 - float(i) / float(arc_points.size())
		draw_circle(to_local(arc_points[i]), lerpf(1.5, 3.5, fade),
			Color(tint.r, tint.g, tint.b, tint.a * (0.35 + 0.65 * fade)))

	var landing := to_local(arc_points[arc_points.size() - 1])
	draw_arc(landing, 9.0, 0.0, TAU, 20, tint, 1.5, true)
	draw_circle(landing, 2.0, tint)
	if arc_radius > 1.0:
		# What it will actually cover, drawn on the ground it will cover.
		# Fainter than the flight path and the landing mark: it is the answer
		# to "is that room inside it", which you check once, not the thing you
		# are steering with.
		draw_arc(landing, arc_radius, 0.0, TAU, 64,
			Color(tint.r, tint.g, tint.b, tint.a * 0.4), 1.5, true)


## One ray from the muzzle, drawn between two distances. Alpha fades in off the
## muzzle and fades out beyond `reach`, so the far end trails away instead of
## stopping dead in mid-air.
func _draw_ray(muzzle: Vector2, angle: float, near: float, end: float,
		reach: float, far: float, tint: Color) -> void:
	if end <= near:
		return
	var dir := Vector2.RIGHT.rotated(angle)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i in STEPS + 1:
		var distance := lerpf(near, end, float(i) / float(STEPS))
		points.append(muzzle + dir * distance)
		var alpha := tint.a
		if distance <= reach:
			alpha *= smoothstep(muzzle_gap, muzzle_gap + 45.0, distance)
		else:
			alpha *= 1.0 - smoothstep(reach, far, distance)
		colors.append(Color(tint.r, tint.g, tint.b, alpha))
	draw_polyline_colors(points, colors, width, true)


## Two edges running out alongside the shot line, closed by an arc at the
## reticle's distance. Everything between them is where a round can land.
func _draw_cone(muzzle: Vector2, reach: float, far: float, angle: float, tint: Color) -> void:
	var edge := Color(tint.r, tint.g, tint.b, tint.a * cone_alpha_scale)

	for side in [-1.0, 1.0]:
		# Edges start further out than the centre line: near the muzzle the cone
		# is only a few pixels wide and the three lines would just smear together.
		_draw_ray(muzzle, angle + spread * side, reach * 0.35, far, reach, far, edge)

	draw_arc(muzzle, reach, angle - spread, angle + spread,
		maxi(8, int(rad_to_deg(spread) * 2.0)), edge, width, true)
