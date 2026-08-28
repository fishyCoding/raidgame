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

	_check_ropes(self)

	# --- a screen goes up, anchored ------------------------------------------
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var ult: Object = maker.from_gadget(load("res://resources/gadgets/screen.tres"))
	ult.charge = 1.0
	player.inventory.set_ultimate(ult, 0)
	player.global_position = Vector2(-1051.0, 360.0)
	for i in 20:
		await physics_frame

	# Placed the way a person places one: open the view, click one end, click the
	# other. Driven through the real input edges rather than by calling the
	# placement directly - "two clicks make a screen" is the feature, and a test
	# that hands the function two points would pass with the clicks unwired.
	# Opened by pressing the key, not by calling the function. That distinction
	# is the whole of the last bug: the view treats a press of this button as
	# "put it away", so opening it from inside that press shut it again in the
	# same frame - and a test that called _use_ultimate directly never saw the
	# edge and passed happily while the gadget did not work at all.
	Input.action_press(&"ultimate")
	await physics_frame
	Input.action_release(&"ultimate")
	await physics_frame
	await physics_frame
	_check(player.screen_aiming, "pressing the ultimate opens the placing view")
	_check(ult.charge >= 1.0, "and looking at it costs nothing yet")

	# Aimed by setting the crosshair's own offset, not by writing
	# PlayerInput.touch_aim_point. The touch pad rewrites that field every frame
	# it processes, so a harness that sets it is quietly overruled - which is
	# exactly what happened here: the click landed somewhere else entirely.
	# And it stays open across frames rather than closing itself.
	for i in 10:
		await physics_frame
	_check(player.screen_aiming, "and it stays open")

	var anchor: Vector2 = player.global_position + Vector2(90.0, -20.0)
	_aim_at(player, anchor)
	await physics_frame
	await _click()
	print("-- first end at %s" % str(player.screen_first.round()))
	_check(player.screen_first.is_finite(), "the first click sets one end")

	# Further than the leash allows, to prove it is held rather than refused.
	_aim_at(player, anchor + Vector2(0.0, -900.0))
	await physics_frame
	var span: float = player.screen_first.distance_to(player.screen_to)
	var cap: float = player.SCREEN_REACH * player.size.y
	print("-- dragged 900 px away, the sheet is %.0f px (cap %.0f)" % [span, cap])
	_check(span <= cap + 1.0, "and the second end is held to the leash")

	_aim_at(player, anchor + Vector2(0.0, -200.0))
	await physics_frame
	await _click()
	var raised: bool = not player.screen_aiming
	await physics_frame
	var sheets := get_nodes_in_group(&"screen")
	print("-- raised=%s, screens in the world: %d" % [raised, sheets.size()])
	_check(raised and sheets.size() == 1, "casting it puts a screen up")
	if sheets.is_empty():
		_finish()
		return

	var sheet: Node2D = sheets[0]
	var sheet_from: Vector2 = sheet._from
	var sheet_to: Vector2 = sheet._to
	var made: float = (sheet._from as Vector2).distance_to(sheet._to)
	print("-- the sheet that went up spans %.0f px" % made)
	_check(made <= cap + 1.0, "and never longer than its reach allows")
	_check(made > player.size.y * 0.5, "but long enough to hide behind")
	_check(ult.charge < 1.0, "setting it is what spends the meter")

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

	# --- the click that sets it must not also shoot it -----------------------
	#
	# A view closes on the press, so on the very next frame the button is not
	# "just pressed" any more, it is held - and a held trigger fires. The click
	# that set a screen down was therefore also the shot that destroyed it.
	#
	# Held across several frames here, the way a real finger holds a mouse
	# button, because releasing it inside one frame is precisely what hid this.
	sheet.take_damage(1.0, mid_of(sheet), Vector2.RIGHT)
	await physics_frame
	ult.charge = 1.0
	Input.action_press(&"ultimate")
	await physics_frame
	Input.action_release(&"ultimate")
	for i in 3:
		await physics_frame
	_aim_at(player, player.global_position + Vector2(80.0, -20.0))
	await physics_frame
	Input.action_press(&"fire")
	await physics_frame
	Input.action_release(&"fire")
	await physics_frame
	_aim_at(player, player.global_position + Vector2(80.0, -220.0))
	await physics_frame

	# The finger goes down and stays down.
	var rounds_before := main.get_node("Bullets").get_child_count()
	Input.action_press(&"fire")
	for i in 20:
		await physics_frame
	Input.action_release(&"fire")
	await physics_frame
	var standing := get_nodes_in_group(&"screen").size()
	var rounds := main.get_node("Bullets").get_child_count() - rounds_before
	print("-- placed with the button held: %d screens standing, %d rounds fired" % [
		standing, rounds])
	_check(standing == 1, "a screen survives the click that placed it")
	_check(rounds == 0, "and that click does not fire the gun")
	for node in get_nodes_in_group(&"screen"):
		node.queue_free()
	await physics_frame

	# Put one back for the checks below. Through the tree, not by name: a
	# --script tool compiles without the autoloads.
	net.raise_screen(sheet_from, sheet_to, 1)
	await physics_frame
	sheet = get_nodes_in_group(&"screen")[0]

	# --- and it is solid -----------------------------------------------------
	#
	# Walking into it has to stop you. Checked by moving a body at it rather than
	# by reading the mask: the mask is on the player and the layer is on the
	# sheet, and the two agreeing is the only thing that matters.
	var mid: Vector2 = (sheet._from + sheet._to) * 0.5
	player.global_position = mid + Vector2(-70.0, 0.0)
	player.velocity = Vector2.ZERO
	for i in 6:
		await physics_frame
	var start_x: float = player.global_position.x
	for i in 40:
		player.velocity.x = 400.0
		await physics_frame
	var through: bool = player.global_position.x > mid.x + 20.0
	print("-- walked at it from %.0f, ended at %.0f (sheet at %.0f)" % [
		start_x, player.global_position.x, mid.x])
	_check(not through, "a screen stops you walking through it")

	# --- one hit and it is gone ----------------------------------------------
	sheet.take_damage(10.0, across, Vector2.RIGHT)
	await physics_frame
	await physics_frame
	var after := get_nodes_in_group(&"screen").size()
	print("-- after one hit, screens left: %d" % after)
	_check(after == 0, "a single hit takes it down")

	_finish()


## The middle of a sheet.
func mid_of(sheet: Node2D) -> Vector2:
	return ((sheet._from as Vector2) + (sheet._to as Vector2)) * 0.5


## Points at a spot in the world.
##
## Through PlayerInput.screen_point, which is the field a thumb would use. The
## desktop path reads the real cursor and headless has none, and writing
## touch_aim_point does not work either - the touch pad rewrites that every frame
## it processes and quietly overrules a harness.
func _aim_at(_player: Node2D, spot: Vector2) -> void:
	_input.screen_point = spot


## One trigger press, seen by the placing view.
func _click() -> void:
	Input.action_press(&"fire")
	await physics_frame
	Input.action_release(&"fire")
	await physics_frame


func _finish() -> void:
	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("  FAIL  %s" % what)
	else:
		print("  ok    %s" % what)


## Ziplines are scenery the dark swallows, not bodies the recon arrow paints.
##
## Checked as its own thing because the two groups are easy to confuse and the
## consequence of confusing them is quiet: put a rope in "hideable" and every
## cable on the map grows a recon diamond the first time somebody fires an arrow.
func _check_ropes(tree: SceneTree) -> void:
	var ropes := tree.get_nodes_in_group(&"zipline")
	var shadowed := 0
	var painted := 0
	for rope in ropes:
		if (rope as Node).is_in_group(&"shadowed"):
			shadowed += 1
		if (rope as Node).is_in_group(&"hideable"):
			painted += 1
	print("-- ropes: %d, in shadow: %d, in the recon set: %d" % [
		ropes.size(), shadowed, painted])
	_check(ropes.size() > 0, "there are ropes to check")
	_check(shadowed == ropes.size(), "every rope is hidden by the dark")
	_check(painted == 0, "and none of them are things the recon arrow paints")
	_check(ropes.is_empty() or (ropes[0] as Node).has_method(&"sight_points"),
		"a rope says where to look for it, being long and thin")
