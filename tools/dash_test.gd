extends SceneTree

## The dash ultimate: two of them, spent by swiping, and usable in mid-air.
##
## Driven through the swipe path rather than by calling the dash directly. The
## question worth asking is whether a gesture moves the character, and a test
## that pokes _update_dash would pass just as happily with the input unwired.

const DASH := "res://resources/gadgets/dash.tres"

var _ok := true
## Reached through the tree, not by name: a --script tool compiles without the
## autoloads, so naming PlayerInput fails the whole file.
var _input: Node


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
	var screen: Node = get_first_node_in_group(&"map_screen")
	if screen:
		screen.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	_input = root.get_node("PlayerInput")
	var player: Node2D = net.local_player
	if player == null:
		print("no character - cannot run")
		quit(1)
		return
	for guard in main.get_node("Enemies").get_children():
		guard.set_physics_process(false)
		guard.set_process(false)

	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var ult: Object = maker.from_gadget(load(DASH))
	ult.charge = 1.0
	player.inventory.set_ultimate(ult)

	# --- casting hands you the dashes ----------------------------------------
	player._use_ultimate()
	await physics_frame
	print("-- cast: %d dashes, charge %.2f" % [player.dashes_left, ult.charge])
	_check(player.dashes_left == 2, "casting it gives you two dashes")
	_check(ult.charge < 1.0, "and spends the meter")

	# --- a swipe moves you ---------------------------------------------------
	while not player.is_on_floor():
		await physics_frame
	# Whichever way has room. The spawn is not fixed between runs, and dashing at
	# a wall measures the wall - an earlier version of this failed at one spawn
	# and passed at another with the code identical.
	var way := _open_way(player)
	var from: Vector2 = player.global_position
	await _swipe(Vector2(way, 0.0))
	var went: float = (player.global_position.x - from.x) * way
	# Well past what walking covers in the same time - about 67 px at the
	# character's own top speed. A "dash" you could have walked is not one.
	print("-- swiped along a clear floor: travelled %.0f px, %d dashes left" % [
		went, player.dashes_left])
	_check(went > 140.0, "a swipe has to actually throw you across the ground")
	_check(player.dashes_left == 1, "and cost one of the two")

	# --- and works with nothing under you ------------------------------------
	#
	# The point of the gadget. Being airborne is when you most want to be
	# somewhere else, because it is when you have least say in where you go.
	player.velocity = Vector2(0.0, -260.0)
	for i in 6:
		await physics_frame
	_check(not player.is_on_floor(), "the character is genuinely airborne for this")
	var air_from: Vector2 = player.global_position
	var air_way := _open_way(player)
	await _swipe(Vector2(air_way, 0.0))
	var air_went: float = (player.global_position.x - air_from.x) * air_way
	print("-- swiped in mid-air: travelled %.0f px, %d dashes left" % [
		air_went, player.dashes_left])
	_check(air_went > 90.0, "a dash in mid-air has to work")
	_check(player.dashes_left == 0, "and spend the last one")

	# --- and then there are none ---------------------------------------------
	while not player.is_on_floor():
		await physics_frame
	# Settled first. A dash leaves you travelling at nearly a thousand pixels a
	# second and the ground takes a moment to take that off you - measuring
	# straight after landing measures the last dash, not this swipe.
	for i in 40:
		await physics_frame
	var spent_from: Vector2 = player.global_position
	await _swipe(Vector2(1.0, 0.0))
	var after: float = absf(player.global_position.x - spent_from.x)
	print("-- swiped with none left: moved %.0f px" % after)
	_check(after < 60.0, "swiping with no dashes left must do nothing")

	# --- a dash does not drag your aim with it -------------------------------
	#
	# The gesture that starts a dash is a flick of the mouse or a thumb across
	# the glass, and both of those are also how you aim. Without this the dash
	# threw your view across the room along with your body, which is the thing it
	# was most complained about.
	ult.charge = 1.0
	player._use_ultimate()
	while not player.is_on_floor():
		await physics_frame
	_input.touch_dash = true
	_input.touch_dash_way = Vector2(1.0, 0.0)
	await physics_frame
	_check(player.is_dashing(), "the dash is actually running for this check")
	var facing_before: Vector2 = player.aim_direction
	_input.add_aim_motion(Vector2(600.0, -400.0))
	await physics_frame
	await physics_frame
	var swung: float = facing_before.angle_to(player.aim_direction)
	print("-- aim moved %.3f rad during the dash" % absf(swung))
	_check(absf(swung) < 0.02, "aiming has to be frozen while dashing")

	# --- the pad turns a drag into a swipe -----------------------------------
	var pad: Control = main.get_node("HUD/TouchControls")
	_input.touch_dash = false
	pad._swipes[9] = {"from": Vector2(200.0, 400.0), "at": Time.get_ticks_msec()}
	pad._watch_for_swipe(9, Vector2(200.0 + pad.SWIPE_MIN + 40.0, 400.0))
	print("-- pad saw a swipe: %s toward %s" % [
		_input.touch_dash, str(_input.touch_dash_way)])
	_check(_input.touch_dash, "a fast drag on the pad has to read as a swipe")
	_check(_input.touch_dash_way.x > 0.8, "and know which way it went")

	# A slow one must not. Same distance, taken too long over.
	_input.touch_dash = false
	pad._swipes[9] = {"from": Vector2(200.0, 400.0),
		"at": Time.get_ticks_msec() - pad.SWIPE_MS - 200}
	pad._watch_for_swipe(9, Vector2(200.0 + pad.SWIPE_MIN + 40.0, 400.0))
	_check(not _input.touch_dash, "but a slow drag over the same ground must not")

	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


## Which way there is room to dash, as -1 or 1.
##
## Asked of the level rather than assumed, because the spawn moves between runs
## and a dash into a wall is a measurement of the wall.
func _open_way(player: Node2D) -> float:
	var space := player.get_world_2d().direct_space_state
	var best := 1.0
	var best_room := -1.0
	for way in [1.0, -1.0]:
		var from: Vector2 = player.global_position - Vector2(0.0, 14.0)
		var probe := PhysicsRayQueryParameters2D.create(
			from, from + Vector2(way * 420.0, 0.0))
		probe.collision_mask = Layers.WORLD
		var hit := space.intersect_ray(probe)
		var room: float = 420.0 if hit.is_empty() else from.distance_to(hit.position)
		if room > best_room:
			best_room = room
			best = way
	return best


## One swipe, and the frames for it to play out.
func _swipe(way: Vector2) -> void:
	_input.touch_dash = true
	_input.touch_dash_way = way
	for i in 18:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("  FAIL  %s" % what)
	else:
		print("  ok    %s" % what)
