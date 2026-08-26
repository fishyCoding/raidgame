extends SceneTree

## The Projection ultimate: it walks off on its own, it rides cables, it takes
## three rounds, and it never makes a sound.
##
## Nothing here names Projection, Player, Zipline or Damage. All four reach Net,
## and a --script tool that names a class which reaches Net compiles that class
## before the autoloads are registered as globals - which does not read as a
## compile error, it reads as the level quietly failing to work. Everything is
## fetched by group or by path instead. See the headless-test notes.

const GADGET := "res://resources/gadgets/projection.tres"


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var audio: Node = root.get_node("Audio")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame

	# Past the shop and the briefing, or the tree stays paused and no character
	# ever runs a physics frame. Order matters - see the notes.
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
	assert(player != null, "the test needs a character to cast from")

	print("-- the legend --")
	_check_legend(main)

	print("\n-- casting --")
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var gadget: Resource = load(GADGET)
	var item: Object = maker.from_gadget(gadget)
	item.charge = 1.0
	player.inventory.set_ultimate(item)

	# Something to copy that is worth copying. Plates up is the one piece of kit a
	# person can read off a body across the yard, so it is the one the decoy most
	# has to get right.
	player.armored = true
	player.facing = -1
	var cast_at: Vector2 = player.global_position
	player._use_ultimate()

	# Grabbed before a single frame runs. A ghost picks a heading in its first
	# physics tick and turns to face it, so "does it come out wearing what the
	# caster wore" is a question with about a sixtieth of a second to ask it in.
	var ghost: Node2D = _the_ghost()
	assert(ghost != null, "Q with a charged Projection has to put a ghost in the world")

	print("  ghost %s at %s, caster at %s" % [
		ghost.name, str(ghost.global_position), str(cast_at)])
	assert(ghost.global_position.distance_to(cast_at) < 1.0,
		"it steps out of the caster, not beside them")

	print("  it wears what you wore: facing=%d armored=%s stowed=%s crouch=%.2f" % [
		ghost.facing, ghost.armored, ghost.stowed, ghost.crouch])
	assert(ghost.facing == player.facing, "it faces the way the caster did")
	assert(ghost.armored == player.armored, "and wears the plates the caster had up")
	assert(ghost.stowed == player.stowed, "and carries the gun the same way")
	assert(ghost.get_node_or_null(^"Body/ShieldOutline") != null,
		"the plates have to be drawable on it, or armour is invisible on a ghost")
	assert(ghost.get_node_or_null(^"AimPivot/Arm") != null,
		"and so does the gun arm, or a ghost is unarmed at a glance")

	# It keeps them after the caster drops theirs. That is the lie being bought:
	# a photograph of the moment you spent the charge, not a mirror.
	player.armored = false
	await physics_frame
	assert(ghost.armored, "the ghost keeps the plates after the caster drops theirs")
	# Not exactly zero: a physics frame has passed and the meter has already
	# started refilling. Spent is what matters, not empty.
	assert(item.charge < 0.05, "and the charge is spent")

	print("\n-- it cannot shoot --")
	print("  Weapon node: %s   has try_fire: %s" % [
		ghost.get_node_or_null(^"Weapon"), ghost.has_method(&"try_fire")])
	assert(ghost.get_node_or_null(^"Weapon") == null, "a ghost carries no weapon node")
	assert(not ghost.has_method(&"try_fire"), "and nothing that could pull a trigger")

	print("\n-- it makes no sound --")
	_check_silence()

	print("\n-- it goes off on its own --")
	var from: Vector2 = ghost.global_position
	var walked := 0.0
	for i in 180:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		walked = maxf(walked, from.distance_to(ghost.global_position))
	assert(is_instance_valid(ghost), "it should still be up three seconds in")
	print("  wandered %.0f px from where it was cast in 3s" % walked)
	assert(walked > 60.0, "a ghost that stands where you left it fools nobody")

	print("\n-- it can zip --")
	await _check_zipline(ghost, audio)

	print("\n-- three rounds and it is gone --")
	assert(is_instance_valid(ghost), "still up before anybody shoots it")
	assert(ghost.max_hits == 3, "the gadget says three")
	for shot in ghost.max_hits:
		ghost.take_damage(40.0, ghost.sight_centre(), Vector2.RIGHT)
		await physics_frame
		print("  hit %d: hits=%d glitch=%.2f still here=%s" % [
			shot + 1, ghost.hits, ghost.glitch, is_instance_valid(ghost)])
		assert(ghost.hits == shot + 1, "every round has to count")
		assert(ghost.glitch > 0.0, "and every round has to tear the picture")
		if shot == 0:
			# Mind.HIDE is 1. Named by value because naming the class would drag
			# Projection - and therefore Net - into this tool's compile.
			print("    ...and it breaks for cover: mind=%d threat=%s" % [
				ghost._mind, str(ghost._threat)])
			assert(ghost._mind == 1, "one round in and it should be running")
			assert(ghost._threat.is_finite(),
				"and it should have worked out roughly where the round came from")
		if shot < ghost.max_hits - 1:
			assert(not ghost.gone, "it does not give up before the third")

	assert(ghost.gone, "the third round finishes it")
	# It does not vanish on the frame it dies - it comes apart over half a
	# second, which is the whole point of the animation.
	assert(is_instance_valid(ghost), "the glitch has to be watchable, not instant")
	for i in 40:
		await physics_frame
		if not is_instance_valid(ghost):
			break
	print("  gone after the tear finished: %s" % not is_instance_valid(ghost))
	assert(not is_instance_valid(ghost), "and then it is gone")

	print("\n-- it hides when it is seen --")
	_check_cover(main, player)

	print("\nPASS")
	quit()


## Every keyboard action in the map has to be printed somewhere on the legend.
func _check_legend(main: Node) -> void:
	var label: Label = main.get_node("HUD/Controls")
	var shown: String = label.text
	assert(not shown.is_empty(), "the legend must not be blank on a desktop build")

	var missing: PackedStringArray = []
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		var keyed := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keyed = true
		if not keyed:
			continue
		# The key itself has to be on screen. Checking for the printed key rather
		# than the action name is the point: the legend is a list of keys, and a
		# key that is bound but not printed is exactly the failure this guards.
		var text := OS.get_keycode_string((InputMap.action_get_events(action)[0]
			as InputEventKey).physical_keycode)
		if not shown.findn(text) >= 0:
			missing.append("%s (%s)" % [action, text])
	print("  %d lines, %d chars" % [shown.split("\n").size(), shown.length()])
	for line in shown.split("\n"):
		print("    %s" % line)
	assert(missing.is_empty(), "keys bound but not shown: %s" % ", ".join(missing))


## The one sound a ghost could plausibly make is a rope, because that is the one
## the player makes continuously rather than in bursts. Checked at the source as
## well: the guarantee is that this file never reaches the Audio autoload at all,
## and that is a property of the script, not of one run.
func _check_silence() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/projection.gd")
	var stripped: PackedStringArray = []
	for line in source.split("\n"):
		var hash := line.find("#")
		stripped.append(line.substr(0, hash) if hash >= 0 else line)
	var code := "\n".join(stripped)
	for forbidden in ["Audio.", "_audio", "AudioStreamPlayer", "play("]:
		print("  mentions %-18s %s" % [forbidden, code.find(forbidden) >= 0])
		assert(code.find(forbidden) < 0,
			"a projection that can reach %s is a projection you can hear" % forbidden)


## It gets on a cable, it goes up it, and the rope stays silent while it does.
func _check_zipline(ghost: Node2D, audio: Node) -> void:
	var cables: Array = get_nodes_in_group(&"zipline")
	assert(not cables.is_empty(), "the level has to have a cable to test with")
	# The longest one, so there is room to travel before either end arrives.
	var cable: Node2D = cables[0]
	for line in cables:
		if line.cable_length() > cable.cable_length():
			cable = line

	ghost.global_position = cable.world_bottom()
	ghost.velocity = Vector2.ZERO
	ghost._target = cable.world_top()
	ghost._mind = 0

	var rode := false
	var climbed := 0.0
	var started: float = ghost.global_position.y
	for i in 90:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		if ghost.riding:
			rode = true
			climbed = maxf(climbed, started - ghost.global_position.y)
			# The rope is the loudest thing it could be doing. Nobody may be
			# holding the sound, and it must not be playing on its account.
			assert(audio._zip_owner != ghost.get_instance_id(),
				"a ghost on a rope must never claim the zipline sound")
	print("  got on a cable: %s, climbed %.0f px, gun slung: %s" % [
		rode, climbed, ghost.stow > 0.0 or not ghost.riding])
	assert(rode, "a ghost has to be able to take a zipline")
	assert(climbed > 20.0, "and actually travel along it")
	assert(not audio._zip.playing, "and the rope stays silent under it")


## Being seen sends it looking for somewhere the watcher cannot draw a line to.
##
## Exercised directly rather than through a second player, because solo there is
## nobody else to be seen by - a ghost never hides from its own caster, which is
## deliberate and is why the state has to be poked rather than provoked here.
func _check_cover(main: Node, player: Node2D) -> void:
	var ghost: Node2D = (load("res://scenes/projection.tscn") as PackedScene).instantiate()
	ghost.name = "Ghost_probe"
	main.get_node("Players").add_child(ghost)
	ghost.global_position = player.global_position
	ghost._threat = player.global_position + Vector2(600.0, 0.0)

	var spot: Vector2 = ghost._find_cover()
	print("  threat at +600px, cover chosen at %s (%.0f px away, %s the threat)" % [
		str(spot), absf(spot.x - ghost.global_position.x),
		"away from" if spot.x < ghost.global_position.x else "toward"])
	assert(spot.is_finite(), "being seen has to produce somewhere to go")
	assert(not spot.is_equal_approx(ghost.global_position),
		"and somewhere is not where it is already standing")
	ghost.queue_free()


func _the_ghost() -> Node2D:
	for node in get_nodes_in_group(&"projection"):
		return node as Node2D
	return null
