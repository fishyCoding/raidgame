extends SceneTree

## TEST DRIVE: one button, and you are standing in the level able to move.
##
##   godot --headless --path . --script res://tools/test_drive_test.gd
##
## The point of the button is the absence of everything else - no shop, no
## briefing, no intro, no countdown - so most of this checks that things are
## *not* there, and then that the character actually walks.

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var input: Node = root.get_node("PlayerInput")

	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _wait(10)

	# Pressed through the handler the button is wired to, so this fails if the
	# path breaks rather than only if the button is missing.
	lobby._on_test_drive()
	_check("it staged a kit", net.staged_kit != null)
	_check("and flagged the shortcut", net.test_drive)
	_check("in a session", net.in_session)
	_check("and not a networked one", not net.is_networked())

	var waited := 0
	while (current_scene == null or current_scene.name != "Main") and waited < 900:
		await physics_frame
		waited += 1
	_check("the level loaded", current_scene != null and current_scene.name == "Main")
	if current_scene == null or current_scene.name != "Main":
		_finish()
		return

	waited = 0
	while net.local_player == null and waited < 600:
		await physics_frame
		waited += 1
	var player: Node2D = net.local_player
	_check("with a character in it", player != null)
	if player == null:
		_finish()
		return

	await _wait(30)

	# --- nothing in the way --------------------------------------------------
	var screens: Node = current_scene.get_node("HUD/Screens")
	var shop: Node = current_scene.get_node_or_null("HUD/Shop")
	_check("no shop over it", shop == null or not shop.visible)
	_check("nothing paused", not paused)
	_check("no briefing", screens.phase != screens.Phase.BRIEFING)
	_check("straight to playing", screens.phase == screens.Phase.PLAYING)
	# Read and cleared, or the next real raid would skip its own briefing.
	_check("the flag was consumed", not net.test_drive)
	_check("and the kit was taken off Net", net.staged_kit == null)

	# --- kitted, so there is something to test with --------------------------
	var kit: Inventory = player.inventory
	_check("a rifle in hand", kit != null and kit.primary != null)
	_check("something to throw", kit.get_throwable(0) != null)
	_check("an ultimate", kit.ultimates[0] != null)
	_check("a bag", kit.backpack_item != null)
	_check("and rounds for the rifle", kit.total_rounds() > 100)
	_say("kitted with: %s" % kit.summary())

	# --- and it moves --------------------------------------------------------
	var settled := 0
	while not player.is_on_floor() and settled < 300:
		await physics_frame
		settled += 1
	var from_x: float = player.global_position.x
	input.touch_move_axis = 1.0
	for i in 30:
		await physics_frame
	input.touch_move_axis = 0.0
	var walked: float = absf(player.global_position.x - from_x)
	_say("walked %.0f px straight off the button" % walked)
	_check("it plays immediately", walked > 10.0)

	_finish()


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("testdrive | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
