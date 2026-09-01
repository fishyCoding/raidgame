extends SceneTree

## What you actually deploy with, playing alone, having bought nothing.
##
##   godot --headless --path . --script res://tools/solo_kit_test.gd
##
## The menu's kit is a sidearm and the rounds for it. Nothing else is free -
## every gadget, every plate and every rifle is bought at the counter, and that
## rule is most of the game. This walks the solo path exactly as the "play alone"
## button does, all the way to the body, and reads back what is in its hands.
##
## Written because an ultimate and two throwables were reported turning up in a
## kit nobody paid for. Whatever the cause, this is the assertion that says so.

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	# One frame first, or Net does not exist yet and naming Weapon compiles it
	# too early. See tools/headcount_test.gd and the memory note on autoloads.
	await process_frame
	var net: Node = root.get_node("Net")

	# Exactly what lobby.gd hands over when "play alone" is pressed and nothing
	# was bought. Built through the same call the menu uses rather than assembled
	# here, so a change to the starting kit shows up as a failure and not as a
	# stale copy of it.
	var weapon: Object = (load("res://scripts/weapon.gd") as GDScript).new()
	var staged: Object = weapon.starting_inventory()
	_say("staged from the menu: %s" % _describe(staged))
	_check(staged.get_ultimate(0) == null and staged.get_ultimate(1) == null,
		"the menu's kit has no ultimate in it")
	_check(staged.get_throwable(0) == null and staged.get_throwable(1) == null,
		"and nothing to throw")
	net.staged_kit = staged
	net.play_solo()

	# The level after that, in the order the scene change makes: in the tree
	# first, then current_scene, or the briefing map measures nothing.
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 12:
		await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("no character - cannot run")
		quit(1)
		return
	# A staged kit skips the counter, so the only gate is the briefing.
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	await physics_frame

	var kit: Object = player.inventory
	_say("deployed with: %s" % _describe(kit))
	_check(kit.get_ultimate(0) == null, "deployed with no ultimate in the first slot")
	_check(kit.get_ultimate(1) == null, "and none in the second")
	_check(kit.get_throwable(0) == null, "and nothing in the first throw slot")
	_check(kit.get_throwable(1) == null, "and nothing in the second")
	_check(kit.primary == null, "and no primary - a raid starts with a sidearm")
	_check(kit.secondary != null, "which you do have")
	_check(not net.test_drive, "and the test-drive flag did not survive the trip")

	print("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _describe(kit: Object) -> String:
	return "primary=%s secondary=%s ult=[%s, %s] throw=[%s, %s]" % [
		_name(kit.primary), _name(kit.secondary),
		_name(kit.get_ultimate(0)), _name(kit.get_ultimate(1)),
		_name(kit.get_throwable(0)), _name(kit.get_throwable(1))]


func _name(item: Object) -> String:
	if item == null:
		return "-"
	return "%s x%d" % [item.label(), item.count]


func _say(line: String) -> void:
	print("-- %s" % line)


func _check(pass_: bool, says: String) -> void:
	print("   %s  %s" % ["ok  " if pass_ else "FAIL", says])
	if not pass_:
		_ok = false
