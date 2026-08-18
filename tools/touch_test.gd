extends SceneTree

## The game, played with thumbs, driven by synthetic touches.
##
##   godot --headless --path . --script res://tools/touch_test.gd
##
## The thing worth testing is not that a button exists - it is that three fingers
## work at once. Moving, aiming and firing simultaneously is the normal case in a
## fight and the one Godot's mouse emulation cannot express, so every press here
## goes in as an InputEventScreenTouch with its own index.

var _ok := true
var _pad: Control
var _input: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	_input = root.get_node("PlayerInput")

	# Forced, rather than waiting to be on a phone. This is exactly what the
	# switch is for.
	_input.control_scheme = _input.Controls.TOUCH
	_check("forcing touch mode takes", _input.is_touch())

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame

	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(20)

	# Out of the briefing and actually playing. The preamble above leaves Screens
	# in BRIEFING, and in touch mode a briefing eats the first tap by design - it
	# is how you dismiss it without a keyboard - which would otherwise swallow the
	# first touch of every test below it.
	var screens: Node = main.get_node("HUD/Screens")
	screens.phase = screens.Phase.PLAYING
	await _wait(5)

	var player: Node2D = net.local_player
	if player == null:
		_say("FAILED: never got a character")
		quit(1)
		return

	_pad = main.get_node_or_null("HUD/TouchControls")
	_check("the level has an on-screen pad", _pad != null)
	if _pad == null:
		_finish()
		return
	_check("and it is showing in touch mode", _pad.visible)
	_check("with the pointer left alone", Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)

	# --- every action is reachable -------------------------------------------
	#
	# The point of "everything accounted for": an action with no way to trigger
	# it is a mechanic that does not exist on a phone.
	var reachable := {}
	for entry in _pad.BUTTONS:
		reachable[entry.action] = true
	for entry in _pad.all_pills():
		reachable[entry.action] = true
	for action in ["fire", "jump", "grapple", "interact", "aim", "crouch",
			"reload", "heal", "ultimate", "throw_1", "throw_2", "inventory", "map"]:
		_check("%s has a button" % action, reachable.has(StringName(action)))
	# move_left/right/down come off the stick rather than a button.
	_say("%d buttons + %d pills cover %d actions" % [
		_pad.BUTTONS.size(), _pad.all_pills().size(), reachable.size()])

	# --- a touch must not pull the trigger by itself -------------------------
	#
	# Godot emulates a mouse from the first touch and `fire` was bound to the
	# left button, so every touch anywhere - dragging the movement stick
	# included - emptied the magazine into the floor. Emulation has to stay (it
	# is what lets a thumb press the shop's buttons), so the binding goes.
	# Asserted through the real Input layer, because that is where it went wrong.
	_check("no mouse button is bound to fire in touch mode",
		not _has_mouse_binding(&"fire"))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await physics_frame
	_check("so a stray tap does not shoot", not Input.is_action_pressed(&"fire"))
	click.pressed = false
	Input.parse_input_event(click)
	await physics_frame

	var settled := 0
	while not player.is_on_floor() and settled < 300:
		await physics_frame
		settled += 1

	# --- the left stick walks -------------------------------------------------
	#
	# Aimed at the ring itself. The sticks are fixed now: they used to appear
	# wherever the thumb landed, which drew a second joystick under the one
	# already on screen.
	var from_x: float = player.global_position.x
	var move_at: Vector2 = _pad._move_home()
	_touch(0, move_at, true)
	await physics_frame
	_drag(0, move_at + Vector2(90.0, 0.0))
	for i in 30:
		await physics_frame
	var walked: float = player.global_position.x - from_x
	_say("stick pushed right: walked %.0f px, axis %.2f" % [walked, _input.touch_move_axis])
	_check("the move stick walks", walked > 10.0)
	_check("and reports analog, not just on/off",
		_input.touch_move_axis > 0.1 and _input.touch_move_axis <= 1.0)

	# --- and the emulated mouse cannot steal it ------------------------------
	#
	# On a device Godot emulates a mouse from the *first* touch, and that echo
	# arrives as its own pointer. It grabbed the move stick as id -1, so every
	# real drag afterwards - carrying index 0 - was ignored as a different
	# finger, and the move stick did not work at all while the aim stick did.
	# Simulated here by driving the mouse at the ring while a finger holds it.
	var stolen := InputEventMouseButton.new()
	stolen.button_index = MOUSE_BUTTON_LEFT
	stolen.pressed = true
	stolen.position = move_at
	stolen.global_position = move_at
	root.push_input(stolen, true)
	await _wait(4)
	_check("a mouse echo does not take the stick", _pad._move_id == 0)
	_check("and the stick keeps reporting", _input.touch_move_axis > 0.1)
	stolen.pressed = false
	root.push_input(stolen, true)
	await _wait(2)
	_check("nor does letting it go drop the stick", _pad._move_id == 0)

	# The harder half: on a device the echo can arrive *before* the touch it came
	# from, so _saw_touch is still false and does not save us. Only knowing the
	# platform sends real touches does - which a headless desktop is not, so it
	# is told to pretend.
	_touch(0, move_at + Vector2(90.0, 0.0), false)
	await _wait(4)
	_pad._mouse_is_an_echo = true
	_pad._saw_touch = false
	stolen.pressed = true
	root.push_input(stolen, true)
	await _wait(4)
	_check("an echo arriving first is ignored outright", _pad._move_id == -2)
	stolen.pressed = false
	root.push_input(stolen, true)
	await _wait(2)

	# And a real finger still works with the echo guard up.
	_touch(0, move_at, true)
	await physics_frame
	_drag(0, move_at + Vector2(90.0, 0.0))
	await _wait(6)
	_check("while a real touch still drives it", _pad._move_id == 0
		and _input.touch_move_axis > 0.1)
	_pad._mouse_is_an_echo = false

	# --- a second finger aims while the first still walks --------------------
	var aim_at: Vector2 = _pad._aim_home()
	_touch(1, aim_at, true)
	_drag(1, aim_at + Vector2(-70.0, 0.0))
	await _wait(10)
	_say("aim vector %s, aim angle %.2f" % [_input.touch_aim_direction, player.aim_angle])
	_check("the aim stick points the gun", absf(player.aim_angle) > PI * 0.5)
	_check("while the move stick is still held", _input.touch_move_axis > 0.1)

	# --- and a third fires ----------------------------------------------------
	var fire := _button_at(&"fire")
	_check("there is a fire button to find", fire != Vector2.INF)
	_touch(2, fire, true)
	await _wait(4)
	_check("three fingers at once: firing", Input.is_action_pressed(&"fire"))
	_check("still walking", _input.touch_move_axis > 0.1)
	_check("still aiming", not _input.touch_aim_direction.is_zero_approx())

	# --- and letting go lets go ----------------------------------------------
	_touch(2, fire, false)
	_touch(1, aim_at + Vector2(-70.0, 0.0), false)
	_touch(0, move_at + Vector2(90.0, 0.0), false)
	await _wait(4)
	_check("fire released", not Input.is_action_pressed(&"fire"))
	_check("move centred", is_zero_approx(_input.touch_move_axis))
	_check("aim released", _input.touch_aim_direction.is_zero_approx())

	# --- a held button stays held --------------------------------------------
	var duck := _button_at(&"crouch")
	_touch(3, duck, true)
	await _wait(30)
	_check("crouch is held down, not tapped", Input.is_action_pressed(&"crouch"))
	_check("and the character actually crouched", player.crouch > 0.5)
	_touch(3, duck, false)
	await _wait(10)
	_check("and stands back up", not Input.is_action_pressed(&"crouch"))

	# --- and you can get back out of a screen --------------------------------
	#
	# Opening the map hides the pad, which used to take away the very pill that
	# opened it: the map went up and could never come down. The pad now shrinks
	# to a CLOSE button instead of vanishing.
	var map_pill := _button_at(&"map")
	_touch(4, map_pill, true)
	await _wait(4)
	_touch(4, map_pill, false)
	await _wait(20)
	var map_screen: CanvasItem = get_first_node_in_group(&"map_screen")
	_check("the MAP pill opens the map", map_screen != null and map_screen.visible)
	_check("the pad is still there", _pad.visible)
	_check("shrunk to a way out", _pad._closing == &"map")

	var close: Rect2 = _pad._close_rect()
	_touch(5, close.get_center(), true)
	await _wait(4)
	_touch(5, close.get_center(), false)
	await _wait(20)
	_check("and CLOSE shuts it again", not map_screen.visible)
	_check("with the full pad back", _pad._closing == &"" and _pad.visible)

	# --- switching back to desktop puts it away ------------------------------
	_input.control_scheme = _input.Controls.DESKTOP
	await _wait(5)
	_check("desktop mode hides the pad", not _pad.visible)
	_check("and leaves nothing pressed", not Input.is_action_pressed(&"crouch")
		and is_zero_approx(_input.touch_move_axis))
	# And the mouse gets its trigger back, or switching to touch once would cost
	# a desktop player the left button for the rest of the session.
	_check("the mouse can shoot again on desktop", _has_mouse_binding(&"fire"))

	_finish()


func _has_mouse_binding(action: StringName) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			return true
	return false


## Where a button sits on screen right now, or INF if there is no such button.
func _button_at(action: StringName) -> Vector2:
	for button in _pad._button_rects():
		if button.action == action:
			return button.at
	for pill in _pad._pill_rects():
		if pill.action == action:
			return (pill.rect as Rect2).get_center()
	return Vector2.INF


## Pushed at the viewport in **local** coordinates, not through
## Input.parse_input_event.
##
## parse_input_event applies the screen-to-viewport transform, and headless runs
## a 64 px window against a 1280 px viewport - so a touch aimed at (256, 1024)
## arrived at (5120, 20480), twenty times out and off the pad entirely. Worse, it
## still looked like it worked: touch emulates a mouse, and `fire` is bound to
## the left button, so the fire assertion passed without the fire button ever
## being hit.
func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	root.push_input(event, true)


func _drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	root.push_input(event, true)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("touch | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
