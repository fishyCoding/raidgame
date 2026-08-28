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
	var from: Vector2 = player.global_position
	await _swipe(Vector2(-1.0, 0.0))
	var went: float = from.x - player.global_position.x
	# Well past what walking covers in the same time - about 67 px at the
	# character's own top speed. A "dash" you could have walked is not one.
	print("-- swiped left on the ground: travelled %.0f px, %d dashes left" % [
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
	await _swipe(Vector2(1.0, 0.0))
	var air_went: float = player.global_position.x - air_from.x
	print("-- swiped right in mid-air: travelled %.0f px, %d dashes left" % [
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
