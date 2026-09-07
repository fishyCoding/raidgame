extends SceneTree

## Two duos-paired clients try to hurt each other and fail: a round fired at a
## squadmate does nothing, a frag dropped at their feet does nothing, and the
## squadmate's own body reads differently on screen so there was never any
## doubt who they were aiming at.
##
## Run as two clients against a real dedicated server, the same shape
## tools/duos_queue_test.gd uses to get two peers paired:
##
##   godot --headless --path . -- --server=27786
##   godot --headless --path . --script res://tools/friendly_fire_test.gd -- --peer=1 --port=27786
##   godot --headless --path . --script res://tools/friendly_fire_test.gd -- --peer=2 --port=27786
##
## server/test_friendly_fire.ps1 does all three.
##
## Fired through Net directly, the same seam tools/match_test.gd's _pvp uses to
## prove damage lands between two FFA players - this is that test's mirror
## image, proving it does not land between two teammates.

const FRAG := "res://resources/gadgets/frag.tres"

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27786
var _first := false
var _net: Node
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

	_net.staged_kit = load("res://scripts/weapon.gd").starting_inventory()
	_net.wants_duos = true

	if _net.join(_host, _port) != OK:
		_say("FAILED: could not dial %s:%d" % [_host, _port])
		quit(1)
		return
	var waited := 0
	while not _net.in_session and waited < 600:
		await physics_frame
		waited += 1
	_check("connected", _net.in_session)
	if not _net.in_session:
		_finish()
		return

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await physics_frame

	waited = 0
	while _net.teammate(_net.peer_id()) == 0 and waited < 1800:
		await physics_frame
		waited += 1
	_check("paired with a squadmate", _net.teammate(_net.peer_id()) != 0)

	waited = 0
	while _net.local_player == null and waited < 900:
		await physics_frame
		waited += 1
	_check("deployed once paired", _net.local_player != null)
	if _net.local_player == null:
		_finish()
		return

	waited = 0
	while _net.player_count() < 2 and waited < 900:
		await physics_frame
		waited += 1
	_check("both squadmates on the floor", _net.player_count() == 2)

	var mine: Node2D = _net.local_player
	var theirs: Node2D = null
	for body in _net.players():
		if body != mine:
			theirs = body
	if theirs == null:
		_say("FAILED: no squadmate body")
		_finish()
		return

	# --- the squadmate reads differently on screen ---------------------------
	#
	# Every machine draws its own copy of both bodies, so this is checked from
	# both ends: whichever one is not mine should be tinted, and mine should
	# not be tinted to myself.
	var their_torso := theirs.get_node("Body/Torso") as Polygon2D
	var my_torso := mine.get_node("Body/Torso") as Polygon2D
	_check("squadmate is tinted", their_torso.self_modulate.is_equal_approx(
		load("res://scripts/player.gd").TEAMMATE_TINT))
	_check("I am not tinted to myself", my_torso.self_modulate.is_equal_approx(Color.WHITE))

	# --- a round does nothing -------------------------------------------------
	await _wait(20)
	var start: float = theirs.max_health if _first else mine.max_health

	if _first:
		var weapon: Node = mine.weapon
		for side in [-70.0, 70.0]:
			var muzzle: Vector2 = theirs.global_position + Vector2(side, 0.0)
			var angle := (theirs.global_position - muzzle).angle()
			for i in 3:
				_net.fire(muzzle, angle, weapon.data.resource_path,
					weapon.hit_mask, weapon.damage_scale, _net.peer_id())
				await _wait(30)
		# --- and neither does a frag dropped at their feet --------------------
		_net.throw_gadget(FRAG, theirs.global_position, Vector2.ZERO,
			Layers.PLAYER_SHOT, _net.peer_id())

	await _wait(200 if _first else 800)

	if _first:
		_say("their health %.0f -> %.0f" % [start, theirs.health])
		_check("bullets did nothing to my squadmate", is_equal_approx(theirs.health, start))
	else:
		_say("my health %.0f -> %.0f" % [start, mine.health])
		_check("nothing landed on me from my squadmate", is_equal_approx(mine.health, start))

	_finish()


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
