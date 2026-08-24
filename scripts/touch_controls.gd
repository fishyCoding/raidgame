extends Control

## The game, played with thumbs.
##
## Drawn in _draw like the rest of the UI here, and it writes where a keyboard
## writes - PlayerInput.touch_move_axis for the stick, PlayerInput.add_aim_motion
## for the aim, and Input.action_press for the buttons - so no gameplay code
## knows or cares that a thumb is driving it.
##
## **The left hand steers, the right hand aims, and only the left hand has a
## stick.** Aiming used to be a second stick in the opposite corner, which meant
## a thumb pinned inside one 96 px circle for a whole raid. Now the entire right
## side is the aim surface: put a thumb down anywhere that is not a button and
## drag, exactly like a trackpad. Aim arrives as *motion* rather than as a
## direction for the same reason a mouse does - "turn this far from where you
## were" survives the camera leaning off centre, "point exactly there" does not.
##
## **FIRE is an aim surface too.** Holding it shoots and brings the sights up at
## once, and you can keep dragging from it to track a target while firing - which
## is the whole of a fight, and would otherwise need a third thumb.
##
## **Two toggles, not two holds.** Crouch and ADS latch. A posture you have to
## hold a button for is a posture you cannot hold while doing anything else, and
## on a phone every held button costs a finger you have not got.
##
## **Multitouch is the whole problem.** Moving, aiming and firing at once is
## three fingers, and Godot only emulates a mouse from the *first* touch - so
## this reads InputEventScreenTouch/Drag by index, and ignores the mouse outright
## on hardware that sends real touches, where every mouse event is an echo of the
## first finger and stole the move stick.

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
## Screen pixels of drag per pixel of aim.
##
## Was one to one, on the reasoning that Player.mouse_sensitivity already exists
## and two multipliers is one too many. True, and it still made aiming on a phone
## unusable - because a mouse has as much desk as it wants and a thumb has about
## an inch of glass before it runs into the edge of the screen or its own palm.
## Sharing a number with the mouse meant sharing an assumption that only the
## mouse gets to make.
##
## This is the thumb's own multiplier, and it is the only thing that should ever
## be tuned for touch: leave mouse_sensitivity to the desk.
const AIM_DRAG := 2.4

## How long a tapped button is held down for, in seconds.
##
## A tap is a press and a release inside one frame, and some actions read as
## nothing at all when they arrive that way - see the jump button, which was
## losing more than half its height to a thumb that was simply faster than a
## held key. Long enough to cover a full rise (Player.jump_time_to_peak is
## 0.38s), short enough that it is over before you could want to jump again.
const TAP_HOLD := 0.45

const PANEL := Color(0.08, 0.09, 0.12, 0.5)
const RING := Color(0.62, 0.68, 0.78, 0.35)
const KNOB := Color(0.85, 0.89, 0.94, 0.5)
const LABEL := Color(0.88, 0.91, 0.95, 0.85)
const ACCENT := Color(0.98, 0.78, 0.35)
const HELD_TINT := Color(0.98, 0.78, 0.35, 0.4)

## How a button behaves:
##   press   - down while the thumb is down, the ordinary case
##   tap     - down for TAP_HOLD however briefly it was touched, and the thumb
##             coming off does not end it. For actions that read how long you
##             held them: a tap has no duration, so without this it reads as the
##             shortest possible hold rather than as a press
##   toggle  - latches on, latches off, survives the thumb leaving
##   fire    - press, and an aim surface as well: drag from it to keep tracking
##   swap    - presses whichever hand you are *not* holding, worked out on the
##             press, because "the other gun" is not a fixed action
const BUTTONS := [
	# Right, under the aiming thumb.
	{"action": &"fire", "label": "FIRE", "at": Vector2(-180.0, -330.0), "r": 86.0,
		"mode": "fire"},
	{"action": &"aim", "label": "ADS", "at": Vector2(-350.0, -180.0), "r": 74.0,
		"mode": "toggle"},
	# Tapped, not pressed. The player cuts a jump short when you let go of it
	# (Player.jump_cut), which is right for a key and wrong for glass: a thumb is
	# off the button before the character has left the floor, so every jump on a
	# phone was a 45% hop and the height was unreachable. Tap it and you get all
	# of it, which is the only jump a phone can usefully offer.
	{"action": &"jump", "label": "JUMP", "at": Vector2(-330.0, -420.0), "r": 62.0,
		"mode": "tap"},
	# Left, under the steering thumb.
	{"action": &"interact", "label": "USE", "at": Vector2(390.0, -150.0), "r": 62.0,
		"mode": "press", "left": true},
	{"action": &"crouch", "label": "DUCK", "at": Vector2(350.0, -330.0), "r": 62.0,
		"mode": "toggle", "left": true},
	{"action": &"grapple", "label": "HOOK", "at": Vector2(200.0, -390.0), "r": 62.0,
		"mode": "press", "left": true},
	# Pressed, not latched, even though the shield *is* a latch in the game.
	# The latching lives in Player._update_shield, which flips on the press edge -
	# so a pad button that held the action down would flip it once and then never
	# again. One tap, one edge, one toggle.
	#
	# Left hand, with the movement controls rather than the shooting ones: the
	# plates cost you speed, so putting them up is a decision about how you are
	# moving and it belongs under the thumb that moves you.
	{"action": &"shield", "label": "PLATES", "at": Vector2(530.0, -300.0), "r": 62.0,
		"mode": "press", "left": true},
]

## Shown only when there is something under your feet worth opening. A body is
## the whole point of the game and the prompt for it used to be a line of text
## naming a key - so on a phone the single most important verb in a raid had no
## control at all, only a caption telling you to press F.
const LOOT_BUTTON := {
	"action": &"interact", "label": "LOOT", "at": Vector2(-180.0, -500.0), "r": 70.0,
	"mode": "press",
}

## Riding a cable takes the left hand over entirely: there is no walking on a
## zipline, so the stick and its cluster are replaced by the three things that do
## mean something there. Up and down are *held*, which is exactly why they could
## not stay as they were - "W up, S down" is not advice a thumb can take, and it
## was the whole reason ziplines were unusable on a phone.
const RIDE_BUTTONS := [
	{"action": &"jump", "label": "UP", "at": Vector2(200.0, -400.0), "r": 68.0,
		"mode": "press", "left": true},
	{"action": &"move_down", "label": "DOWN", "at": Vector2(200.0, -180.0), "r": 68.0,
		"mode": "press", "left": true},
	{"action": &"interact", "label": "LET GO", "at": Vector2(390.0, -290.0), "r": 60.0,
		"mode": "press", "left": true},
]

## The rest of it, as pills along the top - a deliberate press rather than a
## thumb that happens to be nearby. Split down the same seam: kit and information
## on the left, things you spend on the right, and the centre of the top edge
## left alone because that is where you are looking.
const PILLS_LEFT := [
	{"action": &"inventory", "label": "BAG"},
	{"action": &"map", "label": "MAP"},
	{"action": &"heal", "label": "MEDKIT"},
	# Next to the medkit, because the pair of them is the decision: one puts the
	# bar back up and one stops it falling, and picking the wrong one wastes a
	# scarce item. Two pills side by side make that a choice you can see rather
	# than one you have to remember.
	{"action": &"surgical", "label": "SURGERY"},
]
const PILLS_RIGHT := [
	{"action": &"swap", "label": "SWAP", "mode": "swap"},
	{"action": &"reload", "label": "RELOAD"},
	{"action": &"ultimate", "label": "ULT"},
	{"action": &"throw_1", "label": "FRAG"},
	{"action": &"throw_2", "label": "SMOKE"},
]
const PILL_SIZE := Vector2(118.0, 56.0)
const PILL_GAP := 8.0
const PILL_SPLIT := 60.0


## Everything the pills cover, for anything that wants the whole set.
static func all_pills() -> Array:
	return PILLS_LEFT + PILLS_RIGHT


## Which pointer is driving what. -2 means nobody; a touch index otherwise, and
## -1 for the mouse standing in for a finger on a desktop.
var _move_id := -2
var _move_vec := Vector2.ZERO
## The pointer currently dragging to aim, and where it was a moment ago. It may
## be a bare finger on the right of the screen or one holding FIRE down.
var _aim_id := -2
var _aim_last := Vector2.ZERO
## pointer id -> action it is holding down.
var _pressed := {}
## action -> latched on. Toggles live here rather than in _pressed: the thumb
## leaves and the state stays.
var _latched := {}
## action -> seconds of hold left on a tap. Like _latched in that the thumb is
## already gone, unlike it in that this runs out on its own.
var _tapped := {}
## Set by the first real touch, after which the mouse is an echo.
var _saw_touch := false
## True on hardware that sends real touches, where every mouse event is an echo
## of the first finger and must be ignored outright. Held as its own field so a
## test can pretend to be a phone.
var _mouse_is_an_echo := false
## The action that would shut whatever screen is up, or "" in the normal state.
var _closing := &""
## True while the character is hanging off a cable.
var _riding := false
## True while standing over something that can be opened.
var _looting := false


func _ready() -> void:
	# Input is read in _input rather than _gui_input: these are not widgets you
	# click, and letting them stop mouse input would take it from the shop.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	PlayerInput.controls_changed.connect(_on_controls_changed)
	_mouse_is_an_echo = PlayerInput.has_touchscreen()
	visible = false


func _on_controls_changed(_touch: bool) -> void:
	# Whatever was held is not held any more, and a scheme swap mid-press would
	# otherwise leave an action stuck down for the rest of the session.
	_release_everything()
	_latched.clear()
	_set_action(&"crouch", false)
	_set_action(&"aim", false)


func _process(delta: float) -> void:
	_age_taps(delta)
	var touch := PlayerInput.is_touch()
	# "A / D move ... SPACE jump" is a lie on a phone, and it sits exactly where
	# the pills go.
	var help := get_parent().get_node_or_null(^"Controls") as CanvasItem
	if help:
		help.visible = not touch

	# A screen being up hides the pad - it would be drawn straight over the map -
	# but hiding it also takes away the button that opened the thing, and the map
	# could then never be closed. So the pad shrinks to the one control that is
	# still meaningful rather than disappearing.
	_closing = _close_action() if touch and PlayerInput.wants_cursor() else &""

	var wanted := touch and (not PlayerInput.wants_cursor() or _closing != &"")
	if wanted != visible:
		visible = wanted
		if not wanted:
			_release_everything()
	if not visible:
		return
	if _closing != &"":
		if not _pressed.is_empty() or not _move_vec.is_zero_approx():
			_release_everything()
		queue_redraw()
		return

	_looting = _over_loot()
	var was_riding := _riding
	_riding = _on_a_cable()
	if was_riding != _riding:
		# The left hand's controls are about to be swapped out from under a thumb
		# that may still be down on one of them.
		_release_everything()

	# Written every frame rather than on change: these are levels, and a stick
	# that stops reporting because nothing moved reads as the thumb lifting.
	PlayerInput.touch_move_axis = 0.0 if _riding else _move_vec.x
	# Down on the move stick drops you through a one-way platform, exactly as S
	# does. Not while riding: down means down the cable there, and the RIDE
	# buttons drive that directly.
	if not _riding:
		_set_action(&"move_down", _move_vec.y > 0.55)

	# The two latches, plus the one that is not a latch: holding the trigger aims
	# as well as shoots, so the sights come up without spending a second thumb.
	_set_action(&"crouch", _latched.get(&"crouch", false))
	_set_action(&"aim", _latched.get(&"aim", false) or _holding(&"fire"))
	queue_redraw()


## Runs the clock down on anything tapped, and lets go when it reaches zero.
##
## Deliberately the first thing _process does, before any of the returns that
## follow: a tap has nobody holding it, so if this were skipped for a frame -
## the pad hidden, a screen opened - the action would stay pressed with nothing
## left to release it.
func _age_taps(delta: float) -> void:
	if _tapped.is_empty():
		return
	for action in _tapped.keys():
		var left: float = _tapped[action] - delta
		if left > 0.0:
			_tapped[action] = left
			continue
		_tapped.erase(action)
		# Not if a thumb is genuinely holding it as well - the hold outlives the
		# tap that started it.
		if not _holding(action):
			_set_action(action, false)


func _exit_tree() -> void:
	_release_everything()


func _on_a_cable() -> bool:
	var player := Net.local_player
	return player != null and player.get(&"zipline") != null


## Whether a body is in reach right now. Asked of the player rather than
## recomputed, so the button appears exactly when the prompt does.
func _over_loot() -> bool:
	var player := Net.local_player
	if player == null:
		return false
	var target: Variant = player.get(&"loot_target")
	return target != null and is_instance_valid(target)


## Which screen is covering the game, expressed as the action that toggles it.
##
## The shop is deliberately not here: it has a button of its own, and offering a
## second way out that skips the button would be a way to deploy without ever
## having pressed READY.
func _close_action() -> StringName:
	for node in get_tree().get_nodes_in_group(&"map_screen"):
		var screen := node as CanvasItem
		if screen and screen.visible:
			return &"map"
	for node in get_tree().get_nodes_in_group(&"inventory_ui"):
		var screen := node as CanvasItem
		if screen and screen.visible:
			return &"inventory"
	return &""


func _close_rect() -> Rect2:
	var box := Vector2(150.0, 62.0)
	return Rect2(Vector2(size.x - SAFE - box.x, SAFE * 0.4), box)


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

	# Desktop, standing in for a finger.
	#
	# Never on a device. Godot emulates a mouse from the **first** touch, and that
	# echo arrives as its own pointer - so it grabbed the move stick as id -1 and
	# every real drag afterwards, carrying index 0, was ignored as a different
	# finger. _saw_touch alone was not enough: the echo can beat the touch it
	# came from.
	if _saw_touch or _mouse_is_an_echo:
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

	if _closing != &"":
		if _close_rect().has_point(at):
			_hold(id, _closing)
			return true
		return false

	# Buttons first, then the stick, then the bare right side. A button inside a
	# stick's reach has to win, or the ones nearest the corner are unreachable.
	for pill in _pill_rects():
		if not (pill.rect as Rect2).has_point(at):
			continue
		if pill.get("mode", "press") == "swap":
			_hold(id, _other_hand())
		else:
			_hold(id, pill.action)
		return true
	for button in _button_rects():
		if at.distance_to(button.at) > button.r * 1.15:
			continue
		match button.mode:
			"toggle":
				# No entry in _pressed: a latch has nothing to release.
				_latched[button.action] = not _latched.get(button.action, false)
			"tap":
				# No entry in _pressed either, for the same reason - the thumb
				# lifting must not end this one. _age_taps does that.
				_tapped[button.action] = TAP_HOLD
				_set_action(button.action, true)
			"swap":
				_hold(id, _other_hand())
			"fire":
				_hold(id, button.action)
				_take_aim(id, at)
			_:
				_hold(id, button.action)
		return true

	if not _riding and at.distance_to(_move_home()) <= STICK_RADIUS * STICK_GRAB:
		if _move_id != -2:
			return false
		_move_id = id
		_move_vec = _swing(at - _move_home())
		return true

	# Anywhere else on the right is the aim surface. No ring to find and no ring
	# to stay inside - put a thumb down and drag.
	if at.x > size.x * 0.5 and _aim_id == -2:
		_take_aim(id, at)
		return true
	return false


## The hand you are not currently holding, as the action that equips it.
##
## Worked out on the press rather than bound once: a single SWAP is the right
## control for two hands on a phone, and which of the two it means depends on
## what is in them at the time.
func _other_hand() -> StringName:
	var player := Net.local_player
	var held := 0
	if player and player.get(&"weapon") != null:
		held = player.weapon.slot
	return &"weapon_1" if held != 0 else &"weapon_2"


func _take_aim(id: int, at: Vector2) -> void:
	_aim_id = id
	_aim_last = at


## A finger sliding. The stick measures from its ring; the aim measures from
## wherever the finger was a moment ago.
func _drag(id: int, at: Vector2) -> bool:
	var ours := false
	if id == _move_id:
		_move_vec = _swing(at - _move_home())
		ours = true
	if id == _aim_id:
		PlayerInput.add_aim_motion((at - _aim_last) * AIM_DRAG)
		_aim_last = at
		ours = true
	return ours


func _lift(id: int) -> bool:
	var ours := false
	if id == _move_id:
		_move_id = -2
		_move_vec = Vector2.ZERO
		ours = true
	if id == _aim_id:
		_aim_id = -2
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
	for action in _tapped:
		_set_action(action, false)
	_tapped.clear()
	_set_action(&"move_down", false)
	_move_id = -2
	_aim_id = -2
	_move_vec = Vector2.ZERO
	PlayerInput.touch_move_axis = 0.0


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


func _move_home() -> Vector2:
	return Vector2(SAFE + STICK_RADIUS, size.y - SAFE - STICK_RADIUS)


## Where each button is this frame. Measured from a corner so the layout survives
## a screen of any shape - which on phones is the normal case.
func _button_rects() -> Array:
	var out: Array = []
	for button in _live_buttons():
		var offset: Vector2 = button.at
		var at := Vector2(offset.x if button.get("left", false) else size.x + offset.x,
			size.y + offset.y)
		out.append({
			"action": button.action, "label": button.label, "r": button.r,
			"mode": button.mode, "at": at,
		})
	return out


## Riding swaps the left cluster out; the right hand is untouched, because you
## can still shoot from a cable.
func _live_buttons() -> Array:
	var out: Array = []
	if _riding:
		# The left cluster is replaced; the right hand is untouched, because you
		# can still shoot from a cable.
		for button in BUTTONS:
			if not button.get("left", false):
				out.append(button)
		out.append_array(RIDE_BUTTONS)
	else:
		out.append_array(BUTTONS)
	if _looting:
		out.append(LOOT_BUTTON)
	return out


func _pill_rects() -> Array:
	var count := PILLS_LEFT.size() + PILLS_RIGHT.size()
	var gaps := (PILLS_LEFT.size() - 1 + PILLS_RIGHT.size() - 1) * PILL_GAP
	var room := size.x - SAFE * 2.0 - PILL_SPLIT
	# Shrunk to fit rather than allowed to run off the edge, which on a phone
	# would mean an action you simply cannot reach.
	var wide: float = minf(PILL_SIZE.x, (room - gaps) / count)
	var top := SAFE * 0.4

	var out: Array = []
	var x := SAFE
	for pill in PILLS_LEFT:
		out.append({"action": pill.action, "label": pill.label,
			"mode": pill.get("mode", "press"),
			"rect": Rect2(Vector2(x, top), Vector2(wide, PILL_SIZE.y))})
		x += wide + PILL_GAP

	var span := PILLS_RIGHT.size() * wide + (PILLS_RIGHT.size() - 1) * PILL_GAP
	x = size.x - SAFE - span
	for pill in PILLS_RIGHT:
		out.append({"action": pill.action, "label": pill.label,
			"mode": pill.get("mode", "press"),
			"rect": Rect2(Vector2(x, top), Vector2(wide, PILL_SIZE.y))})
		x += wide + PILL_GAP
	return out


func _holding(action: StringName) -> bool:
	return _pressed.values().has(action)


## A control reads as on when a thumb is on it or when it is latched, so a toggle
## looks the same as a hold while it is doing the same thing.
func _lit(action: StringName) -> bool:
	return _holding(action) or _latched.get(action, false)


func _draw() -> void:
	var font := ThemeDB.fallback_font

	if _closing != &"":
		var box := _close_rect()
		var down := _holding(_closing)
		draw_rect(box, HELD_TINT if down else PANEL)
		draw_rect(box, ACCENT if down else RING, false, 2.0)
		draw_string(font, box.position + Vector2(0.0, 38.0), "CLOSE",
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 18, ACCENT if down else LABEL)
		return

	if not _riding:
		_draw_stick(_move_id != -2, _move_home(), _move_vec, "MOVE")

	# A hint at the aim surface, not a control. Faint, and only while nobody is
	# using it: once a thumb is down, the character turning is the feedback.
	if _aim_id == -2:
		draw_string(font, Vector2(size.x * 0.5, size.y * 0.44), "drag anywhere to aim",
			HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.5 - SAFE, 15, Color(LABEL, 0.22))

	for button in _button_rects():
		var down := _lit(button.action)
		draw_circle(button.at, button.r, HELD_TINT if down else PANEL)
		draw_arc(button.at, button.r, 0.0, TAU, 32, ACCENT if down else RING, 2.0, true)
		draw_string(font, button.at + Vector2(-button.r, 5.0), button.label,
			HORIZONTAL_ALIGNMENT_CENTER, button.r * 2.0, 16, ACCENT if down else LABEL)
		# A latch says so, or there is no telling a toggle from a button you
		# happen to still be touching.
		if button.mode == "toggle" and _latched.get(button.action, false):
			draw_arc(button.at, button.r + 7.0, 0.0, TAU, 32, Color(ACCENT, 0.55), 2.0, true)

	for pill in _pill_rects():
		var rect: Rect2 = pill.rect
		var down := _lit(pill.action)
		draw_rect(rect, HELD_TINT if down else PANEL)
		draw_rect(rect, ACCENT if down else RING, false, 1.5)
		draw_string(font, rect.position + Vector2(0.0, 36.0), pill.label,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14, ACCENT if down else LABEL)


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
