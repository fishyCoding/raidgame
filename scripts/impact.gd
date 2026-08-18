extends Node2D

## Bullet hit spark: a short burst of lines along the surface normal that fades
## itself out and frees the node. Purely code-driven so there is no art to load.

@export var line_count := 5
@export var length := 14.0
@export var lifetime := 0.14

var _age := 0.0
var _lines: Array[Vector2] = []


func _ready() -> void:
	for i in line_count:
		var spread := randf_range(-0.9, 0.9)
		_lines.append(Vector2.RIGHT.rotated(spread) * randf_range(0.4, 1.0) * length)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := 1.0 - clampf(_age / lifetime, 0.0, 1.0)
	var color := Color(1.0, 1.0, 1.0, t)
	for offset in _lines:
		draw_line(Vector2.ZERO, offset * (1.0 - t * 0.4), color, 2.0 * t, true)
	draw_circle(Vector2.ZERO, 3.0 * t, color)
