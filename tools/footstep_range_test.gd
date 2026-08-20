extends SceneTree

## Whose boots you can hear, and from how far.
##
##   godot --headless --path . --script res://tools/footstep_range_test.gd
##
## Read off the pooled player each call actually configures, rather than from a
## copy of the numbers - so this checks what the mixer is told, not what the
## constants say it should be told.
##
## "Reach" here is how far the sound is still above a listening floor under
## Godot's 2D falloff, which is (1 - d/max) ^ attenuation in linear. That is the
## number that matters: max_distance alone says nothing when the curve has
## already buried the sound at a third of it.

const FLOOR_DB := -40.0

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var audio: Node = root.get_node("Audio")
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

	var here: Vector2 = net.local_player.global_position
	print("-- the ranges --")
	print("  guard %.0f px, player %.0f px, gunshot %.0f px" % [
			audio.HEARING.guard_footstep, audio.HEARING.player_footstep,
			audio.HEARING.gunshot])
	_check("a guard carries less far than boots used to",
			audio.HEARING.guard_footstep < audio.HEARING.footstep)
	# How much further is asserted on audible reach below, not on the ceiling -
	# max_distance says nothing on its own when the two use different curves.
	_check("a player carries further than boots used to",
			audio.HEARING.player_footstep > audio.HEARING.footstep)
	_check("as far as a rifle, in fact",
			audio.HEARING.player_footstep >= audio.HEARING.gunshot)

	print("\n-- what the mixer is actually told --")
	var guard := _mixed(audio, func() -> void: audio.guard_footstep(here))
	var player := _mixed(audio, func() -> void: audio.player_footstep(here))
	var mine := _mixed(audio, func() -> void: audio.footstep(here))
	for row in [["a guard", guard], ["a player", player], ["your own", mine]]:
		var slot: Dictionary = row[1]
		print("  %-9s %6.1f dB, max %.0f px, falloff %.2f  ->  audible to %.0f px" % [
				row[0], slot.db, slot.max, slot.falloff, _reach(slot)])

	_check("a guard is quieter than a player", guard.db < player.db - 5.0)
	_check("and dies away faster", guard.falloff > player.falloff)
	var guard_reach := _reach(guard)
	var player_reach := _reach(player)
	print("\n  a player is audible %.1fx as far as a guard" % (player_reach / maxf(guard_reach, 1.0)))
	_check("a player is heard from much further off", player_reach > guard_reach * 2.0)
	# Close enough to place the man on the next walkway, short enough that the
	# far side of the level is not a wall of shuffling.
	_check("a guard is still heard from a walkway away", guard_reach > 600.0)
	_check("but not from across the level", guard_reach < 800.0)

	print("\n-- out of range is not mixed at all --")
	# _play drops anything past its own reach before it takes a pool slot, so a
	# guard on the far side of the level cannot cut off the gunfire next to you.
	var far := here + Vector2(audio.HEARING.player_footstep + 500.0, 0.0)
	var before: int = audio._next
	audio.guard_footstep(far)
	audio.player_footstep(far)
	_check("nothing across the level took a slot", audio._next == before)

	if _failures > 0:
		print("\nfootsteps | %d FAILED" % _failures)
		quit(1)
		return
	print("\nfootsteps | PASS")
	quit()


## Runs one call and reads back the pool slot it configured.
func _mixed(audio: Node, call: Callable) -> Dictionary:
	var slot: int = audio._next
	call.call()
	var used: AudioStreamPlayer2D = audio._players[slot]
	return {
		# master_db and the clear-line trim are added by _play to every sound
		# alike, so they are taken back off to compare boots with boots.
		"db": used.volume_db - audio.master_db - audio.CLEAR_LINE_TRIM,
		"max": used.max_distance,
		"falloff": used.attenuation,
	}


## How far this sound is still above FLOOR_DB, in pixels.
func _reach(slot: Dictionary) -> float:
	var quiet: float = FLOOR_DB - (slot.db as float)
	if quiet >= 0.0:
		return slot.max
	var left := pow(db_to_linear(quiet), 1.0 / maxf(slot.falloff, 0.01))
	return (slot.max as float) * clampf(1.0 - left, 0.0, 1.0)


func _check(what: String, passed: bool) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures += 1
	print("  FAIL %s" % what)
