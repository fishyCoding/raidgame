extends SceneTree

## Checks the dedicated-server path: a real server process with nobody in it,
## and two clients that join it over a real socket.
##
## Run as a client only. The server is a separate process started the way the
## Oracle box starts it - the whole point is that it is the same command:
##
##   godot --headless --path . -- --server=27778
##   godot --headless --path . --script res://tools/dedicated_test.gd -- --peer=1
##   godot --headless --path . --script res://tools/dedicated_test.gd -- --peer=2
##
## `server/test_dedicated.ps1` does all three and reads the results.
##
## What would go wrong if this stopped passing, in the order it usually breaks:
## the server spawning a character for itself (three bodies, not two), the server
## pausing behind its own shop (nothing moves anywhere), or the guards thinking
## on a client as well as on the server (two AIs fighting over one patrol).

## Defaults to a server on this machine, because that is the common case. Point
## it at the real box with --host= to prove the whole path end to end - which
## tests two things a local run cannot: the VCN ingress rule and the instance's
## own firewall.
var _host := "127.0.0.1"
var _port := 27778
## How many characters should end up in the world. Two clients is the usual run;
## --expect=4 fills the server, which is the case that finds a shortage of spawn
## points or a MAX_PLAYERS off-by-one.
var _expect := 2

var _tag := "CLIENT"
var _net: Node
var _main: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_tag = "CLIENT%s" % arg.get_slice("=", 1)
		elif arg.begins_with("--host="):
			_host = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--expect="):
			_expect = int(arg.get_slice("=", 1))
	_run()


func _run() -> void:
	_net = root.get_node("Net")
	# No MultiplayerAPI until the tree has ticked; a peer attached before then is
	# quietly attached to nothing.
	await physics_frame

	var err: int = _net.join(_host, _port)
	_say("dialling %s:%d -> %s" % [_host, _port, "ok" if err == OK else "FAILED"])
	if err != OK:
		quit(1)
		return
	var waited := 0
	while not _net.in_session and waited < 600:
		await physics_frame
		waited += 1
	if not _net.in_session:
		_say("FAILED: never connected - is the server up?")
		quit(1)
		return
	_say("connected as peer %d" % _net.peer_id())

	# Level second, exactly as the lobby does it: the character is asked for from
	# the level's own _ready, once there is somewhere to put one.
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	# Two clients, two characters - and no third one for the server. A server that
	# spawned itself a body would show up right here as a count of three.
	# Generous, because a networked session is a match now: nobody deploys until
	# the roster is full enough and the countdown has run out.
	waited = 0
	while _net.player_count() < _expect and waited < 1500:
		await physics_frame
		waited += 1
	_say("%d character(s) in the world after %.1fs" % [_net.player_count(), waited / 60.0])
	if _net.player_count() != _expect:
		_say("FAILED: expected exactly %d characters, got %d" % [_expect, _net.player_count()])
		quit(1)
		return

	# Past the shop and the briefing, or this client's own tree stays paused.
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
	if mine == null:
		_say("FAILED: no local character")
		quit(1)
		return
	var theirs: Node2D = null
	for body in _net.players():
		if body != mine:
			theirs = body
	_say("mine=%s (local=%s)  theirs=%s (local=%s)" % [
		mine.name, mine.is_local(), theirs.name, theirs.is_local()])

	# Walk, and watch the other client's body walk. Opposite directions so each
	# side has something to see.
	#
	# Their movement is the furthest they got at any point, not where they are at
	# the end, and the watching outruns the walking. Two processes started
	# seconds apart do not share a clock: whoever went first can be standing
	# still again by the time the other one looks, and a single reading at the
	# end then says the replication is broken when it is working perfectly.
	var input: Node = root.get_node("PlayerInput")
	var my_start: Vector2 = mine.global_position
	var their_start: Vector2 = theirs.global_position
	var they_moved := 0.0
	var i_moved := 0.0
	# Both directions in turn, and the furthest either of us got. Players come in
	# at opposite ends of the map now, and one of those ends has a wall
	# immediately to the right of it - a single direction reads as "movement does
	# not replicate" when what actually happened is that somebody walked into a
	# shipping container.
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
	_say("I walked %.0f px; the other client moved %.0f px on my screen" % [i_moved, they_moved])

	# The server is the brain. Nothing here should be thinking for a guard, and
	# the guards should still be moving - which is the proof that the server is
	# running its world rather than sitting paused behind a shop nobody can see.
	var guards: Node = _main.get_node("Enemies")
	var thinking := 0
	for g in guards.get_children():
		if g.is_brain():
			thinking += 1
	# Sampled over five seconds and counting anyone who moved at any point in it,
	# not a snapshot at each end. A guard that has just been alerted stops dead
	# and listens, and a squad that all did that at once - which is exactly what
	# two clients walking past them causes - looked identical to a server frozen
	# behind a shop screen.
	var guard_start := PackedVector2Array()
	for g in guards.get_children():
		guard_start.append((g as Node2D).global_position)
	var stirred := {}
	for i in 300:
		await physics_frame
		for j in guards.get_child_count():
			if (guards.get_child(j) as Node2D).global_position.distance_to(guard_start[j]) > 1.0:
				stirred[j] = true
	var guards_moved := stirred.size()
	# A match has no guards in it at the moment - see Enemy._ready, where they
	# free themselves in any networked session and stay put when you are playing
	# alone. So "none of them moved" here is the level doing as it was told
	# rather than the server sitting paused, and the check is that the level is
	# empty rather than that it is patrolling.
	#
	# Written as a question about the session rather than about a constant, so
	# the day guards come back to matches this starts demanding they move instead
	# of quietly passing on an empty node.
	var patrolling := guards.get_child_count() > 0
	var want := guards_moved > 0 if patrolling else true
	_say("guards: %d thinking here (want 0), %d of %d moving (%s)" % [
		thinking, guards_moved, guards.get_child_count(),
		"want some" if patrolling else "none in a match, as expected"])

	var ok := i_moved > 20.0 and they_moved > 20.0 and thinking == 0 and want
	_say("PASS" if ok else "FAIL")
	await _wait(20)
	quit(0 if ok else 1)


func _say(text: String) -> void:
	print("%s | %s" % [_tag, text])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
