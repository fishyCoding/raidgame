extends SceneTree

## A frag has to be stopped by the level. Same guard, same distance, twice: once
## with a wall in the way and once without.
##
##   godot --headless --path . --script res://tools/grenade_wall_test.gd
##
## Run against the real map rather than a rig built for the occasion, because
## what is being tested is a raycast against this level's geometry - and WallEast
## is 60 px of it standing in a known place.

## WallEast in main.tscn: centred on x=1889, 60 wide, so it spans 1859..1919.
const WALL_X := 1889.0
const GUARD_AT := Vector2(1810.0, 14.0)
## Far side of the wall, and the same distance out from it on the near side. The
## two shots are the same range on purpose: if the blocked one did less damage
## because it was further away, the test would prove nothing.
const BEHIND_WALL := Vector2(1968.0, 14.0)
const SAME_SIDE := Vector2(1652.0, 14.0)

var _ok := true


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
	await physics_frame

	if net.local_player == null:
		_say("FAILED: never got a character")
		quit(1)
		return

	# A guard parked where we want him. Frozen first: he walks a patrol, and a
	# test that moves him and then lets him wander has no idea where he was when
	# it went off.
	var guard: Node2D = null
	for node in main.get_node("Enemies").get_children():
		if node.has_method(&"is_brain"):
			guard = node
			break
	guard.set_physics_process(false)
	guard.global_position = GUARD_AT
	await physics_frame

	_say("guard parked at %.0f,%.0f - wall spans 1859..1919" % [
		guard.global_position.x, guard.global_position.y])
	_check("he really is where we put him",
		guard.global_position.distance_to(GUARD_AT) < 1.0)
	_check("and the wall is between him and the far shot",
		GUARD_AT.x < WALL_X and BEHIND_WALL.x > WALL_X)
	_check("both shots are the same range",
		absf(GUARD_AT.distance_to(BEHIND_WALL) - GUARD_AT.distance_to(SAME_SIDE)) < 2.0)

	# --- through the wall ----------------------------------------------------
	var before: float = guard._health
	_blast_at(main, BEHIND_WALL)
	await physics_frame
	var through: float = guard._health
	_say("frag %.0f px away through the wall: %.0f -> %.0f health" % [
		GUARD_AT.distance_to(BEHIND_WALL), before, through])
	_check("the wall stopped it", is_equal_approx(through, before))

	# --- and the same shot with nothing in the way ---------------------------
	#
	# The control, and it is the half that matters most: a line-of-sight check
	# that is simply always false would pass the test above and quietly make
	# grenades useless.
	_blast_at(main, SAME_SIDE)
	await physics_frame
	var clear: float = guard._health
	_say("frag %.0f px away in the open: %.0f -> %.0f health" % [
		GUARD_AT.distance_to(SAME_SIDE), through, clear])
	_check("but an open one still lands", clear < through)

	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


## Sets a frag off at a point, without throwing it there - the arc is not what is
## on trial and bouncing one into position is a test about physics.
func _blast_at(main: Node, at: Vector2) -> void:
	var grenade: Node2D = (load("res://scenes/grenade.tscn") as PackedScene).instantiate()
	grenade.setup(load("res://resources/gadgets/frag.tres"), Vector2.ZERO,
		Layers.PLAYER_SHOT)
	main.add_child(grenade)
	grenade.global_position = at
	grenade._blast()
	grenade.queue_free()


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("grenade | %s" % text)
