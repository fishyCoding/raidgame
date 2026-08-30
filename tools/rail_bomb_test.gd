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

## How far a bomb holding station may wander and still count as parked - it bobs
## up and down on purpose, so "stays where it stopped" cannot mean "does not
## move a pixel".
const HOVER_SLACK := 20.0

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
	# It hangs off the world, not off the cable, so the dark can have it - the
	# rope is deliberately always lit and a bomb inheriting that floodlight
	# could be read across a blacked-out yard through two walls.
	_check("the dark can take it", bomb.is_in_group(&"shadowed"))
	_check("and it is not hung off the always-lit rope",
		not cable.is_ancestor_of(bomb))

	var parked: Vector2 = bomb.global_position
	await _wait(20)
	_check("and it does not move until it is told",
		bomb.global_position.distance_to(parked) < 1.0)
	# The rope says so from the moment it is clamped on, not from the moment it
	# starts moving - a bomb sitting still on a cable is exactly as bad to grab.
	_check("the rope has gone yellow", bool(cable._bombed))

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
	#
	# A third of a second, not three quarters. At 600 px/s a longer window puts
	# the bomb off the top of most ropes in the level and turns a speed check
	# into a clamp check.
	var from := bomb.global_position
	var span := 20
	await _wait(span)
	var seconds := float(span) / 60.0
	var climbed: float = from.y - bomb.global_position.y
	var want: float = gadget.travel_speed * seconds
	_say("climbed %.0f px in %.2fs (want about %.0f)" % [climbed, seconds, want])
	_check("it goes up the rope", climbed > 40.0)
	# A quarter, not a fixed number of pixels: the first frame or two are spent
	# on the launch edge, and that lag is a fraction of the speed rather than a
	# constant, so a tolerance in pixels is tight at one speed and meaningless
	# at another.
	_check("at about the speed it is meant to", absf(climbed - want) < want * 0.25)

	# --- and takes a bite out of somebody on the rope ------------------------
	var victim := _stub_rider(level, bomb.global_position + Vector2(0.0, -60.0))
	net._players[4242] = victim
	await _wait(40)
	_say("a rider it went past took %.0f (%.1f jolts of %.0f)"
		% [victim.taken, victim.taken / gadget.damage, gadget.damage])
	_check("a rider it passes gets hit", victim.taken > 0.0)
	_check("a whole jolt, not a slice of one", victim.taken >= gadget.damage)

	# Out of its reach entirely: no jolts, and no reason to break off either.
	victim.taken = 0.0
	victim.global_position = bomb.global_position + Vector2(gadget.sight_range + 600.0, 0.0)
	await _wait(20)
	_check("and leaves alone somebody it cannot reach", victim.taken == 0.0)
	net._players.erase(4242)
	victim.queue_free()

	# --- and the rope tick is the fast one -----------------------------------
	#
	# A fresh bomb low on the rope, because by now the last one is at the top and
	# holding station, and the two phases tick at deliberately different rates -
	# measuring the wrong one was how the first draft of this check quietly
	# passed for the wrong reason.
	ult.charge = 1.0
	player.arc_stop = 0.0
	player.global_position = cable.world_bottom() + Vector2(0.0, -20.0)
	await physics_frame
	player._use_ultimate(0)
	await _wait(3)
	bomb = get_first_node_in_group(&"rail_bomb")
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	await physics_frame

	# Pinned to it, so the fly-past becomes a stay and what is measured is the
	# interval rather than how long the pass lasts. Made a rider and held in
	# strike range from the first frame, which is also what keeps it out of the
	# "somebody worth stopping for" branch.
	var clung := _stub_rider(level, bomb.global_position)
	net._players[4245] = clung
	var held := 24
	var still_climbing := true
	for i in held:
		clung.global_position = bomb.global_position
		await physics_frame
		if bool(bomb.hovering):
			still_climbing = false
	var seconds_held := float(held) / 60.0
	var jolts: float = clung.taken / gadget.damage
	_say("held against it for %.2fs on the rope: %.0f damage, %.1f jolts"
		% [seconds_held, clung.taken, jolts])
	_check("it was still on the rope for that", still_climbing)
	_check("staying on the rope with it ticks fast", jolts >= 3.0)
	# Which is only possible because it goes through the immunity window. A body
	# ignores anything inside invulnerable_time of the last hit, so without
	# Net.relentless this could never beat one jolt per 0.35s however often the
	# bomb asked.
	_check("faster than the immunity window would allow on its own",
		jolts > seconds_held / _player_iframes(player))
	net._players.erase(4245)
	clung.queue_free()

	# --- it gets off early if it sees somebody -------------------------------
	#
	# A man standing off the rope, in the open, well inside its reach. The bomb
	# is still climbing and has no business with him - until it looks up.
	ult.charge = 1.0
	player.arc_stop = 0.0
	player.global_position = cable.world_bottom() + Vector2(0.0, -20.0)
	await physics_frame
	player._use_ultimate(0)
	await _wait(3)
	bomb = get_first_node_in_group(&"rail_bomb")
	var seen_early := _stub_rider(level,
		cable.world_bottom() + Vector2(120.0, -260.0))
	seen_early.set(&"riding", false)
	net._players[4244] = seen_early
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	await _wait(30)
	_say("stopped at %.2f of the way up, %.0f px short of the top"
		% [bomb.along, cable.world_top().distance_to(bomb.global_position)])
	_check("it broke off before the top", bomb.along < 0.9)
	_check("and let go of the rope", bool(bomb.hovering))
	_check("the stop was written down", player.arc_stop > 0.0)
	_check("and the rope is not yellow any more", not bool(cable._bombed))
	# Frozen there. Every other machine reads that number rather than deciding
	# for itself, and the number has to stop moving for that to be worth
	# anything.
	var stopped_at: Vector2 = bomb.global_position
	var stop_reading: float = player.arc_stop
	await _wait(30)
	_check("and it stays where it stopped",
		bomb.global_position.distance_to(stopped_at) < HOVER_SLACK)
	_check("without the stopping point drifting",
		is_equal_approx(player.arc_stop, stop_reading))
	_check("shooting the man it stopped for", seen_early.taken > 0.0)
	net._players.erase(4244)
	seen_early.queue_free()

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
	_check("and the last bomb's stopping point went with it",
		is_zero_approx(player.arc_stop))
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
	# And the rope is a rope again. The danger has left it and is now a thing in
	# the air saying so on its own account; a cable still flying a hazard colour
	# under it would be warning about something that is no longer there.
	_check("the rope is not yellow any more", not bool(cable._bombed))

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
	_check("and no yellow left behind on the rope", not bool(cable._bombed))


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## A body's immunity window, in seconds. Read off the body rather than typed,
## because the claim being made about the rope tick is a claim relative to it.
func _player_iframes(body: Node2D) -> float:
	var window: float = body.get(&"invulnerable_time")
	return maxf(window, 0.001)


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
