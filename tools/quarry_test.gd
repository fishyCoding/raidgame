extends SceneTree

## The quarry has to be a level you can actually play, not just a scene that
## loads: a character standing in it, guards that patrol, ground under your feet
## and a way home marked on the map.
##
## It is reached from the menu's map button, which is checked at the bottom -
## the level goes into the tree first because everything in it measures itself
## against whatever the tree calls the current scene. See Net.LEVELS.

func _initialize() -> void:
	_run()


func _run() -> void:
	# Fetched by path, not as the global: --script compiles before autoloads
	# are registered as script globals, which is why every tool here does this.
	var net: Node = root.get_node("Net")
	print("-- the map list --")
	var found := -1
	for i in net.LEVELS.size():
		print("  %d  %-12s %s" % [i, net.LEVELS[i]["name"], net.LEVELS[i]["scene"]])
		if str(net.LEVELS[i]["scene"]).ends_with("quarry.tscn"):
			found = i
	assert(found > 0, "the quarry has to be on the list the menu cycles through")
	assert(net.level_named("quarry") == found, "and --solo=quarry has to find it")
	net.solo_level = found
	assert(net.solo_scene().ends_with("quarry.tscn"), "picking it has to open it")

	var quarry: Node = (load(net.solo_scene()) as PackedScene).instantiate()
	root.add_child(quarry)
	current_scene = quarry
	# The character is spawned now, not placed, so give it a couple of frames.
	for i in 6:
		await physics_frame

	print("\n-- the session --")
	var player: Node2D = net.local_player
	print("  in_session=%s  local player=%s" % [
		net.in_session, player.name if player else "NONE"])
	assert(net.in_session, "opening the level should open a session")
	assert(player != null, "the quarry has to put a character in the world")
	assert(player.is_local(), "and it must be ours to drive")

	# Every insertion point in this map is the same corner while it is being
	# built, so this checks that one of them was chosen - not that they are far
	# apart, which they deliberately are not yet.
	var spawns: Array = get_nodes_in_group(&"spawn")
	print("  %d insertion points, spawned at %s" % [spawns.size(), player.global_position])
	assert(spawns.size() >= 2, "a raid needs somewhere to come in and somewhere to leave")
	var landed_on_one := false
	for point in spawns:
		if (point as Node2D).global_position.distance_to(player.global_position) < 200.0:
			landed_on_one = true
	assert(landed_on_one, "the body should be standing on an insertion point")

	# Two of them are this player's way home, marked by the player itself - so
	# this is also a check that the raid got as far as working out a route out.
	var exits := 0
	for point in spawns:
		if point.is_extraction:
			exits += 1
	print("  %d of them marked as a way out" % exits)
	assert(exits > 0, "a raid with no extraction is not an extraction game")

	print("\n-- the world --")
	# Some of this map's guards are parked at the root of the scene rather than
	# under Enemies. It makes no difference to them - they are found by what they
	# can do, here and everywhere else.
	var guards: Array = []
	for node in quarry.get_children():
		if node.has_method(&"is_brain"):
			guards.append(node)
		elif node.name == "Enemies":
			guards.append_array(node.get_children())
	var thinking := 0
	for g in guards:
		if g.is_brain():
			thinking += 1
	print("  %d guards, %d of them thinking here (host)" % [guards.size(), thinking])
	assert(guards.size() > 0, "an empty map is not a raid")
	assert(thinking == guards.size(), "the host thinks for every guard")

	# The briefing map measures itself off World, and draws only what is in it.
	var map: Node = get_first_node_in_group(&"map_screen")
	var outside := 0
	for node in quarry.get_children():
		if node is Node2D and typeof(node.get(&"size")) == TYPE_VECTOR2:
			outside += 1
	print("  briefing map covers %s" % map._bounds)
	print("  %d blocks are parked outside World, so the map cannot draw them" % outside)
	assert(map._bounds.size.x > 1000.0, "the map has to have measured the level")

	# Past the shop and the briefing, both of which pause the tree - the preamble
	# every solo tool here shares.
	var shop: Node = quarry.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	var was: Vector2 = guards[0].global_position
	for i in 60:
		await physics_frame
	print("  a guard moved %.0f px in a second" % was.distance_to(guards[0].global_position))
	assert(was.distance_to(guards[0].global_position) > 5.0, "guards should be patrolling")

	print("\n-- the player still plays --")
	var input: Node = root.get_node("PlayerInput")
	var start: Vector2 = player.global_position
	input.touch_move_axis = 1.0
	for i in 30:
		await physics_frame
	input.touch_move_axis = 0.0
	print("  walked %.0f px on input, dropped %.0f" % [
		absf(player.global_position.x - start.x), player.global_position.y - start.y])
	assert(absf(player.global_position.x - start.x) > 10.0, "input must still drive it")
	assert(player.global_position.y - start.y < 400.0, "and there must be ground under it")

	# The way a player actually gets here: the button, not the number behind it.
	print("\n-- the menu's map button --")
	net.solo_level = 0
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	await process_frame
	var button: Button = null
	for node in lobby.get_children():
		if node is Button and str((node as Button).text).begins_with("map:"):
			button = node
	print("  opens on '%s'" % (button.text if button else "NOTHING"))
	assert(button != null, "the menu has to offer the map")
	var presses := 0
	while net.solo_level != found and presses < net.LEVELS.size():
		button.pressed.emit()
		presses += 1
	print("  after %d press(es): '%s' -> %s" % [presses, button.text, net.solo_scene()])
	assert(button.text.contains("quarry"), "and say which one it landed on")
	assert(net.solo_scene().ends_with("quarry.tscn"), "so that pressing it opens the quarry")
	lobby.free()

	print("\nOK")
	quit()
