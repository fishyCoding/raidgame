extends SceneTree

## How far a scoped sniper can actually SEE down its own sightline while fully
## aimed, versus how far its rounds actually reach (WeaponData.bullet_range).
##
## Reported: a big scope lets you watch a target the gun cannot touch - the
## round vanishes with no impact partway there, which reads as a networking
## bug rather than as running out of range.
##
##   godot --headless --path . --script res://tools/scope_range_probe.gd

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
	for i in 10:
		await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("FAILED: never got a character")
		quit(1)
		return

	var gun_path := "res://resources/weapons/sniper.tres"
	var scope_path := "res://resources/attachments/sniper_scope.tres"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gun="):
			gun_path = "res://resources/weapons/%s.tres" % arg.get_slice("=", 1)
		elif arg.begins_with("--scope="):
			scope_path = "res://resources/attachments/%s.tres" % arg.get_slice("=", 1)

	# Give it a gun with the scope on, the same object shape the gunsmith would
	# produce, then hold it fully aimed (focus = 1.0).
	var sniper_data: Resource = load(gun_path)
	var scope_data: Resource = load(scope_path)
	var item_script: GDScript = load("res://scripts/item.gd")
	var item: RefCounted = item_script.from_weapon(sniper_data)
	item.parts.append(scope_data)
	item.rebuild()

	var weapon: Node = player.weapon
	weapon.inventory.primary = item
	weapon.equip(0, true)  # Inventory.Slot.PRIMARY

	# focus is a ramp driven every physics frame off the real aim input
	# (Player._update_focus), so it has to be held down rather than poked once -
	# a one-time player.set("focus", 1.0) gets walked straight back to 0 on the
	# next frame.
	Input.action_press(&"aim")
	for i in 180:
		await physics_frame

	var zoom: float = player.get_camera_zoom()
	var half: Vector2 = root.get_visible_rect().size * 0.5 / zoom
	var lead: Vector2 = player.call("_get_lead_offset")
	var straight_ahead: float = lead.length() + half.x

	print("focus %.2f  weapon.data.ads_zoom %.4f" % [player.focus, weapon.data.ads_zoom])
	print("viewport %s  camera zoom %.4f" % [root.get_visible_rect().size, zoom])
	print("half-screen at this zoom: %s px" % half)
	print("camera lean while aimed: %s px" % lead)
	print("visible straight down the sightline: %.0f px" % straight_ahead)
	print("weapon.data.bullet_range: %.0f px" % weapon.data.bullet_range)
	print("gap (visible - reach): %.0f px" % (straight_ahead - weapon.data.bullet_range))

	quit()
