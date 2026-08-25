extends SceneTree

## A long drop gives you away.
##
##   godot --headless --path . --script res://tools/fall_ping_test.gd
##
## Three separate things, tested separately: that a real fall through real
## physics is measured and only counts past the threshold, that the noise sends
## the guards near it to look and leaves the ones out of earshot alone, and that
## being carried down - a cable, a rope - is not a fall.

var _failures := 0
var _drops: Array[float] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame

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
	player.landed_hard.connect(func(drop: float) -> void: _drops.append(drop))
	print("-- the dials --")
	# Said in men as well as pixels: the threshold is easier to argue about as
	# "how far up is that" than as a number.
	# A guard is the unit of height here, so with none in the level fall back to
	# the player rather than skipping - what this tool measures is the player.
	var guards: Node = main.get_node("Enemies")
	var guard_tall: float = player.size.y
	if guards.get_child_count() > 0:
		guard_tall = (guards.get_child(0) as Node2D).size.y
	print("  past %.0f px it carries (%.1f guards tall), %.0f px around it, lit for %.1fs" % [
			player.fall_ping_height, player.fall_ping_height / guard_tall,
			player.fall_ping_radius, player.fall_ping_time])

	# The yard floor: 5200x80 centred on y=460, so its top is at 420.
	var floor_y := 420.0

	print("\n-- a long drop --")
	var want: float = player.fall_ping_height + 260.0
	# The yard is roofed with walkways almost everywhere, so the drop site is
	# found by raycast rather than guessed at: a column with nothing between the
	# height we want and the floor. Mask 3 is world plus one-way, because a
	# catwalk you can jump up through still stops you falling onto it.
	var at_x := 0.0
	var space := player.get_world_2d().direct_space_state
	for step in 52:
		var x := -2400.0 + step * 96.0
		var probe := PhysicsRayQueryParameters2D.create(
				Vector2(x, floor_y - want - 40.0), Vector2(x, floor_y - 8.0))
		probe.collision_mask = 3
		if space.intersect_ray(probe).is_empty():
			at_x = x
			break
	var fell := await _drop_from(player, at_x, floor_y, want)
	print("  fell %.0f px at x=%.0f, reported %s" % [fell, at_x, str(_drops)])
	_check("found somewhere to fall from", fell > want - 40.0)
	_check("the fall was heard", _drops.size() == 1)
	_check("and measured about right",
			_drops.size() == 1 and absf(_drops[0] - fell) < 30.0)
	_check("and it said so", player.loot_message.contains("landing"))

	print("\n-- a short one --")
	_drops.clear()
	var hop := await _drop_from(player, at_x, floor_y, player.fall_ping_height * 0.35)
	print("  fell %.0f px, reported %s" % [hop, str(_drops)])
	_check("stepping off something is not a fall", _drops.is_empty())

	print("\n-- who hears it --")
	var near: Node2D = null
	var far: Node2D = null
	for node in main.get_node("Enemies").get_children():
		var guard := node as Node2D
		if guard == null or guard.state != 0:  # PATROL
			continue
		if near == null:
			near = guard
		elif far == null and guard.global_position.distance_to(
				near.global_position) > player.fall_ping_radius * 2.2:
			far = guard
	if near == null or far == null:
		print("  needed two patrolling guards far enough apart; got %s / %s" % [near, far])
		quit(1)
		return

	# Put the noise beside one of them. Driven through Net rather than by
	# dropping the player on his head, so the guard's own eyes cannot be what
	# sets him off and the test is about hearing.
	var noise: Vector2 = near.global_position + Vector2(280.0, 0.0)
	print("  %s is %.0f px away, %s is %.0f px away" % [
			near.name, near.global_position.distance_to(noise),
			far.name, far.global_position.distance_to(noise)])
	net._fall_landed(net.peer_id(), noise, player.fall_ping_height + 200.0)
	await physics_frame
	print("  %s -> state %d (last seen %s), %s -> state %d" % [
			near.name, near.state, str(near._last_seen), far.name, far.state])
	_check("the guard in earshot goes to look", near.state == 2)  # SEARCH
	_check("and looks where the noise was",
			near._last_seen.distance_to(noise) < 1.0)
	_check("the one out of earshot carries on", far.state == 0)

	print("\n-- being carried down is not falling --")
	_drops.clear()
	var input: Node = root.get_node("PlayerInput")
	var cable: Node2D = main.get_node("Ziplines/ZipYard4")
	var top: Vector2 = cable.world_top()
	var drop_len: float = top.distance_to(cable.world_bottom())
	print("  %s is %.0f px long" % [cable.name, drop_len])
	_check("a cable long enough to have counted", drop_len > player.fall_ping_height)
	player.global_position = top
	player.velocity = Vector2.ZERO
	await physics_frame
	input.touch_interact_pressed = true
	await physics_frame
	_check("on the cable", player.riding)
	# Ride it all the way down.
	input.touch_down_held = true
	var frames := 0
	while player.riding and frames < 600:
		await physics_frame
		frames += 1
	input.touch_down_held = false
	for i in 60:
		await physics_frame
	print("  rode down and stepped off; reported %s" % str(_drops))
	_check("riding a cable down does not give you away", _drops.is_empty())

	if _failures > 0:
		print("\nfall | %d FAILED" % _failures)
		quit(1)
		return
	print("\nfall | PASS")
	quit()


## Parks the character `height` above the floor, lets go, and returns how far it
## actually fell.
func _drop_from(player: Node2D, x: float, floor_y: float, height: float) -> float:
	player.global_position = Vector2(x, floor_y - height)
	player.velocity = Vector2.ZERO
	await physics_frame
	var from: float = player.global_position.y
	var frames := 0
	while not player.is_on_floor() and frames < 400:
		await physics_frame
		frames += 1
	var fell: float = player.global_position.y - from
	for i in 4:
		await physics_frame
	return fell


func _check(what: String, passed: bool) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures += 1
	print("  FAIL %s" % what)
