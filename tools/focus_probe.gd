extends SceneTree

## Two of these are launched windowed, a second apart. The one launched second
## takes the focus; the first one loses it and must let go of the mouse.
##
##   godot --path . --script res://tools/focus_probe.gd -- --tag=A
##   godot --path . --script res://tools/focus_probe.gd -- --tag=B
##
## `server/test_focus.ps1` does both and reads the answer.

var _tag := "?"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.get_slice("=", 1)
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame

	# Past the shop and the briefing, or nothing is "playing" and the pointer is
	# legitimately free - see headless-test-must-unpause.
	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(30)

	var input: Node = root.get_node("PlayerInput")
	if net.local_player == null:
		print("%s | FAILED: never got a character" % _tag)
		quit(1)
		return
	print("%s | playing, wants_cursor=%s" % [_tag, input.wants_cursor()])

	# Long enough for the second instance to come up and steal the focus.
	await _wait(360)

	var focused: bool = root.get_window().has_focus()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	print("%s | focused=%s mouse=%s" % [_tag, focused,
		"CAPTURED" if captured else "free"])

	# The rule, from either side of it: the window being looked at holds the
	# mouse and nothing else does.
	var ok := focused == captured
	print("%s | %s" % [_tag, "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
