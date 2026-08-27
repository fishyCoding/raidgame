extends SceneTree

## The flash grenade, and the projection's death stutter.
##
## Two things that both happen on a *screen* rather than to a body, which is why
## they share a runner: neither is resolved by the host, neither is replicated,
## and both are checked by reading what the drawing code would actually draw.
##
## Nothing here names Grenade, Player or Projection - all three reach Net, and a
## --script tool that names one compiles it before the autoloads exist. See the
## headless-test notes.

const FLASH := "res://resources/gadgets/flash.tres"
const PROJECTION := "res://resources/gadgets/projection.tres"

## Checks are counted rather than asserted, and that is not a style preference.
## `assert()` inside a function called from _run unwinds only that function - the
## runner carries straight on to the next check and prints PASS at the end, so a
## broken build reports a clean run. Not hypothetical: the first version of this
## file failed four checks and still finished by printing PASS.
var _ok := true


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
	_check("there is a character to blind", player != null)
	if player == null:
		_finish()
		return

	print("-- a flash in your face --")
	await _check_close(main, player)

	print("\n-- and one behind a wall --")
	await _check_cover(main, player)

	print("\n-- and one across the room --")
	await _check_distance(main, player)

	print("\n-- it clears on its own --")
	await _check_fade(player)

	print("\n-- it takes the readouts with it --")
	_check_covers_hud(main, player)

	print("\n-- the ghost stutters out --")
	await _check_stutter(player)

	_finish()


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	print("  %s %s" % ["ok  " if ok else "FAIL", what])


func _finish() -> void:
	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


## A grenade going off on top of you whites the screen out.
func _check_close(main: Node, player: Node2D) -> void:
	_clear(player)
	var data: Resource = load(FLASH)
	_pop(main, player.global_position + Vector2(20.0, 0.0), data)
	await physics_frame

	print("  strength=%.2f left=%.2fs amount=%.2f" % [
		player.flash_strength, player.flash_left, player.flash_amount()])
	_check("a flash at your feet lands", player.flash_left > 0.0)
	_check("at close to full strength", player.flash_strength > 0.9)
	_check("whiting the screen out at once", player.flash_amount() > 0.9)
	_check("for the %.1fs the gadget says" % data.duration,
		is_equal_approx(player.flash_span, data.duration))


## A wall between you and it is the counterplay, and the only one.
func _check_cover(main: Node, player: Node2D) -> void:
	_clear(player)
	# Somewhere with solid geometry between. Found rather than assumed: the
	# insertion roll moves the character, so a hardcoded pair of points would be
	# testing a different question on every run.
	var space := player.get_world_2d().direct_space_state
	var eye: Vector2 = player.sight_centre()
	var beyond := Vector2.INF
	for step in [160.0, 240.0, 320.0, 400.0]:
		for way in [1.0, -1.0]:
			for lift in [0.0, -120.0, 120.0]:
				var spot := eye + Vector2(way * step, lift)
				var query := PhysicsRayQueryParameters2D.create(eye, spot)
				query.collision_mask = 1
				var hit := space.intersect_ray(query)
				if hit.is_empty():
					continue
				# Past the wall, not in it. Dropping the grenade on the hit point
				# puts it *inside* the collider, and a ray that starts inside a
				# shape does not report hitting that shape - so the flash read as
				# unobstructed and this check passed a bug on its first run.
				var dir: Vector2 = (spot - eye).normalized()
				beyond = (hit.position as Vector2) + dir * 90.0
				break
			if beyond.is_finite():
				break
		if beyond.is_finite():
			break

	if not beyond.is_finite():
		print("  no wall within reach of this spawn - skipped")
		return
	_pop(main, beyond, load(FLASH))
	await physics_frame
	print("  it went off %.0f px away, through a wall" % eye.distance_to(beyond))
	_check("a flash you could not see does not blind you",
		player.flash_amount() <= 0.0)


## Far enough away and it is a flicker, not a blinding.
func _check_distance(main: Node, player: Node2D) -> void:
	_clear(player)
	var data: Resource = load(FLASH)
	var reach: float = data.radius * 0.6
	var eye: Vector2 = player.sight_centre()
	var space := player.get_world_2d().direct_space_state

	# A clear line at that exact distance, in whatever direction the level
	# happens to offer one. The first version of this pointed straight up and
	# skipped whenever there was a ceiling - which on this map was every run, so
	# the falloff curve it exists to check was never once measured. A check that
	# always skips is a check that is not there.
	var far := Vector2.INF
	for step in 24:
		var angle := TAU * float(step) / 24.0
		var spot: Vector2 = eye + Vector2.RIGHT.rotated(angle) * reach
		var query := PhysicsRayQueryParameters2D.create(eye, spot)
		query.collision_mask = 1
		if space.intersect_ray(query).is_empty():
			far = spot
			break
	_check("the level has a clear line %.0f px long to test with" % reach,
		far.is_finite())
	if not far.is_finite():
		return

	_pop(main, far, data)
	await physics_frame
	print("  at %.0f px of a %.0f px radius: strength=%.2f" % [
		data.radius * 0.6, data.radius, player.flash_strength])
	# Both ends matter. Too little and the radius is decorative - the gadget
	# becomes a direct-hit weapon with a circle drawn round it for show. Too much
	# and there is no reason to ever throw it accurately.
	_check("one across the room still reaches you", player.flash_strength > 0.15)
	_check("but is nothing like one in your face", player.flash_strength < 0.6)


## Two seconds, and gone. That is the number the gadget promises.
func _check_fade(player: Node2D) -> void:
	_clear(player)
	player.flashed(1.0, 2.0)
	var readings: Array[float] = []
	for i in 150:
		await physics_frame
		if i % 30 == 0:
			readings.append(player.flash_amount())
		if player.flash_amount() <= 0.0:
			break
	print("  amount over time: %s" % str(readings))
	_check("it clears on its own", player.flash_left <= 0.0)
	_check("over long enough to be worth sampling", readings.size() > 2)
	_check("getting better rather than worse",
		readings[0] > readings[readings.size() - 1])

	# Held at full at the start rather than fading evenly from frame one. An even
	# fade is readable the whole way through, which makes a flash an inconvenience
	# you play through instead of a thing that costs you the fight.
	player.flashed(1.0, 2.0)
	await physics_frame
	var fresh: float = player.flash_amount()
	player.flash_left = 2.0 * 0.5
	var half: float = player.flash_amount()
	player.flash_left = 2.0 * 0.9
	var most: float = player.flash_amount()
	print("  90%% left=%.2f, 50%% left=%.2f, fresh=%.2f" % [most, half, fresh])
	_check("the first fifth is a total white-out", most >= 0.999)
	_check("and then it genuinely recovers", half < most * 0.8)


## Being blinded has to cost you the HUD as well, or it costs you nothing.
func _check_covers_hud(main: Node, player: Node2D) -> void:
	var hud: Control = main.get_node("HUD/WeaponHUD")
	var source: String = FileAccess.get_file_as_string("res://scripts/hud.gd")
	var draws := source.count("_draw_flash()")
	print("  the white-out is painted from %d places in hud.gd" % draws)
	# One per path out of the drawing code: the no-weapon early return, the
	# downed branch and the live branch. Miss one and a blinded player still
	# reads their ammo, their health and their ultimate meter off a white screen.
	_check("every path through the HUD paints it", draws >= 3)
	_check("and the HUD owns the drawing", hud.has_method(&"_draw_flash"))

	_clear(player)
	player.flashed(1.0, 2.0)
	_check("with the player deciding how white", player.flash_amount() > 0.9)

	# The part that matters, and the part the first version got wrong: some of
	# the screen has to be *gone*, not dimmed. A translucent wash over everything
	# is not being blinded, it is being mildly inconvenienced, and you could
	# still read the map through it.
	var span := hud.size.length() * 0.5
	var full: float = hud.flash_core_radius()
	print("  a point-blank flash blanks a %.0f px circle of a %.0f px half-screen"
		% [full, span])
	_check("a flash in your face takes the whole screen", full >= span)

	# And a partial one still has to take *something* completely, or the falloff
	# has quietly turned every non-perfect throw back into a wash.
	player.flash_left = 0.0
	player.flash_strength = 0.0
	player.flashed(0.35, 2.0)
	var part: float = hud.flash_core_radius()
	print("  a third-strength one blanks %.0f px" % part)
	_check("and a glancing one still blanks part of it", part > 60.0)
	_check("but not all of it", part < span)


## The ghost cuts in and out on the way out rather than fading.
func _check_stutter(player: Node2D) -> void:
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var item: Object = maker.from_gadget(load(PROJECTION))
	item.charge = 1.0
	player.inventory.set_ultimate(item)
	# Q opens the placing view; the click is what casts. Both halves, because
	# what this check is about is the body's death animation, not the control.
	player._use_ultimate()
	player._send_projection(player.global_position + Vector2(-300.0, 0.0))

	var ghost: Node2D = null
	for node in get_nodes_in_group(&"projection"):
		ghost = node as Node2D
	_check("there is a ghost to kill", ghost != null)
	if ghost == null:
		return

	var torso: Polygon2D = ghost.get_node("Body/Torso")
	ghost.hits = ghost.max_hits
	ghost._finish()
	_check("it knows it is going", ghost.dying_at > 0.0)

	# Watch the silhouette itself, not the node's alpha. The effect is that the
	# body is *not drawn* for whole slots at a time, and a check that only looked
	# at how visible it was on average would pass an ordinary alpha fade - which
	# is exactly what this replaced.
	var on := 0
	var off := 0
	var flips := 0
	var was := torso.visible
	for i in 90:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		if torso.visible:
			on += 1
		else:
			off += 1
		if torso.visible != was:
			flips += 1
			was = torso.visible
	print("  silhouette drawn %d frames, missing %d, flipped %d times" % [
		on, off, flips])
	_check("it actually disappears rather than fading", off > 0)
	_check("and comes back, rather than just being deleted", on > 0)
	_check("several times over - one blink is not a glitch", flips >= 4)
	_check("and is gone at the end of it", not is_instance_valid(ghost))


## Puts a live grenade at a spot and lets its fuse run out this frame.
func _pop(main: Node, at: Vector2, data: Resource) -> void:
	var nade: Node2D = (load("res://scenes/grenade.tscn") as PackedScene).instantiate()
	nade.setup(data, Vector2.ZERO, 4)
	nade.global_position = at
	# Straight to the bang. The arc is the throw's business and is covered by the
	# touch and throw checks; this is about what happens when it goes off.
	nade._fuse = 0.001
	main.get_node("Bullets").add_child(nade)
	nade.global_position = at


func _clear(player: Node2D) -> void:
	player.flash_left = 0.0
	player.flash_strength = 0.0
