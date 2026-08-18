extends Control

## The map: the whole level drawn to scale, with where you came in and where you
## can get out.
##
## Shown once at the start of the raid as a briefing, and any time you press M.
## It is drawn from the level's own geometry rather than from a hand-made image,
## so it can never fall out of step with the map you are standing in.

const BG := Color(0.04, 0.05, 0.07, 0.94)
const SOLID := Color(0.42, 0.48, 0.58)
const CATWALK := Color(0.35, 0.46, 0.55, 0.85)
const CABLE := Color(0.55, 0.62, 0.72, 0.6)
const TEXT := Color(0.85, 0.89, 0.94)
const DIM := Color(0.5, 0.55, 0.62)
const ACCENT := Color(0.98, 0.78, 0.35)
const EXIT := Color(0.45, 0.9, 0.62)
const YOU := Color(0.95, 0.95, 1.0)

## Briefing mode holds the map up on its own; M just toggles it.
var briefing := false

var _player: Node2D
var _world: Node2D
var _bounds := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_player = Net.local_player
	Net.player_spawned.connect(func(body: Node) -> void:
		if body == Net.local_player:
			_player = body)
	var scene := get_tree().current_scene
	if scene:
		_world = scene.get_node_or_null(^"World")
	_measure()


## The extent of the level, so the drawing can be scaled to fit whatever gets
## built later without anyone updating a number here.
func _measure() -> void:
	if _world == null:
		return
	for block in _world.get_children():
		var size_value: Variant = block.get(&"size")
		if typeof(size_value) != TYPE_VECTOR2:
			continue
		var rect := Rect2((block as Node2D).global_position - (size_value as Vector2) * 0.5,
			size_value as Vector2)
		_bounds = rect if _bounds.size == Vector2.ZERO else _bounds.merge(rect)
	_bounds = _bounds.grow(120.0)


func show_briefing() -> void:
	briefing = true
	visible = true


func toggle() -> void:
	if briefing:
		return
	visible = not visible


func dismiss() -> void:
	briefing = false
	visible = false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## World point to a point on the drawn map.
func _to_map(at: Vector2) -> Vector2:
	if _bounds.size == Vector2.ZERO:
		return at
	var frame := _frame()
	var scale := minf(frame.size.x / _bounds.size.x, frame.size.y / _bounds.size.y)
	var offset := frame.position + frame.size * 0.5 - _bounds.size * scale * 0.5
	return offset + (at - _bounds.position) * scale


func _scale() -> float:
	var frame := _frame()
	return minf(frame.size.x / _bounds.size.x, frame.size.y / _bounds.size.y)


func _frame() -> Rect2:
	return Rect2(Vector2(70.0, 110.0), size - Vector2(140.0, 210.0))


func _draw() -> void:
	if _world == null or _bounds.size == Vector2.ZERO:
		return
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), BG)

	draw_string(font, Vector2(70.0, 66.0), "THE COMPLEX",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ACCENT)
	draw_string(font, Vector2(70.0, 90.0),
		"four rooms, four hallways, and a vault in the middle - your way out is across it",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)

	_draw_geometry()
	_draw_cables()
	_draw_points(font)

	if _player:
		var here := _to_map((_player as Node2D).global_position)
		draw_circle(here, 6.0, YOU)
		draw_arc(here, 11.0, 0.0, TAU, 24, YOU, 1.5, true)
		draw_string(font, here + Vector2(14.0, 4.0), "YOU",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, YOU)

	# On a phone there is no ENTER and no M. The briefing is dismissed by a tap
	# anywhere (Screens._input) and the map by the CLOSE button the touch pad
	# shrinks to while a screen is up (TouchControls._close_action).
	var hint := ""
	if PlayerInput.is_touch():
		hint = "TAP  close" if briefing else "CLOSE  top right"
	else:
		hint = "ENTER or M  close" if briefing else "M  close"
	draw_string(font, Vector2(0.0, size.y - 54.0), hint,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, ACCENT)


func _draw_geometry() -> void:
	var scale := _scale()
	for block in _world.get_children():
		var size_value: Variant = block.get(&"size")
		if typeof(size_value) != TYPE_VECTOR2:
			continue
		var extent := (size_value as Vector2) * scale
		var corner := _to_map((block as Node2D).global_position - (size_value as Vector2) * 0.5)
		var one_way: Variant = block.get(&"one_way")
		var solid: bool = not (typeof(one_way) == TYPE_BOOL and one_way)
		draw_rect(Rect2(corner, Vector2(maxf(extent.x, 1.5), maxf(extent.y, 1.5))),
			SOLID if solid else CATWALK)


func _draw_cables() -> void:
	for node in get_tree().get_nodes_in_group(&"zipline"):
		var cable := node as Zipline
		if cable:
			draw_line(_to_map(cable.world_top()), _to_map(cable.world_bottom()), CABLE, 1.5, true)


## Insertion and extraction points. The one you came in at is marked, and the
## live exits are the ones worth looking at.
func _draw_points(font: Font) -> void:
	for node in get_tree().get_nodes_in_group(&"spawn"):
		var point := node as SpawnPoint
		if point == null:
			continue
		var at := _to_map(point.global_position)
		if point.is_extraction:
			draw_arc(at, 9.0, 0.0, TAU, 24, EXIT, 2.0, true)
			draw_circle(at, 4.0, EXIT)
			draw_string(font, at + Vector2(13.0, 4.0), "EXIT  %s" % point.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, EXIT)
		else:
			draw_circle(at, 3.5, DIM)
			draw_string(font, at + Vector2(10.0, 4.0), point.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
