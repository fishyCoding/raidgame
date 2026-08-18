extends SceneTree

## The whole way in, from the menu: kit out, press one button, and end up
## standing in a raid holding what you bought.
##
##   godot --headless --path . -- --server=27783
##   godot --headless --path . --script res://tools/queue_test.gd -- --peer=1 --port=27783
##   godot --headless --path . --script res://tools/queue_test.gd -- --peer=2 --port=27783
##
## `server/test_queue.ps1` does all three.
##
## Driven through lobby.tscn rather than by calling Net.join, because the menu is
## what changed and the thing worth checking is that there is exactly one way
## through it. A kit bought a scene earlier than the body it goes on is the part
## that can quietly go missing: nothing errors if it does, you simply deploy with
## the starting pistol and a receipt for a rifle.

## The rifle, in the shop's primary catalogue. Bought through the shop's own
## code path so this fails if buying breaks, not only if carrying it over does.
const KIT_PRIMARY := 1

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27783
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

	# --- the menu ------------------------------------------------------------
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _wait(10)

	var shop: Node = lobby._shop
	_check("the menu is the kit screen", shop != null and shop.visible)
	if shop == null:
		_finish()
		return
	_check("and the button queues", shop.deploy_label == "JOIN MATCHMAKING")

	# Nothing to host with and nowhere to type an address. Checked by walking the
	# scene rather than by reading the script, because "the button is gone" and
	# "the button is off screen" are the same thing to a player and different
	# things to a grep.
	var typed := 0
	var buttons: Array[String] = []
	for node in _controls(lobby):
		if node is LineEdit:
			typed += 1
		var button := node as Button
		if button:
			buttons.append(button.text.to_lower())
	_say("buttons: %s   text fields: %d" % [" / ".join(buttons), typed])
	_check("no address to type", typed == 0)
	_check("nothing offers to host", not buttons.has("host a session"))
	_check("and nothing offers to join an address", not buttons.has("join"))

	# --- kitting out, before anyone has queued -------------------------------
	shop._open = {"kind": "slot", "id": "primary", "list": "primary", "label": "PRIMARY"}
	shop._buy(shop.CATALOGUE["primary"][KIT_PRIMARY])
	await physics_frame
	var bought: Item = lobby._kit.primary
	_check("bought a primary in the menu", bought != null)
	_say("kitted out with: %s" % (bought.label() if bought else "nothing"))

	# --- and queuing ---------------------------------------------------------
	#
	# Pointed at the test server rather than the live one. Everything else is the
	# button doing what the button does.
	lobby._address = _host
	lobby._port = _port
	shop.deployed.emit()
	# Read here rather than after the handshake: the level is loaded the moment
	# the connection lands and the first thing it does is take the kit off Net,
	# so a check any later is racing the thing it is checking.
	_check("the kit was parked for the level", _net.staged_kit != null)

	var waited := 0
	while not _net.in_session and waited < 900:
		await physics_frame
		waited += 1
	_check("the button put me in a session", _net.in_session)
	_check("and not as a host", not _net.is_host)
	if not _net.in_session:
		_finish()
		return

	# The level comes up on its own now: the lobby watches for the handshake and
	# changes scene.
	waited = 0
	while (current_scene == null or current_scene.name != "Main") and waited < 900:
		await physics_frame
		waited += 1
	_check("the level loaded itself", current_scene != null and current_scene.name == "Main")
	if current_scene == null or current_scene.name != "Main":
		_finish()
		return

	# --- waiting for somebody, with no shop over it --------------------------
	await _wait(30)
	var level_shop: Node = current_scene.get_node_or_null("HUD/Shop")
	_check("no second kit screen in the level", level_shop == null or not level_shop.visible)
	_check("and the tree is not paused behind one", not paused)
	if _first and _net.match_state != _net.Match.LIVE:
		_check("nobody deploys alone", _net.local_player == null)

	# --- the countdown, then a body ------------------------------------------
	var saw_countdown := false
	waited = 0
	while _net.match_state != _net.Match.LIVE and waited < 1800:
		if _net.match_state == _net.Match.COUNTDOWN:
			saw_countdown = true
		await physics_frame
		waited += 1
	_check("saw a countdown", saw_countdown)
	_check("match went live", _net.match_state == _net.Match.LIVE)

	waited = 0
	while _net.local_player == null and waited < 900:
		await physics_frame
		waited += 1
	var mine: Node2D = _net.local_player
	_check("I have a character", mine != null)
	if mine == null:
		_finish()
		return

	await _wait(60)
	# The whole point of kitting out a scene early.
	var carrying: Item = mine.inventory.primary if mine.inventory else null
	_say("deployed carrying: %s" % (carrying.label() if carrying else "nothing"))
	_check("the rifle I bought in the menu came in with me", carrying != null)
	if carrying and bought:
		_check("and it is the one I bought", carrying.title() == bought.title())
	# Handed over rather than left lying about: a kit still parked on Net is a
	# kit the next raid would be issued for free.
	_check("nothing is left staged", _net.staged_kit == null)

	_finish()


func _controls(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is Control:
		found.append(node)
	for child in node.get_children():
		found.append_array(_controls(child))
	return found


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
