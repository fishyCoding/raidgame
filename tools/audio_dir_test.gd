extends SceneTree

## Sound is panned from the character's head, not from the lens.
##
##   godot --headless --path . --script res://tools/audio_dir_test.gd
##
## Without an AudioListener2D, Godot pans an AudioStreamPlayer2D against the
## current Camera2D - and this camera leans a long way down range while aiming,
## by ads_lead_fraction * the weapon's ads_lead_scale of a half-screen. A shot at
## your own feet was arriving from one side. The Ear node fixes that, and this
## measures how much error it was worth.

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
	var audio: Node = root.get_node("Audio")
	print("-- the output --")
	print("  %s, %s, %d channel pair(s)" % [
			AudioServer.get_driver_name(), audio.speaker_layout(),
			AudioServer.get_bus_channels(0)])

	print("\n-- the listener --")
	var ear := player.get_node("Ear") as AudioListener2D
	var listening: Node = player.get_viewport().get_audio_listener_2d()
	print("  viewport listener: %s" % (listening.get_path() if listening else "NONE (the camera)"))
	_check("the ear is the listener", listening == ear)
	_check("and it is current", ear.is_current())
	_check("it sits on the character", ear.global_position.distance_to(player.global_position) < 40.0)

	print("\n-- what it was worth --")
	# Scoped with the longest-leaning sight in the game.
	var sniper: Resource = load("res://resources/weapons/sniper.tres")
	player.weapon.inventory.set_slot(0, load("res://scripts/item.gd").from_weapon(sniper))
	player.weapon.equip_data(sniper)
	player._aim_reach = Vector2(220, 0)
	input.touch_aim_held = true
	for i in 90:
		await physics_frame
	var camera: Camera2D = player.get_node("Camera2D")
	var lean := camera.get_screen_center_position().distance_to(player.global_position)
	print("  scoped with the %s, the camera is %.0f px off the body" % [
			sniper.short_name, lean])
	print("  the ear is %.0f px off it" % ear.global_position.distance_to(player.global_position))
	_check("the camera really does lean far enough to matter", lean > 150.0)
	_check("the ear does not move with it",
			ear.global_position.distance_to(player.global_position) < 40.0)
	input.touch_aim_held = false

	print("\n-- panning --")
	var strength: float = ProjectSettings.get_setting("audio/general/2d_panning_strength")
	print("  project %.2f x node %.2f = %.2f effective" % [
			strength, audio.PANNING, strength * audio.PANNING])
	_check("panning is the number audio.gd thinks it is",
			absf(strength * audio.PANNING - audio.PANNING) < 0.001)

	if _failures > 0:
		print("\naudio_dir | %d FAILED" % _failures)
		quit(1)
		return
	print("\naudio_dir | PASS")
	quit()


func _check(what: String, passed: bool) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures += 1
	print("  FAIL %s" % what)
