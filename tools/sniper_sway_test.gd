extends SceneTree

## The scope wanders, and only the scoped rifle's does.
##
##   godot --headless --path . --script res://tools/sniper_sway_test.gd
##
## Sway is measured as the gap between the angle the player is steering
## (_aim_base) and the angle the gun is actually pointing (aim_angle), with the
## trigger untouched so recoil kick is not in the picture. Nothing drives the
## aim during the sample, so anything that moves is the wander.

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
		print("sway | never got a character")
		quit(1)
		return

	var sniper: Resource = load("res://resources/weapons/sniper.tres")
	var rifle: Resource = load("res://resources/weapons/assault_rifle.tres")
	print("-- the sniper, scoped --")
	print("  ads_sway=%.2f deg at %.2f Hz, aim_speed_scale=%.2f" % [
			sniper.ads_sway, sniper.ads_sway_speed, sniper.aim_speed_scale])
	_check("the sniper has a wander to it", sniper.ads_sway > 0.0)
	_check("and it is a slight one", sniper.ads_sway <= 3.0)

	var scoped := await _sample(player, input, sniper)
	print("  scoped:  peak %.2f deg, %d reversals over 3s" % [scoped.peak, scoped.turns])
	# What the wander is actually worth: how far off the point of aim ends up at
	# the range this gun is for. A character is 48 px tall.
	print("  which is %.0f px either side at %d px - about %.1f bodies" % [
			tan(deg_to_rad(scoped.peak)) * sniper.falloff_start, sniper.falloff_start,
			tan(deg_to_rad(scoped.peak)) * sniper.falloff_start / 48.0])
	_check("the sight wanders while scoped",
			scoped.peak > sniper.ads_sway * 0.5)
	_check("by about the amount asked for, not more",
			scoped.peak <= sniper.ads_sway + 0.1)
	_check("and it wanders rather than drifting off",
			scoped.turns >= 2)

	print("\n-- the sniper, from the hip --")
	var hip := await _sample(player, input, sniper, false)
	print("  hip:     peak %.2f deg" % hip.peak)
	_check("an unscoped gun does not sway", hip.peak < 0.01)

	print("\n-- the assault rifle, scoped --")
	print("  ads_sway=%.2f" % rifle.ads_sway)
	var other := await _sample(player, input, rifle)
	print("  scoped:  peak %.2f deg" % other.peak)
	_check("nothing else was given a wander", other.peak < 0.01)

	if _failures > 0:
		print("\nsway | %d FAILED" % _failures)
		quit(1)
		return
	print("\nsway | PASS")
	quit()


## Three seconds of a gun held still, as {peak, turns}: the furthest the muzzle
## strayed from where it was pointed, and how many times it changed direction.
func _sample(player: Node2D, input: Node, data: Resource, scoped := true) -> Dictionary:
	# Put it in his hands first - equip_data only reaches for guns he is already
	# carrying. Loaded by path rather than named: a --script tool compiles before
	# the autoloads are script globals, and naming a class here compiles its file
	# too early. PRIMARY is Inventory.Slot 0.
	var item: RefCounted = load("res://scripts/item.gd").from_weapon(data)
	player.weapon.inventory.set_slot(0, item)
	if not player.weapon.equip_data(data):
		_failures += 1
		print("  FAIL could not put the %s in his hands" % data.short_name)
	input.touch_aim_held = scoped
	# Let the sight come up (ads_time * ads_speed_scale) before measuring.
	for i in 40:
		await physics_frame

	print("    holding %s, focus %.2f" % [
			player.weapon.data.short_name if player.weapon.data else "NONE", player.focus])
	var peak := 0.0
	var turns := 0
	var last := 0.0
	var rising := true
	for i in 180:
		await physics_frame
		var off: float = rad_to_deg(wrapf(player.aim_angle - player._aim_base, -PI, PI))
		peak = maxf(peak, absf(off))
		if i > 0 and (off > last) != rising:
			rising = off > last
			turns += 1
		last = off
	input.touch_aim_held = false
	for i in 30:
		await physics_frame
	return {"peak": peak, "turns": turns}


func _check(what: String, passed: bool) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures += 1
	print("  FAIL %s" % what)
