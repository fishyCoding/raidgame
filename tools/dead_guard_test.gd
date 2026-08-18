extends SceneTree

## A guard killed in a real session has to be dead on every machine in it -
## including the ones that were not looking when it happened.
##
##   godot --headless --path . -- --server=27784
##   godot --headless --path . --script res://tools/dead_guard_test.gd -- --peer=1 --port=27784
##   godot --headless --path . --script res://tools/dead_guard_test.gd -- --peer=2 --port=27784
##   godot --headless --path . --script res://tools/dead_guard_test.gd -- --peer=3 --port=27784
##
## `server/test_dead_guard.ps1` does all four, with the third client started
## late on purpose.
##
## Three roles, because "the other machine" is two different things and they can
## fail separately:
##
##   1 killer     - shoots a guard until the server says he is dead
##   2 watcher    - was in the raid the whole time and never fired
##   3 latecomer  - joined after the shooting, so the news came and went
##
## Each of them prints the set of guards it believes are dead. The runner
## compares the three, which is the only place the bug is visible: every client
## on its own is perfectly consistent about a guard who is standing up.

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27784
var _role := 1
var _net: Node
var _main: Node
var _ok := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_role = int(arg.get_slice("=", 1))
			_tag = ["", "KILLER   ", "WATCHER  ", "LATECOMER"][_role]
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

	# Waiting on a body rather than on the state: a drop-in is deployed the moment
	# it asks, and the two arrive in the same breath.
	waited = 0
	while _net.local_player == null and waited < 3000:
		await physics_frame
		waited += 1
	_check("I have a character", _net.local_player != null)
	_check("and the match says it is live", _net.match_state == _net.Match.LIVE)
	if _net.local_player == null:
		_finish()
		return

	await _wait(30)
	if shop:
		shop.visible = false
	var mine: Node2D = _net.local_player

	# --- one of us kills something -------------------------------------------
	if _role == 1:
		var guard: Node2D = _nearest_guard(mine.global_position)
		if guard == null:
			_say("FAILED: no guard to shoot")
			_finish()
			return
		var weapon: Node = mine.weapon
		# Arm's length, so the starting sidearm's range is not what is on trial.
		var muzzle: Vector2 = guard.global_position - Vector2(80.0, 0.0)
		var angle := (guard.global_position - muzzle).angle()
		_say("shooting %s at %.0f,%.0f" % [guard.name,
			guard.global_position.x, guard.global_position.y])
		for i in 80:
			if not guard.net_alive:
				break
			_net.fire(muzzle, angle, weapon.data.resource_path, weapon.hit_mask,
				weapon.damage_scale, _net.peer_id())
			await _wait(4)
		await _wait(90)
		_check("he died where I shot him", not guard.net_alive)

	# The two who were here have to outlast the one who was not, or they quit,
	# the server empties, and it resets the level out from under the arrival -
	# which reads as the latecomer never being deployed. The latecomer itself
	# only needs long enough to be told everything it is going to be told.
	await _wait(600 if _role == 3 else 2100)

	# --- and everyone has to agree he is gone --------------------------------
	#
	# Printed as sets rather than asserted against a name, because no client but
	# the killer knows which guard it was - and that is the whole problem.
	_say("dead: %s" % _dead_guards())
	_say("standing: %s" % _standing_dead())
	_say("bodies: %d" % get_nodes_in_group(&"lootable").size())

	_check("somebody is dead here", not _dead_guards().is_empty())
	# A guard drawn upright with nothing left in him. This is the reported
	# symptom, from the inside: position keeps arriving (it is replicated every
	# tick) so he is standing exactly where he fell, and the flag that would take
	# him off the map went out once, before this machine was listening.
	_check("no guard is standing there dead", _standing_dead().is_empty())
	# The corpse is put down by an explicit RPC and replayed to latecomers, so it
	# arrives even when the guard's own state does not. Seeing one without the
	# other is the tell.
	_check("there is a body on the floor", not get_nodes_in_group(&"lootable").is_empty())

	_finish()


## The guards, and only the guards.
##
## Enemies holds the corpses too - a body is laid down under the parent of
## whoever it came off - and reading net_alive off a Lootable is a runtime error,
## which in GDScript abandons the function and hands back an empty list. That
## reads exactly like "nobody is dead" and cost a run to spot.
##
## Filtered by method rather than by class on purpose: naming Enemy here would
## compile enemy.gd before the autoloads exist, and its one reference to Net
## would break the class for the whole process. See headless-test-must-unpause.
func _guards() -> Array:
	var found: Array = []
	for node in _main.get_node("Enemies").get_children():
		if node.has_method(&"is_brain"):
			found.append(node)
	return found


## Guards this machine believes are dead, by name, in an order every machine
## agrees on.
func _dead_guards() -> String:
	var names: Array[String] = []
	for guard in _guards():
		if not guard.net_alive:
			names.append(String(guard.name))
	names.sort()
	return " ".join(names)


## Guards still drawn on this machine that have nothing left in them. Should
## never be anybody: dying takes a guard out of the world, and one still standing
## is a guard whose death did not arrive.
func _standing_dead() -> String:
	var names: Array[String] = []
	for guard in _guards():
		if guard.visible and guard.net_health <= 0.0:
			names.append(String(guard.name))
	names.sort()
	return " ".join(names)


func _nearest_guard(to: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for g in _guards():
		var body := g as Node2D
		if body == null or not body.net_alive:
			continue
		var d: float = body.global_position.distance_to(to)
		if d < best_d:
			best_d = d
			best = body
	return best


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
