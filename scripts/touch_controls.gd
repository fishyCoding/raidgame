extends Control

## The game, played with thumbs.
##
## Two floating sticks and a set of buttons, drawn in _draw like the rest of the
## UI here. It writes into the same places a keyboard does - PlayerInput's
## touch_move_axis and touch_aim_direction for the sticks, and Input.action_press
## for everything else - so no gameplay code knows or cares that a thumb is
## driving it. Adding an action to the game means adding one line to BUTTONS.
##
## **The sticks are fixed, and that is deliberate.** They used to float - touch
## anywhere in your half and the ring appeared under your thumb - which is nicer
## in theory and was unusable in practice: a ring is drawn at rest so you know
## where the stick is, you put your thumb on it, and the ring jumps to the exact
## pixel you touched. It reads as a *second* joystick appearing underneath the
## first. One ring, always in the same place, is worth more than the theory.
##
## Touching anywhere within reach of a ring grabs it, so you do not have to hit
## it precisely - but the knob is always measured from the ring's own centre, and
## the ring never moves.
##
## **Multitouch is the whole problem.** Moving, aiming and firing at once is
## three fingers, and Godot only emulates a mouse from the *first* touch - so
## this reads InputEventScreenTouch/Drag by index and never relies on the mouse
## on a real device. Mouse events are handled too, but only until a genuine touch
## arrives: that is what lets the controls be tried on a desktop, and what stops
## the emulated-mouse echo of a real touch being counted twice.

## Radius of the ring a stick swings in, and of the knob you push around it.
const STICK_RADIUS := 96.0
const STICK_KNOB := 40.0
## Below this the stick reads as centred. Generous: a thumb resting on glass
## drifts, and a character that strolls off on its own is worse than one that
## needs a deliberate push.
const STICK_DEAD := 0.16
## How far outside the drawn ring still counts as grabbing it. Thumbs are wide
## and the ring is a picture, not a target.
const STICK_GRAB := 1.55
## Kept clear of every edge. A phone has a notch on one side and a home indicator
## across the bottom, and a control under either is a control you cannot press.
const SAFE := 54.0

const PANEL := Color(0.08, 0.09, 0.12, 0.5)
const RING := Color(0.62, 0.68, 0.78, 0.35)
const KNOB := Color(0.85, 0.89, 0.94, 0.5)
const LABEL := Color(0.88, 0.91, 0.95, 0.85)
const ACCENT := Color(0.98, 0.78, 0.35)
const HELD_TINT := Color(0.98, 0.78, 0.35, 0.4)

## Every action a thumb can reach, and where. `hold` marks the ones that mean
## something for as long as they are down rather than on the press - aiming and
## crouching are postures, not events.
##
## Laid out from the bottom-right corner outwards, in rough order of how often
## you need them: fire and jump under the thumb, then the two you press in a
## fight, then the housekeeping along the top where a mis-hit costs nothing.
## `left` measures from the left edge instead of the right, for the one button
## the left thumb should own. Everything else is right-thumb work, placed clear
## of the aim stick's swing and above the readouts along the bottom.
const BUTTONS := [
	{"action": &"fire", "label": "FIRE", "at": Vector2(-370.0, -200.0), "r": 60.0, "hold": true},
	{"action": &"jump", "label": "JUMP", "at": Vector2(-370.0, -350.0), "r": 50.0, "hold": false},
	{"action": &"grapple", "label": "HOOK", "at": Vector2(-508.0, -272.0), "r": 46.0, "hold": false},
	{"action": &"interact", "label": "USE", "at": Vector2(-508.0, -136.0), "r": 44.0, "hold": false},
	{"action": &"aim", "label": "ADS", "at": Vector2(-232.0, -350.0), "r": 44.0, "hold": true},
	{"action": &"crouch", "label": "DUCK", "at": Vector2(300.0, -150.0), "r": 44.0,
		"hold": true, "left": true},
]

## The rest of it, as a strip of pills along the top. Reloading and healing are
## not things you do mid-leap, and the ultimate and the throws want a deliberate
## press rather than a thumb that happens to be nearby.
const PILLS := [
	{"action": &"reload", "label": "RELOAD"},
	{"action": &"heal", "label": "MEDKIT"},
	{"action": &"ultimate", "label": "ULT"},
	{"action": &"throw_1", "label": "FRAG"},
	{"action": &"throw_2", "label": "SMOKE"},
	{"action": &"inventory", "label": "BAG"},
	{"action": &"map", "label": "MAP"},
]
const PILL_SIZE := Vector2(96.0, 44.0)
const PILL_GAP := 8.0

## Which pointer is driving what. -2 means nobody; a touch index otherwise, and
## -1 for the mouse standing in for a finger on a desktop.
var _move_id := -2
var _aim_id := -2
var _move_vec := Vector2.ZERO
var _aim_vec := Vector2.ZERO
## pointer id -> action it is holding down.
var _pressed := {}
## Set by the first real touch. From then on the mouse is ignored, because on a
## device every touch also arrives as an emulated mouse click and acting on both
## would fire twice.
var _saw_touch := false


func _ready() -> void:
	# Input is read in _input rather than _gui_input: these are not widgets you
	# click, and letting them stop mouse input would take it from the shop.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	PlayerInput.controls_changed.connect(_on_controls_changed)
	visible = false


func _on_controls_changed(_touch: bool) -> void:
	# Whatever was held is not held any more, and a scheme swap mid-press would
	# otherwise leave an action stuck down for the rest of the session.
	_release_everything()


func _process(_delta: float) -> void:
	var touch := PlayerInput.is_touch()
	# "A / D move ... SPACE jump" is a lie on a phone, and it sits exactly where
	# the pills go. Toggled from here rather than by the label itself, because
	# whether there is a keyboard is this node's subject.
	var help := get_parent().get_node_or_null(^"Controls") as CanvasItem
	if help:
		help.visible = not touch

	var wanted := touch and not PlayerInput.wants_cursor()
	if wanted != visible:
		visible = wanted
		if not wanted:
			_release_everything()
	if not visible:
		return

	# Written every frame rather than on change: these are levels, and a stick
	# that stops reporting because nothing moved reads as the thumb lifting.
	PlayerInput.touch_move_axis = _move_vec.x
	PlayerInput.touch_aim_direction = _aim_vec
	# Down on the move stick is the drop-through-a-platform input, exactly as
	# S is on a keyboard. Held, not tapped, so it pairs with jump the same way.
	_set_action(&"move_down", _move_vec.y > 0.55)
	queue_redraw()


func _exit_tree() -> void:
	_release_everything()


# --- pointers -----------------------------------------------------------------


func _input(event: InputEvent) -> void:
	if not visible:
		return

	var touch := event as InputEventScreenTouch
	if touch:
		_saw_touch = true
		if _pointer(touch.index, touch.position, touch.pressed):
			get_viewport().set_input_as_handled()
		return

	var drag := event as InputEventScreenDrag
	if drag:
		if _drag(drag.index, drag.position):
			get_viewport().set_input_as_handled()
		return

	# Desktop, standing in for a finger - and only until a real one shows up.
	if _saw_touch:
		return
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT:
		if _pointer(-1, click.position, click.pressed):
			get_viewport().set_input_as_handled()
		return
	var moved := event as InputEventMouseMotion
	if moved and (moved.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if _drag(-1, moved.position):
			get_viewport().set_input_as_handled()


## A finger going down or coming up. True when it landed on something of ours.
func _pointer(id: int, at: Vector2, down: bool) -> bool:
	if not down:
		return _lift(id)

	# Buttons first, then sticks: a button sitting inside a stick's zone should
	# be a button, or the two nearest the corner would be unreachable.
	for pill in _pill_rects():
		if (pill.rect as Rect2).has_point(at):
			_hold(id, pill.action)
			return true
	for button in _button_rects():
		if at.distance_to(button.at) <= button.r * 1.15:
			_hold(id, button.action)
			return true

	# Within reach of a ring, not merely on the right half of the screen. A thumb
	# that lands in the empty middle should do nothing at all, rather than snap
	# the stick to full deflection because the maths says that way is "left".
	if _move_id == -2 and at.distance_to(_move_home()) <= STICK_RADIUS * STICK_GRAB:
		_move_id = id
		_move_vec = _swing(at - _move_home())
		return true
	if _aim_id == -2 and at.distance_to(_aim_home()) <= STICK_RADIUS * STICK_GRAB:
		_aim_id = id
		_aim_vec = _point(at - _aim_home())
		return true
	return false


## A finger sliding. Only the sticks care.
func _drag(id: int, at: Vector2) -> bool:
	if id == _move_id:
		_move_vec = _swing(at - _move_home())
		return true
	if id == _aim_id:
		_aim_vec = _point(at - _aim_home())
		return true
	return false


## Aim is a direction, not a distance: it points where the thumb is relative to
## the ring, and pushing further out does not aim harder.
func _point(offset: Vector2) -> Vector2:
	if offset.length() <= STICK_RADIUS * STICK_DEAD:
		return Vector2.ZERO
	return offset.normalized()


func _lift(id: int) -> bool:
	var ours := false
	if id == _move_id:
		_move_id = -2
		_move_vec = Vector2.ZERO
		ours = true
	if id == _aim_id:
		_aim_id = -2
		_aim_vec = Vector2.ZERO
		ours = true
	if _pressed.has(id):
		_set_action(_pressed[id], false)
		_pressed.erase(id)
		ours = true
	return ours


func _hold(id: int, action: StringName) -> void:
	_pressed[id] = action
	_set_action(action, true)


## Pressed and released through the real input map, so everything downstream -
## PlayerInput's helpers, the player, the screens - reads a thumb exactly as it
## reads a key. Nothing had to be taught about touch.
func _set_action(action: StringName, down: bool) -> void:
	if down:
		if not Input.is_action_pressed(action):
			Input.action_press(action)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _release_everything() -> void:
	for id in _pressed:
		_set_action(_pressed[id], false)
	_pressed.clear()
	_set_action(&"move_down", false)
	_move_id = -2
	_aim_id = -2
	_move_vec = Vector2.ZERO
	_aim_vec = Vector2.ZERO
	PlayerInput.touch_move_axis = 0.0
	PlayerInput.touch_aim_direction = Vector2.ZERO


## How far round the ring a thumb has pushed, 0 to 1, with the dead zone taken
## out rather than clipped - so the first movement past it is slow instead of a
## jump to a fifth of full speed.
func _swing(offset: Vector2) -> Vector2:
	var reach := offset.length() / STICK_RADIUS
	if reach <= STICK_DEAD:
		return Vector2.ZERO
	var scaled := minf((reach - STICK_DEAD) / (1.0 - STICK_DEAD), 1.0)
	return offset.normalized() * scaled


# --- drawing ------------------------------------------------------------------


## Where each button is this frame. Measured from the bottom-right corner so the
## layout survives a screen of any shape - which on phones is the normal case.
func _button_rects() -> Array:
	var out: Array = []
	for button in BUTTONS:
		var offset: Vector2 = button.at
		# Both anchors hang off the bottom; only the horizontal edge differs.
		var at := Vector2(offset.x if button.get("left", false) else size.x + offset.x,
			size.y + offset.y)
		out.append({
			"action": button.action, "label": button.label, "r": button.r,
			"hold": button.hold, "at": at,
		})
	return out


## The secondary strip, centred along the top and shrunk to fit if the screen is
## too narrow to hold it at full size - a pill that runs off the edge is an
## action you cannot reach, which on a phone means a mechanic that does not
## exist.
func _pill_rects() -> Array:
	var out: Array = []
	var wide: float = PILL_SIZE.x
	var span := PILLS.size() * wide + (PILLS.size() - 1) * PILL_GAP
	var room := size.x - SAFE * 2.0
	if span > room:
		wide = (room - (PILLS.size() - 1) * PILL_GAP) / PILLS.size()
		span = room
	var x := size.x * 0.5 - span * 0.5
	for pill in PILLS:
		out.append({
			"action": pill.action, "label": pill.label,
			"rect": Rect2(Vector2(x, SAFE * 0.4), Vector2(wide, PILL_SIZE.y)),
		})
		x += wide + PILL_GAP
	return out


func _draw() -> void:
	var font := ThemeDB.fallback_font

	_draw_stick(_move_id != -2, _move_home(), _move_vec, "MOVE")
	_draw_stick(_aim_id != -2, _aim_home(), _aim_vec, "AIM")

	for button in _button_rects():
		var down := _holding(button.action)
		draw_circle(button.at, button.r, HELD_TINT if down else PANEL)
		draw_arc(button.at, button.r, 0.0, TAU, 32, ACCENT if down else RING, 2.0, true)
		draw_string(font, button.at + Vector2(-button.r, 5.0), button.label,
			HORIZONTAL_ALIGNMENT_CENTER, button.r * 2.0, 15, ACCENT if down else LABEL)

	for pill in _pill_rects():
		var rect: Rect2 = pill.rect
		var down := _holding(pill.action)
		draw_rect(rect, HELD_TINT if down else PANEL)
		draw_rect(rect, ACCENT if down else RING, false, 1.5)
		draw_string(font, rect.position + Vector2(0.0, 28.0), pill.label,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 13, ACCENT if down else LABEL)


func _holding(action: StringName) -> bool:
	return _pressed.values().has(action)


## The two rings never move. Where the knob sits inside one is the only thing
## that changes, which is what makes them read as one control each.
func _move_home() -> Vector2:
	return Vector2(SAFE + STICK_RADIUS, size.y - SAFE - STICK_RADIUS)


func _aim_home() -> Vector2:
	return Vector2(size.x - SAFE - STICK_RADIUS, size.y - SAFE - STICK_RADIUS)


func _draw_stick(live: bool, centre: Vector2, vec: Vector2, label: String) -> void:
	var alpha := 1.0 if live else 0.45

	draw_arc(centre, STICK_RADIUS, 0.0, TAU, 48, Color(RING, RING.a * alpha), 2.0, true)
	var knob := centre + vec * STICK_RADIUS
	draw_circle(knob, STICK_KNOB, Color(KNOB, KNOB.a * alpha))
	draw_arc(knob, STICK_KNOB, 0.0, TAU, 24, Color(ACCENT, alpha * 0.8), 2.0, true)

	if not live:
		var font := ThemeDB.fallback_font
		draw_string(font, centre + Vector2(-STICK_RADIUS, 5.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, STICK_RADIUS * 2.0, 13, Color(LABEL, 0.35))
