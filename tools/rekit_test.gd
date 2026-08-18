extends SceneTree

## You cannot go back in without buying a kit first.
##
##   godot --headless --path . --script res://tools/rekit_test.gd
##
## Dying used to reload the level, which handed you a fresh starting kit and put
## you straight back in a raid - so the bet you had just lost cost you nothing.
## The way out of a run, either way it ends, is the shop.
##
## Driven with a real ENTER through the input map rather than by calling the
## handler, because "hitting enter puts you back in" is the thing being denied.

const ENTER := KEY_ENTER

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
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
	_check("in a raid with a character", player != null and net.in_session)
	if player == null:
		_finish()
		return

	# Something on him worth losing, so the death screen has something to name.
	var stim := Item.from_revive(3)
	for pocket in player.inventory.pockets:
		if pocket.add(stim):
			break
	var carried: String = player.inventory.summary()
	_say("going in with: %s" % carried)

	# --- die -----------------------------------------------------------------
	for i in 20:
		if not player.is_alive:
			break
		player._invulnerable = 0.0
		player.take_damage(90.0, player.global_position, Vector2.RIGHT)
		for j in 4:
			await physics_frame
	_check("dead", not player.is_alive)

	var screens: Node = main.get_node("HUD/Screens")
	_check("the death screen is up", screens.phase == screens.Phase.DEAD)
	_check("and it remembers what was lost", not screens._carried.is_empty())
	_say("death screen reports: %s" % screens._carried)

	# --- ENTER, which must not put us back in a raid -------------------------
	#
	# After the screen's own hold: it ignores the key for the first beat so a
	# trigger finger cannot skip past the verdict.
	for i in 120:
		await physics_frame
	_press(ENTER)
	for i in 90:
		await physics_frame

	var scene := current_scene
	_say("landed on: %s" % (scene.name if scene else "NOTHING"))
	_check("back at the kit menu", scene != null and scene.name == "Lobby")
	_check("and out of the session", not net.in_session)
	_check("with no character left in the world", net.local_player == null)
	if scene == null or scene.name != "Lobby":
		_finish()
		return

	# --- and it is a real shop, with the bill to pay again -------------------
	var menu_shop: Node = scene._shop
	_check("the kit screen is up", menu_shop != null and menu_shop.visible)
	if menu_shop:
		_check("the button queues rather than deploys",
			menu_shop.deploy_label == "JOIN MATCHMAKING")
		_check("full credits to spend", menu_shop.credits == menu_shop.CREDITS)
		# The whole point: what died with you is not on the counter waiting.
		var fresh: String = scene._kit.summary()
		_say("the new kit starts as: %s" % fresh)
		_check("and the dead man's kit is not in it", fresh != carried)

	_finish()


func _press(keycode: int) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await physics_frame
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("rekit | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
