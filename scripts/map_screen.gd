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
## Every block in the level, found once. The geometry is static, so this is the
## survey and not a per-frame walk of the tree.
var _blocks: Array[Node2D] = []
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
		_collect(scene)
	_measure()


## Finds the level's blocks, wherever in the scene they are filed.
##
## This used to be the children of World and nothing else, which is right until
## somebody blocks out a wing of the map at the root of the scene - and then the
## briefing map quietly stops drawing that wing, while the level you are standing
## in still has it. What makes a block a block is that it is a Platform, so that
## is what is asked: `one_way` is the property only Platform has, which keeps the
## backdrop panels off the map the way filing them elsewhere used to.
func _collect(node: Node) -> void:
	for child in node.get_children():
		var block := child as Node2D
		if block != null and typeof(block.get(&"size")) == TYPE_VECTOR2 				and typeof(block.get(&"one_way")) == TYPE_BOOL:
			_blocks.append(block)
		elif child.get_child_count() > 0:
			_collect(child)


## The extent of the level, so the drawing can be scaled to fit whatever gets
## built later without anyone updating a number here.
func _measure() -> void:
	var measured := false
	for block in _blocks:
		for corner in _quad(block):
			_bounds = Rect2(corner, Vector2.ZERO) if not measured else _bounds.expand(corner)
			measured = true
	if measured:
		_bounds = _bounds.grow(120.0)


## A block's four corners, in world space and in order round the outline.
##
## Not a Rect2 of its `size`. A wall is as often stood on its end as laid flat,
## and half this level is blocked out by dragging the scale handles rather than
## by typing a size - so `size` alone describes a block before it was rotated or
## stretched into place. Running the corners through the block's own transform is
## the whole fix, and it mattered twice over: a vertical wall was not only drawn
## lying on its side, it was *measured* lying on its side, which stretched the
## level's extent sideways and rescaled the entire drawing around it.
func _quad(block: Node2D) -> PackedVector2Array:
	var half: Vector2 = (block.get(&"size") as Vector2) * 0.5
	var at := block.global_transform
	return PackedVector2Array([
		at * Vector2(-half.x, -half.y),
		at * Vector2(half.x, -half.y),
		at * Vector2(half.x, half.y),
		at * Vector2(-half.x, half.y),
	])


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


func _frame() -> Rect2:
	return Rect2(Vector2(70.0, 110.0), size - Vector2(140.0, 210.0))


func _draw() -> void:
	if _blocks.is_empty() or _bounds.size == Vector2.ZERO:
		return
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), BG)

	# Which map this is, asked of the map list rather than written here. There is
	# more than one now, and a briefing that describes the yard while you are
	# standing in the quarry is worse than no briefing at all.
	var level := Net.level_here()
	draw_string(font, Vector2(70.0, 66.0), str(level.get("name", "the complex")).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ACCENT)
	draw_string(font, Vector2(70.0, 90.0), str(level.get("blurb", "")),
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
	for block in _blocks:
		var outline := PackedVector2Array()
		for corner in _quad(block):
			outline.append(_to_map(corner))
		var one_way: Variant = block.get(&"one_way")
		var solid: bool = not (typeof(one_way) == TYPE_BOOL and one_way)
		draw_colored_polygon(_thick_enough_to_see(outline), SOLID if solid else CATWALK)


## Opens a drawn block out until its short side is worth a pixel, about its own
## centre and in whichever direction it is thin.
##
## A 24 px catwalk on a level fourteen thousand across is a fifth of a pixel on
## the map, and a polygon that thin is drawn as nothing at all. The old drawing
## did this by flooring the width and height of an upright rectangle, which is
## the same idea and only works while every block is upright.
func _thick_enough_to_see(quad: PackedVector2Array, least := 1.5) -> PackedVector2Array:
	var out := PackedVector2Array(quad)
	# Two edges from the same corner: the block's own axes, however it is turned.
	for axis in [Vector2i(1, 3), Vector2i(3, 1)]:
		var edge := out[axis.x] - out[0]
		var span := edge.length()
		if span >= least or span < 0.0001:
			continue
		var push := edge / span * (least - span) * 0.5
		out[0] -= push
		out[axis.y] -= push
		out[axis.x] += push
		out[2] += push
	return out


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
