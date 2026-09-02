extends SceneTree

## The pointer has to be free on every screen you are expected to click, and
## captured only while you are actually aiming something.
##
## The lobby is the one that got missed: no character, no shop, tree not paused,
## so the old rule concluded you were playing and grabbed the mouse on the menu.
## Nothing caught it because every other test starts inside the level.

var _input: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	_input = root.get_node("PlayerInput")
	await physics_frame
	var ok := true

	# --- the lobby: a menu, so a pointer -------------------------------------
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await physics_frame
	ok = _expect("lobby", true) and ok
	lobby.queue_free()
	await physics_frame

	# --- the level, once a character exists: aiming, so captured -------------
	var net: Node = root.get_node("Net")
	net.play_solo()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await physics_frame

	var waited := 0
	while net.local_player == null and waited < 600:
		await physics_frame
		waited += 1
	if net.local_player == null:
		print("cursor | FAILED: never got a character")
		quit(1)
		return

	# Past the shop and the briefing, which legitimately want a pointer.
	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(10)
	ok = _expect("playing", false) and ok

	# --- and a shop back up: a pointer again ---------------------------------
	shop.visible = true
	await physics_frame
	ok = _expect("shop open", true) and ok

	# --- and the workshop, which is a screen the shop hides itself behind -----
	#
	# Its own group rather than the shop's, so it needs its own line here. A
	# full-screen panel that does not free the pointer is one you cannot click a
	# single thing on, and the way this screen is opened - the kit screen goes
	# invisible - means the group it is *not* in would have stopped answering.
	shop.visible = false
	shop._open_gunsmith(shop._inventory.secondary)
	await physics_frame
	ok = _expect("gunsmith", true) and ok
	shop._smith.visible = false
	shop.visible = true

	print("cursor | %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _expect(where: String, wanted: bool) -> bool:
	var got: bool = _input.wants_cursor()
	print("cursor | %-12s wants_cursor=%s (want %s) %s" % [
		where, got, wanted, "ok" if got == wanted else "WRONG"])
	return got == wanted


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
