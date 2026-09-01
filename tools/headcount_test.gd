extends SceneTree

## The Headcount ultimate: how many people are near you, and roughly which way.
##
##   godot --headless --path . --script res://tools/headcount_test.gd
##
## Solo, with stand-ins for the other players. The gadget's whole job is to
## separate people from everything else that moves - guards, ghosts, corpses -
## so most of what is asserted here is what it refuses to count, not what it
## counts. The bearings are checked through the HUD's own dial rather than by
## re-deriving them, because a compass that agrees with itself proves nothing.

const HEADCOUNT := "res://resources/gadgets/headcount.tres"

var _ok := true
## Kept alive for the length of the run: a stand-in with no parent is freed the
## moment the last reference to it goes.
var _stand_ins: Array[Node2D] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame
	# Two gates, not one: the shop pauses the tree and the briefing keeps it
	# paused. Hiding the shop goes last, or the deferred call that opens it
	# undoes this. See the note in tools/dash_test.gd.
	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("no character - cannot run")
		quit(1)
		return
	var hud: Node = main.get_node("HUD/WeaponHUD")
	var guards: Node = main.get_node("Enemies")
	for guard in guards.get_children():
		guard.set_physics_process(false)
		guard.set_process(false)

	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var ult: Object = maker.from_gadget(load(HEADCOUNT))
	ult.charge = 1.0
	player.inventory.set_ultimate(ult)
	# Let him land first. Every offset below is measured from where he is
	# standing, and a character still falling out of his spawn moves several
	# pixels a frame - enough to swing a bearing into the next wedge, which is
	# what this failed on first time round.
	var waited := 0
	while not player.is_on_floor() and waited < 240:
		await physics_frame
		waited += 1

	# Three people and a corpse. East is the sector-0 case and straight up is the
	# one worth saying out loud, because screen y is down - so up is 6 of the
	# eight, not 2, and that is the kind of thing that is quietly wrong for
	# months.
	var east := _stand_in(2, Vector2(320.0, 0.0))
	var north := _stand_in(3, Vector2(0.0, -520.0))
	var far := _stand_in(4, Vector2(9000.0, 0.0))
	var corpse := _stand_in(5, Vector2(-260.0, 0.0), false)
	var roster: Dictionary = net._players
	for body in _stand_ins:
		roster[int(body.get_meta(&"peer"))] = body
	_anchor(player)
	# A guard right on top of him. The whole point of the gadget is that this
	# does not move the number.
	if guards.get_child_count() > 0:
		guards.get_child(0).global_position = player.global_position + Vector2(60.0, 0.0)

	# --- casting it ----------------------------------------------------------
	player._use_ultimate()
	await physics_frame
	print("-- cast: %.1fs left, reach %.0fpx, charge %.2f" % [
		player.count_left, player.count_reach, ult.charge])
	_check(is_equal_approx(snappedf(player.count_left, 0.5), 15.0),
		"it runs for fifteen seconds")
	_check(player.count_reach > 4000.0, "and hears several screens out, not one")
	_check(ult.charge < 1.0, "and the cast spends the meter")

	# --- who is in it --------------------------------------------------------
	var heard: Array = player.headcount_contacts()
	print("-- heard %d: %s" % [heard.size(),
		", ".join(heard.map(func(b): return str(b.name)))])
	_check(heard.size() == 2, "two live players in reach, and only those two")
	_check(heard.has(east) and heard.has(north), "the near two are both in it")
	_check(not heard.has(far), "somebody 9000px away is not 'in the vicinity'")
	_check(not heard.has(corpse), "and the dead are not counted")
	var counted_a_guard := false
	for body in heard:
		if body.get_parent() == guards:
			counted_a_guard = true
	_check(not counted_a_guard and guards.get_child_count() > 0,
		"a guard standing on your foot does not move the number")

	# --- which way they are --------------------------------------------------
	#
	# Re-anchored on the frame the dial is read. He is on the floor by now but
	# still settling by a pixel or two, and a bearing is measured from wherever
	# he actually is.
	_anchor(player)
	var lit: Array = hud.count_sectors()
	print("-- dial lit sectors: %s of 8 (0 is east, 6 is straight up)" % [lit])
	_check(lit.size() == 2, "one wedge each, not one for every guard on the map")
	_check(lit.has(0), "the man due east lights the east wedge")
	_check(lit.has(6), "the man straight up lights the wedge above")

	# Vague on purpose, and this is where that is worth pinning down: a wedge is
	# forty-five degrees, so a man well off due east still reads as east. An
	# instrument sharp enough to separate these two is one you could shoot along.
	east.set_meta(&"offset", Vector2(900.0, -300.0))
	_anchor(player)
	_check(hud.count_sectors().has(0),
		"and eighteen degrees off east is still just 'east'")
	east.set_meta(&"offset", Vector2(320.0, 0.0))
	_anchor(player)

	# It is a bearing and not a position: twice as far away is the same wedge.
	east.set_meta(&"offset", Vector2(1100.0, 0.0))
	_anchor(player)
	_check(hud.count_sectors().has(0), "and distance does not change the bearing")
	east.set_meta(&"offset", Vector2(320.0, 0.0))
	_anchor(player)

	# --- the clock -----------------------------------------------------------
	var was: float = player.count_left
	for i in 30:
		await physics_frame
	print("-- half a second on: %.2fs left (was %.2fs)" % [player.count_left, was])
	_check(player.count_left < was, "the clock runs down")
	_check(hud._ult_running(ult) > 0.0, "and the tile shows it running")

	# --- and what the other end gets -----------------------------------------
	#
	# Driven through the signal rather than by poking the HUD, because the whole
	# chain that matters on the far machine is rpc -> mark_counted -> signal ->
	# a mark on the glass, and only the last two links are reachable from here.
	_check(hud._watched_left <= 0.0, "nothing on your own screen until you are in one")
	player.mark_counted()
	await process_frame
	print("-- after being counted: mark at %.2fs" % hud._watched_left)
	_check(hud._watched_left > 0.0, "being counted puts a mark on your screen")
	_check(hud._watched_left > 0.5, "that outlasts the gap between taps")

	for body in _stand_ins:
		roster.erase(int(body.get_meta(&"peer")))
		body.free()
	print("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


## A body for the roster. Not a real character - Net.players() is a dictionary of
## whatever has been registered, and the count only ever asks a member where it
## is and whether it is alive.
func _stand_in(peer: int, offset: Vector2, alive := true) -> Node2D:
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar is_alive := %s\n" % ("true" if alive else "false")
	script.reload()
	var body := Node2D.new()
	body.set_script(script)
	body.name = "StandIn%d" % peer
	body.set_meta(&"peer", peer)
	body.set_meta(&"offset", offset)
	_stand_ins.append(body)
	return body


## Puts every stand-in back where it is meant to be relative to the character,
## as of right now. Called immediately before anything that reads a bearing.
func _anchor(player: Node2D) -> void:
	for body in _stand_ins:
		body.global_position = player.global_position + body.get_meta(&"offset")


func _check(pass_: bool, says: String) -> void:
	print("   %s  %s" % ["ok  " if pass_ else "FAIL", says])
	if not pass_:
		_ok = false
