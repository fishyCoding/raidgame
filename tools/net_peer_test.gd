extends SceneTree

## Two of these are run at once - one with --host, one without - to check a real
## session over a real socket: connect, spawn a character each, and see the
## other one move.

var _net: Node
var _main: Node
var _hosting := false
var _clock := 0.0


func _initialize() -> void:
	_hosting = "--host" in OS.get_cmdline_user_args()
	_run()


func _run() -> void:
	_net = root.get_node("Net")
	# There is no MultiplayerAPI until the tree has ticked, and attaching a peer
	# before then quietly does nothing.
	await physics_frame
	var tag := "HOST  " if _hosting else "CLIENT"

	# Connect first, load the level second - the order a lobby would use. Loading
	# first means the level opens a solo session and spawns a character before
	# anyone can join, and that character then collides with the host's.
	if _hosting:
		var err: int = _net.host(27777)
		print("%s | hosting on 27777 -> %s" % [tag, "ok" if err == OK else "FAILED"])
		if err != OK:
			quit(1)
			return
	else:
		await _wait(45)
		var err: int = _net.join("127.0.0.1", 27777)
		print("%s | dialling 127.0.0.1:27777 -> %s" % [tag, "ok" if err == OK else "FAILED"])
		if err != OK:
			quit(1)
			return
		var waited_link := 0
		while not _net.in_session and waited_link < 300:
			await physics_frame
			waited_link += 1
		print("%s | connected: %s" % [tag, _net.in_session])
		if not _net.in_session:
			quit(1)
			return

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	# Wait for both characters to exist on this machine. Generously, because a
	# networked session is now a match: nobody deploys until there are two of
	# you and the ten-second countdown has run out.
	var waited := 0
	while _net.player_count() < 2 and waited < 1500:
		await physics_frame
		waited += 1
	print("%s | %d character(s) in the world after %.1fs" % [
		tag, _net.player_count(), waited / 60.0])
	if _net.player_count() < 2:
		print("%s | FAILED: never saw both players" % tag)
		quit(1)
		return

	# Past the shop and the briefing, or the tree stays paused and nothing walks.
	var shop: Node = _main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(10)

	var mine: Node2D = _net.local_player
	var theirs: Node2D = null
	for body in _net.players():
		if body != mine:
			theirs = body
	print("%s | mine=%s (local=%s)  theirs=%s (local=%s)" % [
		tag, mine.name, mine.is_local(), theirs.name, theirs.is_local()])

	# Somebody else's body must not be drawing its owner's readouts on our
	# screen: one camera, one crosshair, one torch.
	var their_overlay: CanvasLayer = theirs.get_node("Overlay")
	# Their dash streak is the other way round - it is meant to be drawn here,
	# which is the whole reason `dash_left` is on the wire. What must be true is
	# that this machine built one for their body at all, and that it is scenery
	# the dark can take away rather than something drawn through walls.
	var their_trail: Node = theirs.get_parent().get_node_or_null(
		"DashTrail_%s" % theirs.name)
	var theirs_hidden: bool = (not their_overlay.visible
		and their_trail != null and their_trail.is_in_group(&"shadowed"))
	print("%s | their overlay drawn here: %s; their streak built here: %s" % [
		tag, their_overlay.visible, their_trail != null])

	# Drive our own character and watch whether the other machine's copy of it
	# follows. Both sides walk, in opposite directions, so each has something to
	# observe.
	# Their movement is the furthest they got at any point, not where they are at
	# the end, and the watching outruns the walking. The two processes are started
	# a moment apart and do not share a clock, so whoever went first can be
	# standing still again before the other one looks - which read as "their
	# character moved 0 px" and failed a run where nothing was wrong.
	var input: Node = root.get_node("PlayerInput")
	var their_start: Vector2 = theirs.global_position
	var my_start: Vector2 = mine.global_position
	var they_moved := 0.0
	var i_moved := 0.0
	# Both directions, and the furthest either of us got - players deploy at
	# opposite ends of the map now, and one of those ends has a wall to the
	# right of it.
	for direction in [1.0, -1.0]:
		input.touch_move_axis = direction
		for i in 90:
			await physics_frame
			i_moved = maxf(i_moved, absf(mine.global_position.x - my_start.x))
			they_moved = maxf(they_moved, absf(theirs.global_position.x - their_start.x))
	input.touch_move_axis = 0.0
	for i in 150:
		await physics_frame
		i_moved = maxf(i_moved, absf(mine.global_position.x - my_start.x))
		they_moved = maxf(they_moved, absf(theirs.global_position.x - their_start.x))
	print("%s | I walked %.0f px; their character moved %.0f px on my screen" % [
		tag, i_moved, they_moved])

	# Guards must be thinking on exactly one machine - and be moving on both.
	#
	# Thinking-here alone is not enough, and used to be all this checked. A
	# client where the guards are correctly not thinking and also not moving is a
	# client that is receiving nothing about them, which is what a synchroniser
	# that spoke to this peer before the level existed leaves behind. It looked
	# exactly like a pass.
	var guards: Node = _main.get_node("Enemies")
	var thinking := 0
	for g in guards.get_children():
		if g.is_brain():
			thinking += 1
	var guard_start := PackedVector2Array()
	for g in guards.get_children():
		guard_start.append((g as Node2D).global_position)
	var stirred := {}
	for i in 180:
		await physics_frame
		for j in guards.get_child_count():
			if (guards.get_child(j) as Node2D).global_position.distance_to(guard_start[j]) > 1.0:
				stirred[j] = true
	print("%s | guards: %d of %d thinking here, %d of %d moving" % [
		tag, thinking, guards.get_child_count(), stirred.size(), guards.get_child_count()])

	var ok := (i_moved > 20.0 and they_moved > 20.0 and stirred.size() > 0
		and theirs_hidden)
	if _hosting:
		ok = ok and thinking > 0
	else:
		ok = ok and thinking == 0
	print("%s | %s" % [tag, "PASS" if ok else "FAIL"])
	await _wait(30)
	quit(0 if ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
