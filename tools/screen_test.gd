extends SceneTree

## The screen: a sheet that shows you the room without the people in it.
##
## What is worth checking is the set of things it does *not* do. Blocking sight
## is easy; blocking sight without becoming a wall, without muffling anything,
## and without surviving contact is the actual gadget.

var _ok := true
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
	var screen_ui: Node = get_first_node_in_group(&"map_screen")
	if screen_ui:
		screen_ui.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("no character - cannot run")
		quit(1)
		return
	_input = root.get_node("PlayerInput")

	# --- guards are off for testing ------------------------------------------
	var left := main.get_node("Enemies").get_child_count()
	print("-- guards still in the level: %d" % left)
	_check(left == 0, "the guards are off, as asked")

	# --- a screen goes up, anchored ------------------------------------------
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var ult: Object = maker.from_gadget(load("res://resources/gadgets/screen.tres"))
	ult.charge = 1.0
	player.inventory.set_ultimate(ult, 0)
	player.global_position = Vector2(-1051.0, 360.0)
	for i in 20:
		await physics_frame

	var raised: bool = player._raise_screen(ult.gadget)
	await physics_frame
	var sheets := get_nodes_in_group(&"screen")
	print("-- raised=%s, screens in the world: %d" % [raised, sheets.size()])
	_check(raised and sheets.size() == 1, "casting it puts a screen up")
	if sheets.is_empty():
		_finish()
		return

	var sheet: Node2D = sheets[0]
	var span: float = (sheet._from as Vector2).distance_to(sheet._to)
	var cap: float = ult.gadget.reach_in_heights * player.size.y
	print("-- it spans %.0f px, the cap is %.0f" % [span, cap])
	_check(span <= cap + 1.0, "and never longer than its reach allows")
	_check(span > player.size.y * 0.5, "but long enough to hide behind")

	# --- it hides bodies -----------------------------------------------------
	var across: Vector2 = (sheet._from + sheet._to) * 0.5
	var one := across + Vector2(-240.0, 0.0)
	var two := across + Vector2(240.0, 0.0)
	var sheets_script: GDScript = load("res://scripts/screen.gd")
	print("-- across it: %s, along one side: %s" % [
		sheets_script.blocks_sight(self, one, two),
		sheets_script.blocks_sight(self, one, one + Vector2(-100.0, 0.0))])
	_check(sheets_script.blocks_sight(self, one, two),
		"a line of sight through it is broken")
	_check(not sheets_script.blocks_sight(self, one, one + Vector2(-100.0, 0.0)),
		"and a line that never crosses it is not")

	# --- it is not a wall ----------------------------------------------------
	#
	# The level behind it has to look exactly as it did. Sight against world
	# geometry is a separate mask, and a screen must be absent from it or it
	# would darken the room it is pretending is empty.
	var vision: Node = get_first_node_in_group(&"vision")
	var mask: int = vision.SIGHT_MASK if vision else load(
		"res://scripts/vision_system.gd").SIGHT_MASK
	print("-- sight mask %d, screen bit %d" % [mask, Layers.SCREEN])
	_check((mask & Layers.SCREEN) == 0,
		"a screen is not in the world-geometry sight mask")

	# --- and it does not stop sound ------------------------------------------
	#
	# Checked at the source: occlusion in this game is not raycast, so the
	# guarantee is that nothing in the audio path consults a collision mask at
	# all. If that ever changes this is the check that should fail.
	var audio_src := FileAccess.get_file_as_string("res://scripts/audio.gd")
	print("-- audio consults a collision mask: %s" % audio_src.contains("collision_mask"))
	_check(not audio_src.contains("collision_mask"),
		"sound is not occluded by anything, screens included")

	# --- one hit and it is gone ----------------------------------------------
	sheet.take_damage(10.0, across, Vector2.RIGHT)
	await physics_frame
	await physics_frame
	var after := get_nodes_in_group(&"screen").size()
	print("-- after one hit, screens left: %d" % after)
	_check(after == 0, "a single hit takes it down")

	_finish()


func _finish() -> void:
	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("  FAIL  %s" % what)
	else:
		print("  ok    %s" % what)
