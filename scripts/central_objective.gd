class_name CentralObjective
extends Node2D

## The raid's real prize: sits in the shaft until every subobjective has been
## captured by the same person, then can be walked up to and carried out.
##
## Deliberately never joins the "hideable" group VisionSystem hides things
## through - nothing puts it there, which is the whole trick - and is drawn
## unconditionally on the minimap and map screen (minimap.gd/map_screen.gd),
## the same way an extraction point already is. That is the "visible to
## everyone in the map" half; this file is the world-space half.
##
## Position while unclaimed is wherever the level put it. While carried, it
## is derived every frame from the carrier's own already-replicated body
## (Net.player_for(Net.objective_carrier)) rather than being sent as a
## second position of its own - the same trick Net.rail_bombs already uses.
## While dropped (carrier died) it is Net.objective_drop_at, which starts at
## Vector2.ZERO and is read as "never actually dropped" until the first real
## drop sets it - the shaft is nowhere near the world origin, so that is safe.

## Where to draw it above whoever is carrying it, so it does not sit drawn
## through their own head.
const CARRY_OFFSET := Vector2(0.0, -36.0)

## How close counts as close enough to pick it up.
@export var pickup_range := 48.0

var _spawn_at := Vector2.ZERO


func _ready() -> void:
	add_to_group(&"central_objective")
	_spawn_at = global_position


func _process(_delta: float) -> void:
	var carrier := Net.player_for(Net.objective_carrier)
	if carrier:
		global_position = carrier.global_position + CARRY_OFFSET
	elif Net.objective_carrier == 0 and Net.objective_drop_at != Vector2.ZERO:
		global_position = Net.objective_drop_at
	else:
		global_position = _spawn_at
	queue_redraw()


func _draw() -> void:
	var lit := Net.objective_unlocked
	var core := Color(0.95, 0.78, 0.25) if lit else Color(0.42, 0.46, 0.52)
	draw_circle(Vector2.ZERO, 14.0, core)
	draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, Color(core.r, core.g, core.b, 0.6), 2.0, true)
	# A pulse once it can actually be taken, so "unlocked" reads from across
	# the shaft and not only up close.
	if lit:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		draw_arc(Vector2.ZERO, 26.0 + pulse * 6.0, 0.0, TAU, 32,
			Color(core.r, core.g, core.b, 0.35 * (1.0 - pulse)), 2.0, true)
