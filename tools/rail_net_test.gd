extends SceneTree

## Does a rail bomb cross the wire, and does it bite a man on the rope?
##
## Two clients against a real server:
##
##   godot --headless --path . -- --server=27781
##   godot --headless --path . --script res://tools/rail_net_test.gd -- --peer=1 --port=27781
##   godot --headless --path . --script res://tools/rail_net_test.gd -- --peer=2 --port=27781
##
## `server/test_rail.ps1` does all three.
##
## The solo test covers clamping one on and following it up - the reach rule,
## the charge, the climb, the hover, the damage maths. What only two machines
## can answer is whether the *other* one ever builds a bomb at all, which is the
## part that has no rpc behind it and therefore the part most likely to be
## quietly doing nothing.
##
## Peer 1 clamps one on and points it up. Peer 2 looks at peer 1's replica, then
## at its own copy of the bomb, then gets on the rope in front of it. Nothing
## here names Zipline or Player - both reach Net, and a --script tool compiles
## before the autoloads exist.

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

	# --- peer 1 clamps one on and points it up -------------------------------
	#
	# Set rather than pressed. Which key sends it is the solo test's business;
	# what this one is asking is whether the numbers reach the other machine and
	# turn into a bomb there.
	if _first:
		mine.global_position = midpoint
		await _wait(10)
		mine.arc_at = midpoint
		mine.arc_from = 0.5
		mine.arc_left = 12.0
		mine.arc_launch = 12.0
		mine.arc_way = 1
		_say("clamped one on at %s and sent it up" % str(midpoint))
	await _wait(90)

	# --- peer 2 checks it arrived --------------------------------------------
	if not _first:
		_check("their arc_left crossed the wire", float(theirs.get(&"arc_left")) > 0.0)
		_check("their arc_at crossed the wire",
			(theirs.get(&"arc_at") as Vector2).distance_to(midpoint) < 40.0)
		_check("and which way they sent it", int(theirs.get(&"arc_way")) == 1)
		# The bomb itself, built on this machine off those numbers alone.
		var bombs: Array = get_nodes_in_group(&"rail_bomb")
		_check("this machine built the bomb", bombs.size() == 1)
		if not bombs.is_empty():
			var bomb: Node2D = bombs[0]
			var off: float = cable.closest_point(bomb.global_position).distance_to(
				bomb.global_position)
			_say("their bomb is %.0f px off the rope on my screen" % off)
			_check("and put it on the right rope", off < 60.0)

		# --- and that standing in front of it costs --------------------------
		#
		# Put on the rope just above where the bomb has got to, so it climbs
		# into me. Not at the midpoint: the thing has been travelling for a
		# second and a half by now and is nowhere near where it was clamped,
		# which is the whole difference between this gadget and the one it
		# replaced.
		#
		# Both halves of the ride state, not just the flag. `riding` alone is
		# what a body looks like for one frame before its own update notices
		# there is no cable under it and turns it off again - which is a fine
		# way to write a test that proves nothing.
		var before: float = mine.health
		var meet := midpoint
		if not bombs.is_empty():
			meet = (bombs[0] as Node2D).global_position + Vector2(0.0, -40.0)
		mine.global_position = cable.clamp_to_cable(meet)
		mine.zipline = cable
		mine.riding = true

		# Long enough for it to cover those forty pixels and a little more. The
		# host decides you were hit and tells your own machine so
		# (Net.tell_owner_hit), and that is a round trip - health cannot fall
		# here on the same frame it is worked out there.
		await _wait(40)
		var dealt: float = before - mine.health
		var phase := "on the rope"
		if not bombs.is_empty() and bool((bombs[0] as Node2D).get(&"hovering")):
			# Short cables exist and this one may already have run out of rope
			# by now. Which phase it caught me in is not the claim being made -
			# that their bomb reached this machine and cost me health is - but
			# saying which one keeps the number below readable.
			phase = "holding station"
		_say("health %.0f -> %.0f with it %s (dealt %.0f)"
			% [before, mine.health, phase, dealt])
		_check("somebody else's bomb hurts me here", mine.health < before)
		# One whole jolt at least, not a per-frame slice of one - which is what
		# a body's 0.35s of immunity turns thin damage into, silently.
		_check("a whole jolt, not a sliver", dealt >= 20.0)
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
