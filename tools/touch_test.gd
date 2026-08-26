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
	for action in ["fire", "jump", "grapple", "interact", "aim", "crouch", "shield",
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

	# --- a second finger aims by dragging, anywhere on the right -------------
	#
	# No ring to find and no ring to stay inside: the whole right side is the aim
	# surface, and it reports motion rather than a direction - the same path a
	# mouse takes, so the aiming code cannot tell them apart.
	var aim_at := Vector2(_pad.size.x * 0.7, _pad.size.y * 0.5)
	var before_aim: float = player.aim_angle
	_touch(1, aim_at, true)
	for i in 8:
		aim_at += Vector2(0.0, -22.0)
		_drag(1, aim_at)
		await physics_frame
	await _wait(6)
	_say("aim %.2f -> %.2f rad by dragging" % [before_aim, player.aim_angle])
	_check("dragging the right side aims", not is_equal_approx(before_aim, player.aim_angle))
	_check("while the move stick is still held", _input.touch_move_axis > 0.1)

	# --- and a third fires ----------------------------------------------------
	var fire := _button_at(&"fire")
	_check("there is a fire button to find", fire != Vector2.INF)
	_touch(2, fire, true)
	await _wait(4)
	_check("three fingers at once: firing", Input.is_action_pressed(&"fire"))
	_check("still walking", _input.touch_move_axis > 0.1)
	# Holding the trigger brings the sights up as well, so a fight does not cost
	# a second thumb.
	_check("and holding fire aims too", Input.is_action_pressed(&"aim"))

	# Dragging from the fire button keeps tracking while it shoots.
	var tracked: float = player.aim_angle
	var from := fire
	for i in 6:
		from += Vector2(0.0, 26.0)
		_drag(2, from)
		await physics_frame
	await _wait(4)
	_check("and can still be dragged to track", not is_equal_approx(tracked, player.aim_angle))

	# --- and letting go lets go ----------------------------------------------
	_touch(2, from, false)
	_touch(1, aim_at, false)
	_touch(0, move_at + Vector2(90.0, 0.0), false)
	await _wait(4)
	_check("fire released", not Input.is_action_pressed(&"fire"))
	_check("and the sights drop with it", not Input.is_action_pressed(&"aim"))
	_check("move centred", is_zero_approx(_input.touch_move_axis))

	# --- a tapped jump is a whole jump ---------------------------------------
	#
	# Player._update_jump cuts the rise short the moment `jump` stops being held,
	# which is how a keyboard gets a short hop out of a quick press. A thumb has
	# no slow press: the touch goes down and up inside a frame, so every jump on
	# a phone was the shortest one available and the top of the level could not
	# be reached at all. The button holds the action down on its own instead.
	#
	# Measured in height rather than in flags, because the flag was never the
	# complaint - "I cannot get up there" was.
	while not player.is_on_floor():
		await physics_frame
	var floor_y: float = player.global_position.y
	var leap := _button_at(&"jump")
	_touch(4, leap, true)
	_touch(4, leap, false)
	await physics_frame
	_check("the jump survives the thumb leaving", Input.is_action_pressed(&"jump"))
	var peak := floor_y
	var airborne := 0
	while airborne < 240:
		peak = minf(peak, player.global_position.y)
		if airborne > 6 and player.is_on_floor():
			break
		airborne += 1
		await physics_frame
	var rise: float = floor_y - peak
	_say("tapped jump rose %.0f px of a %.0f px jump" % [rise, player.jump_height])
	# Most of the way up, not the 45% a cut jump gets (Player.jump_cut). Not the
	# full number either - the character is measured at its own origin and the
	# peak is sampled per frame - so this is the gap between a real jump and a
	# clipped one, which is all that was wrong.
	_check("a tap gets the full jump, not a hop",
		rise > player.jump_height * player.jump_cut + 8.0)
	_check("and it lets go by itself afterwards", not Input.is_action_pressed(&"jump"))
	while not player.is_on_floor():
		await physics_frame

	# --- crouch latches, it is not held --------------------------------------
	#
	# A posture you have to keep a thumb on is a posture you cannot hold while
	# doing anything else, and on a phone every held button costs a finger.
	var duck := _button_at(&"crouch")
	_touch(3, duck, true)
	_touch(3, duck, false)
	await _wait(30)
	_check("crouch latches on after the thumb leaves", Input.is_action_pressed(&"crouch"))
	_check("and the character actually crouched", player.crouch > 0.5)
	_touch(3, duck, true)
	_touch(3, duck, false)
	await _wait(20)
	_check("and pressing again stands back up", not Input.is_action_pressed(&"crouch"))

	# --- so does ADS, for aiming without shooting ----------------------------
	var ads := _button_at(&"aim")
	_touch(3, ads, true)
	_touch(3, ads, false)
	await _wait(10)
	_check("ADS latches", Input.is_action_pressed(&"aim"))
	_check("without firing", not Input.is_action_pressed(&"fire"))
	_touch(3, ads, true)
	_touch(3, ads, false)
	await _wait(10)
	_check("and unlatches", not Input.is_action_pressed(&"aim"))

	# --- swapping hands ------------------------------------------------------
	#
	# There was no touch control for this at all: nothing pressed weapon_1 or
	# weapon_2 and nothing set touch_weapon_slot, so on a phone you were stuck
	# with whatever you deployed holding. SWAP works out which hand you are *not*
	# in on the press, because "the other gun" is not a fixed action.
	# A gun in each hand first. The starting kit is a sidearm only, and equip()
	# rightly refuses an empty hand - so with the default loadout there is nothing
	# to swap to and every assertion here passes for the wrong reason.
	player.inventory.set_slot(Inventory.Slot.PRIMARY,
		Item.from_weapon(load("res://resources/weapons/assault_rifle.tres")))
	await _wait(4)
	player.weapon.equip(0)
	await _wait(4)
	_check("holding the primary to start with", player.weapon.slot == 0)
	var swap := _button_at(&"swap")
	_check("there is a swap control", swap != Vector2.INF)
	_touch(7, swap, true)
	await _wait(6)
	_touch(7, swap, false)
	await _wait(6)
	_say("slot after swap: %d" % player.weapon.slot)
	_check("swap moves to the other hand", player.weapon.slot == 1)
	_touch(7, swap, true)
	await _wait(6)
	_touch(7, swap, false)
	await _wait(6)
	_check("and back again", player.weapon.slot == 0)

	# --- a body under your feet gets its own button --------------------------
	#
	# Looting is the point of the game and its only prompt was a caption naming a
	# key. The button appears exactly when the prompt does and nowhere else.
	_check("no LOOT button with nothing to loot", _loot_button() == Vector2.INF)
	_check("and the pad knows it", not _pad._looting)
	var corpse: Node2D = _drop_a_body(main, player)
	await _wait(20)
	_say("loot target: %s" % (player.loot_target.name if player.loot_target else "none"))
	_check("standing over it is noticed", _pad._looting)
	var loot_at := _loot_button()
	_check("a LOOT button appears", loot_at != Vector2.INF)
	if loot_at != Vector2.INF:
		_touch(8, loot_at, true)
		await _wait(6)
		_touch(8, loot_at, false)
		await _wait(20)
		_check("and it opens the body", player._searching != null or player.inventory_open)
		if player.inventory_open:
			player._close_screen()
		await _wait(10)
	if is_instance_valid(corpse):
		corpse.queue_free()
	await _wait(20)
	_check("and it goes away with the body", not _pad._looting)

	# --- riding a cable ------------------------------------------------------
	#
	# Ziplines were unusable on a phone: up is jump *held* and down is the move
	# stick pushed down, and the on-screen hint said "W up, S down, F to let go",
	# which is not advice a thumb can take. Riding now replaces the left hand with
	# three buttons that mean exactly those three things.
	var cable: Node2D = _find_cable(main)
	_check("the level has a cable to ride", cable != null)
	if cable == null:
		_finish()
		return
	# Put on at the bottom, so riding up has somewhere to go. Dropped on wherever
	# the character happened to be standing, it started at the top, rode 12 px and
	# stepped straight off the end - which reads as the button not working.
	player.zipline = cable
	player.global_position = cable.world_bottom()
	await _wait(6)
	_check("the pad knows we are on a cable", _pad._riding)

	var riding := {}
	for button in _pad._button_rects():
		riding[button.action] = button
	_check("UP is offered", riding.has(&"jump"))
	_check("DOWN is offered", riding.has(&"move_down"))
	_check("LET GO is offered", riding.has(&"interact"))
	_check("and the move stick is gone", not _pad._holding(&"move_left"))

	var rode_from: Vector2 = player.global_position
	_touch(6, (riding[&"jump"] as Dictionary).at, true)
	await _wait(30)
	_say("rode %.0f px up the cable" % rode_from.distance_to(player.global_position))
	_check("UP moves you along it",
		rode_from.distance_to(player.global_position) > 20.0)
	_touch(6, (riding[&"jump"] as Dictionary).at, false)
	await _wait(4)

	# Still on it, and LET GO is the way off.
	if player.zipline != null:
		_touch(6, (riding[&"interact"] as Dictionary).at, true)
		await _wait(4)
		_touch(6, (riding[&"interact"] as Dictionary).at, false)
		await _wait(10)
	_check("LET GO steps off it", player.zipline == null)
	await _wait(6)
	_check("and the move stick comes back", not _pad._riding)

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

	# Put the machine back the way it was found. control_scheme has a setter that
	# writes user://controls.cfg, and that is the same file the real game reads on
	# launch - so a run that ends here leaves the exported build pinned to
	# DESKTOP, and a run that ends in TOUCH leaves it drawing thumbsticks on a PC
	# with the keyboard unable to move. That has already cost an afternoon once:
	# see the note in tools/projection_test.gd. AUTO is the shipped default and
	# follows the device.
	_input.control_scheme = _input.Controls.AUTO

	_finish()


## The LOOT button, which only exists while there is something to open.
func _loot_button() -> Vector2:
	for button in _pad._button_rects():
		if button.label == "LOOT":
			return button.at
	return Vector2.INF


## A searchable body at the player's feet, put there directly rather than by
## killing something - what is being tested is the button, not the guard AI.
func _drop_a_body(main: Node, player: Node2D) -> Node2D:
	var body: Node2D = (load("res://scenes/lootable.tscn") as PackedScene).instantiate()
	var kit: Inventory = load("res://scripts/weapon.gd").starting_inventory()
	body.setup(kit, Color(0.6, 0.4, 0.3), Vector2(30, 52), "guard")
	main.add_child(body)
	body.global_position = player.global_position
	return body


## Any cable in the level. Found by method rather than by class name, which
## keeps enemy.gd-style compile poisoning off the table and does not care where
## the level files them.
func _find_cable(node: Node) -> Node2D:
	if node.has_method(&"clamp_to_cable"):
		return node as Node2D
	for child in node.get_children():
		var found := _find_cable(child)
		if found:
			return found
	return null


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
