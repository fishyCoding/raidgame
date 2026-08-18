extends SceneTree

## A gunfight has to sound like one from every seat.
##
##   godot --headless --path . -- --server=27786
##   godot --headless --path . --script res://tools/sound_net_test.gd -- --peer=1 --port=27786
##   godot --headless --path . --script res://tools/sound_net_test.gd -- --peer=2 --port=27786
##
## `server/test_sound.ps1` does all three.
##
## Client 1 shoots; client 2 only listens. The report used to be played by
## weapon.gd, which runs on the machine that pulled the trigger and nowhere else -
## so another player's gun was silent, and on a client so was every guard's. It
## is played from Net._make_bullet now, which is the one place a round exists on
## every machine.

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27786
var _first := false
var _net: Node
var _audio: Node
var _main: Node
var _ok := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_tag = "SHOOTER " if arg.ends_with("1") else "LISTENER"
			_first = arg.ends_with("1")
		elif arg.begins_with("--host="):
			_host = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
	_run()


func _run() -> void:
	_net = root.get_node("Net")
	_audio = root.get_node("Audio")
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
	while _net.local_player == null and waited < 2400:
		await physics_frame
		waited += 1
	_check("I have a character", _net.local_player != null)
	if _net.local_player == null:
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
	if theirs == null:
		_say("FAILED: nobody else here")
		_finish()
		return

	# --- one of us shoots ----------------------------------------------------
	#
	# Fired next to the *listener*, because a report is dropped before it takes a
	# pooled player if it is out of earshot of this machine - and the two of us
	# deploy at opposite ends of the map on purpose.
	var rifle: WeaponData = load("res://resources/weapons/assault_rifle.tres")
	var muzzle: Vector2 = theirs.global_position + Vector2(80.0, 0.0) if _first \
		else Vector2.ZERO

	var before: int = _audio._next
	if _first:
		_say("firing next to them at %.0f,%.0f" % [muzzle.x, muzzle.y])
		_net.fire(muzzle, PI, rifle.resource_path, 0, 1.0, _net.peer_id())
	await _wait(60)

	var heard: int = _audio._next - before
	_say("sounds played here: %d" % heard)
	if _first:
		# Nothing expected here: the shot was fired next to *them*, and the two
		# of us deploy at opposite ends of the map - four thousand pixels apart
		# against a fifteen-hundred-pixel range. A report that is inaudible from
		# where you are standing should be dropped before it takes a pooled
		# player, or a firefight across the level cuts off the one next to you.
		_check("a shot across the map does not reach me", heard == 0)

		# Fired at my own feet this time, which is the other half of the same
		# rule: the range check is a range check, not a mute.
		var here: int = _audio._next
		_net.fire(mine.global_position + Vector2(60.0, 0.0), PI,
			rifle.resource_path, 0, 1.0, _net.peer_id())
		await _wait(30)
		_say("my own shot, next to me: %d" % (_audio._next - here))
		_check("but one at my feet does", _audio._next > here)
	else:
		# The whole point. Nothing on this machine pulled a trigger.
		_check("I hear the other player's shot", heard > 0)
		if heard > 0:
			var last: AudioStreamPlayer2D = _audio._players[before]
			_say("heard at %.0f,%.0f, %.1f dB, pitch %.2f" % [
				last.global_position.x, last.global_position.y,
				last.volume_db, last.pitch_scale])
			_check("from where they fired it",
				last.global_position.distance_to(mine.global_position) < 400.0)
			_check("and it is placed, not centred", last is AudioStreamPlayer2D)

	# --- the rope ------------------------------------------------------------
	#
	# A replica had no idea anyone was on a cable: the sound was driven from
	# _update_zipline, which only runs on the machine doing the riding. `riding`
	# is replicated now, and a rider's velocity is pinned to zero so "are they
	# travelling" comes from the position instead.
	var cable: Node2D = _find_cable(_main)
	_check("the level has a cable", cable != null)
	if cable != null:
		if _first:
			mine.zipline = cable
			mine.riding = true
			mine.global_position = cable.world_bottom()
			await _wait(20)
			Input.action_press(&"jump")
			await _wait(60)
			Input.action_release(&"jump")
			await _wait(10)
			mine._leave_zipline(false)
		else:
			var told := false
			var rope := false
			for i in 110:
				await physics_frame
				if theirs.riding:
					told = true
					if _audio._zip and _audio._zip.playing:
						rope = true
			_say("their riding reached me: %s, rope playing: %s" % [told, rope])
			_check("I am told they are on a cable", told)
			_check("and the rope makes a noise here", rope)
		await _wait(30)

	# --- boots ---------------------------------------------------------------
	#
	# Nobody else's footsteps ever played. Both replica paths gated on
	# is_on_floor(), which move_and_slide sets and a replica never calls - so on
	# the one machine that needed to hear them it was false forever.
	if _first:
		# Walk on the spot for a while so the listener has something to hear.
		var input: Node = root.get_node("PlayerInput")
		input.touch_move_axis = 1.0
		await _wait(90)
		input.touch_move_axis = -1.0
		await _wait(90)
		input.touch_move_axis = 0.0
	else:
		# Counted modulo the pool size: _next is a ring index, and subtracting two
		# raw values across a wrap gives a negative count.
		var pool: int = _audio._players.size()
		var steps := 0
		var seen: int = _audio._next
		# Stand next to them, or their boots are dropped as out of earshot the
		# same way the shot was.
		mine.global_position = theirs.global_position + Vector2(60.0, 0.0)
		for i in 190:
			await physics_frame
			while _audio._next != seen:
				# Only what came from where they are standing. Guards patrol and
				# make noise of their own, and "some sound happened" was weak
				# enough to pass with the bug put back - it counted one stray
				# report and called it a walk.
				var slot: AudioStreamPlayer2D = _audio._players[seen]
				if slot.global_position.distance_to(theirs.global_position) < 150.0:
					steps += 1
				seen = (seen + 1) % pool
		_say("footsteps heard from where they were walking: %d" % steps)
		# A real walk is about ten. One or two is somebody else's boots nearby.
		_check("I hear the other player walking", steps >= 4)
		_check("and their replica thinks it is grounded", theirs._replica_grounded())

	_finish()


## Any cable in the level, found by method rather than class name.
func _find_cable(node: Node) -> Node2D:
	if node.has_method(&"clamp_to_cable"):
		return node as Node2D
	for child in node.get_children():
		var found := _find_cable(child)
		if found:
			return found
	return null


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
