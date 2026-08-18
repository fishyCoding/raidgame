extends SceneTree

## A recon arrow paints somebody, and that somebody has to find out.
##
##   godot --headless --path . -- --server=27785
##   godot --headless --path . --script res://tools/scanned_test.gd -- --peer=1 --port=27785
##   godot --headless --path . --script res://tools/scanned_test.gd -- --peer=2 --port=27785
##
## `server/test_scanned.ps1` does both.
##
## Client 1 looses the arrow, client 2 stands in it. The reveal itself is one
## machine's business - the shooter is the one who gets to see through walls -
## which is exactly why the warning has to travel: without it the only thing the
## person being watched ever learns is that they have been shot.

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27785
var _first := false
var _net: Node
var _main: Node
var _ok := true
## Set by the signal, which is the whole point: nothing polls for this.
var _was_scanned := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_tag = "SHOOTER" if arg.ends_with("1") else "TARGET "
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

	# The signal is what the HUD listens to, so it is what this listens to.
	mine.scanned.connect(func() -> void: _was_scanned = true)
	_check("not scanned before anybody shoots", not _was_scanned)

	# --- the arrow -----------------------------------------------------------
	if _first:
		# Landed on them rather than fired at them: the bow's arc is not what is
		# being tested, and leading a shot across the map from a headless client
		# would be a test about ballistics.
		var bolt: Node2D = (load("res://scenes/recon_bolt.tscn") as PackedScene).instantiate()
		bolt.setup(load("res://resources/gadgets/recon_bow.tres"), 1.0)
		_main.add_child(bolt)
		bolt.global_position = theirs.global_position
		_say("planting an arrow on them at %.0f,%.0f" % [
			bolt.global_position.x, bolt.global_position.y])
		bolt._land()
		await _wait(10)
		_check("their body is in my hideable set", theirs.is_in_group(&"hideable"))
		var vision: Node = get_first_node_in_group(&"vision_system")
		_check("and my arrow revealed them to me",
			vision != null and vision.is_revealed(theirs))
		# The shooter must not paint themselves - you are never in your own
		# hideable set, and a self-scan would fire the banner every ultimate.
		_check("it did not scan me", not _was_scanned)

	await _wait(240)

	_say("scanned=%s" % _was_scanned)
	if _first:
		_check("still not scanned - it was my arrow", not _was_scanned)
	else:
		_check("I was told I had been scanned", _was_scanned)

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
