extends SceneTree

## A long drop gives you away to the people near it, and only to them.
##
##   godot --headless --path . -- --server=27787
##   godot --headless --path . --script res://tools/fall_net_test.gd -- --peer=1 --port=27787
##   godot --headless --path . --script res://tools/fall_net_test.gd -- --peer=2 --port=27787
##
## `server/test_fall.ps1` does all three.
##
## Client 1 keeps landing hard in one spot. Client 2 stands well out of earshot
## for the first half and walks into it for the second, and the only thing that
## is allowed to change is whether they can see client 1 through the walls.
##
## The two halves are long and the pings repeated on purpose: the clients start
## a couple of seconds apart, so the windows have to overlap generously rather
## than line up on a frame.

const FAR_PHASE := 260
const NEAR_PHASE := 260
## Landed on rather than fallen from: the arc of a drop is not what is being
## tested, and the reveal is driven by the same call a real landing makes.
const SPOT := Vector2(-600.0, 300.0)

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27787
var _first := false
var _net: Node
var _main: Node
var _ok := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_first = arg.ends_with("1")
			_tag = "FALLER  " if _first else "LISTENER"
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

	# Both machines start their clocks from the moment the second character
	# arrives, which is the same moment on both - so the halves line up without
	# anything being sent to line them up.
	var mine: Node2D = _net.local_player
	var theirs: Node2D = null
	waited = 0
	while theirs == null and waited < 1800:
		for body in _net.players():
			if body != mine:
				theirs = body
		await physics_frame
		waited += 1
	if theirs == null:
		_say("FAILED: nobody else here")
		_finish()
		return

	var vision: Node = get_first_node_in_group(&"vision_system")
	var radius: float = mine.fall_ping_radius
	var drop: float = mine.fall_ping_height + 300.0
	_say("radius %.0f px, drop %.0f px, spot %.0f,%.0f" % [radius, drop, SPOT.x, SPOT.y])

	# --- out of earshot ------------------------------------------------------
	var far := SPOT + Vector2(radius * 1.9, 0.0)
	var lit_when_far := false
	for frame in FAR_PHASE:
		if _first:
			mine.global_position = SPOT
			mine.velocity = Vector2.ZERO
			if frame % 30 == 0:
				_net.fall_heard(SPOT, drop)
		else:
			mine.global_position = far
			mine.velocity = Vector2.ZERO
			if frame > 80 and vision.is_revealed(theirs):
				lit_when_far = true
		await physics_frame

	# --- and then within it --------------------------------------------------
	var near := SPOT + Vector2(radius * 0.45, 0.0)
	var lit_when_near := false
	for frame in NEAR_PHASE:
		if _first:
			mine.global_position = SPOT
			mine.velocity = Vector2.ZERO
			if frame % 30 == 0:
				_net.fall_heard(SPOT, drop)
		else:
			mine.global_position = near
			mine.velocity = Vector2.ZERO
			if frame > 100 and vision.is_revealed(theirs):
				lit_when_near = true
		await physics_frame

	if _first:
		_say("I landed hard %d times" % (FAR_PHASE / 30 + NEAR_PHASE / 30))
		# You cannot hear yourself land into a reveal: you already know where
		# you are, and lighting yourself up would blind you to nothing useful.
		_check("my own landings never lit me up",
			float(mine.get_meta(&"revealed_until", 0.0)) <= 0.0)
		_check("and never lit them up either", not vision.is_revealed(theirs))
	else:
		_say("%.0f px away: lit=%s   then %.0f px away: lit=%s" % [
			far.distance_to(SPOT), lit_when_far, near.distance_to(SPOT), lit_when_near])
		_check("out of earshot I never saw them", not lit_when_far)
		_check("in earshot the landing gave them away", lit_when_near)

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
