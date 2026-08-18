extends SceneTree

## Two clients against a real server: one of them dies, and what they were
## carrying has to be lying on the floor of both machines.
##
##   godot --headless --path . -- --server=27782
##   godot --headless --path . --script res://tools/death_loot_test.gd -- --peer=1 --port=27782
##   godot --headless --path . --script res://tools/death_loot_test.gd -- --peer=2 --port=27782
##
## `server/test_death_loot.ps1` does all three.
##
## Client 2 dies; client 1 only watches. Kitting out costs money and everything
## carried can be lost, which only means anything if it is lost *to somebody* -
## a player who died with a full pack and left nothing behind made shooting them
## worth nothing at all.
##
## The dying is done to its own body rather than by the other client's rifle, on
## purpose: a player's death is resolved on their own machine either way (the
## server says you were hit, your body decides what that did to it), so this is
## the same path with the aim taken out of it.

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27782
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

	_check("the floor is clear to start with", get_nodes_in_group(&"lootable").is_empty())

	# --- one of us dies with something worth taking --------------------------
	var died_at := Vector2.ZERO
	if not _first:
		# Something on the body that no default kit would put there, so a body
		# built out of "what a player starts with" cannot pass this by accident.
		# A pocket is one cell, so it has to be something that fits in one - a
		# medkit is 2x1 and is refused, silently, which is exactly the kind of
		# pass-by-accident this item is here to stop.
		var stim := Item.from_revive(4)
		var stowed := false
		for pocket in mine.inventory.pockets:
			if pocket.add(stim):
				stowed = true
				break
		_check("stowed something distinctive", stowed)
		mine.inventory.changed.emit()
		await _wait(10)
		var carried := _kit_of(mine.inventory)
		died_at = mine.global_position
		_say("dying at %.0f,%.0f carrying: %s" % [died_at.x, died_at.y, carried])
		_check("I had something to lose", not mine.inventory.is_empty())

		# Down first, then finished off - the two halves of dying, both of which
		# have to end in the same body.
		for i in 20:
			if not mine.is_alive:
				break
			mine._invulnerable = 0.0
			mine.take_damage(90.0, mine.global_position, Vector2.RIGHT)
			await _wait(4)
		_check("I am dead", not mine.is_alive)
		_check("and not carrying it any more", mine.inventory.is_empty())

	# --- and left it on the floor --------------------------------------------
	waited = 0
	while _player_body() == null and waited < 600:
		await physics_frame
		waited += 1
	var body := _player_body()
	_check("a player's body is on the floor", body != null)
	if body == null:
		_finish()
		return

	_check("with the kit still on it", body.has_loot())
	_check("and it reads as a player, not a guard", body.tag == "player")
	_check("the prompt says so too", body.get_prompt() == "player")
	if not _first:
		_check("laid where I fell", body.global_position.distance_to(died_at) < 80.0)

	# Printed for the runner: the one check neither client can make is that the
	# two of them are looking at the same kit. Item labels rather than names,
	# because a list of names would match two machines that each rolled the same
	# starting pistol - see match_test._bodies.
	_say("dropped %s[%s]" % [body.name, _kit_of(body.inventory)])

	# --- and it can be gone through the ordinary way -------------------------
	#
	# A player's body is a Lootable like any other, so the whole search protocol
	# should already work on it. The survivor is the one who gets to prove it.
	if _first:
		mine.global_position = body.global_position + Vector2(0.0, -24.0)
		await _wait(10)
		mine._begin_search(body)
		await _wait(120)
		_check("I could go through it", mine._searching != null)
		if mine._searching != null:
			var took := body.loot_into(mine.inventory)
			mine._close_screen()
			await _wait(120)
			_say("took %d item(s) off them" % took.size())
			_check("and took something off it", not took.is_empty())

	await _wait(180)
	_say("left on the body %s" % _kit_of(body.inventory))
	_finish()


## The body a player left, as opposed to any guard's. There are no guards dying
## in this test, but keying on the tag rather than on "the only one there" is
## what the tag is for.
func _player_body() -> Lootable:
	for node in get_nodes_in_group(&"lootable"):
		var body := node as Lootable
		if body and body.tag == "player":
			return body
	return null


func _kit_of(kit: Inventory) -> String:
	if kit == null:
		return "-"
	var what: Array[String] = []
	for item in kit.all_items():
		what.append(item.label())
	what.sort()
	return ", ".join(what)


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
