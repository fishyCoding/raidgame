extends SceneTree

## Getting out still works, and only from your own way home.
##
## The hold used to be counted on the spawn point. It is counted on the player
## now, because there is one set of spawn points and several players standing at
## different corners of them - so this checks the replacement actually extracts
## somebody, and that a point which is not one of your exits does nothing no
## matter how long you stand in it.

var _ok := true
var _extracted_from: SpawnPoint = null


func _initialize() -> void:
	_run()


func _run() -> void:
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
	var player: Node2D = net.local_player
	if player == null:
		print("extract | FAILED: no character")
		quit(1)
		return

	# Past the shop and the briefing, or the tree stays paused and nothing counts.
	await _wait(15)
	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(20)

	var exits: Array = player._exits
	print("extract | came in near %.0f,%.0f with %d exit(s)" % [
		player.global_position.x, player.global_position.y, exits.size()])
	_check("has a way home", exits.size() > 0)
	if exits.is_empty():
		_finish()
		return

	# --- a point that is not yours does nothing ------------------------------
	var not_mine: SpawnPoint = null
	for node in get_nodes_in_group(&"spawn"):
		var point := node as SpawnPoint
		if point and not exits.has(point):
			not_mine = point
			break
	if not_mine:
		player.global_position = not_mine.global_position
		# Comfortably longer than hold_time, so a point that was counting would
		# have taken us out by now.
		await _wait(420)
		_check("somebody else's exit does nothing",
			not player.extracted_out and player.extracting == null)
		print("extract | stood in %s for 7s, still here" % not_mine.display_name)

	# --- your own takes you out ----------------------------------------------
	player.extracted.connect(func(from: SpawnPoint) -> void: _extracted_from = from)
	var home: SpawnPoint = exits[0]
	player.global_position = home.global_position
	var held := 0
	while not player.extracted_out and held < 600:
		# Held in place: the player is under gravity and physics, and drifting a
		# few pixels out of the ring restarts the count.
		player.global_position = home.global_position
		await physics_frame
		held += 1

	_check("got out", player.extracted_out)
	_check("out of the right one", _extracted_from == home)
	print("extract | out of %s after %.1fs (hold_time %.1fs)" % [
		home.display_name, held / 60.0, home.hold_time])
	# It has to take the time it says it takes, or the ring is decorative.
	_check("took about the hold time", held / 60.0 >= home.hold_time * 0.8)

	# --- and getting out still ends the run ----------------------------------
	#
	# Coming home is not a way back in. Both endings lead to the shop: a raid you
	# can re-enter on one keypress with a kit you did not pay for is a raid with
	# nothing at stake, whichever way the last one finished.
	await _wait(90)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await _wait(90)
	_check("back at the kit menu", current_scene != null and current_scene.name == "Lobby")
	_check("and out of the session", not net.in_session)

	_finish()


func _check(what: String, passed: bool) -> void:
	print("extract | %-34s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _finish() -> void:
	print("extract | %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
