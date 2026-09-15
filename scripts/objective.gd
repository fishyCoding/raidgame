class_name CapturePoint
extends Node2D

## One of three sites that has to be personally visited - all three, by the
## same person - before the central object unlocks.
##
## Mirrors SpawnPoint's own hold_time/radius/show_hold/progress/ring-_draw
## shape closely: stand still until a ring fills. It gets its own script
## rather than subclassing SpawnPoint because what the ring means is
## different in a way that matters - SpawnPoint's is_extraction is
## deliberately per-viewer (see its own comment on why), where a
## subobjective's captured state is genuinely shared, the same value on
## every machine.
##
## Deliberately knows nothing about Net, the same way SpawnPoint does not:
## this node only ever answers "how close is this" and "how full is my
## ring." Who has captured what, and telling the host about it, is
## Player._update_capture's business - see its own comment for the split.

## Which of the three this is - matched against index into
## Net.objective_captured. 0, 1 or 2.
@export var id := 0
## Shown on the HUD prompt while in range.
@export var display_name := "SITE A"
@export var hold_time := 6.0
@export var radius := 90.0

## Pushed from outside once a frame (Player._update_capture), the same way
## SpawnPoint.is_extraction is pushed rather than read off Net directly here.
var captured := false

var _progress := 0.0


func _ready() -> void:
	add_to_group(&"objective")


func in_range(from: Vector2) -> bool:
	return global_position.distance_to(from) <= radius


## Told by the local player how far along its own hold is, the same way
## SpawnPoint.show_hold works - see Player._update_capture.
func show_hold(seconds_held: float) -> void:
	_progress = clampf(seconds_held, 0.0, hold_time)


func progress() -> float:
	return clampf(_progress / maxf(hold_time, 0.01), 0.0, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var ring := Color(0.42, 0.85, 0.6, 0.55) if captured else Color(0.98, 0.82, 0.3, 0.55)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, ring, 2.0, true)
	if not captured and progress() > 0.0:
		draw_arc(Vector2.ZERO, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * progress(),
			40, Color(1.0, 0.92, 0.5, 0.95), 4.0, true)
	draw_circle(Vector2.ZERO, 6.0, ring)
