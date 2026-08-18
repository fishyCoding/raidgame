extends SceneTree

## What a sound tells you: where it came from, and who made it.
##
##   godot --headless --path . --script res://tools/sound_test.gd
##
## Runs against the real Audio autoload and reads the pooled player it used, so
## these are the numbers that actually reach the mixer rather than the ones the
## call site asked for. Headless has a dummy audio driver, which does not matter:
## every property being checked is set before play() and would be identical on a
## machine with speakers.

var _ok := true
var _audio: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	_audio = root.get_node("Audio")
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
	await _wait(10)

	var player: Node2D = net.local_player
	if player == null:
		_say("FAILED: never got a character")
		quit(1)
		return
	# Near the listener, or _play drops the sound before it takes a slot - the
	# range check is measured from Net.local_player.
	var near: Vector2 = player.global_position + Vector2(120.0, 0.0)
	var rifle: WeaponData = load("res://resources/weapons/assault_rifle.tres")

	# --- it comes from somewhere ---------------------------------------------
	#
	# Positional players, so panning and falloff are the engine's job - but only
	# if the sound is actually given a place and a range, which is what this
	# checks.
	var shot := _played(func() -> void: _audio.gunshot(rifle, near, false))
	_check("a shot takes a pooled player", shot != null)
	if shot == null:
		_finish()
		return
	_check("which is positional", shot is AudioStreamPlayer2D)
	_check("placed where it happened", shot.global_position.distance_to(near) < 1.0)
	_check("panned, not centred", shot.panning_strength > 0.0)
	_check("and given a range to fade over", shot.max_distance > 0.0)
	_say("shot at %s, panning %.1f, carries %.0f px" % [
		shot.global_position, shot.panning_strength, shot.max_distance])

	# --- and you can hear who made it ----------------------------------------
	#
	# Eleven guards and one other player. Which of those two just fired is the
	# most useful thing a sound can carry, and it used to carry nothing: the same
	# report at the same level either way.
	var by_player := _played(func() -> void: _audio.gunshot(rifle, near, false))
	var by_guard := _played(func() -> void: _audio.gunshot(rifle, near, true))
	_say("shot: player %.1f dB / pitch %.2f   guard %.1f dB / pitch %.2f" % [
		by_player.volume_db, by_player.pitch_scale,
		by_guard.volume_db, by_guard.pitch_scale])
	_check("a player's gun is louder than a guard's",
		by_player.volume_db > by_guard.volume_db)
	_check("and a different pitch", by_guard.pitch_scale < by_player.pitch_scale)
	# Far enough apart to survive the per-shot randomisation either way round.
	_check("far enough apart to hear",
		by_player.volume_db - by_guard.volume_db >= 4.0)

	# --- boots too ------------------------------------------------------------
	#
	# A remote player used to use the guard's own footstep, so the one sound that
	# means "somebody who can shoot back is in this room" was identical to the
	# eleven men who cannot surprise you.
	var walked := _played(func() -> void: _audio.player_footstep(near))
	var patrol := _played(func() -> void: _audio.guard_footstep(near))
	_say("step: player %.1f dB / pitch %.2f   guard %.1f dB / pitch %.2f" % [
		walked.volume_db, walked.pitch_scale, patrol.volume_db, patrol.pitch_scale])
	_check("a player's boots are louder", walked.volume_db > patrol.volume_db)
	_check("and pitched apart from a guard's", patrol.pitch_scale < walked.pitch_scale)

	# --- distance still does its work ----------------------------------------
	var close := _played(func() -> void: _audio.gunshot(rifle, near, false))
	var far := _played(func() -> void:
		_audio.gunshot(rifle, player.global_position + Vector2(1200.0, 0.0), false))
	_check("a distant shot is still placed further away",
		far != null and far.global_position.x > close.global_position.x)
	# Past its own range it should not even take a slot, or a firefight across
	# the level cycles the pool and cuts off the shot next to you.
	var beyond := _played(func() -> void:
		_audio.gunshot(rifle, player.global_position + Vector2(9000.0, 0.0), false))
	_check("and one out of earshot is dropped entirely", beyond == null)

	# --- and walls no longer change it ---------------------------------------
	#
	# Sounds used to raycast to the listener and be scored on what they passed
	# through. That is gone: level is distance and nothing else, so the same shot
	# at the same range is the same level whether or not there is a building in
	# between.
	var open_air := _played(func() -> void: _audio.gunshot(rifle, near, false))
	# Straight down through the floor the character is standing on - guaranteed
	# geometry, at the same distance.
	var through_floor := _played(func() -> void:
		_audio.gunshot(rifle, player.global_position + Vector2(0.0, 120.0), false))
	_say("open %.1f dB, through the floor %.1f dB" % [
		open_air.volume_db, through_floor.volume_db])
	_check("a wall does not change the level",
		is_equal_approx(open_air.volume_db, through_floor.volume_db))

	# --- and the curve is not too steep --------------------------------------
	#
	# Godot applies the falloff itself from max_distance and attenuation, so what
	# is checked here is the shape that was handed to it.
	_say("falloff: shared %.1f, footsteps %.1f" % [
		_audio.ATTENUATION, _audio.FOOTSTEP_ATTENUATION])
	_check("the shared curve is gentle", _audio.ATTENUATION <= 1.0)
	_check("footsteps still fall away faster than the rest",
		_audio.FOOTSTEP_ATTENUATION > _audio.ATTENUATION)

	# --- the rope carries ----------------------------------------------------
	_audio.zipline(near, true, 1)
	_say("rope at %.1f dB, carries %.0f px" % [
		_audio._zip.volume_db, _audio._zip.max_distance])
	_check("the rope is not buried", _audio._zip.volume_db > 0.0)
	_audio.zipline_stopped(1)

	_finish()


## Runs `make_noise` and hands back the pooled player it used, or null if the
## sound was dropped before it took one.
func _played(make_noise: Callable) -> AudioStreamPlayer2D:
	var before: int = _audio._next
	make_noise.call()
	if _audio._next == before:
		return null
	return _audio._players[before]


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("sound | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
