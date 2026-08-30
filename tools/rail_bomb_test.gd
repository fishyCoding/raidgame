extends SceneTree

## The Rail Bomb, and the sight check on a cable's amber warning.
##
##   godot --headless --path . --script res://tools/live_rail_test.gd
##
## Two halves, because they are two features that happen to live in the same
## file. The first builds a bare scene with one cable and one wall in it and
## asks the cable what it can see - no player, no session, nothing to go wrong.
## The second opens the world for real and casts the thing.
##
## Nothing here names Zipline or Player. Both reach Net, and a --script tool is
## compiled before the autoloads are registered as script globals, so naming one
## compiles its file too early and leaves the *class* broken for the whole
## process - which reads as the level being empty rather than as a compile
## error. Loaded by path and duck-typed instead. See the memory note on it.

const BOMB := "res://resources/gadgets/rail_bomb.tres"

var _ok := true


func _initialize() -> void:
	_run()


func _say(text: String) -> void:
	print("rail | %s" % text)


func _check(what: String, passed: bool) -> void:
	_say("%-42s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _run() -> void:
	await process_frame
	await _sight_half()
	await _bomb_half()
	print("")
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


# --- half one: can the cable see you --------------------------------------

func _sight_half() -> void:
	_say("-- the warning needs line of sight --")
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	var cable: Node2D = (load("res://scenes/zipline.tscn") as PackedScene).instantiate()
	cable.position = Vector2.ZERO
	world.add_child(cable)
	cable.set(&"top", Vector2(0.0, -300.0))
	cable.set(&"bottom", Vector2.ZERO)

	# A wall between x=-400 and the cable, and nothing between x=+400 and it.
	var wall: Node2D = (load("res://scenes/platform.tscn") as PackedScene).instantiate()
	world.add_child(wall)
	wall.position = Vector2(-200.0, -150.0)
	wall.set(&"size", Vector2(600.0, 24.0))
	wall.rotation = PI * 0.5
	await physics_frame
	await physics_frame

	_check("clear side can see the cable", cable._in_sight_of(Vector2(400.0, -150.0)))
	_check("walled side cannot", not cable._in_sight_of(Vector2(-400.0, -150.0)))
	# Standing on the cable itself is always sight of it, whatever is around.
	_check("on the cable counts as seeing it", cable._in_sight_of(Vector2(0.0, -150.0)))

	# And the warning itself, which is the thing the sight check is guarding.
	# Close enough to be in WARN_RANGE of an end, on both sides.
	_check("in range but walled off is not 'at an end'",
		not cable._at_an_end(_marker(world, Vector2(-400.0, -20.0))))
	_check("in range with a view is",
		cable._at_an_end(_marker(world, Vector2(400.0, -20.0))))

	world.queue_free()
	await physics_frame


func _marker(parent: Node, at: Vector2) -> Node2D:
	var node := Node2D.new()
	node.position = at
	parent.add_child(node)
	return node




# --- half two: clamping one on and following it up ------------------------

func _bomb_half() -> void:
	_say("")
	_say("-- a bomb on a rope --")
	var net: Node = root.get_node("Net")
	net.solo_level = 0
	var level: Node = (load(net.solo_scene()) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for i in 6:
		await physics_frame

	# Past the shop and the briefing, both of which pause the tree.
	var shop: Node = level.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	var player: Node2D = net.local_player
	_check("there is a character", player != null)
	if player == null:
		return
	net._players[net.peer_id()] = player

	var gadget: Resource = load(BOMB)
	player.inventory.set_ultimate(Item.from_gadget(gadget))
	var ult = player.inventory.get_ultimate(0)
	ult.charge = 1.0

	# The longest rope in the level, so there is room to watch one climb.
	var cable: Node2D = null
	var longest := 0.0
	for node in get_nodes_in_group(&"zipline"):
		var line := node as Node2D
		if line != null and line.cable_length() > longest:
			longest = line.cable_length()
			cable = line
	_check("the level has a cable", cable != null)
	if cable == null:
		return
	_say("cable is %.0f px long" % longest)

	# --- nowhere near one: the press has to cost nothing ---------------------
	player.global_position = Vector2(0.0, -20000.0)
	await physics_frame
	player._use_ultimate(0)
	_check("no cable in reach: nothing happens", player.arc_left <= 0.0)
	_check("no cable in reach: charge kept", ult.charge >= 1.0)

	# --- clamped on, waiting to be told --------------------------------------
	player.global_position = cable.world_bottom() + Vector2(0.0, -20.0)
	await physics_frame
	player._use_ultimate(0)
	_check("it clamps on", player.arc_left > 0.0)
	_check("charge spent", ult.charge < 1.0)
	_check("onto that cable", cable.closest_point(player.arc_at).distance_to(player.arc_at) <= 24.0)
	_check("near the bottom, where I was standing", player.arc_from < 0.2)
	_check("and it is waiting for orders", player.arc_way == 0)

	# The cable builds its own copy the moment the numbers exist. Nothing was
	# sent to make that happen - see RailBomb.
	await _wait(3)
	var bomb: Node2D = get_first_node_in_group(&"rail_bomb")
	_check("the cable has built the bomb", bomb != null)
	if bomb == null:
		return
	var parked: Vector2 = bomb.global_position
	await _wait(20)
	_check("and it does not move until it is told",
		bomb.global_position.distance_to(parked) < 1.0)

	# --- pointed up ----------------------------------------------------------
	#
	# Through the real key, not by setting the field: W is also the jump key and
	# the whole reason the order is read before _update_jump is that it must not
	# do both. A test that set arc_way by hand would never notice it hopping.
	var was_y: float = player.global_position.y
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	await _wait(4)
	_check("W sends it up", player.arc_way == 1)
	_check("and the launch time was recorded", player.arc_launch > 0.0)
	_check("and it did not also jump me into the air",
		absf(player.global_position.y - was_y) < 24.0)

	# --- it climbs -----------------------------------------------------------
	var from := bomb.global_position
	await _wait(45)
	var climbed: float = from.y - bomb.global_position.y
	_say("climbed %.0f px in 0.75s (want about %.0f)"
		% [climbed, gadget.travel_speed * 0.75])
	_check("it goes up the rope", climbed > 60.0)
	_check("at about the speed it is meant to",
		absf(climbed - gadget.travel_speed * 0.75) < 60.0)

	# --- and takes a bite out of somebody on the rope ------------------------
	var victim := _stub_rider(level, bomb.global_position + Vector2(0.0, -60.0))
	net._players[4242] = victim
	await _wait(40)
	_say("the rider took %.0f" % victim.taken)
	_check("a rider it passes gets hit", victim.taken > 0.0)
	_check("a whole jolt, not a slice of one",
		is_equal_approx(victim.taken, gadget.damage)
		or victim.taken >= gadget.damage)
	# Off the rope is out of it. The bomb does not chase people who are not on
	# the cable with it.
	victim.set(&"riding", false)
	victim.taken = 0.0
	await _wait(30)
	_check("somebody not on the rope is left alone", victim.taken == 0.0)
	net._players.erase(4242)
	victim.queue_free()

	# --- to the top, and then it holds station -------------------------------
	#
	# Wound forward by re-clamping near the top rather than waited out: the rest
	# of the climb is the same arithmetic already checked above, and four
	# seconds of headless frames proves none of it twice.
	ult.charge = 1.0
	player.global_position = cable.world_top() + Vector2(0.0, 30.0)
	await physics_frame
	player._use_ultimate(0)
	_check("clamped on near the top", player.arc_from > 0.8)
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	await _wait(60)
	bomb = get_first_node_in_group(&"rail_bomb")
	_check("still one bomb, not two", get_nodes_in_group(&"rail_bomb").size() == 1)
	_check("it ran out of rope and let go", bool(bomb.hovering))
	var above: float = cable.world_top().y - bomb.global_position.y
	_say("holding station %.0f px above the top of the cable" % above)
	_check("hovering above the end of it", above > 20.0)

	# --- and shoots what it can see ------------------------------------------
	var seen := _stub_rider(level, bomb.global_position + Vector2(80.0, 40.0))
	seen.set(&"riding", false)
	net._players[4243] = seen
	await _wait(30)
	_say("the man underneath it took %.0f" % seen.taken)
	_check("it shoots somebody standing under it", seen.taken > 0.0)
	_check("rider or not", not bool(seen.get(&"riding")))

	# Out of range is out of it.
	seen.taken = 0.0
	seen.global_position = bomb.global_position + Vector2(gadget.sight_range + 400.0, 0.0)
	await _wait(30)
	_check("and not somebody out of its reach", seen.taken == 0.0)
	net._players.erase(4243)
	seen.queue_free()

	# --- the cell runs flat --------------------------------------------------
	player.arc_left = 0.0
	await _wait(4)
	_check("a flat cell is no bomb anywhere",
		get_nodes_in_group(&"rail_bomb").is_empty())


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## A body that can be on a rope and remembers being hurt, and nothing else.
## Written out here rather than kept as a scene because what it has to be is
## exactly the handful of properties RailBomb reads off a player, plus one
## method.
func _stub_rider(parent: Node, at: Vector2) -> Node2D:
	var script := GDScript.new()
	script.source_code = """
extends Node2D
var riding := true
var is_alive := true
var arc_at := Vector2.ZERO
var arc_left := 0.0
var arc_from := 0.0
var arc_way := 0
var arc_launch := 0.0
var taken := 0.0
func take_damage(amount: float, _at: Vector2, _dir: Vector2) -> void:
	taken += amount
"""
	script.reload()
	var body := Node2D.new()
	body.set_script(script)
	body.name = "StubRider"
	parent.add_child(body)
	body.global_position = at
	body.set_multiplayer_authority(4242)
	return body
