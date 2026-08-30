extends SceneTree

## The Live Rail ultimate, and the sight check on a cable's amber warning.
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

const RAIL := "res://resources/gadgets/live_rail.tres"

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
	await _cast_half()
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


# --- half two: casting it in the world ------------------------------------

func _cast_half() -> void:
	_say("")
	_say("-- casting a live rail --")
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

	# Kit the rail into ultimate slot 0 and fill the meter by hand.
	var gadget: Resource = load(RAIL)
	player.inventory.set_ultimate(Item.from_gadget(gadget))
	var ult = player.inventory.get_ultimate(0)
	ult.charge = 1.0

	# --- nowhere near a cable: the press has to cost nothing -----------------
	var cables := get_nodes_in_group(&"zipline")
	_check("the level has cables", not cables.is_empty())
	if cables.is_empty():
		return
	player.global_position = Vector2(0.0, -20000.0)
	await physics_frame
	player._use_ultimate(0)
	_check("no cable in reach: nothing happens", player.arc_left <= 0.0)
	_check("no cable in reach: charge kept", ult.charge >= 1.0)

	# --- standing on one: it goes hot ---------------------------------------
	var cable: Node2D = cables[0]
	var midpoint: Vector2 = (cable.world_top() + cable.world_bottom()) * 0.5
	player.global_position = midpoint
	await physics_frame
	player._use_ultimate(0)
	_check("cable in reach: rail is live", player.arc_left > 0.0)
	_check("cable in reach: charge spent", ult.charge < 1.0)
	_check("it is that cable that is hot",
		cable.closest_point(player.arc_at).distance_to(player.arc_at) <= 24.0)
	_check("live for the gadget's active_time",
		absf(player.arc_left - gadget.active_time) < 0.2)

	# --- and what it does to somebody on it ---------------------------------
	#
	# The caster is immune to their own rail, so the victim has to be a second
	# body. Net.players() reads its own dict, so one goes in it: this is the
	# same seam a real second player arrives through.
	var victim := _stub_rider(level, midpoint)
	net._players[4242] = victim
	# The caster has to be in that dict too or the cable cannot find the current.
	net._players[net.peer_id()] = player

	# One frame, so Net can gather the live rails. Which cables are hot is
	# worked out once a frame by Net and read by every cable from there, so a
	# rail cast this instant is known to the level on the next tick - 1/60s in
	# play, and a thing a test has to actually wait for rather than assume.
	var spun := 0
	while net.live_rails.is_empty() and spun < 10:
		await process_frame
		spun += 1
	_check("Net gathered the rail", not net.live_rails.is_empty())
	_check("the cable agrees it is powered", cable._current_through_me() != 0)
	_check("host resolves the damage here", net.deals_damage())
	# Two ticks on purpose. Who is powering a cable is re-asked on the watch
	# interval, not per frame - so the first tick is the one that notices and
	# the second is the one that hurts. Up to a tenth of a second of grace, and
	# the test says so rather than papering over it.
	cable._process(0.016)
	_check("jolted on the very first tick", victim.taken > 0.0)
	_check("a whole jolt, not a slice of one", is_equal_approx(victim.taken, gadget.damage))
	# Immunity frames are why this cannot be damage-per-frame: a body ignores
	# anything inside 0.35s of the last hit, so the cable has to wait too.
	victim.taken = 0.0
	cable._process(0.016)
	_check("no second jolt straight away", victim.taken == 0.0)
	cable._process(0.4)
	_check("another once the interval is up", is_equal_approx(victim.taken, gadget.damage))

	# Standing at the end of it is safe - the gadget denies the rope, not the
	# ledge, and that distinction is the whole shape of it.
	victim.taken = 0.0
	victim.set(&"riding", false)
	cable._process(0.5)
	_check("standing at the end is safe", victim.taken == 0.0)

	# And the caster does not electrocute himself on his own cable.
	victim.set(&"riding", true)
	victim.set_multiplayer_authority(net.peer_id())
	victim.taken = 0.0
	cable._process(0.5)
	_check("your own rail does not bite you", victim.taken == 0.0)

	# --- it runs out --------------------------------------------------------
	#
	# A frame has to pass first. Who is arcing is worked out once per frame and
	# shared by every cable in the level, so the answer is up to one frame stale
	# by design - invisible in play, and worth being explicit about here rather
	# than letting the test look like it caught something.
	player.arc_left = 0.0
	await process_frame
	_check("a spent rail is a dead cable", cable._current_through_me() == 0)


## A body that rides and remembers being hurt, and nothing else. Written out
## here rather than kept as a scene because what it has to be is exactly the
## three properties Zipline reads off a player and one method.
func _stub_rider(parent: Node, at: Vector2) -> Node2D:
	var script := GDScript.new()
	script.source_code = """
extends Node2D
var riding := true
var arc_at := Vector2.ZERO
var arc_left := 0.0
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
