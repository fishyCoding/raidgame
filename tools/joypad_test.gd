extends SceneTree

## A gamepad has to drive the game, because on an iPhone it is the only thing
## that can: Xogot's on-screen controller is Apple's GCVirtualController, which
## arrives as a joypad and not as touches.
##
##   godot --headless --path . --script res://tools/joypad_test.gd
##
## Driven through Input.action_press on the joypad actions rather than by faking
## a device, which is as close to a real stick as a headless run gets: the same
## actions the virtual controller raises, read by the same code that reads a
## keyboard.

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var input: Node = root.get_node("PlayerInput")
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
	await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		_say("FAILED: never got a character")
		quit(1)
		return

	# --- every action the virtual controller can raise is bound --------------
	for action in ["move_left", "move_right", "move_down", "jump", "fire",
			"interact", "grapple", "aim_left", "aim_right", "aim_up", "aim_down"]:
		_check("%s is bound to a joypad" % action, _has_joypad(action))

	var settled := 0
	while not player.is_on_floor() and settled < 300:
		await physics_frame
		settled += 1

	# --- the left stick walks -------------------------------------------------
	var from_x: float = player.global_position.x
	Input.action_press(&"move_right", 1.0)
	for i in 30:
		await physics_frame
	Input.action_release(&"move_right")
	var walked: float = player.global_position.x - from_x
	_say("stick right walked %.0f px" % walked)
	_check("the left stick moves the character", walked > 10.0)

	# --- the right stick aims -------------------------------------------------
	#
	# Read as a direction rather than as a press: get_stick_aim hands _update_aim
	# a vector, which is why these four actions exist at all.
	var before: float = player.aim_angle
	Input.action_press(&"aim_left", 1.0)
	for i in 20:
		await physics_frame
	_say("aim %.2f -> %.2f rad with the stick pushed left" % [before, player.aim_angle])
	_check("the right stick turns the gun", not is_equal_approx(before, player.aim_angle))
	_check("and points it the way the stick went", absf(player.aim_angle) > PI * 0.5)
	_check("which the input layer agrees with", input.get_stick_aim().x < 0.0)
	Input.action_release(&"aim_left")
	await physics_frame

	# A released stick hands aiming back rather than pinning the gun where it was
	# last pushed - on a desktop the mouse has to keep working.
	_check("a centred stick reports nothing", input.get_stick_aim().is_zero_approx())

	# --- and A jumps ---------------------------------------------------------
	settled = 0
	while not player.is_on_floor() and settled < 300:
		await physics_frame
		settled += 1
	var floor_y: float = player.global_position.y
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	var rose := 0.0
	for i in 25:
		await physics_frame
		rose = maxf(rose, floor_y - player.global_position.y)
	_say("A button rose %.0f px" % rose)
	_check("the A button jumps", rose > 8.0)

	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _has_joypad(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("joypad | %s" % text)
