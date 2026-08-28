extends SceneTree

## The glint has to cross the wire, not just the room.
##
##   godot --headless --path . -- --server=27786
##   godot --headless --path . --script res://tools/glint_net_test.gd -- --peer=1 --port=27786
##   godot --headless --path . --script res://tools/glint_net_test.gd -- --peer=2 --port=27786
##
## `server/test_glint.ps1` does all three.
##
## Client 1 puts a sniper up and looks down it; client 2 watches the copy of him
## on its own machine. What is being defended is that `scoped` is a replicated
## property and not a local one - it is worked out on the machine holding the
## rifle, from a weapon and a focus value that nothing else replicates, so if it
## did not travel the mark would simply never appear on the machine that needs
## it and would look perfect in single player forever.
##
## Both directions are checked. A bit that is stuck true replicates just as
## badly as one that is stuck false, and only the falling edge tells you the
## scope coming *down* also reaches the other end.

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27786
var _sniper := false
var _net: Node
var _main: Node
var _ok := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_sniper = arg.ends_with("1")
			_tag = "SNIPER " if _sniper else "WATCHER"
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

	_check("nobody is scoped to start with", not theirs.scoped)

	# --- up ------------------------------------------------------------------
	if _sniper:
		mine.inventory.set_slot(Inventory.Slot.PRIMARY,
			Item.from_weapon(load("res://resources/weapons/sniper.tres")))
		mine.weapon.equip(Inventory.Slot.PRIMARY, true)
		await _wait(10)
		_check("I am holding the sniper",
			mine.weapon.data != null and mine.weapon.data.scope_glint)
		# The real door, not a poke at the variable: focus is walked up by
		# _update_focus from the aim action, and scoped is set from focus.
		Input.action_press(&"aim")
		_say("aiming down the scope")

	await _wait(180)

	if _sniper:
		_check("my own scoped bit is up", mine.scoped)
	else:
		_check("the scope reached me over the wire", theirs.scoped)
		_say("their focus is not replicated, only the bit: scoped=%s" % theirs.scoped)

	# --- and down ------------------------------------------------------------
	if _sniper:
		Input.action_release(&"aim")
		_say("scope down")

	await _wait(180)

	if _sniper:
		_check("my own scoped bit is down again", not mine.scoped)
	else:
		_check("and the scope coming down reached me too", not theirs.scoped)

	_finish()


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("%s | %s" % [_tag, text])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	await _wait(30)
	quit(0 if _ok else 1)
