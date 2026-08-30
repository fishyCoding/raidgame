extends SceneTree

## Does a live rail cross the wire, and does it bite the moment you are on it?
##
## Two clients against a real server:
##
##   godot --headless --path . -- --server=27781
##   godot --headless --path . --script res://tools/rail_net_test.gd -- --peer=1 --port=27781
##   godot --headless --path . --script res://tools/rail_net_test.gd -- --peer=2 --port=27781
##
## `server/test_rail.ps1` does all three.
##
## The solo test covers casting it - the reach rule, the charge, the damage
## maths. What only two machines can answer is whether the *other* one ever
## hears about it, which is the part that has no rpc behind it and therefore the
## part most likely to be quietly doing nothing.
##
## Peer 1 lights a cable. Peer 2 looks at peer 1's replica, then at the cable,
## then rides it. Nothing here names Zipline or Player - both reach Net, and a
## --script tool compiles before the autoloads exist.

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27781
var _first := false
var _net: Node
var _main: Node
var _ok := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_tag = "RAIL%s" % arg.get_slice("=", 1)
			_first = arg.ends_with("1")
		elif arg.begins_with("--host="):
			_host = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
	_run()


func _say(text: String) -> void:
	print("%s | %s" % [_tag, text])


func _check(what: String, passed: bool) -> void:
	_say("%-42s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _run() -> void:
	await process_frame
	_net = root.get_node("Net")

	if _net.join(_host, _port) != OK:
		_say("FAILED: could not dial %s:%d" % [_host, _port])
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
	waited = 0
	while not _net.level_settled() and waited < 600:
		await physics_frame
		waited += 1

	_main = (load(_net.match_level) as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	# Both in, both deployed.
	waited = 0
	while _net.match_state != _net.Match.LIVE and waited < 3000:
		await physics_frame
		waited += 1
	_check("match went live", _net.match_state == _net.Match.LIVE)
	await _wait(60)

	var mine: Node2D = _net.local_player
	var theirs: Node2D = _other_player(mine)
	_check("both bodies exist", mine != null and theirs != null)
	if mine == null or theirs == null:
		_finish()
		return

	# Everyone stands on the same cable, so that one rope is the subject of
	# every check below. Chosen by name rather than by nearest, or the two
	# machines could pick different ones and agree about nothing.
	var cable: Node2D = _pick_cable()
	_check("found the test cable", cable != null)
	if cable == null:
		_finish()
		return
	var midpoint: Vector2 = (cable.world_top() + cable.world_bottom()) * 0.5

	# --- peer 1 lights it ----------------------------------------------------
	if _first:
		mine.global_position = midpoint
		await _wait(10)
		mine.arc_at = midpoint
		mine.arc_left = 9.0
		_say("lit the cable at %s" % str(midpoint))
	await _wait(90)

	# --- peer 2 checks it arrived --------------------------------------------
	if not _first:
		_check("their arc_left crossed the wire", float(theirs.get(&"arc_left")) > 0.0)
		_check("their arc_at crossed the wire",
			(theirs.get(&"arc_at") as Vector2).distance_to(midpoint) < 40.0)
		_check("and this machine calls the cable live", cable._current_through_me() != 0)
		_check("powered by them, not by nobody",
			cable._current_through_me() == theirs.get_multiplayer_authority())

		# --- and that being on it costs, straight away -----------------------
		#
		# Both halves of the ride state, not just the flag. `riding` alone is
		# what a body looks like for one frame before its own update notices
		# there is no cable under it and turns it off again - which is a fine
		# way to write a test that proves nothing.
		var before: float = mine.health
		mine.global_position = midpoint
		mine.zipline = cable
		mine.riding = true

		# Six frames, not one. The host decides you were hit and tells your own
		# machine so (Net.tell_owner_hit), and that is a round trip - health
		# cannot fall here on the same frame it is worked out there. What is
		# being checked is that the first jolt lands on contact rather than
		# waiting out an interval, so the window is as small as the wire allows.
		await _wait(6)
		var after_first: float = mine.health
		_check("first jolt lands on contact", after_first < before)

		# Long enough for two more at 0.4s apart, and the reason this is
		# measured rather than assumed: spread thinly across frames instead,
		# nearly all of it is eaten by the 0.35s of immunity a body gets after
		# any hit, and the rail quietly does about a fiftieth of its damage.
		await _wait(50)
		var dealt: float = before - mine.health
		_say("health %.0f -> %.0f after ~0.93s on it (dealt %.0f)"
			% [before, mine.health, dealt])
		_check("it keeps jolting while you stay on", mine.health < after_first)
		_check("three jolts in, not one", dealt > 60.0)
		mine.riding = false
		mine.zipline = null

	await _wait(60)
	_finish()


## The other player's body, whichever peer this is.
func _other_player(mine: Node2D) -> Node2D:
	for body in _net.players():
		if body != mine and is_instance_valid(body):
			return body
	return null


## One cable both machines will agree on. By name, from the group, so it is the
## same rope on both - and skipping any that is too short to ride.
func _pick_cable() -> Node2D:
	var found: Array[Node2D] = []
	for node in get_nodes_in_group(&"zipline"):
		var line := node as Node2D
		if line != null and line.cable_length() > 300.0:
			found.append(line)
	if found.is_empty():
		return null
	found.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return found[0]


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
