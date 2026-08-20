@tool
extends EditorPlugin

## Drag handles for anything in the level built between two points.
##
## Select a Zipline or a Platform and both of its ends become grabbable in the
## 2D viewport, so placing one is a drag between two points instead of guessing
## at Vector2 fields. Hold Ctrl to snap to a grid, Shift to line the end you are
## dragging up with the one you are not - which is how you get a cable that is
## exactly vertical, or a wall that is exactly level.
##
## The two node types keep their ends in different places, and this papers over
## the difference rather than making them agree. A cable is a pair of points
## hung off a pivot, so its ends are node-local and moving one leaves the node
## where it is. A block is a rotated rectangle whose collision shape has to stay
## centred on the node, so its ends are read out of - and written back into -
## the node's own position, rotation and size, in the parent's space.

const SNAP_STEP := 8.0
## How close the cursor has to be, in screen pixels, to grab an end.
const PICK_RADIUS := 14.0
const FIRST := 0
const SECOND := 1

## Amber marks the first end, blue the second, matching the colours a Zipline
## draws its own guides in.
const FIRST_COLOUR := Color(1.0, 0.72, 0.28)
const SECOND_COLOUR := Color(0.36, 0.72, 1.0)

var _node: Node2D = null
## Which pair of properties this node keeps its ends in.
var _ends := ["", ""]
## Everything the drag is allowed to disturb, so undo has a whole state to go
## back to. A block's ends are spread across four properties, not two.
var _touches: PackedStringArray = []
## What the undo entry is called.
var _label := "endpoint"
var _dragging := -1
var _hovering := -1
var _before := {}


func _handles(object: Object) -> bool:
	return object is Zipline or object is Platform


func _edit(object: Object) -> void:
	_node = object as Node2D
	if object is Platform:
		_label = "platform"
		_ends = ["start", "finish"]
		# Setting either end rewrites the transform as well as the size.
		_touches = PackedStringArray(["position", "rotation", "scale", "size"])
	elif object is Zipline:
		_label = "zipline"
		_ends = ["top", "bottom"]
		_touches = PackedStringArray(["top", "bottom"])
	_dragging = -1
	_hovering = -1
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_node = null
		_dragging = -1
		_hovering = -1
	update_overlays()


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not is_instance_valid(_node):
		return false
	var to_screen := _to_screen()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var picked := _pick(to_screen, event.position)
			if picked == -1:
				# Not on a handle: let the editor move the node as usual.
				return false
			_dragging = picked
			_before = {}
			for property in _touches:
				_before[property] = _node.get(property)
			update_overlays()
			return true
		if _dragging != -1:
			_commit()
			return true

	elif event is InputEventMouseMotion:
		if _dragging != -1:
			_node.set(_ends[_dragging], _place(to_screen, event))
			update_overlays()
			return true
		var picked := _pick(to_screen, event.position)
		if picked != _hovering:
			_hovering = picked
			update_overlays()

	return false


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not is_instance_valid(_node):
		return
	var to_screen := _to_screen()
	var first: Vector2 = to_screen * _point(FIRST)
	var second: Vector2 = to_screen * _point(SECOND)

	_draw_handle(overlay, first, FIRST_COLOUR, FIRST)
	_draw_handle(overlay, second, SECOND_COLOUR, SECOND)

	if _dragging == -1:
		return
	# A live readout while dragging, of whichever number actually matters when
	# placing this kind of thing.
	var at := (first + second) * 0.5 + Vector2(16, -6)
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	overlay.draw_string(font, at + Vector2.ONE, _readout(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	overlay.draw_string(font, at, _readout(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1))


func _readout() -> String:
	var platform := _node as Platform
	if platform:
		return "%d px  -  %d px thick" % [
				roundi(platform.world_length()), roundi(platform.world_thickness())]
	var cable := _node as Zipline
	if cable:
		var length := cable.cable_length()
		return "%d px  -  %.1fs" % [roundi(length), length / maxf(cable.speed, 1.0)]
	return ""


func _draw_handle(overlay: Control, at: Vector2, colour: Color, which: int) -> void:
	var lit := _dragging == which or (_dragging == -1 and _hovering == which)
	overlay.draw_circle(at, 8.0 if lit else 6.0, Color(colour, 0.9 if lit else 0.5))
	overlay.draw_arc(at, 8.0 if lit else 6.0, 0.0, TAU, 24, colour, 2.0, true)


func _point(which: int) -> Vector2:
	return _node.get(_ends[which])


## The space the ends are expressed in, mapped to viewport pixels. A block's are
## in its parent's space, so its own transform must not be applied twice.
func _to_screen() -> Transform2D:
	var space := _node.get_global_transform()
	if _node is Platform:
		var parent := _node.get_parent() as Node2D
		space = parent.get_global_transform() if parent else Transform2D()
	return _node.get_viewport_transform() * space


func _pick(to_screen: Transform2D, mouse: Vector2) -> int:
	# First end first: with a collapsed cable both handles sit on each other,
	# and that is the one you are more likely to be pulling away.
	for which in [FIRST, SECOND]:
		if (to_screen * _point(which)).distance_to(mouse) <= PICK_RADIUS:
			return which
	return -1


## Where the dragged end should land, given the modifiers held.
func _place(to_screen: Transform2D, event: InputEventMouseMotion) -> Vector2:
	var local: Vector2 = to_screen.affine_inverse() * event.position
	if event.shift_pressed:
		# Line up with the end that is staying put, on whichever axis is closer
		# to straight - so a near-vertical drag becomes exactly vertical.
		var anchor := _point(SECOND if _dragging == FIRST else FIRST)
		var offset := local - anchor
		if absf(offset.x) < absf(offset.y):
			local.x = anchor.x
		else:
			local.y = anchor.y
	if event.ctrl_pressed:
		local = local.snapped(Vector2(SNAP_STEP, SNAP_STEP))
	return local


func _commit() -> void:
	_dragging = -1
	update_overlays()
	var after := {}
	var moved := false
	for property in _touches:
		after[property] = _node.get(property)
		if typeof(after[property]) == TYPE_VECTOR2:
			moved = moved or not (after[property] as Vector2).is_equal_approx(_before[property])
		else:
			moved = moved or after[property] != _before[property]
	if not moved:
		return
	var history := get_undo_redo()
	history.create_action("Move %s end" % _label)
	for property in _touches:
		history.add_do_property(_node, property, after[property])
		history.add_undo_property(_node, property, _before[property])
	# The values are already set by the drag, so do not run the do half again.
	history.commit_action(false)
