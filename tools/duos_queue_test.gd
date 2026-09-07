extends SceneTree

## A duos queuer must not deploy alone - not even once the server has been up
## long enough that a solo queuer in the same spot already would have.
##
## Reported after the first pass at duos: readiness only checked the total
## number of waiting peers, so a lone duos queuer sat at a countdown that was
## really counting down for somebody else's solo queue and then got deployed
## by it, with no teammate at all. Net.request_character/_begin_match/
## _advance_match now gate on Net._is_ready (has a teammate, or never asked
## for one) rather than on raw headcount - see net.gd.
##
##   godot --headless --path . -- --server=27784
##   godot --headless --path . --script res://tools/duos_queue_test.gd -- --peer=1 --port=27784
##   godot --headless --path . --script res://tools/duos_queue_test.gd -- --peer=2 --port=27784
##
## server/test_duos_queue.ps1 does all three, starting peer 2 late enough
## that peer 1 has already sat through what would have been a solo countdown.

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27784
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

	var err: int = _net.join(_host, _port)
	if err != OK:
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

	# Level second, the way the lobby does it - request_character fires from
	# Screens._start_session once this is up, carrying Net.wants_duos.
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await physics_frame

	if _first:
		# Long enough that test_queue.ps1's plain solo case is already live by
		# now (its countdown alone is 10s) - a duos queuer sitting here alone
		# must still be exactly nowhere.
		await _wait(900)
		_check("no teammate yet", _net.teammate(_net.peer_id()) == 0)
		_check("still no character", _net.local_player == null)
		_check("never went live alone", _net.match_state != _net.Match.LIVE)

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
