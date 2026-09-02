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

	# --- the guards are parked, not absent -----------------------------------
	#
	# They are back in a solo raid, which this is. Stopped rather than checked
	# for: two of the measurements below count rounds in the level, and a guard
	# firing at the far end of the yard adds to that count without having
	# anything to do with what is being tested.
	var guards := main.get_node("Enemies")
	for guard in guards.get_children():
		guard.set_physics_process(false)
		guard.set_process(false)
	print("-- guards in the level: %d, all parked" % guards.get_child_count())

	await _check_ropes(self)

	# --- a screen goes up, anchored ------------------------------------------
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var ult: Object = maker.from_gadget(load("res://resources/gadgets/screen.tres"))
	ult.charge = 1.0
	player.inventory.fit_default_power()
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

	# --- and it comes apart where everybody can see it -----------------------
	#
	# Down and gone are not the same thing. It stops hiding anybody on the frame
	# it is hit - that is what the count above says - but it stays in the tree a
	# little longer to break up, because the person who shot it has to be told
	# that what they shot was a picture rather than a wall.
	print("-- while it breaks: still here=%s, %.2fs of it left, %d pieces" % [
		is_instance_valid(sheet), sheet._breaking, sheet._shards.size()])
	_check(is_instance_valid(sheet) and sheet._breaking > 0.0,
		"the break has to be watchable, not instant")
	_check(sheet._shards.size() > 1, "and it goes into pieces rather than fading")
	_check(not sheets_script.blocks_sight(self, one, two),
		"but it hides nobody while the pieces fall")
	for i in 240:
		await physics_frame
		if not is_instance_valid(sheet):
			break
	print("-- gone once the pieces had fallen: %s" % not is_instance_valid(sheet))
	_check(not is_instance_valid(sheet), "and then it frees itself")

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


## Hooks are hidden by the dark; ziplines are not.
##
## Both halves matter and they pull in opposite directions. A rope somebody else
## fired, drawn across an unlit room, hands you their position, heading and speed
## without you having looked at anything. A zipline is level furniture that has
## always been drawn and should stay drawn.
func _check_ropes(tree: SceneTree) -> void:
	var lines := tree.get_nodes_in_group(&"zipline")
	var shadowed := 0
	for line in lines:
		if (line as Node).is_in_group(&"shadowed"):
			shadowed += 1
	print("-- ziplines: %d, of those hidden by the dark: %d" % [lines.size(), shadowed])
	_check(lines.size() > 0, "there are ziplines to check")
	_check(shadowed == 0, "ziplines are not hidden by the dark")

	var hook: Node2D = (load("res://scenes/grapple_hook.tscn") as PackedScene).instantiate()
	# Asked the moment it enters the tree. A hook with nobody holding it retracts
	# and frees itself on its first frame, so waiting one is waiting too long.
	(tree.current_scene as Node).add_child(hook)
	var hidden: bool = hook.is_in_group(&"shadowed")
	var walks: bool = hook.has_method(&"sight_points")
	var painted: bool = hook.is_in_group(&"hideable")
	print("-- hook: in shadow=%s, says where to look=%s, in the recon set=%s" % [
		hidden, walks, painted])
	_check(hidden, "a fired hook is hidden by the dark")
	_check(walks, "and is looked for along its rope, not at one end of it")
	_check(not painted, "and is not something the recon arrow paints")
	hook.queue_free()
