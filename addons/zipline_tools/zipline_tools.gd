@tool
extends EditorPlugin

## Drag handles for the ends of a Zipline.
##
## Select a Zipline and its two ends become grabbable in the 2D viewport, so
## placing a cable is a drag between two points instead of guessing at two
## Vector2 fields. Hold Ctrl to snap to a grid, Shift to line the end you are
## dragging up with the one you are not - which is how you get a cable that is
## exactly vertical.

const SNAP_STEP := 8.0
## How close the cursor has to be, in screen pixels, to grab an end.
const PICK_RADIUS := 14.0
const TOP := 0
const BOTTOM := 1

var _zipline: Zipline = null
var _dragging := -1
var _hovering := -1
## Where the dragged end started, so undo has something to go back to.
var _drag_from := Vector2.ZERO


func _handles(object: Object) -> bool:
	return object is Zipline


func _edit(object: Object) -> void:
	_zipline = object as Zipline
	_dragging = -1
	_hovering = -1
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_zipline = null
		_dragging = -1
		_hovering = -1
	update_overlays()


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not is_instance_valid(_zipline):
		return false
	var to_screen := _to_screen()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var picked := _pick(to_screen, event.position)
			if picked == -1:
				# Not on a handle: let the editor move the node as usual.
				return false
			_dragging = picked
			_drag_from = _point(picked)
			update_overlays()
			return true
		if _dragging != -1:
			_commit()
			return true

	elif event is InputEventMouseMotion:
		if _dragging != -1:
			_set_point(_dragging, _place(to_screen, event))
			update_overlays()
			return true
		var picked := _pick(to_screen, event.position)
		if picked != _hovering:
			_hovering = picked
			update_overlays()

	return false


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not is_instance_valid(_zipline):
		return
	var to_screen := _to_screen()
	var top: Vector2 = to_screen * _zipline.top
	var bottom: Vector2 = to_screen * _zipline.bottom
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size

	_draw_handle(overlay, top, Zipline.TOP_COLOUR, TOP)
	_draw_handle(overlay, bottom, Zipline.BOTTOM_COLOUR, BOTTOM)

	if _dragging == -1:
		return
	# A live readout while dragging: the length you are setting, and the ride
	# time that falls out of it at the cable's current speed.
	var length := _zipline.cable_length()
	var seconds := length / maxf(_zipline.speed, 1.0)
	var text := "%d px  -  %.1fs" % [roundi(length), seconds]
	var at := (top + bottom) * 0.5 + Vector2(16, -6)
	overlay.draw_string(font, at + Vector2.ONE, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	overlay.draw_string(font, at, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1))


func _draw_handle(overlay: Control, at: Vector2, colour: Color, which: int) -> void:
	var lit := _dragging == which or (_dragging == -1 and _hovering == which)
	overlay.draw_circle(at, 8.0 if lit else 6.0, Color(colour, 0.9 if lit else 0.5))
	overlay.draw_arc(at, 8.0 if lit else 6.0, 0.0, TAU, 24, colour, 2.0, true)


## Local-space point of an end, on the node being edited.
func _point(which: int) -> Vector2:
	return _zipline.top if which == TOP else _zipline.bottom


func _set_point(which: int, value: Vector2) -> void:
	if which == TOP:
		_zipline.top = value
	else:
		_zipline.bottom = value


## Node-local space to viewport pixels.
func _to_screen() -> Transform2D:
	return _zipline.get_viewport_transform() * _zipline.get_global_transform()


func _pick(to_screen: Transform2D, mouse: Vector2) -> int:
	# Top first: with a collapsed cable both handles sit on each other, and the
	# top is the one you are more likely to be pulling away.
	for which in [TOP, BOTTOM]:
		if (to_screen * _point(which)).distance_to(mouse) <= PICK_RADIUS:
			return which
	return -1


## Where the dragged end should land, given the modifiers held.
func _place(to_screen: Transform2D, event: InputEventMouseMotion) -> Vector2:
	var local: Vector2 = to_screen.affine_inverse() * event.position
	if event.shift_pressed:
		# Line up with the end that is staying put, on whichever axis is closer
		# to straight - so a near-vertical drag becomes exactly vertical.
		var anchor := _point(BOTTOM if _dragging == TOP else TOP)
		var offset := local - anchor
		if absf(offset.x) < absf(offset.y):
			local.x = anchor.x
		else:
			local.y = anchor.y
	if event.ctrl_pressed:
		local = local.snapped(Vector2(SNAP_STEP, SNAP_STEP))
	return local


func _commit() -> void:
	var property := "top" if _dragging == TOP else "bottom"
	var landed := _point(_dragging)
	_dragging = -1
	update_overlays()
	if landed.is_equal_approx(_drag_from):
		return
	var history := get_undo_redo()
	history.create_action("Move zipline %s" % property)
	history.add_do_property(_zipline, property, landed)
	history.add_undo_property(_zipline, property, _drag_from)
	# The value is already set by the drag, so do not run the do half again.
	history.commit_action(false)
