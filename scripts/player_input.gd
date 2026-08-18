extends Node

## Autoload: the single seam between raw input devices and gameplay.
##
## Gameplay code never reads Input directly, so the touch HUD can be added later
## by writing to the touch_* fields below instead of rewriting player.gd.
## Keyboard/mouse and touch are merged, so both work at once while testing.
##
## One-frame flags (the *_pressed fields) are cleared automatically at the end of
## the physics frame, so a HUD button can just set one and forget it.

## Set by a virtual joystick: -1.0 (left) .. 1.0 (right). 0.0 when untouched.
var touch_move_axis := 0.0

## Set by an aim stick: direction the player is aiming. Zero when untouched.
var touch_aim_direction := Vector2.ZERO

## How far the aim stick has to be pushed before it counts. Generous, because a
## stick that rests a hair off centre would otherwise drag the crosshair round
## and hold it there against the mouse.
const STICK_DEADZONE := 0.25

## Set by a touch throw, which needs a spot rather than a direction: a grenade
## is placed, not pointed. Vector2.INF means "not set, use the cursor".
var touch_aim_point := Vector2.INF

## Set true by a HUD jump button on press; consumed (reset) when read.
var touch_jump_pressed := false

## Held for as long as the HUD jump button is down (drives variable jump height).
var touch_jump_held := false

## Held while a HUD "down" button is down (drop through one-way platforms).
var touch_down_held := false

## Held while the fire button is down. The just-pressed edge is derived from it,
## so an auto-fire button and a tap both work.
var touch_fire_held := false

## Held while the aim-down-sights button is down.
var touch_aim_held := false

## Held while the crouch button is down.
var touch_crouch_held := false

## Set true for one frame by a HUD "pick up" button.
var touch_interact_pressed := false

## Set true for one frame by a HUD grapple button.
var touch_grapple_pressed := false

## Set true for one frame by a HUD "bag" button.
var touch_inventory_pressed := false

## Set true for one frame by a HUD "patch up" button.
var touch_heal_pressed := false

## Set true for one frame by a HUD reload button.
var touch_reload_pressed := false

## Set to 0-4 for one frame by a HUD weapon slot button. -1 means "no request".
var touch_weapon_slot := -1

## Last non-zero aim, so the character keeps facing somewhere sane when the
## aim stick is released on mobile.
var _last_aim := Vector2.RIGHT
var _touch_fire_prev := false

## Mouse movement since gameplay last read it, in screen pixels.
##
## Relative motion, not a cursor position. Aiming at wherever the pointer happens
## to sit only works if the character is at a known place on screen, and this
## camera leans off centre as you aim - so the same cursor position meant a
## different angle from one moment to the next. Relative motion has no such
## dependency, and nothing has to chase anything, so there is no lag in it.
var _mouse_motion := Vector2.ZERO

## Groups whose screens need a real pointer. While any of them is on screen the
## cursor comes back; the rest of the time it is captured and hidden.
const CURSOR_GROUPS := [&"shop", &"inventory_ui", &"map_screen"]

## Which way the game is being played.
##
## AUTO is right almost always - a phone is a phone and a PC is a PC - but it has
## to be overridable, because the whole reason to build touch controls on a
## desktop is to look at them without a deploy in the loop. Switching is
## instant: nothing about a control scheme needs a restart.
enum Controls { AUTO, TOUCH, DESKTOP }

## Where the choice is remembered. A setting you have to make again every launch
## is one you stop using.
const CONTROLS_FILE := "user://controls.cfg"

var control_scheme := Controls.AUTO:
	set(value):
		if control_scheme == value:
			return
		control_scheme = value
		_save_controls()
		_apply_scheme_to_input_map()
		controls_changed.emit(is_touch())

## Raised when the scheme changes, so the on-screen controls can appear or go
## away without polling for it.
signal controls_changed(touch: bool)


## Whether the game should be driven by thumbs.
##
## "mobile" alone is not enough: a **web** export running in Safari on a phone
## reports its platform as web, so the feature is false and the on-screen
## controls would never appear on the one device that needs them. Godot exposes
## web_ios / web_android for exactly this, and the browser build is how the game
## gets onto a phone without an App Store account - see server/serve_web.ps1.
func is_touch() -> bool:
	match control_scheme:
		Controls.TOUCH:
			return true
		Controls.DESKTOP:
			return false
	return has_touchscreen()


## Whether this machine actually sends touch events.
##
## Distinct from is_touch(), which is a *choice* and can be forced on a desktop
## that has no touchscreen at all. Anything that needs to know "will real touches
## arrive" - as opposed to "should thumbs be catered for" - wants this one.
func has_touchscreen() -> bool:
	return OS.has_feature("mobile") \
		or OS.has_feature("web_ios") or OS.has_feature("web_android")


## The next scheme round the loop, for a button that cycles rather than a menu.
func cycle_controls() -> void:
	control_scheme = ((control_scheme + 1) % Controls.size()) as Controls


func scheme_name() -> String:
	match control_scheme:
		Controls.TOUCH:
			return "touch"
		Controls.DESKTOP:
			return "desktop"
	return "auto (%s)" % ("touch" if is_touch() else "desktop")


## Actions a mouse button can trigger. In touch mode their mouse bindings are
## taken out of the input map and put back when the scheme changes again.
##
## This is not tidiness, it is the difference between a playable build and an
## unplayable one. Godot emulates a mouse from the first touch, `fire` is bound
## to the left button, and the result is that **every** touch pulls the trigger -
## dragging the movement stick empties your magazine into the floor. Emulation
## cannot simply be switched off, because it is also what lets a thumb press the
## buttons on the shop and the inventory screen. So the emulation stays and the
## bindings go: shooting comes from the FIRE button and nothing else.
const MOUSE_ACTIONS := [&"fire", &"aim"]

## action -> the mouse events lifted out of it, waiting to go back.
var _stashed_mouse := {}


func _apply_scheme_to_input_map() -> void:
	if is_touch():
		for action in MOUSE_ACTIONS:
			if _stashed_mouse.has(action) or not InputMap.has_action(action):
				continue
			var lifted: Array[InputEvent] = []
			for event in InputMap.action_get_events(action):
				if event is InputEventMouseButton:
					lifted.append(event)
			for event in lifted:
				InputMap.action_erase_event(action, event)
			_stashed_mouse[action] = lifted
		return

	for action in _stashed_mouse:
		for event in _stashed_mouse[action]:
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
	_stashed_mouse.clear()


func _load_controls() -> void:
	var file := ConfigFile.new()
	if file.load(CONTROLS_FILE) != OK:
		return
	var saved: int = file.get_value("controls", "scheme", Controls.AUTO)
	if saved >= 0 and saved < Controls.size():
		# Set the backing value directly: going through the setter here would
		# save the file we have just read and announce a change nobody has made.
		control_scheme = saved as Controls


func _save_controls() -> void:
	var file := ConfigFile.new()
	file.set_value("controls", "scheme", int(control_scheme))
	file.save(CONTROLS_FILE)


func _ready() -> void:
	# Run after every gameplay node so one-frame flags are cleared only once
	# everyone has had a chance to read them.
	process_priority = 500
	process_physics_priority = 500
	_load_controls()
	# _load_controls sets the backing value directly, so the setter never ran and
	# the map is still whatever the project file said.
	_apply_scheme_to_input_map()


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_motion += motion.relative


func _process(_delta: float) -> void:
	_update_mouse_mode()


## Whether a pointer is wanted right now: paused, or some screen is up that you
## have to click on. Split out from the mode switch below so it can be checked
## without a display attached.
func wants_cursor() -> bool:
	if get_tree().paused:
		return true
	# No character means there is nothing to aim, so the pointer belongs to
	# whoever is looking at the screen. That is the lobby - which is a menu of
	# buttons and a text field, and came up with the mouse already captured and
	# no way to click any of it - and also the gap between a level loading and a
	# spawn arriving, and a dedicated server, which has no character ever.
	var player := Net.local_player
	if player == null:
		return true
	# Dying does not pause the tree, so without this the death screen came up
	# with the pointer still captured and no way to click anything.
	var alive: Variant = player.get(&"is_alive")
	if typeof(alive) == TYPE_BOOL and not alive:
		return true
	for group in CURSOR_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var control := node as CanvasItem
			if control and control.visible:
				return true
	return false


## Captured while you are playing, free while a screen is up. Captured rather
## than merely hidden: a hidden pointer still hits the edge of the window and
## silently stops producing motion, which reads as the aim jamming.
##
## And never while the window is in the background. There is one mouse on the
## machine and two copies of the game will both take it, which is a problem the
## moment you run them side by side to test anything: the instance you are not
## looking at holds the cursor hidden and clipped, so there is nothing to click
## the other window with, and a window that cannot be given focus is never sent a
## key. It reads as the second copy ignoring the keyboard - the mouse is the
## cause and the keys are the symptom.
##
## Checked here rather than in wants_cursor(), which is about what the *game*
## wants and is deliberately answerable with no display attached.
func _update_mouse_mode() -> void:
	# Thumbs do not need the pointer taking away from them, and on a phone there
	# is no pointer to take. Capturing it would also hide the cursor on a desktop
	# testing touch mode, which is the one place you still need to see it.
	var free := is_touch() or wants_cursor() or not _window_has_focus()
	var wanted := Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted
		# Whatever the pointer did while it was free is not aim input. That covers
		# alt-tabbing away and back: the desktop is not a mouse movement, and
		# without this you come back to the raid aiming somewhere else.
		_mouse_motion = Vector2.ZERO


## Whether anybody is actually looking at this window.
##
## Headless has no window to focus and answers false, which is why this is not
## allowed anywhere near wants_cursor().
func _window_has_focus() -> bool:
	var window := get_window()
	return window != null and window.has_focus()


## Mouse movement since the last call, and clears it. Gameplay decides what a
## pixel of movement is worth - that depends on the weapon, which is not
## something this file should know about.
func consume_aim_motion() -> Vector2:
	var motion := _mouse_motion
	_mouse_motion = Vector2.ZERO
	return motion


## The aim stick, for touch, for a gamepad, and for the test harnesses. Zero when
## unused, which is what leaves the mouse in charge on a desktop.
##
## The right stick is read here rather than through the input map because aiming
## is a direction, not an action: _update_aim wants a vector it can point the gun
## along, and an action can only ever say pressed or not. A held stick keeps
## reporting, so this reads it live rather than waiting to be told.
##
## Deliberately after the touch field: anything actually driving touch_aim_direction
## - the test harnesses today, a thumbstick drawn on the screen later - outranks a
## controller that is probably not plugged in.
func get_stick_aim() -> Vector2:
	if not touch_aim_direction.is_zero_approx():
		return touch_aim_direction
	var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	# Past the deadzone, or a stick resting off-centre by a pixel drags the aim
	# round and pins it there - the gun would never point where the mouse said.
	return stick if stick.length() > STICK_DEADZONE else Vector2.ZERO


func _physics_process(_delta: float) -> void:
	_touch_fire_prev = touch_fire_held
	touch_jump_pressed = false
	touch_reload_pressed = false
	touch_interact_pressed = false
	touch_grapple_pressed = false
	touch_inventory_pressed = false
	touch_heal_pressed = false
	touch_weapon_slot = -1


func get_move_axis() -> float:
	if not is_zero_approx(touch_move_axis):
		return clampf(touch_move_axis, -1.0, 1.0)
	return Input.get_axis(&"move_left", &"move_right")


func is_jump_just_pressed() -> bool:
	if touch_jump_pressed:
		touch_jump_pressed = false
		return true
	return Input.is_action_just_pressed(&"jump")


func is_jump_held() -> bool:
	return touch_jump_held or Input.is_action_pressed(&"jump")


func is_down_held() -> bool:
	return touch_down_held or Input.is_action_pressed(&"move_down")


func is_fire_just_pressed() -> bool:
	var touch_edge := touch_fire_held and not _touch_fire_prev
	return touch_edge or Input.is_action_just_pressed(&"fire")


func is_fire_held() -> bool:
	return touch_fire_held or Input.is_action_pressed(&"fire")


## True while aiming down sights (right mouse button, for now).
func is_aim_held() -> bool:
	return touch_aim_held or Input.is_action_pressed(&"aim")


## True while crouching (left control or C, for now).
func is_crouch_held() -> bool:
	return touch_crouch_held or Input.is_action_pressed(&"crouch")


## True on the frame the grapple is fired or released (E or middle mouse).
func is_grapple_just_pressed() -> bool:
	if touch_grapple_pressed:
		touch_grapple_pressed = false
		return true
	return Input.is_action_just_pressed(&"grapple")


## True on the frame the loot button is pressed (F, for now).
func is_interact_just_pressed() -> bool:
	if touch_interact_pressed:
		touch_interact_pressed = false
		return true
	return Input.is_action_just_pressed(&"interact")


## True on the frame the heal button is pressed (H, for now).
func is_heal_just_pressed() -> bool:
	if touch_heal_pressed:
		touch_heal_pressed = false
		return true
	return Input.is_action_just_pressed(&"heal")


## True on the frame the ultimate is fired (Q, for now).
func is_ultimate_just_pressed() -> bool:
	return Input.is_action_just_pressed(&"ultimate")


## True on the frame throwable `slot` is started (G and T, for now).
func is_throw_just_pressed(slot: int) -> bool:
	return Input.is_action_just_pressed("throw_%d" % (slot + 1))


## True while that throw key is held - grenades are wound up, not tapped.
func is_throw_held(slot: int) -> bool:
	return Input.is_action_pressed("throw_%d" % (slot + 1))


## True on the frame the inventory screen is toggled (TAB, for now).
func is_inventory_just_pressed() -> bool:
	if touch_inventory_pressed:
		touch_inventory_pressed = false
		return true
	return Input.is_action_just_pressed(&"inventory")


func is_reload_just_pressed() -> bool:
	return touch_reload_pressed or Input.is_action_just_pressed(&"reload")


## Returns the requested weapon slot (0-4) for this frame, or -1 for none.
func get_weapon_slot() -> int:
	if touch_weapon_slot >= 0:
		return touch_weapon_slot
	for i in 5:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			return i
	return -1


## Where the player is pointing, as a spot in the world rather than a direction.
## `offset` is the character's own crosshair, relative to it - there is no cursor
## to read a position off any more, so the crosshair is the position.
func get_aim_point(origin: Vector2, offset: Vector2) -> Vector2:
	if touch_aim_point.is_finite():
		return touch_aim_point
	if not touch_aim_direction.is_zero_approx():
		# A stick has a direction but no distance, so a touch throw without an
		# explicit point goes a sensible middle distance.
		return origin + touch_aim_direction.normalized() * 420.0
	return origin + offset


## Aim direction from the stick, for touch and for the harnesses. Mouse aim is
## no longer a direction this file can work out on its own - it is integrated
## from relative motion by whoever is doing the aiming.
func get_aim_direction(_from: Node2D) -> Vector2:
	if not touch_aim_direction.is_zero_approx():
		_last_aim = touch_aim_direction.normalized()
	return _last_aim


## Aim delivered as movement rather than as a direction.
##
## A dragging thumb is a mouse: it says "turn this far from where you were", not
## "point exactly there". Fed into the same accumulator the mouse uses so the
## aiming code cannot tell them apart - and deliberately not through _input's
## mouse branch, which only listens while the pointer is captured, and on a phone
## it never is.
func add_aim_motion(motion: Vector2) -> void:
	_mouse_motion += motion
