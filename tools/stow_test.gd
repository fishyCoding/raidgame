extends SceneTree

## Both hands go on the rope, and the gun costs a draw to get back.
##
##   godot --headless --path . --script res://tools/stow_test.gd
##
## The point of the feature is the bill at the far end, so that is what this
## measures: that nothing fires while you are on a cable or a hook, that the
## trigger stays dead for the weapon's own equip time after you step off, and
## that the arm has finished coming up on the frame it starts working again.

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
	await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("stow | never got a character")
		quit(1)
		return

	print("-- hooks --")
	print("  %d charge, %.0fs back" % [player.grapple_charges, player.grapple_recharge])
	_check("only one hook", player.grapple_charges == 1)
	_check("and it is slow coming back", player.grapple_recharge >= 25.0)
	_check("starting the raid with it", player.grapple_left == 1)

	print("\n-- on a cable --")
	var cable: Node2D = main.get_node("Ziplines/ZipYard")
	player.global_position = cable.world_top()
	await physics_frame
	print("  gun up:   stow=%.2f  can fire=%s" % [player.stow, not player.weapon.is_equipping()])
	_check("the gun is up before you touch anything", player.stow < 0.01)

	input.touch_interact_pressed = true
	await physics_frame
	_check("grabbed the cable", player.riding)
	_check("and the gun went away at once", player.weapon.is_equipping())
	_check("stowed says so", player.stowed)

	# Long enough for the put-away to finish, short enough to still be riding.
	for i in 20:
		await physics_frame
	print("  riding:   stow=%.2f  arm=%.0f deg  can fire=%s" % [
			player.stow, rad_to_deg(player._arm.rotation),
			not player.weapon.is_equipping()])
	_check("the gun is fully slung", player.stow > 0.99)
	_check("the arm moved with it", absf(player._arm.rotation) > 0.1)
	_check("still nothing fires", player.weapon.is_equipping())
	# The crosshair rides the muzzle rather than the aim, so it goes down with
	# the gun instead of hanging in the air where the gun is not.
	var swung := absf(angle_difference(player.gun_angle, player.aim_angle))
	var off_gun: float = player._reticle.global_position.angle_to_point(
			player.global_position)
	print("  crosshair: gun %.0f deg off the aim, sitting %.0f deg off the body, alpha %.2f" % [
			rad_to_deg(swung), rad_to_deg(absf(angle_difference(off_gun + PI, player.gun_angle))),
			player._reticle.modulate.a])
	_check("the gun is swung well off the aim", swung > 0.5)
	_check("the crosshair is gone on the rope", player._reticle.modulate.a <= 0.001)
	_check("the aim line went with it", player._aim_line.modulate.a <= 0.001)
	# Still tracking underneath, so it has somewhere to fade back in to rather
	# than popping in wherever it was left.
	_check("but it is still following the gun underneath",
			absf(angle_difference(off_gun + PI, player.gun_angle)) < 0.05)

	print("\n-- stepping off --")
	var draw_time: float = player.weapon.data.get_equip_time()
	input.touch_interact_pressed = true
	await physics_frame
	_check("off the cable", not player.riding)
	_check("but still not holding it", player.weapon.is_equipping())

	# Watched frame by frame, because the whole point of the change is that the
	# two used to finish on different ones.
	var frames := 0
	var stow_when_ready := -1.0
	var fired_early := false
	var fade: Array[float] = []
	while frames < 600:
		await physics_frame
		frames += 1
		fade.append(player._reticle.modulate.a)
		if not player.weapon.is_equipping():
			stow_when_ready = player.stow
			break
		if player.stow <= 0.0:
			fired_early = true
	var took := frames * (1.0 / 60.0)
	print("  draw took %.2fs, the %s wants %.2fs; stow=%.3f the frame it came back" % [
			took, player.weapon.data.short_name, draw_time, stow_when_ready])
	_check("the draw cost the weapon's own equip time",
			absf(took - draw_time) < 0.09)
	_check("the gun came back with the arm all the way up, not before",
			stow_when_ready == 0.0)
	_check("and it never sat finished-but-still-locked", not fired_early)

	# The fade: up from nothing, in step, and full by the time the gun works.
	var climbing := true
	for i in range(1, fade.size()):
		if fade[i] < fade[i - 1] - 0.001:
			climbing = false
	print("  crosshair faded %.2f -> %.2f over %d frames" % [
			fade[0], fade[fade.size() - 1], fade.size()])
	_check("it starts out of sight", fade[0] < 0.35)
	_check("it only ever comes in, never flickers back out", climbing)
	_check("and it is all the way in when the gun works",
			fade[fade.size() - 1] > 0.99)
	_check("more than one frame of it, so it reads as a fade", fade.size() > 4)

	for i in 20:
		await physics_frame
	_check("the gun is all the way up", player.stow < 0.01)
	_check("and works again", not player.weapon.is_equipping())
	_check("the crosshair is back on the aim",
			absf(angle_difference(player.gun_angle, player.aim_angle)) < 0.001)
	_check("and fully up", player._reticle.modulate.a > 0.99)

	print("\n-- on the hook --")
	player.global_position = Vector2(-1500, 0)
	await physics_frame
	input.touch_grapple_pressed = true
	await physics_frame
	print("  hook out: stowed=%s  hooks left=%d" % [player.stowed, player.grapple_left])
	_check("throwing it puts the gun away", player.stowed)
	_check("and it cost the only hook", player.grapple_left == 0)
	_check("with a wait on the next one", player.grapple_recharge_left() >= 24.0)

	if _failures > 0:
		print("\nstow | %d FAILED" % _failures)
		quit(1)
		return
	print("\nstow | PASS")
	quit()


func _check(what: String, passed: bool) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures += 1
	print("  FAIL %s" % what)
