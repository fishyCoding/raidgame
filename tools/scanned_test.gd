extends SceneTree

## Being seen, from the far end. Both ways of finding out: a recon arrow, and a
## Headcount.
##
##   godot --headless --path . -- --server=27785
##   godot --headless --path . --script res://tools/scanned_test.gd -- --peer=1 --port=27785
##   godot --headless --path . --script res://tools/scanned_test.gd -- --peer=2 --port=27785
##
## `server/test_scanned.ps1` does both.
##
## Client 1 does the looking, client 2 is looked at. The reveal itself is one
## machine's business in both cases - the watcher is the only one whose screen
## changes - which is exactly why the warning has to travel: without it the only
## thing the person being watched ever learns is that they have been shot.
##
## The two warnings ride down one rpc with a flag between them (see
## Net.tell_scanned), so the thing most worth asserting here is that they do not
## bleed into each other: a headcount must never raise the arrow's banner, and
## the man running the headcount must not appear in his own count.

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27785
var _first := false
var _net: Node
var _main: Node
var _ok := true
## Set by the signal, which is the whole point: nothing polls for this.
var _was_scanned := false
## Same again for the quieter of the two. Kept apart from _was_scanned on
## purpose - telling them apart is most of what this file is for.
var _was_counted := false


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

	# The signals are what the HUD listens to, so they are what this listens to.
	mine.scanned.connect(func() -> void: _was_scanned = true)
	mine.counted.connect(func() -> void: _was_counted = true)
	_check("not scanned before anybody shoots", not _was_scanned)
	_check("and not counted either", not _was_counted)

	# --- the headcount -------------------------------------------------------
	#
	# First, so the arrow below lands on a clean slate: the point of this half is
	# that being counted leaves _was_scanned alone, and that is only worth
	# checking while nothing has scanned anybody yet.
	if _first:
		var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
		var ult: Object = maker.from_gadget(
			load("res://resources/gadgets/headcount.tres"))
		ult.charge = 1.0
		# The second slot, so whatever the menu staged in the first is left alone.
		mine.inventory.fit_default_power()
		mine.inventory.set_ultimate(ult, 1)
		mine._use_ultimate(1)
		# Widened after the cast. Two players insert at opposite ends of the map
		# and the gap between them is a property of the level rather than of this
		# gadget - a test that failed because the spawns are far apart would be
		# measuring the wrong thing.
		mine.count_reach = 100000.0
		_say("counting heads for %.1fs across %.0fpx" % [
			mine.count_left, mine.count_reach])
		_check("the cast started a count", mine.count_left > 0.0)
		_check("and they are in it", mine.headcount_contacts().has(theirs))

	# Two ticks' worth of taps, and then some. See Player.COUNT_PING.
	await _wait(90)

	_say("counted=%s scanned=%s" % [_was_counted, _was_scanned])
	if _first:
		_check("I am not in my own count", not _was_counted)
	else:
		_check("I was told somebody is counting me", _was_counted)
	_check("and a headcount is not an arrow - no banner", not _was_scanned)

	# The two clients are launched seconds apart and never resynchronise, so the
	# shooter reaches every checkpoint first and the gap between them is not a
	# fixed number - it is however long each took to connect and be given a body.
	# Both sides of the arrow below therefore need slack, and the failures look
	# nothing like the cause:
	#
	# - too little here and the arrow lands while the target is still on its way
	#   to the assertion above, so the banner fails a check about the headcount.
	#   It reads as the two messages having bled into each other.
	# - too much, and the target has finished the whole run and disconnected
	#   before the arrow is planted. That one reads as `global_position on a
	#   previously freed object`, which sounds like a lifetime bug in the game.
	#
	# Four seconds here and ten at the end below, which holds for any stagger
	# under about four seconds. Only the shooter waits here: the target is the
	# one being outrun.
	if _first:
		await _wait(240)

	# --- the arrow -----------------------------------------------------------
	if _first and not is_instance_valid(theirs):
		# Said plainly rather than left to fault on the next line. See the note
		# on the wait above - this is the "too much slack" end of it.
		_check("the target is still in the session to be shot at", false)
	elif _first:
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

	# Long, and deliberately so: it is what keeps the target in the session until
	# the shooter - which may be seconds ahead of it - has actually got round to
	# planting the arrow. See the note above.
	await _wait(600)

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
