class_name Smoke
extends Node2D

## A cloud that hides what is behind it.
##
## Sight in this game is a raycast against solid geometry, and smoke is not
## solid - so rather than fake a collider, the vision system asks the clouds
## directly whether a line of sight passes through one. Both sides use the same
## call, so smoke conceals the player from guards exactly as it conceals guards
## from the player.

var radius := 180.0
var life := 8.0

## Points around the occluder disc. Enough to read as round, few enough that
## rebuilding it every frame while the cloud billows costs nothing.
const OCCLUDER_POINTS := 16

var _age := 0.0
var _colour := Color(0.66, 0.7, 0.76, 0.85)
var _blocks := true
## Smoke does not just hide what is behind it, it shades it: the cloud stands in
## the light and throws a shadow like anything else solid enough to see. Built in
## code rather than in the scene because it has to grow with the cloud.
var _occluder: LightOccluder2D


func setup(cloud_radius: float, duration: float,
		colour := Color(0.66, 0.7, 0.76, 0.85), blocks_sight := true) -> void:
	radius = cloud_radius
	life = duration
	_colour = colour
	_blocks = blocks_sight


func _ready() -> void:
	if _blocks:
		add_to_group(&"smoke")
		_build_occluder()
	z_index = 6


## A disc that blocks light, matched to the cloud. Culling is disabled because a
## cloud has no inside or outside worth speaking of - it should shade whichever
## way the light comes at it.
func _build_occluder() -> void:
	var polygon := OccluderPolygon2D.new()
	polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED
	polygon.closed = true
	_occluder = LightOccluder2D.new()
	_occluder.occluder = polygon
	add_child(_occluder)
	_shape_occluder()


func _shape_occluder() -> void:
	if _occluder == null:
		return
	# Slightly inside the drawn edge: the visible cloud has soft edges, and a
	# shadow starting at the hard outer rim reads as bigger than the smoke.
	var r := _current_radius() * 0.86
	var points := PackedVector2Array()
	for i in OCCLUDER_POINTS:
		var angle := TAU * float(i) / OCCLUDER_POINTS
		points.append(Vector2(cos(angle), sin(angle)) * r)
	(_occluder.occluder as OccluderPolygon2D).polygon = points
	# The cloud stops shading before it stops being drawn, so the shadow thins
	# out with the smoke instead of switching off under a still-visible cloud.
	_occluder.visible = _opacity() >= 0.35


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	_shape_occluder()
	queue_redraw()


## Billows out fast, holds, then thins away.
func _current_radius() -> float:
	return radius * clampf(_age / 0.5, 0.25, 1.0)


func _opacity() -> float:
	var fade_in := clampf(_age / 0.4, 0.0, 1.0)
	var fade_out := clampf((life - _age) / 1.2, 0.0, 1.0)
	return fade_in * fade_out


func _draw() -> void:
	var r := _current_radius()
	var alpha := _opacity()
	# Three discs of decreasing size read as volume without any texture work.
	for i in 3:
		var t := float(i) / 3.0
		draw_circle(Vector2.ZERO, r * (1.0 - t * 0.28),
			Color(_colour.r, _colour.g, _colour.b, _colour.a * alpha * (0.42 + t * 0.3)))


## True if the segment from `from` to `to` passes through any live cloud.
static func blocks_sight(tree: SceneTree, from: Vector2, to: Vector2) -> bool:
	for node in tree.get_nodes_in_group(&"smoke"):
		var cloud := node as Smoke
		if cloud == null or cloud._opacity() < 0.35:
			continue
		var r: float = cloud._current_radius()
		var nearest := Geometry2D.get_closest_point_to_segment(cloud.global_position, from, to)
		if nearest.distance_to(cloud.global_position) <= r:
			return true
	return false
