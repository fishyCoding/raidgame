extends SceneTree

## Three clients against a real server, for the two things that only go wrong
## when somebody is not there for the whole raid.
##
##   godot --headless --path . -- --server=27781
##   godot --headless --path . --script res://tools/latecomer_test.gd -- --role=killer   --port=27781
##   godot --headless --path . --script res://tools/latecomer_test.gd -- --role=watcher  --port=27781
##   godot --headless --path . --script res://tools/latecomer_test.gd -- --role=latecomer --port=27781
##
## `server/test_latecomer.ps1` does all four, with the latecomer started half a
## minute late so that everything it is meant to be told about has already
## happened.
##
## **The body that fell before you got here.** A corpse is put down by an RPC at
## the moment somebody dies, so a peer still on the menu when the shooting
## started was told about none of them. It drops into a raid where a guard has
## been killed and searched, and the floor says nothing happened. The latecomer
## here never fires a shot and never sees anybody die; everything it knows about
## that body it was told on arrival.
##
## **The search nobody finished.** The killer goes through the body, moves what
## fits onto itself, and then pulls the cable out with the screen still open. The
## kit is on its machine, which has left. If the body it was holding reverts to
## what the host last heard - the full kit, from before it knelt down - then
## everything it walked off with is also still lying on the floor for the next
## person, which in a game about carrying things out is the only bug that counts.
## So the watcher's copy of that body has to match what the killer left, not what
## the guard died with.

var _role := "watcher"
var _host := "127.0.0.1"
var _port := 27781
var _net: Node
var _main: Node
var _ok := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.get_slice("=", 1)
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

	if _role == "latecomer":
		await _late()
	elif _role == "killer":
		await _kill_and_vanish()
	else:
		await _watch()
	_finish()


# --- the one who was not here for it ------------------------------------------


## Joins a raid already under way and checks the floor.
##
## The assertion is deliberately about a body it had no part in: it did not fire
## the shot, it was not in the session when the guard fell, and it did not search
## him. If anything is on this machine's floor at all, it was sent.
func _late() -> void:
	# Dropping into a live match spawns a character straight away - there is no
	# countdown left to wait out.
	var got := await _wait_for(func() -> bool: return _net.local_player != null, 900)
	_check("dropped into the raid", got)
	# The bodies come with request_character, which is the same message that asked
	# for the character above, so by now they are either here or they are not.
	await _wait(60)

	var bodies := get_nodes_in_group(&"lootable").size()
	_say("found %d bodies on arrival" % bodies)
	_check("the raid I joined has a history", bodies > 0)
	_say("bodies %s" % _bodies())


# --- the one who leaves in the middle of it -----------------------------------


func _kill_and_vanish() -> void:
	var mine := await _deployed()
	if mine == null:
		return

	var guard: Node2D = _nearest_guard(mine.global_position)
	if guard == null:
		_say("FAILED: no guard to shoot")
		_ok = false
		return

	var weapon: Node = mine.weapon
	# From arm's length, for the same reason match_test does: a test that misses
	# because of weapon range says nothing about what it is testing.
	var muzzle: Vector2 = guard.global_position - Vector2(80.0, 0.0)
	var angle := (guard.global_position - muzzle).angle()
	_say("shooting %s from %.0f px" % [guard.name,
		muzzle.distance_to(guard.global_position)])
	for i in 60:
		if not guard.net_alive:
			break
		_net.fire(muzzle, angle, weapon.data.resource_path, weapon.hit_mask,
			weapon.damage_scale, _net.peer_id())
		await _wait(4)
	_check("the guard died of it", not guard.net_alive)

	var landed := await _wait_for(
		func() -> bool: return not get_nodes_in_group(&"lootable").is_empty(), 900)
	_check("he left a body", landed)
	var body := _first_body()
	if body == null:
		_ok = false
		return
	_say("before %s" % _kit_of(body.inventory))

	# Kneeling over it, which is the only way to search one.
	mine.global_position = body.global_position + Vector2(0.0, -24.0)
	await _wait(10)
	mine._begin_search(body)
	await _wait(120)
	_check("the host let me in", mine._searching == body)
	if mine._searching != body:
		return

	# One thing off him, rather than everything with loot_into. A body emptied
	# completely is the easy half of this: what has to survive the disconnect is
	# the *partial* state, one item short of what he died with, which no machine
	# but this one has ever seen.
	var took: Item = null
	for item in body.inventory.all_items():
		if not item.is_ammo():
			took = item
			break
	_check("there is something to take", took != null)
	if took == null:
		return
	body.inventory.remove_item(took)
	_check("and room to put it", mine.inventory.store(took))
	_say("took %s" % took.label())

	# Long enough for the running commentary to reach the host - it is flushed
	# from the player's own frame loop, not from the signal. Everything after this
	# is about what the host was told before the connection went.
	await _wait(30)
	_say("left %s" % _kit_of(body.inventory))

	# And out, with the body still open. Closed properly it would be handed back
	# through done_searching, which is the path that already worked.
	_say("pulling the cable with the body still open")
	_net.leave("pulled the cable")
	await _wait(60)


# --- the one who stays --------------------------------------------------------


## Here to make the match two players, and to still be standing at the end so
## that somebody can be asked what the body looks like now.
func _watch() -> void:
	var mine := await _deployed()
	if mine == null:
		return
	# Past the killer's departure and past the latecomer's arrival, so the line
	# printed below can be compared with both.
	await _wait(2700)
	_check("still here", _net.in_session)
	_say("bodies %s" % _bodies())


# --- shared -------------------------------------------------------------------


func _deployed() -> Node2D:
	var live := await _wait_for(
		func() -> bool: return _net.match_state == _net.Match.LIVE, 3600)
	_check("match went live", live)
	var got := await _wait_for(func() -> bool: return _net.local_player != null, 900)
	_check("I have a character", got)
	if not got:
		_ok = false
	return _net.local_player


## Every body on the floor and what is on it, in an order every machine agrees
## on. Item *labels* rather than names - "SMG 17/30", "VEST 62%" - because a list
## of names would match between two machines that disagree about how much of the
## body is left. See match_test._bodies.
func _bodies() -> String:
	var lines: Array[String] = []
	for node in get_nodes_in_group(&"lootable"):
		lines.append("%s[%s]" % [node.name, _kit_of(node.inventory)])
	lines.sort()
	return " ".join(lines)


func _kit_of(kit: Inventory) -> String:
	if kit == null:
		return "-"
	var what: Array[String] = []
	for item in kit.all_items():
		what.append(item.label())
	what.sort()
	return ", ".join(what)


func _first_body() -> Lootable:
	var found: Array[Lootable] = []
	for node in get_nodes_in_group(&"lootable"):
		var body := node as Lootable
		if body:
			found.append(body)
	found.sort_custom(func(a: Lootable, b: Lootable) -> bool: return a.name < b.name)
	return found[0] if not found.is_empty() else null


func _nearest_guard(to: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for g in _main.get_node("Enemies").get_children():
		var body := g as Node2D
		if body == null or not body.net_alive:
			continue
		var d := body.global_position.distance_to(to)
		if d < best_d:
			best_d = d
			best = body
	return best


func _wait_for(test: Callable, frames: int) -> bool:
	for i in frames:
		if test.call():
			return true
		await physics_frame
	return test.call()


func _check(what: String, passed: bool) -> void:
	_say("%-32s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _say(text: String) -> void:
	print("%s | %s" % [_role.to_upper(), text])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
