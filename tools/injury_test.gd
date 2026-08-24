extends SceneTree

## Wounds, the surgical kit that closes them, and the plates gating the vest.
##
##   godot --headless --path . --script res://tools/injury_test.gd
##
## Four things, all of which are easy to get wrong in ways that only show up in
## a real fight:
##
##   - a hit you survive leaves a wound, and a wound bleeds you
##   - the bleed stops at the floor instead of killing you
##   - a surgical kit closes every wound; a medkit closes none
##   - plates down means no vest, so the same round costs twice as much
##
## Solo, so the shop and briefing gates have to be cleared first or the tree
## stays paused and nothing takes a physics frame. See headless-test-must-unpause.

var _main: Node
var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	var shop: Node = _main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	# Duck-typed rather than named: Player reaches Net, and naming the class from
	# a --script tool compiles it before the autoloads exist.
	var net: Node = root.get_node("Net")
	var player: Node = net.local_player
	if player == null:
		_fail("no local player")
		return _finish()

	# --- a survivable hit leaves a wound ------------------------------------
	player.armored = true
	player.shield = 1.0
	await physics_frame
	_check("plates up counts as shielded", player.is_shielded())

	var before: float = player.health
	player.take_damage(30.0, player.global_position, Vector2.RIGHT)
	await physics_frame
	_check("a solid hit wounds you", player.injuries == 1)
	_check("and costs health", player.health < before)

	# --- wounds bleed, and the bleed has a floor ----------------------------
	var bleeding_from: float = player.health
	await _wait(30)
	_check("a wound bleeds you", player.health < bleeding_from)

	player.health = player.injury_floor_health
	await _wait(30)
	_check("the bleed stops at the floor rather than killing you",
		is_equal_approx(player.health, player.injury_floor_health))
	_check("and you are still standing", not player.is_downed)

	# --- a medkit does not close wounds -------------------------------------
	#
	# Into a bought pack, not into grids()[0]. The pockets come first in that
	# list and a pocket is one cell, so a 2x1 medkit and a 2x2 surgical kit both
	# fail to place there - silently, because place() returns false rather than
	# complaining, and the test then reads as the items doing nothing.
	var bag: BackpackData = load("res://resources/backpacks/assault_pack.tres")
	player.inventory.set_backpack(Item.from_backpack(bag))
	var pack: ItemGrid = player.inventory.backpack
	_check("the medkit fits in the pack",
		pack.place(Item.from_medkit(3), Vector2i.ZERO))
	player._use_medkit()
	await physics_frame
	_check("a medkit puts health back", player.health > player.injury_floor_health)
	_check("but leaves the wound open", player.injuries == 1)

	# --- a surgical kit closes them all -------------------------------------
	player.injuries = 3
	var kit := Item.from_surgical(2)
	_check("the surgical kit fits in the pack", pack.place(kit, Vector2i(0, 2)))
	player._use_surgical()
	await physics_frame
	_check("a surgical kit closes every wound at once", player.injuries == 0)
	_check("and spends one use", kit.count == 1)

	player._use_surgical()
	await physics_frame
	_check("with nothing to treat it refuses rather than spending a use",
		kit.count == 1)

	# --- plates gate the vest -----------------------------------------------
	var vest: ArmorData = load("res://resources/armor/medium_vest.tres")
	player.inventory.set_worn(Inventory.Wear.VEST, Item.from_armor(vest))
	player.injuries = 0
	player.health = player.max_health
	player.armored = true
	player.shield = 1.0
	player._invulnerable = 0.0
	await physics_frame
	var plated_from: float = player.health
	player.take_damage(51.0, player.global_position, Vector2.RIGHT)
	await physics_frame
	var plated_cost: float = plated_from - player.health

	player.injuries = 0
	player.health = player.max_health
	player.armored = false
	player.shield = 0.0
	player._invulnerable = 0.0
	await physics_frame
	var bare_from: float = player.health
	player.take_damage(51.0, player.global_position, Vector2.RIGHT)
	await physics_frame
	var bare_cost: float = bare_from - player.health

	print("  a rifle round costs %.1f plated, %.1f caught out" % [plated_cost, bare_cost])
	_check("plates up, the vest takes its half", absf(plated_cost - 26.0) < 0.5)
	_check("plates down, the round lands whole", absf(bare_cost - 51.0) < 0.5)
	_check("so being caught out costs about double", bare_cost > plated_cost * 1.8)

	_finish()


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(what: String, ok: bool) -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	_failures.append(what)
	print("  FAIL %s" % what)


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("OK - injuries, surgical kits and plates all behave")
	else:
		print("FAILED %d check(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
