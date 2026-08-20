extends SceneTree

## Shooting with your feet off the ground.
##
##   godot --headless --path . --script res://tools/air_spread_test.gd
##
## Jumping is a way of being hard to hit. It has to cost the shot, or it is free
## - so the cone opens the moment your boots leave, aiming buys back much less of
## it than it does on the ground, and it settles again after you land rather than
## snapping back on the frame you touch.

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var input: Node = root.get_node("PlayerInput")
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
	for i in 40:
		await physics_frame

	var player: Node2D = net.local_player
	if player == null or not player.is_on_floor():
		print("air | never landed anywhere to test from (on_floor=%s)" % player.is_on_floor())
		quit(1)
		return

	print("-- on the ground --")
	var ground := _cone(player)
	print("  hip:    %.2f deg" % ground)
	_check("a cone at rest", ground > 0.0)

	input.touch_aim_held = true
	for i in 24:
		await physics_frame
	var ground_ads := _cone(player)
	print("  scoped: %.2f deg  (focus %.2f)" % [ground_ads, player.focus])
	_check("a sight tightens it", ground_ads < ground)

	print("
-- scoped, and jumping anyway --")
	# Aimed *before* the jump, so focus is already up and the only thing that
	# changed is the ground leaving.
	input.touch_jump_pressed = true
	await physics_frame
	for i in 8:
		await physics_frame
	var air_ads := _cone(player)
	print("  on_floor=%s  air factor=%.2f  focus=%.2f" % [
			player.is_on_floor(), player._get_air_factor(), player.focus])
	print("  scoped: %.2f deg  (%.1fx the scoped cone on the ground)" % [
			air_ads, air_ads / maxf(ground_ads, 0.001)])
	_check("both feet off the ground", not player.is_on_floor())
	_check("the penalty is on at once", player._get_air_factor() >= 1.0)
	_check("a sight does not buy this one back", air_ads > ground_ads * 2.0)
	input.touch_aim_held = false

	# Down, settled, and unaimed again before anything else is measured.
	await _grounded(player)
	for i in 60:
		await physics_frame
	_check("back where it started before the next test",
			absf(_cone(player) - ground) < 0.05)

	print("
-- from the hip, jumping --")
	input.touch_jump_pressed = true
	await physics_frame
	for i in 8:
		await physics_frame
	var air := _cone(player)
	print("  hip:    %.2f deg  (%.1fx the standing cone)" % [
			air, air / maxf(ground, 0.001)])
	_check("a lot wider, not a little", air > ground * 2.0)

	print("
-- landing --")
	var frames := await _grounded(player)
	var landed := _cone(player)
	print("  %.2f deg on the frame the boots touched, after %d frames in the air" % [
			landed, frames])
	_check("landing does not hand the shot straight back", landed > ground * 1.5)

	var settle: float = player.air_settle_time
	for i in int(settle * 60.0) + 10:
		await physics_frame
	var settled := _cone(player)
	print("  %.2f deg %.1fs later" % [settled, settle])
	_check("and then it settles back to where it was", absf(settled - ground) < 0.05)
	_check("with the factor spent", player._get_air_factor() <= 0.001)

	if _failures > 0:
		print("
air | %d FAILED" % _failures)
		quit(1)
		return
	print("
air | PASS")
	quit()


## Waits for the boots to touch, and says how many frames it took.
func _grounded(player: Node2D) -> int:
	var frames := 0
	while not player.is_on_floor() and frames < 300:
		await physics_frame
		frames += 1
	return frames


## The cone the gun would actually fire into right now, in degrees.
func _cone(player: Node2D) -> float:
	return rad_to_deg(player.weapon.get_spread(
			player._get_move_factor(), player._get_air_factor()))


func _check(what: String, passed: bool) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures += 1
	print("  FAIL %s" % what)
