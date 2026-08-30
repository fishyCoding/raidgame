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

## How far down the stick has to be pushed before it counts as crouching.
const CROUCH_PUSH := 0.62

## What counts as a swipe: this far, this fast, on a touch that is not driving
## anything else.
##
## Only the steering half of the screen. The far side is the aim surface, where
## dragging already means turning to look at something - a flick there is how you
## snap onto somebody, and it must not also throw you across the room.
const SWIPE_MIN := 170.0
const SWIPE_MS := 420
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
	# Everything the shooting and moving hands do now sits on the right, under
	# one thumb, with the left kept for the stick and the hook.
	#
	# Holding the trigger brings the sights up too - see the aim line in
	# _process - so shooting from the hip is not a thing you can do by accident.
	# ADS is still its own button for aiming without firing.
	{"action": &"fire", "label": "FIRE", "at": Vector2(-150.0, -300.0), "r": 92.0,
		"mode": "fire", "riding": true},
	# Tapped, not pressed. The player cuts a jump short when you let go of it
	# (Player.jump_cut), which is right for a key and wrong for glass: a thumb is
	# off the button before the character has left the floor, so every jump on a
	# phone was a 45% hop and the height was unreachable. Tap it and you get all
	# of it, which is the only jump a phone can usefully offer.
	#
	# Becomes ZIP when there is a cable in reach - see _live_buttons. One button,
	# because jumping and grabbing a rope are never both what you want, and a
	# phone has no room for a control that is wrong most of the time.
	{"action": &"jump", "label": "JUMP", "at": Vector2(-330.0, -420.0), "r": 66.0,
		"mode": "tap", "zip": true},
	{"action": &"aim", "label": "ADS", "at": Vector2(-320.0, -230.0), "r": 62.0,
		"mode": "toggle"},
	# There is no DUCK button. Crouch is the stick pushed straight down - see
	# _process - because a posture is a direction you are leaning, and making a
	# thumb leave the stick to change it meant it never got changed in a fight.
	# There is no USE button. Interact does three things and each has its own
	# control now: catching a rope is the JUMP button switching to ZIP, stepping
	# off one is LET GO in the riding cluster, and going through a body is the
	# LOOT button, which appears when there is a body worth opening. A fourth
	# button that duplicated all three was a permanent occupant of the best
	# real estate on the screen for the sake of nothing it could do alone.
	# Pressed, not latched, even though the shield *is* a latch in the game.
	# The latching lives in Player._update_shield, which flips on the press edge -
	# so a pad button that held the action down would flip it once and then never
	# again. One tap, one edge, one toggle.
	{"action": &"shield", "label": "PLATES", "at": Vector2(-490.0, -260.0), "r": 62.0,
		"mode": "press"},
	# The one thing left on the steering hand. It is a movement verb in the sense
	# that matters - it is how you cross a room - but it is aimed with the stick,
	# so it belongs next to it.
	{"action": &"grapple", "label": "HOOK", "at": Vector2(200.0, -390.0), "r": 62.0,
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
	{"action": &"jump", "label": "UP", "at": Vector2(-330.0, -420.0), "r": 68.0,
		"mode": "press"},
	{"action": &"move_down", "label": "DOWN", "at": Vector2(-330.0, -220.0), "r": 68.0,
		"mode": "press"},
	{"action": &"interact", "label": "LET GO", "at": Vector2(-500.0, -320.0), "r": 60.0,
		"mode": "press"},
	# The plates come with you onto the rope. Nothing in the game ever stopped a
	# man riding in his armour - it is slow and loud and you cannot stop, which
	# is cost enough - but this pad used to drop the button for the length of the
	# ride, so a phone could hold a stance it could not change. That was survivable
	# while the ramp was a third of a second. At two seconds the raise is longer
	# than plenty of rides, and starting it as you step off the top is the whole
	# difference between arriving covered and arriving in the open.
	#
	# Above LET GO rather than where it sits on the ground: the ground position is
	# 60 px from this cluster's LET GO with 120 px of radius between them, so
	# keeping it would have put a stance change under the thumb reaching for the
	# way off a rope.
	{"action": &"shield", "label": "PLATES", "at": Vector2(-500.0, -480.0), "r": 60.0,
		"mode": "press"},
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
]

## The things you spend, along the bottom edge between the two thumbs.
##
## They were up on the top rail with the reloads and the map, which put the ult
## and both grenades at the far end of a reach - and all three are things you
## use in the half second when something has gone wrong. Down here they are
## where the hands already are.
##
## Labelled from whatever is actually in the slot - see _pill_label. The names
## here are only the fallback for an empty one.
const PILLS_BOTTOM := [
	{"action": &"ultimate", "label": "ULT"},
	{"action": &"ultimate_2", "label": "ULT 2"},
	{"action": &"throw_1", "label": "THROW 1", "mode": "place", "slot": 0},
	{"action": &"throw_2", "label": "THROW 2", "mode": "place", "slot": 1},
]
## The two buttons that end a throw, while one is being placed.
##
## Two of them, and that is the whole reason this mode exists. On a keyboard a
## grenade is wound up by holding G and thrown by letting go, and the cursor
## places it in between - three things one hand does at once. A thumb cannot: it
## is either on the pill or on the map, never both, and "let go to throw" means
## every throw goes wherever the arc happened to be pointing when the thumb
## slipped. So the throw is split into place-then-commit, and abandoning it needs
## a button of its own because letting go can no longer mean cancel.
const PLACE_BUTTONS := [
	{"id": "throw", "label": "THROW", "at": Vector2(-190.0, -200.0), "r": 84.0},
	{"id": "cancel", "label": "CANCEL", "at": Vector2(-190.0, -390.0), "r": 62.0},
]

## Where the target starts, in pixels in front of the character, so an arc is on
## screen from the first frame rather than after the first drag. Roughly half the
## throw's range: far enough to be a throw, near enough to be a doorway.
const PLACE_DEFAULT_REACH := 340.0

## The pair that end a projection's placing view. Same shape as the throw pad and
## for the same reason: a thumb cannot both point at the level and press the
## thing that commits, so the two have to be separate presses.
const SEND_BUTTONS := [
	{"id": "send", "label": "SEND", "at": Vector2(-190.0, -200.0), "r": 84.0},
	{"id": "cancel", "label": "CANCEL", "at": Vector2(-190.0, -390.0), "r": 62.0},
]

const PILL_SIZE := Vector2(118.0, 56.0)
const PILL_GAP := 8.0
const PILL_SPLIT := 60.0


## Everything the pills cover, for anything that wants the whole set.
static func all_pills() -> Array:
	return PILLS_LEFT + PILLS_RIGHT + PILLS_BOTTOM


## Which pointer is driving what. -2 means nobody; a touch index otherwise, and
## -1 for the mouse standing in for a finger on a desktop.
## Touches that landed on nothing, watched in case they turn into a swipe.
var _swipes := {}

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
## The throw action whose landing spot is currently being placed, or "". While
## this is set the pad is that one job and nothing else: no stick, no aim
## surface, no pills.
var _placing := &""
## Where the finger has put it, in world space.
var _place_at := Vector2.INF


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
	_forget_spent_target()
	# Placing a projection takes the pad over entirely, the same way placing a
	# throw does. Checked before the visibility rules below because the pointer
	# is deliberately free while it is up - wants_cursor() answers true - and the
	# ordinary rule would take the pad away at exactly the wrong moment.
	if _aiming_projection():
		visible = PlayerInput.is_touch()
		if visible:
			_drive_projection()
		queue_redraw()
		return
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

	if _placing != &"":
		_drive_placement()
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

	# Straight down on the stick is the crouch.
	#
	# Straighter than the drop-through above, on purpose. Walking with a bit of
	# down in the stick must not put you on your knees, so this wants the push to
	# be mostly vertical, where dropping through a one-way platform only wants it
	# to be downward at all.
	_set_action(&"crouch", (not _riding and _move_vec.y > CROUCH_PUSH
		and absf(_move_vec.x) < _move_vec.y * 0.6))

	# Holding the trigger aims as well as shoots, so the sights come up without
	# spending a second thumb - and the ADS latch aims without firing.
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


## Drops a placed target once the throw that was going to use it is over.
##
## Asked of the player rather than timed out. A frame count would have to be
## right at every frame rate, and the thing it is really waiting for is a single
## specific event: Player._cancel_throw clearing throw_slot, which happens at the
## end of the throw whether it was thrown or abandoned.
func _forget_spent_target() -> void:
	if _placing != &"" or not PlayerInput.touch_aim_point.is_finite():
		return
	var player := Net.local_player
	if player == null or int(player.get(&"throw_slot")) < 0:
		PlayerInput.touch_aim_point = Vector2.INF


# --- placing a projection -----------------------------------------------------


## Whether the character currently has the projection's placing view open.
func _aiming_projection() -> bool:
	var player := Net.local_player
	if player == null:
		return false
	var aiming: Variant = player.get(&"projection_aiming")
	return typeof(aiming) == TYPE_BOOL and aiming


## A finger down while the projection is being placed. The two buttons win;
## everywhere else on the screen moves the mark.
func _projection_pointer(at: Vector2) -> bool:
	for button in _send_rects():
		if at.distance_to(button.at) <= button.r * 1.15:
			if button.id == "send":
				PlayerInput.touch_projection_send = true
			else:
				_cancel_projection()
			return true
	_mark_at(at)
	return true


## Nothing to drive but the mark, which the player reads straight off its own
## `projection_mark` - so the pad's job here is only to keep writing it.
func _drive_projection() -> void:
	pass


## Where the thumb is, handed to the character rather than written onto it.
##
## It used to set `projection_mark` directly, which did nothing at all: the pad
## runs in _process and the character re-derives the mark from the mouse in
## _physics_process, so every frame the thumb placed the marker the mouse put it
## straight back. On a phone there is no mouse to put it anywhere sensible, so
## the marker sat wherever the pointer happened to have been left.
func _mark_at(at: Vector2) -> void:
	PlayerInput.touch_projection_point = _world_at(at)


func _cancel_projection() -> void:
	PlayerInput.touch_projection_point = Vector2.INF
	var player := Net.local_player
	if player and player.has_method(&"_cancel_projection_aim"):
		player._cancel_projection_aim()


func _send_rects() -> Array:
	var out: Array = []
	for button in SEND_BUTTONS:
		out.append({
			"id": button.id, "label": button.label, "r": button.r,
			"at": Vector2(size.x + button.at.x, size.y + button.at.y),
		})
	return out


func _draw_projection_pad(font: Font) -> void:
	for button in _send_rects():
		var sending: bool = button.id == "send"
		var tint := ACCENT if sending else RING
		draw_circle(button.at, button.r, PANEL)
		draw_arc(button.at, button.r, 0.0, TAU, 32, tint, 2.5, true)
		draw_string(font, button.at + Vector2(-button.r, 5.0), button.label,
			HORIZONTAL_ALIGNMENT_CENTER, button.r * 2.0, 17, tint)


# --- placing a throw ----------------------------------------------------------


## Arms a grenade and hands the whole screen over to putting it somewhere.
##
## The action is pressed here and stays pressed - Player._update_throw treats a
## held throw key as "winding up", which is exactly the state we want it parked
## in while a thumb moves the target about. It is released by the THROW button
## and only by the THROW button.
func _begin_placing(action: StringName) -> void:
	# Whatever else was under a thumb is not any more. The stick especially: it
	# would otherwise be left reporting the last direction it was pushed for the
	# whole time the pad is showing something else.
	_release_everything()
	_placing = action
	_place_at = Vector2.INF
	_set_action(action, true)


func _end_placing(throw_it: bool) -> void:
	if _placing == &"":
		return
	# Letting go of the action is the throw, same as a key coming up.
	_set_action(_placing, false)
	if not throw_it:
		PlayerInput.touch_throw_cancelled = true
		PlayerInput.touch_aim_point = Vector2.INF
	_placing = &""
	_place_at = Vector2.INF
	# On a throw the target is deliberately left set. The pad runs in _process
	# and the throw is resolved in _physics_process, so clearing it here would
	# hand Player._throw_target an INF a frame before it reads it - and the
	# grenade would go to the crosshair instead of to the spot that was just
	# chosen, which is every throw on a phone landing in the wrong place. It is
	# cleared once the player says the throw is done. See _process.


## Written every frame while placing, for the same reason the stick is: this is a
## level, not an event, and a target that stopped being reported would fall back
## to the crosshair mid-throw.
func _drive_placement() -> void:
	var player := Net.local_player
	if player == null or not player.get(&"is_alive"):
		_end_placing(false)
		return
	# The screens take priority. Opening the bag mid-throw has to put the
	# grenade back rather than leave it armed behind a menu.
	if PlayerInput.wants_cursor():
		_end_placing(false)
		return
	if not _place_at.is_finite():
		var way := 1.0 if player.get(&"facing") > 0 else -1.0
		_place_at = player.global_position + Vector2(way * PLACE_DEFAULT_REACH, -60.0)
	PlayerInput.touch_aim_point = _place_at
	# The stick is still yours. Written here rather than left to the main body of
	# _process, which this mode returns before reaching.
	PlayerInput.touch_move_axis = _move_vec.x
	_set_action(&"move_down", _move_vec.y > 0.55)


## Screen pixels to world pixels, through whichever camera is live.
##
## The pad is on a CanvasLayer, so a touch arrives in screen space and the thing
## being placed is in the level. Worked out from the camera rather than from a
## canvas transform because the camera is the only thing that knows about the
## lean this game applies while aiming - see Player._get_lead_offset.
func _world_at(screen: Vector2) -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera == null or camera.zoom.x <= 0.0 or camera.zoom.y <= 0.0:
		return screen
	return camera.get_screen_center_position() + (screen - size * 0.5) / camera.zoom


func _place_rects() -> Array:
	var out: Array = []
	for button in PLACE_BUTTONS:
		out.append({
			"id": button.id, "label": button.label, "r": button.r,
			"at": Vector2(size.x + button.at.x, size.y + button.at.y),
		})
	return out


## A finger down while a throw is being placed.
##
## The two buttons win, then the move stick, then everywhere else on the screen
## is the map. The stick stays live on purpose: on a keyboard you can walk while
## you wind a grenade up, and taking that away on a phone would mean every throw
## is a second or two of standing perfectly still in the open - which is a worse
## trade than the grenade is worth.
func _placing_pointer(id: int, at: Vector2) -> bool:
	for button in _place_rects():
		if at.distance_to(button.at) <= button.r * 1.15:
			_end_placing(button.id == "throw")
			return true
	if _move_id == -2 and at.distance_to(_move_home()) <= STICK_RADIUS * STICK_GRAB:
		_move_id = id
		_move_vec = _swing(at - _move_home())
		return true
	_place_at = _world_at(at)
	return true


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

	# Placing something owns the whole screen. Checked before the close button
	# and before every pad control, because none of them exist right now.
	if _aiming_projection():
		return _projection_pointer(at)
	if _placing != &"":
		return _placing_pointer(id, at)

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
		match pill.get("mode", "press"):
			"swap":
				_hold(id, _other_hand())
			"place":
				# Not held. A grenade on glass is armed by this tap and thrown
				# by a different button entirely - see _begin_placing.
				_begin_placing(pill.action)
			_:
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

	# Landed on nothing. Held on to in case it becomes a swipe, which is how you
	# dash. Not claimed - a touch that turns out to be nothing should stay
	# nothing, and claiming it here would swallow presses the game wants.
	_swipes[id] = {"from": at, "at": Time.get_ticks_msec()}
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
	if _aiming_projection():
		_mark_at(at)
		return true

	# Dragging while placing is either the stick or the target, and which one it
	# is was decided when the finger went down.
	if _placing != &"":
		if id == _move_id:
			_move_vec = _swing(at - _move_home())
			return true
		var over_button := false
		for button in _place_rects():
			if at.distance_to(button.at) <= button.r * 1.15:
				over_button = true
		if not over_button:
			_place_at = _world_at(at)
		return true

	var ours := false
	if id == _move_id:
		_move_vec = _swing(at - _move_home())
		ours = true
	if id == _aim_id:
		PlayerInput.add_aim_motion((at - _aim_last) * AIM_DRAG)
		_aim_last = at
		ours = true
	if not ours:
		_watch_for_swipe(id, at)
	return ours


## A touch that is not driving anything, going somewhere in a hurry.
##
## Both halves of the test matter. Far enough, so resting a thumb and shifting it
## is not a dash; and quick enough, so slowly dragging a finger across the glass
## while doing something else is not either.
func _watch_for_swipe(id: int, at: Vector2) -> void:
	if not _swipes.has(id):
		return
	var start: Dictionary = _swipes[id]
	var went: Vector2 = at - (start.from as Vector2)
	if went.length() < SWIPE_MIN:
		return
	if Time.get_ticks_msec() - int(start.at) > SWIPE_MS:
		# Too slow to be a flick. Dropped rather than restarted, so a long
		# wandering drag cannot eventually qualify by accident.
		_swipes.erase(id)
		return
	_swipes.erase(id)
	PlayerInput.touch_dash = true
	PlayerInput.touch_dash_way = went.normalized()


func _lift(id: int) -> bool:
	_swipes.erase(id)
	var ours := false
	if id == _move_id:
		_move_id = -2
		_move_vec = Vector2.ZERO
		ours = true
	if id == _aim_id:
		_aim_id = -2
		ours = true
	if _pressed.has(id):
		for one in _pressed[id]:
			_set_action(one, false)
		_pressed.erase(id)
		ours = true
	return ours


func _hold(id: int, action: StringName) -> void:
	# A list, because releasing walks it. One entry today; the shape is what
	# stops a second action on a button turning into a leak.
	_pressed[id] = [action]
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
	# A placement in progress is abandoned, not thrown. This runs when the pad is
	# taken away underneath it - scheme change, a screen opening, stepping onto a
	# cable - and none of those are somebody deciding to throw a grenade.
	#
	# It has to release the action explicitly: a placed throw is held by nothing
	# in _pressed, so the loop below would leave it pressed forever and the
	# player would wind up a grenade with no way left to let go of it.
	if _placing != &"":
		_set_action(_placing, false)
		PlayerInput.touch_throw_cancelled = true
		_placing = &""
	_place_at = Vector2.INF
	PlayerInput.touch_aim_point = Vector2.INF
	for id in _pressed:
		for one in _pressed[id]:
			_set_action(one, false)
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
		# Only the trigger survives a ride - you can still shoot from a cable,
		# and everything else about standing on the ground has stopped applying.
		for button in BUTTONS:
			if button.get("riding", false):
				out.append(button)
		out.append_array(RIDE_BUTTONS)
		return out

	for button in BUTTONS:
		# One button for jumping and for catching a rope, showing whichever the
		# ground under you actually offers.
		if button.get("zip", false) and _cable_in_reach():
			var zipping: Dictionary = (button as Dictionary).duplicate()
			zipping.action = &"interact"
			zipping.label = "ZIP"
			# A press, not a tap: grabbing reads the press edge, and TAP_HOLD
			# would leave interact held down afterwards - which is the same
			# button that loots, so it would rifle the next body you walked over.
			zipping.mode = "press"
			out.append(zipping)
			continue
		out.append(button)

	# Only when there is a body worth opening - but then always, because it is
	# now the only way to go through one. The USE button used to be a second
	# route to it; with that gone, this appearing when the prompt does is what
	# stands between a player and a corpse they cannot search.
	if _over_loot():
		out.append(LOOT_BUTTON)
	return out


## Whether there is a cable close enough to catch hold of, and whether you are
## allowed to.
##
## The cooldown counts here and not only in Player. This is the button that
## turns into ZIP, and it is the same button as JUMP - so a rope you cannot
## grab for another ten seconds would otherwise take the jump away from you for
## ten seconds while you stood under it, and hand you a button that does
## nothing in exchange. On a phone that is not a missing prompt, it is a
## missing verb.
func _cable_in_reach() -> bool:
	var player := Net.local_player
	if player == null:
		return false
	var cooling: Variant = player.get(&"zipline_cooldown_left")
	if typeof(cooling) == TYPE_FLOAT and float(cooling) > 0.0:
		return false
	return Zipline.nearest(get_tree(), player.global_position) != null


func _pill_rects() -> Array:
	# Widths come off the top rail only. The bottom row is short and sits in open
	# space, so letting it squeeze the ones along the top would shrink every pill
	# on screen to fit a problem that does not exist.
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
		out.append({"action": pill.action, "label": _pill_label(pill),
			"mode": pill.get("mode", "press"),
			"rect": Rect2(Vector2(x, top), Vector2(wide, PILL_SIZE.y))})
		x += wide + PILL_GAP

	# Centred along the bottom, in the gap between the steering thumb's stick and
	# the shooting thumb's cluster. The middle of the bottom edge is the one part
	# of a phone held in two hands that nothing else wants.
	var across := PILLS_BOTTOM.size() * wide + (PILLS_BOTTOM.size() - 1) * PILL_GAP
	x = (size.x - across) * 0.5
	var floor_row := size.y - SAFE - PILL_SIZE.y
	for pill in PILLS_BOTTOM:
		out.append({"action": pill.action, "label": _pill_label(pill),
			"mode": pill.get("mode", "press"),
			"rect": Rect2(Vector2(x, floor_row), Vector2(wide, PILL_SIZE.y))})
		x += wide + PILL_GAP
	return out


## What to print on a pill.
##
## The two throw pills used to say FRAG and SMOKE because those were the only
## two throwables there were. They are not any more, and a button labelled
## SMOKE that throws a flash grenade is worse than one labelled THROW 2 - on a
## phone the label is the only thing telling you what is about to leave your
## hand, and there is no inventory open beside it to check against.
func _pill_label(pill: Dictionary) -> String:
	var slot: int = pill.get("slot", -1)
	if slot < 0:
		return pill.label
	var player := Net.local_player
	var kit: Variant = player.get(&"inventory") if player else null
	if kit == null:
		return pill.label
	var item: Variant = kit.get_throwable(slot)
	if item == null:
		return pill.label
	# The count too. Running out of throwables is something you plan around,
	# and the pill is the only place a thumb ever sees it.
	return "%s %d" % [item.gadget.short_name, item.count]


func _holding(action: StringName) -> bool:
	for actions in _pressed.values():
		if (actions as Array).has(action):
			return true
	return false


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

	if _aiming_projection():
		_draw_projection_pad(font)
		return

	if _placing != &"":
		_draw_placement(font)
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


## The throw pad: two buttons and a mark on the spot.
##
## Everything else is deliberately gone. The arc itself is not drawn here - the
## player's own AimLine already draws it, on the overlay above the world, and it
## is the same arc a mouse gets. All this adds is the crosshair under the thumb,
## because a finger covers the exact pixel it is choosing and the ring at the end
## of the arc is the only part you can actually see.
func _draw_placement(font: Font) -> void:
	draw_string(font, Vector2(size.x * 0.5, SAFE * 1.6), "drag to place it",
		HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.5 - SAFE, 17, Color(LABEL, 0.5))
	# Still yours to walk with, so it is still drawn. A stick that vanishes is a
	# stick nobody tries.
	_draw_stick(_move_id != -2, _move_home(), _move_vec, "MOVE")

	if _place_at.is_finite():
		var camera := get_viewport().get_camera_2d()
		if camera and camera.zoom.x > 0.0:
			var screen := (_place_at - camera.get_screen_center_position()) * camera.zoom
			screen += size * 0.5
			draw_arc(screen, 26.0, 0.0, TAU, 32, Color(ACCENT, 0.75), 2.0, true)
			draw_line(screen - Vector2(36.0, 0.0), screen + Vector2(36.0, 0.0),
				Color(ACCENT, 0.45), 1.5, true)
			draw_line(screen - Vector2(0.0, 36.0), screen + Vector2(0.0, 36.0),
				Color(ACCENT, 0.45), 1.5, true)

	for button in _place_rects():
		var throwing: bool = button.id == "throw"
		var tint := ACCENT if throwing else RING
		draw_circle(button.at, button.r, PANEL)
		draw_arc(button.at, button.r, 0.0, TAU, 32, tint, 2.5, true)
		draw_string(font, button.at + Vector2(-button.r, 5.0), button.label,
			HORIZONTAL_ALIGNMENT_CENTER, button.r * 2.0, 17, tint)


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
