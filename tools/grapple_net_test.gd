extends SceneTree

## Two clients against a real server: one of them grapples, and both of them have
## to see it happen.
##
##   godot --headless --path . -- --server=27781
##   godot --headless --path . --script res://tools/grapple_net_test.gd -- --peer=1 --port=27781
##   godot --headless --path . --script res://tools/grapple_net_test.gd -- --peer=2 --port=27781
##
## `server/test_grapple.ps1` does all three.
##
## Client 1 fires the hook; client 2 only watches. What is being tested is the
## three things a hook has to do over a wire: bite, pull the man who fired it,
## and be visible - line, anchor and all - to everybody else.

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
			_tag = "CLIENT%s" % arg.get_slice("=", 1)
			_first = arg.ends_with("1")
		elif arg.begins_with("--host="):
			_host = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
	_run()


func _run() -> void:
	_net = root.get_node("Net")
	await physics_frame

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

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	await _wait(20)
	var shop: Node = _main.get_node_or_null("HUD/Shop")
	if shop:
		shop.deployed.emit()
	await physics_frame
	paused = false

	waited = 0
	while _net.match_state != _net.Match.LIVE and waited < 1800:
		await physics_frame
		waited += 1
	_check("match went live", _net.match_state == _net.Match.LIVE)

	waited = 0
	while _net.player_count() < 2 and waited < 900:
		await physics_frame
		waited += 1
	_check("two characters", _net.player_count() == 2)
	if _net.player_count() < 2:
		_finish()
		return

	await _wait(30)
	if shop:
		shop.visible = false
	var mine: Node2D = _net.local_player
	var theirs: Node2D = null
	for body in _net.players():
		if body != mine:
			theirs = body
	if mine == null or theirs == null:
		_say("FAILED: missing a body after deploy")
		_finish()
		return

	# --- one of us grapples --------------------------------------------------
	var their_start: Vector2 = theirs.global_position
	var my_start: Vector2 = mine.global_position

	if _first:
		var aim := _something_to_bite(mine)
		_say("aiming %s from %s" % [aim, my_start])
		_check("found a surface to hook", aim != Vector2.ZERO)
		mine.aim_angle = aim.angle()
		mine.aim_direction = aim
		# Straight at the seam, the same way match_test fires rounds through Net:
		# everything above this is the input stack single player already exercises.
		mine._fire_grapple()

	# Both sides watch for a hook and for movement, for three seconds.
	var saw_hook := false
	var saw_anchor := false
	var anchored_locally := false
	var anchor := Vector2.INF
	var i_moved := 0.0
	var they_moved := 0.0
	for i in 180:
		await physics_frame
		for node in _hooks(_main):
			saw_hook = true
			if node.is_anchored():
				saw_anchor = true
				anchor = node.global_position
		if mine.is_grappling():
			anchored_locally = true
		i_moved = maxf(i_moved, my_start.distance_to(mine.global_position))
		they_moved = maxf(they_moved, their_start.distance_to(theirs.global_position))

	_say("hook seen=%s anchored=%s | I moved %.0f px, they moved %.0f px" % [
		saw_hook, saw_anchor, i_moved, they_moved])
	# Compared across the two logs by the runner: this is the one thing neither
	# client can check, and the reason the anchor is sent rather than agreed by
	# two raycasts that are half a frame apart.
	_say("anchor %.1f,%.1f" % [anchor.x, anchor.y])

	if _first:
		_check("my hook bit something", anchored_locally)
		_check("and it pulled me", i_moved > 60.0)
	else:
		_check("I can see their hook", saw_hook)
		_check("and it is anchored here too", saw_anchor)
		_check("and they were pulled by it", they_moved > 60.0)

	# --- and the line comes off everywhere -----------------------------------
	#
	# A hook that replicates on the way out and not on the way back leaves a rope
	# hanging in mid-air on every screen but the one that let go of it.
	if _first:
		mine._let_go_of_grapple(true)
	await _wait(90)
	var left_over := _hooks(_main).size()
	_say("hooks still in the level after the release: %d" % left_over)
	_check("the line came off here too", left_over == 0)

	_finish()


## Every hook anywhere in the level. Walked rather than fetched from a known
## parent, so the test does not have to agree with Net about where they live.
func _hooks(node: Node) -> Array:
	var found: Array = []
	if node is GrappleHook:
		found.append(node)
	for child in node.get_children():
		found.append_array(_hooks(child))
	return found


func _something_to_bite(from: Node2D) -> Vector2:
	## A direction with solid geometry in hook range down it. Cast around rather
	## than named, because where a player deploys is the server's decision.
	var space := from.get_world_2d().direct_space_state
	var best := Vector2.ZERO
	var best_range := 0.0
	for step in 32:
		var dir := Vector2.RIGHT.rotated(TAU * step / 32.0)
		var q := PhysicsRayQueryParameters2D.create(
			from.global_position, from.global_position + dir * 800.0)
		q.collision_mask = Layers.WORLD
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var reach: float = from.global_position.distance_to(hit.position)
		# Far enough that being reeled in is a visible distance, not a nudge.
		if reach > best_range and reach > 200.0:
			best_range = reach
			best = dir
	return best


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("%s | %s" % [_tag, text])


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	await _wait(30)
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
