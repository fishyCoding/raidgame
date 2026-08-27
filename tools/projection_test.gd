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

## Counted rather than asserted. A bare `assert()` inside a function called from
## _run unwinds only that function, so the runner walks straight on to the next
## section and prints PASS at the end - this file reported a clean run twice
## while checks inside it were failing. Same argument order as `assert()` so the
## call sites read the same; the difference is that every one of them runs, and
## the verdict at the bottom is the truth.
var _ok := true


func _check_that(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("  FAIL  %s" % what)


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
	_check_that(player != null, "the test needs a character to cast from")
	if player == null:
		quit(1)
		return

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
	# Q opens the placing view; the click is what casts. Both halves here, since
	# everything below is about the body that results rather than about the
	# control - which _check_orders covers on its own.
	player._use_ultimate()
	player._send_projection(cast_at + Vector2(-400.0, 0.0))

	# Grabbed before a single frame runs. A ghost picks a leg in its first
	# physics tick and turns to face it, so "does it come out wearing what the
	# caster wore" is a question with about a sixtieth of a second to ask it in.
	var ghost: Node2D = _the_ghost()
	_check_that(ghost != null, "Q with a charged Projection has to put a ghost in the world")
	if ghost == null:
		quit(1)
		return

	print("  ghost %s at %s, caster at %s" % [
		ghost.name, str(ghost.global_position), str(cast_at)])
	_check_that(ghost.global_position.distance_to(cast_at) < 1.0,
		"it steps out of the caster, not beside them")

	print("  it wears what you wore: facing=%d armored=%s stowed=%s crouch=%.2f" % [
		ghost.facing, ghost.armored, ghost.stowed, ghost.crouch])
	_check_that(ghost.facing == player.facing, "it faces the way the caster did")
	_check_that(ghost.stowed == player.stowed, "and carries the gun the same way")
	_check_that(ghost.get_node_or_null(^"Body/ShieldOutline") != null,
		"the plates have to be drawable on it, or armour is invisible on a ghost")
	_check_that(ghost.get_node_or_null(^"AimPivot/Arm") != null,
		"and so does the gun arm, or a ghost is unarmed at a glance")

	# Plates up whatever the caster had on, and up straight away rather than
	# ramping into place - a ghost that spent its first third of a second
	# unarmoured would be readable in exactly the moment somebody is deciding
	# which of the two of you to shoot.
	player.armored = false
	await physics_frame
	print("  plates: armored=%s shield=%.2f (caster armored=%s)" % [
		ghost.armored, ghost.shield, player.armored])
	_check_that(ghost.armored, "a ghost always comes out with its plates up")
	_check_that(ghost.shield >= 1.0, "and up already, not ramping")
	_check_that(ghost.get_node("Body/ShieldOutline")._drawn > 0.0,
		"and the outline has to actually be drawing, or the plates are invisible")
	# Not exactly zero: a physics frame has passed and the meter has already
	# started refilling. Spent is what matters, not empty.
	_check_that(item.charge < 0.05, "and the charge is spent")

	print("\n-- it cannot shoot --")
	print("  Weapon node: %s   has try_fire: %s" % [
		ghost.get_node_or_null(^"Weapon"), ghost.has_method(&"try_fire")])
	_check_that(ghost.get_node_or_null(^"Weapon") == null, "a ghost carries no weapon node")
	_check_that(not ghost.has_method(&"try_fire"), "and nothing that could pull a trigger")

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
	_check_that(is_instance_valid(ghost), "it should still be up three seconds in")
	print("  wandered %.0f px from where it was cast in 3s" % walked)
	_check_that(walked > 60.0, "a ghost that stands where you left it fools nobody")
	# The checks below take longer than a ghost is supposed to live. Wound the
	# clock forward rather than casting a fresh one each time, so what is being
	# exercised is one body over its whole life.
	ghost.life_left = 90.0

	print("\n-- it runs at the caster's pace --")
	await _check_speed(ghost, player)

	print("\n-- it can zip --")
	await _check_zipline(ghost, audio)

	print("\n-- and not the same cable twice --")
	await _check_cable_memory(ghost)

	print("\n-- three rounds and it is gone --")
	_check_that(is_instance_valid(ghost), "still up before anybody shoots it")
	_check_that(ghost.max_hits == 3, "the gadget says three")
	for shot in ghost.max_hits:
		ghost.take_damage(40.0, ghost.sight_centre(), Vector2.RIGHT)
		await physics_frame
		print("  hit %d: hits=%d glitch=%.2f still here=%s" % [
			shot + 1, ghost.hits, ghost.glitch, is_instance_valid(ghost)])
		_check_that(ghost.hits == shot + 1, "every round has to count")
		_check_that(ghost.glitch > 0.0, "and every round has to tear the picture")
		if shot == 0:
			# Mind.BREAK is 3 (ORDERS, LURE, PEEK, BREAK). Named by value because
			# naming the class would drag Projection - and therefore Net - into
			# this tool's compile.
			print("    ...and it runs: mind=%d threat=%s target=%s" % [
				ghost._mind, str(ghost._threat), str(ghost._target)])
			_check_that(ghost._mind == 3, "one round in and it should be running")
			_check_that(ghost._threat.is_finite(),
				"and it should have worked out roughly where the round came from")
			_check_that(ghost._target.is_finite(), "with somewhere to run to")
		if shot < ghost.max_hits - 1:
			_check_that(not ghost.gone, "it does not give up before the third")

	_check_that(ghost.gone, "the third round finishes it")
	# It does not vanish on the frame it dies - it comes apart over half a
	# second, which is the whole point of the animation.
	_check_that(is_instance_valid(ghost), "the glitch has to be watchable, not instant")
	# Long enough for the death animation however long that is, rather than a
	# frame count tuned to whatever it was the day this was written. It was 40
	# frames, the animation went from 0.5s to 0.78s to make room for the stutter,
	# and this read as "the ghost never dies".
	for i in 240:
		await physics_frame
		if not is_instance_valid(ghost):
			break
	print("  gone after the tear finished: %s" % not is_instance_valid(ghost))
	_check_that(not is_instance_valid(ghost), "and then it is gone")

	print("\n-- it lures rather than hides --")
	_check_bait(main, player)

	print("\n-- and it plays to people who can chase it --")
	await _check_ignores_the_uninterested(main, player)

	print("\n-- you click where it should go --")
	await _check_orders(main, player)

	print("\n-- a click in the air lands on the floor --")
	_check_snaps_to_ground(player)

	print("\n-- and it takes a rope to get to another floor --")
	await _check_routes_by_cable(main, player)

	print("\n-- and it does not bounce off walls --")
	await _check_not_jumpy(main, player)

	print("\n-- the bow shows you where the arrow goes --")
	await _check_bow(player)

	print("\n-- throwing with a thumb --")
	await _check_touch_throw(main, player)

	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


## A ghost must not be quicker than the person it is pretending to be.
##
## Measured rather than read off the field: the whole chain - the caster's gun
## weight and wounds coming over on speed_scale, the plates and the crouch
## applied on this body - has to arrive at the same number Player._update_run
## arrives at, and the only honest way to check that is to let it run and watch
## how fast it actually goes.
func _check_speed(ghost: Node2D, player: Node2D) -> void:
	# What the caster could do right now, plated, by the same chain of
	# multipliers. Not a hardcoded 260: the point is that the two agree.
	var carrying := 1.0
	if player.weapon.data:
		carrying = player.weapon.data.get_move_multiplier()
	var caster_cap: float = (player.max_speed * carrying
		* player.injury_speed_multiplier() * player.shield_speed_scale)

	# Somewhere flat and clear, walking one way, so it reaches its cap.
	ghost.global_position = player.global_position
	# Mind.LURE. It used to be 0, which was ROAM and is now ORDERS - and
	# ORDERS with no orders on it drops straight back to LURE and repicks,
	# throwing away the target this check just set.
	ghost._mind = 1
	ghost.crouch = 0.0
	ghost._target = ghost.global_position + Vector2(1400.0, 0.0)
	ghost._rethink = 99.0

	var top := 0.0
	for i in 90:
		await physics_frame
		if not is_instance_valid(ghost):
			return
		if ghost.riding or ghost.crouch > 0.05:
			continue
		top = maxf(top, absf(ghost.velocity.x))
	print("  ghost topped out at %.0f px/s, the caster's plated cap is %.0f" % [
		top, caster_cap])
	_check_that(top <= caster_cap + 2.0,
		"a ghost must never outrun the person it is copying")
	_check_that(top > caster_cap * 0.9,
		"nor crawl - it has to look like somebody actually going somewhere")


## Off a cable and straight back onto the same one is the failure here.
func _check_cable_memory(ghost: Node2D) -> void:
	var cables: Array = get_nodes_in_group(&"zipline")
	var cable: Node2D = cables[0]
	for line in cables:
		if line.cable_length() > cable.cable_length():
			cable = line

	# Put it on, then take it off the way arriving at an end does.
	ghost.global_position = cable.world_bottom()
	ghost._target = cable.world_top()
	ghost._grab(cable)
	_check_that(ghost.riding, "it should be on the rope")
	ghost._let_go(false)
	print("  stepped off %s, cooldown %.1fs" % [cable.name, ghost._cable_cooldown])
	_check_that(ghost._cable_cooldown > 0.0, "stepping off has to start the cooldown")
	_check_that(ghost._last_cable == cable, "and remember which rope it was")

	# Standing right on it, wanting to go somewhere it could take you: still no.
	ghost._target = cable.world_top()
	print("  standing on it, asked for a cable: %s" % ghost._cable_here())
	_check_that(ghost._cable_here() == null,
		"the rope it just rode must be off limits, or it rides it forever")

	var grabbed_again := false
	for i in 60:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		if ghost.riding:
			grabbed_again = true
			break
	print("  got back on within a second: %s" % grabbed_again)
	_check_that(not grabbed_again, "and it must not climb straight back on")
	if is_instance_valid(ghost):
		ghost._cable_cooldown = 0.0
		ghost._last_cable = null


## Drawing the bow has to put the arrow's flight on screen, and the wind-up has
## to visibly change it - that is the entire point of a wind-up.
func _check_bow(player: Node2D) -> void:
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var bow: Object = maker.from_gadget(load("res://resources/gadgets/recon_bow.tres"))
	bow.charge = 1.0
	player.inventory.set_ultimate(bow)
	player.aim_angle = 0.0
	player.aim_direction = Vector2.RIGHT

	player._use_ultimate()
	await physics_frame
	_check_that(player.bow_out, "Q with a charged bow brings it out")

	var line: Node2D = player.get_node("Overlay/AimLine")
	print("  bow out: arc=%s points=%d sweep=%.0f" % [
		line.showing_arc, line.arc_points.size(), line.arc_radius])
	_check_that(line.showing_arc, "the flight has to be drawn before you commit to it")
	_check_that(line.arc_points.size() > 2, "and be an actual flight, not two points")
	_check_that(line.arc_radius > 1.0,
		"with the sweep it will paint, or you cannot aim it at a room")

	# Half-drawn against fully drawn. Compared on the first step of the flight
	# and on the sweep, not on where the arrow ends up: the endpoint depends on
	# whatever wall happens to be in front of the character when the test runs,
	# and a check that passes or fails on where the insertion roll dropped you is
	# no check at all. The first step is the muzzle velocity, which is exactly
	# what the wind-up buys.
	player.bow_drawn = 0.25
	player._show_arrow_flight()
	var slow: float = line.arc_points[0].distance_to(line.arc_points[1])
	var small_sweep: float = line.arc_radius

	player.bow_drawn = 1.0
	player._show_arrow_flight()
	var fast: float = line.arc_points[0].distance_to(line.arc_points[1])
	var big_sweep: float = line.arc_radius

	print("  quarter draw: %.1f px in the first step, sweeps %.0f" % [slow, small_sweep])
	print("  full draw:    %.1f px in the first step, sweeps %.0f" % [fast, big_sweep])
	_check_that(fast > slow * 1.5,
		"pulling it back further has to visibly throw the arrow harder")
	_check_that(big_sweep > small_sweep * 1.5, "and paint a wider sweep")

	# Putting it away takes the line with it, or the level keeps a blue arc
	# drawn across it for the rest of the raid.
	player.bow_out = false
	player.bow_drawn = 0.0
	player._hide_arrow_flight()
	print("  bow away: arc=%s radius=%.0f" % [line.showing_arc, line.arc_radius])
	_check_that(not line.showing_arc, "putting the bow away clears the flight line")
	_check_that(line.arc_radius == 0.0, "and the sweep circle with it")


## The phone's grenade: tap the pill to arm it, drag to place it, THROW to
## commit. The thing that must work is that it lands where the finger put it and
## not where the crosshair happens to be.
##
## Every assertion is held back to the end, after the control scheme has been put
## back. That is not style, it is damage control: PlayerInput.control_scheme has
## a setter that writes user://controls.cfg, so forcing touch mode here changes a
## setting that outlives the process and belongs to whoever owns this machine. An
## assert firing mid-way through would abort the run with the file still saying
## "touch", and every later run - and the actual game, which reads the same file -
## would come up with thumbsticks on a desktop and no keyboard movement at all.
## Which is exactly what happened while this was being written, and it read as
## solo_test suddenly failing to walk.
func _check_touch_throw(main: Node, player: Node2D) -> void:
	var input: Node = root.get_node("PlayerInput")
	var pad: Control = main.get_node("HUD/TouchControls")
	var was: int = input.control_scheme
	input.control_scheme = 1 # Controls.TOUCH
	await process_frame

	var seen := {}

	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var frag: Object = maker.from_gadget(load("res://resources/gadgets/frag.tres"))
	player.inventory.set_throwable(0, frag)

	pad._begin_placing(&"throw_1")
	# Polled rather than checked on the next frame. A real thumb presses the pill
	# from _input, which lands before the physics tick that reads the edge; this
	# is being called from a coroutine that resumes after one, so which frame the
	# just-pressed edge falls on is an artefact of the harness rather than
	# anything about the pad.
	await _wait_for(func() -> bool: return player.throw_slot == 0, 12)
	print("  armed: placing=%s player throw_slot=%d" % [pad._placing, player.throw_slot])
	seen["armed"] = pad._placing == &"throw_1"
	seen["winding"] = player.throw_slot == 0

	# A thumb somewhere on the map. Placed in world space directly - the screen
	# maths is the camera's and is not what this is testing.
	var spot: Vector2 = player.global_position + Vector2(260.0, -40.0)
	pad._place_at = spot
	await physics_frame
	var line: Node2D = player.get_node("Overlay/AimLine")
	print("  placed at %s: arc showing=%s, %d points" % [
		str(spot), line.showing_arc, line.arc_points.size()])
	seen["arc"] = line.showing_arc
	seen["target"] = input.touch_aim_point.is_finite()

	# A thumb lifting must NOT throw it - that is the whole reason for the
	# two-button pad, and the bug it exists to prevent.
	pad._lift(0)
	await physics_frame
	seen["survives_lift"] = pad._placing == &"throw_1" and player.throw_slot == 0
	print("  a thumb lifting left it armed: %s" % seen["survives_lift"])

	var before: int = main.get_node("Bullets").get_child_count()
	pad._end_placing(true)
	await physics_frame
	await physics_frame
	var after: int = main.get_node("Bullets").get_child_count()
	print("  THROW: %d -> %d things in the world, throw_slot=%d" % [
		before, after, player.throw_slot])
	seen["threw"] = after > before
	seen["finished"] = player.throw_slot < 0

	# Where it went. Solved to land on the spot, so it should be heading there.
	var toward := -1.0
	if after > before:
		var thrown: Node2D = main.get_node("Bullets").get_child(after - 1)
		toward = (spot - player.global_position).normalized().dot(
			thrown.velocity.normalized())
	print("  it left travelling %.2f toward the placed spot (1.0 = straight at it)" % toward)
	seen["aimed"] = toward > 0.3

	# CANCEL puts it back.
	pad._begin_placing(&"throw_1")
	await _wait_for(func() -> bool: return player.throw_slot == 0, 12)
	seen["rearmed"] = player.throw_slot == 0
	pad._end_placing(false)
	await physics_frame
	print("  CANCEL: throw_slot=%d, target cleared=%s" % [
		player.throw_slot, not input.touch_aim_point.is_finite()])
	seen["cancelled"] = player.throw_slot < 0
	seen["let_go"] = not input.touch_aim_point.is_finite()

	# Before a single assert. See the note above this function.
	input.control_scheme = was
	await process_frame

	_check_that(seen["armed"], "the pill arms it rather than throwing it")
	_check_that(seen["winding"], "and the player starts winding up")
	_check_that(seen["arc"], "placing has to show the arc, same as a mouse does")
	_check_that(seen["target"], "and hand the player the spot")
	_check_that(seen["survives_lift"], "lifting a thumb must not throw the grenade")
	_check_that(seen["threw"], "THROW has to actually throw it")
	_check_that(seen["finished"], "and end the wind-up")
	_check_that(seen["aimed"], "and throw it at the spot, not at the crosshair")
	_check_that(seen["rearmed"], "a second grenade arms the same way")
	_check_that(seen["cancelled"], "CANCEL has to put the grenade back")
	_check_that(seen["let_go"], "and let go of the target")


## Every keyboard action in the map has to be printed somewhere on the legend.
func _check_legend(main: Node) -> void:
	var label: Label = main.get_node("HUD/Controls")
	var shown: String = label.text
	_check_that(not shown.is_empty(), "the legend must not be blank on a desktop build")

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
	_check_that(missing.is_empty(), "keys bound but not shown: %s" % ", ".join(missing))


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
		_check_that(code.find(forbidden) < 0,
			"a projection that can reach %s is a projection you can hear" % forbidden)


## It gets on a cable, it goes up it, and the rope stays silent while it does.
func _check_zipline(ghost: Node2D, audio: Node) -> void:
	var cables: Array = get_nodes_in_group(&"zipline")
	_check_that(not cables.is_empty(), "the level has to have a cable to test with")
	# The longest one, so there is room to travel before either end arrives.
	var cable: Node2D = cables[0]
	for line in cables:
		if line.cable_length() > cable.cable_length():
			cable = line

	ghost.global_position = cable.world_bottom()
	ghost.velocity = Vector2.ZERO
	ghost._target = cable.world_top()
	ghost._mind = 1
	# Long enough that the lure loop does not repick over the top of it.
	ghost._rethink = 99.0

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
			_check_that(audio._zip_owner != ghost.get_instance_id(),
				"a ghost on a rope must never claim the zipline sound")
	print("  got on a cable: %s, climbed %.0f px, gun slung: %s" % [
		rode, climbed, ghost.stow > 0.0 or not ghost.riding])
	_check_that(rode, "a ghost has to be able to take a zipline")
	_check_that(climbed > 20.0, "and actually travel along it")
	_check_that(not audio._zip.playing, "and the rope stays silent under it")


## Being seen makes it hold, then run - it does not go and hide.
##
## Exercised by poking the state rather than by staging two players, because solo
## there is nobody else to be seen by: a ghost never lures its own caster, which
## is deliberate and is the reason the sweep skips bodies sharing its authority.
func _check_bait(main: Node, player: Node2D) -> void:
	var ghost: Node2D = (load("res://scenes/projection.tscn") as PackedScene).instantiate()
	ghost.name = "Ghost_probe"
	main.get_node("Players").add_child(ghost)
	ghost.global_position = player.global_position

	# Mind: 0 ORDERS, 1 LURE, 2 PEEK, 3 BREAK.
	var watcher: Vector2 = player.global_position + Vector2(600.0, 0.0)
	ghost._mind = 1
	# Raised directly rather than by staging a watcher: _watch rebuilds its own
	# list of eyes from Net.players() every sweep, so anything planted in _eyes
	# is gone by the time it looks - and solo there is nobody on that list but
	# the caster, who a ghost deliberately never plays to.
	ghost._spotted_by(watcher)
	print("  spotted from +600px: mind=%d hold=%.2f" % [ghost._mind, ghost._hold])
	_check_that(ghost._mind == 2, "being seen has to make it stop and hold, not hide")
	_check_that(ghost._hold > 0.0, "for a beat somebody can react to")

	# The peek runs out into a run, away from the man who looked at it.
	ghost._threat = watcher
	ghost._hold = 0.0
	ghost._think(0.016)
	print("  peek over: mind=%d target=%s (watcher at %.0f, ghost at %.0f)" % [
		ghost._mind, str(ghost._target), watcher.x, ghost.global_position.x])
	_check_that(ghost._mind == 3, "and then it should break")
	_check_that(ghost._target.is_finite(), "with somewhere to go")
	_check_that(ghost._target.x < ghost.global_position.x,
		"away from the watcher, who is to the right of it")

	# And the routes it picks favour being seen over being hidden, which is the
	# whole reversal: this used to score cover.
	ghost._mind = 1
	ghost._eyes = [watcher] as Array[Vector2]
	var seen := 0
	for i in 12:
		ghost._pick_lure_target()
		if ghost._seen_from(ghost._eyes, ghost._target).is_finite():
			seen += 1
	print("  %d of 12 chosen spots are in the watcher's view" % seen)
	_check_that(seen > 0, "a decoy that always picks cover is a decoy nobody follows")
	ghost.queue_free()


## Nobody it cannot usefully bait counts as a watcher.
##
## Three separate ways a body can be on the map and not be an audience: it is a
## guard, it is dead, or it is on the floor bleeding out. Peeking at any of them
## costs a whole cycle of the gadget - three quarters of a second stood still,
## then a sprint away from wherever it was working - spent on somebody who is not
## coming. Running from a corpse is the version of this you can actually see.
func _check_ignores_the_uninterested(main: Node, player: Node2D) -> void:
	var guards: Array = main.get_node("Enemies").get_children()
	_check_that(not guards.is_empty(), "the level has to have guards to ignore")
	if guards.is_empty():
		return

	var ghost: Node2D = (load("res://scenes/projection.tscn") as PackedScene).instantiate()
	ghost.name = "Ghost_guardprobe"
	main.get_node("Players").add_child(ghost)

	# --- guards, alive ------------------------------------------------------
	# Standing on top of one, which is as seen as it is possible to be.
	ghost.global_position = guards[0].global_position
	var eyes: Array = ghost._watchers()
	print("  standing on a live guard: %d of %d guards count as watchers" % [
		eyes.size(), guards.size()])
	_check_that(eyes.is_empty(), "a guard is never something it plays to")

	# --- guards, dead -------------------------------------------------------
	# Same question of a corpse. Guards are excluded by construction - they are
	# not on Net.players() at all - so this is really checking that killing one
	# does not somehow put it on a list it was never on.
	var corpse: Node2D = guards[0]
	corpse.take_damage(1000.0, corpse.global_position, Vector2.RIGHT)
	await physics_frame
	ghost.global_position = corpse.global_position
	eyes = ghost._watchers()
	print("  standing on a dead guard: %d watchers" % eyes.size())
	_check_that(eyes.is_empty(), "and a dead one even less so")

	# --- players, dead and downed -------------------------------------------
	# The player *is* on that list, so these are the ones a test has to hold.
	# Checked through _can_be_lured rather than by killing the only character in
	# a solo run, which would take the level down with it.
	print("  a live player: lured=%s" % ghost._can_be_lured(player))
	_check_that(ghost._can_be_lured(player), "a player on their feet is an audience")

	var was_down: bool = player.is_downed
	player.is_downed = true
	print("  a downed player: lured=%s" % ghost._can_be_lured(player))
	_check_that(not ghost._can_be_lured(player),
		"a man on the floor bleeding out is not worth baiting")
	player.is_downed = was_down

	var was_alive: bool = player.is_alive
	player.is_alive = false
	print("  a dead player: lured=%s" % ghost._can_be_lured(player))
	_check_that(not ghost._can_be_lured(player), "and neither is a dead one")
	player.is_alive = was_alive

	# And the sweep actually uses it: a downed rival must not appear as an eye.
	player.is_downed = true
	ghost.global_position = player.global_position
	eyes = ghost._watchers()
	print("  standing on a downed player: %d watchers" % eyes.size())
	_check_that(eyes.is_empty(), "so the sweep drops them too")
	player.is_downed = was_down

	ghost.queue_free()


## Q opens a pulled-back view, and a click on the level sends it there.## Q opens a pulled-back view, and a click on the level sends it there.
func _check_orders(main: Node, player: Node2D) -> void:
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var item: Object = maker.from_gadget(load(GADGET))
	item.charge = 1.0
	player.inventory.set_ultimate(item)

	# Q opens the view rather than casting. Nothing is spent by looking.
	player._use_ultimate()
	print("  Q: aiming=%s zoom scale=%.2f charge=%.2f" % [
		player.projection_aiming, player.projection_view_scale(), item.charge])
	_check_that(player.projection_aiming, "Q opens the placing view")
	_check_that(is_equal_approx(player.projection_view_scale(), 0.5),
		"and pulls the camera back to twice the world")
	_check_that(item.charge >= 1.0, "without spending anything yet")

	var input: Node = root.get_node("PlayerInput")
	_check_that(input.wants_cursor(), "with the pointer free to click with")

	# Somewhere it can actually walk to, so this measures the walk rather than
	# the level. Chosen the same way the other checks choose a direction.
	var space := player.get_world_2d().direct_space_state
	var eye: Vector2 = player.sight_centre()
	var open := -1.0
	for way in [-1.0, 1.0]:
		var query := PhysicsRayQueryParameters2D.create(eye, eye + Vector2(way * 420.0, 0.0))
		query.collision_mask = 1
		if space.intersect_ray(query).is_empty():
			open = way
			break
	var spot: Vector2 = player.global_position + Vector2(open * 420.0, 0.0)

	player._send_projection(spot)
	var ghost: Node2D = _the_ghost()
	_check_that(ghost != null, "clicking casts one")
	if ghost == null:
		return
	print("  clicked %s: destination=%s mind=%d aiming=%s charge=%.2f" % [
		str(spot), str(ghost.destination), ghost._mind, player.projection_aiming,
		item.charge])
	_check_that(not player.projection_aiming, "and closes the view")
	_check_that(ghost.destination.distance_to(spot) < 2.0, "sending it where you clicked")
	_check_that(ghost._mind == 0, "under orders rather than off baiting")
	_check_that(item.charge < 0.05, "and spends the charge at the click, not at the press")

	var start_x: float = ghost.global_position.x
	for i in 90:
		await physics_frame
		if not is_instance_valid(ghost):
			break
	var moved: float = (ghost.global_position.x - start_x) * open
	print("  travelled %.0f px towards it in 1.5s" % moved)
	_check_that(moved > 60.0, "and it has to actually set off")

	# Re-pointing a ghost already out costs nothing and goes through the same two
	# presses, which is the press people actually want: the cast happens while
	# you are being shot at.
	player._use_ultimate()
	_check_that(player.projection_aiming, "Q with one already out opens the view again")
	var elsewhere: Vector2 = player.global_position + Vector2(-open * 300.0, 0.0)
	var charge_before: float = item.charge
	player._send_projection(elsewhere)
	print("  re-sent: destination=%s (charge %.2f -> %.2f)" % [
		str(ghost.destination), charge_before, item.charge])
	_check_that(ghost.destination.distance_to(elsewhere) < 2.0, "a second click moves it")
	_check_that(item.charge <= charge_before + 0.01, "and does not cost another charge")

	# Backing out costs nothing either.
	player._use_ultimate()
	player._cancel_projection_aim()
	_check_that(not player.projection_aiming, "and the view can be closed again")
	_check_that(is_equal_approx(player.projection_view_scale(), 1.0),
		"putting the camera back")


## A click in mid-air is dropped to the floor under it.
##
## The normal case, not the exception: you are picking a *room* on a pulled-back
## view and the middle of a room is empty space. A projection walks, so a point
## in the air is not somewhere it can be sent at all.
func _check_snaps_to_ground(player: Node2D) -> void:
	var space := player.get_world_2d().direct_space_state
	# Somewhere with floor under it: straight up from the character, which is
	# standing on some, then well above.
	var high: Vector2 = player.global_position - Vector2(0.0, 300.0)
	var on_ground: Vector2 = player._ground_at(high)
	print("  a click %.0f px up came back at %.0f px up" % [
		player.global_position.y - high.y,
		player.global_position.y - on_ground.y])
	_check_that(on_ground.y > high.y, "a point in the air is dropped downwards")

	# And what it lands on is actually solid.
	var probe := PhysicsRayQueryParameters2D.create(
		on_ground, on_ground + Vector2(0.0, 90.0))
	probe.collision_mask = 3
	_check_that(not space.intersect_ray(probe).is_empty(),
		"onto something it can stand on")

	# A point already on the floor is left where it is, near enough.
	var standing: Vector2 = player._ground_at(player.global_position)
	print("  a click at the character's own feet moved %.0f px" % 
		standing.distance_to(player.global_position))
	_check_that(standing.distance_to(player.global_position) < 60.0,
		"and a point already on the ground barely moves")


## A destination on another floor has to be reached by rope, not stared at.
##
## The complaint was that the routing was bad: ends were picked by straight-line
## distance, so a cable running through the ceiling directly overhead measured as
## the nearest thing there was, and the ghost set off for a point it had no way
## of walking to, stood under it, and gave up.
func _check_routes_by_cable(main: Node, player: Node2D) -> void:
	var cables: Array = get_nodes_in_group(&"zipline")
	_check_that(not cables.is_empty(), "the level has cables to route through")
	if cables.is_empty():
		return
	var cable: Node2D = cables[0]
	for line in cables:
		if line.cable_length() > cable.cable_length():
			cable = line

	var ghost: Node2D = (load("res://scenes/projection.tscn") as PackedScene).instantiate()
	ghost.name = "Ghost_routeprobe"
	main.get_node("Players").add_child(ghost)

	# --- the end it gets on at has to be one it can walk to ------------------
	# Stood at the foot of the cable, both ends are candidates by distance and
	# only one of them is by height. This is the check that used to fail.
	ghost.global_position = cable.world_bottom()
	var ends: Array = ghost._ends_of(cable)
	print("  at the foot of %s: near end is %.0f px up, far end %.0f px up" % [
		cable.name,
		ghost.global_position.y - (ends[0] as Vector2).y,
		ghost.global_position.y - (ends[1] as Vector2).y])
	_check_that((ends[0] as Vector2).distance_to(cable.world_bottom()) < 1.0,
		"the end on this floor is the near one, whatever the straight line says")

	# --- and it rides it, all the way ---------------------------------------
	var up: Vector2 = cable.world_top()
	_check_that(ghost.order_to(up), "it takes the order")
	print("  sent %.0f px up, chose %s to ride" % [
		absf(up.y - ghost.global_position.y),
		ghost._leg_cable.name if ghost._leg_cable else "nothing"])
	_check_that(ghost._leg_cable != null, "and picks a cable to do it with")

	var rode := false
	var climbed := 0.0
	var from_y: float = ghost.global_position.y
	for i in 210:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		if ghost.riding:
			rode = true
		climbed = maxf(climbed, from_y - ghost.global_position.y)
	print("  rode it: %s, climbed %.0f of %.0f px" % [
		rode, climbed, absf(up.y - from_y)])
	_check_that(rode, "and actually rides it")
	_check_that(climbed > absf(up.y - from_y) * 0.7,
		"gaining most of the height it was sent to")

	# --- a destination that is not itself a cable end ------------------------
	# The real case: you click a spot on an upper floor, and getting there is a
	# walk, then a rope, then another walk. Riding to the top and stopping is not
	# arriving.
	ghost.global_position = cable.world_bottom()
	ghost.life_left = 90.0
	var along: Vector2 = cable.world_top() + Vector2(200.0, 0.0)
	_check_that(ghost.order_to(along), "sent to a spot on the upper floor")
	var best := INF
	for i in 240:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		best = minf(best, absf(ghost.global_position.y - along.y))
	print("  sent to a spot %.0f px along the top floor, got within %.0f px of its height"
		% [200.0, best])
	_check_that(best < 140.0,
		"a destination off the end of the rope still has to be reached")

	if is_instance_valid(ghost):
		ghost.queue_free()


## It should not spend its life bouncing off walls.## It should not spend its life bouncing off walls.## It should not spend its life bouncing off walls.
##
## The reported symptom was "jumps around a lot and runs into walls", which was
## two missing things rather than one: no cooldown between jumps, and no question
## asked about whether the obstacle could be cleared at all. Walking a body into
## a wall it cannot pass is the exact case that produced it.
func _check_not_jumpy(main: Node, player: Node2D) -> void:
	var ghost: Node2D = (load("res://scenes/projection.tscn") as PackedScene).instantiate()
	ghost.name = "Ghost_wallprobe"
	main.get_node("Players").add_child(ghost)
	ghost.global_position = player.global_position

	# Aim it at whichever side has solid geometry close by, so it is walking into
	# something it genuinely cannot get past.
	var space := player.get_world_2d().direct_space_state
	var eye: Vector2 = player.sight_centre()
	var into := 0
	for way in [1.0, -1.0]:
		var query := PhysicsRayQueryParameters2D.create(eye, eye + Vector2(way * 300.0, 0.0))
		query.collision_mask = 1
		if not space.intersect_ray(query).is_empty():
			into = int(way)
			break
	if into == 0:
		print("  no wall within reach of this spawn - skipped")
		ghost.queue_free()
		return

	# Sent straight through the wall, so it is walking at something it cannot
	# pass - which is the case that used to make it hop on the spot.
	var _sent: bool = ghost.order_to(
		ghost.global_position + Vector2(into * 600.0, 0.0))
	var jumps := 0
	var airborne := false
	for i in 180:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		var up: bool = not ghost.is_on_floor()
		if up and not airborne:
			jumps += 1
		airborne = up
	print("  walked into a wall for 3s and jumped %d times" % jumps)
	# A handful is fine - getting onto a crate, dropping off a lip. Thirty is the
	# bug: that is one per two frames, which is what no cooldown looks like.
	_check_that(jumps <= 8, "a ghost against a wall must not bounce on the spot")
	if is_instance_valid(ghost):
		ghost.queue_free()


## Runs physics frames until a condition holds, or gives up. Returns either way -
## the assert that follows is what reports the failure, with its own message.
func _wait_for(done: Callable, frames: int) -> void:
	for i in frames:
		if done.call():
			return
		await physics_frame


## This peer's own ghost, by name rather than by group.
##
## The group holds every projection in the level, including the throwaway probes
## the checks below build - and queue_free() is deferred, so a probe freed a line
## earlier is still in the group when the next section looks. Picking one out of
## the group therefore returned a probe with no orders on it, and "you can tell
## it where to go" failed against a body nobody had told anything.
func _the_ghost() -> Node2D:
	var net: Node = root.get_node("Net")
	return net.projection_for(net.peer_id()) as Node2D
