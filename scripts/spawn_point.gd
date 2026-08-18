class_name SpawnPoint
extends Node2D

## A way into the level, and - from the other side of the ring - a way out.
##
## Every spawn is also an extraction: which one you get dropped at is rolled at
## the start of the raid, and the ones furthest from it become your way home.
## That is what makes the map a journey rather than a room: you always land with
## your exit somewhere across the doughnut.

## Shown on the briefing map.
@export var display_name := "INSERT"

## Whether this is an exit **for whoever is sitting at this screen**.
##
## Display only, and pushed here by the local player. Which points are a way home
## is per-player - it depends on where you came in, and two people who came in at
## opposite ends do not go home the same way - so it cannot live on a node there
## is only one of. It used to, and the result was that the second player to spawn
## re-marked the exits for the whole level: the furthest point from them was
## where the first player was standing, so that player landed on a live
## extraction and started leaving the moment the raid began.
var is_extraction := false

## Seconds you have to stand in one to get out.
@export var hold_time := 5.0
## How close counts as standing in it.
@export var radius := 90.0

## How full to draw the ring, 0 to 1. Also the local player's, for the same
## reason - a shared countdown is one two people can fill between them.
var _progress := 0.0


func _ready() -> void:
	add_to_group(&"spawn")


func in_range(from: Vector2) -> bool:
	return global_position.distance_to(from) <= radius


## Told by the local player how far along its own hold is, so the ring on the
## ground is that player's countdown and nobody else's. The counting itself
## happens on the player - see Player._update_extraction.
func show_hold(seconds_held: float) -> void:
	_progress = clampf(seconds_held, 0.0, hold_time)


func progress() -> float:
	return clampf(_progress / maxf(hold_time, 0.01), 0.0, 1.0)


func _process(_delta: float) -> void:
	if is_extraction:
		queue_redraw()


func _draw() -> void:
	if not is_extraction:
		return
	# A ring on the ground, brighter as it fills. Deliberately visible from a
	# distance: an extraction you cannot find is not an extraction.
	var green := Color(0.42, 0.85, 0.6, 0.5)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, green, 2.0, true)
	if progress() > 0.0:
		draw_arc(Vector2.ZERO, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * progress(),
			40, Color(0.6, 1.0, 0.75, 0.95), 4.0, true)
	draw_circle(Vector2.ZERO, 6.0, green)
