extends SceneTree

## The plates: the toggle, what it costs, and what it saves you from.
##
##   godot --headless --path . --script res://tools/shield_test.gd
##
## The rule the whole thing rests on is that being caught without them up is
## fatal, so most of what is checked here is the *gap* - the 0.3s the plates take
## to come up, during which you are still as vulnerable as you were before you
## pressed anything. A shield you could flick on as a round arrived would be a
## shield with no decision in it.

var _ok := true
var _player: Node2D


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
	await _wait(20)
	var screens: Node = main.get_node("HUD/Screens")
	screens.phase = screens.Phase.PLAYING
	await _wait(5)

	_player = net.local_player
	if _player == null:
		_say("FAILED: never got a character")
		quit(1)
		return

	# --- it starts down ------------------------------------------------------
	_check("you deploy with the plates down", not _player.armored)
	_check("and no protection at all", not _player.is_shielded())

	# --- the button toggles it ----------------------------------------------
	#
	# Pressed through the real input map, which is the same door the touch pad
	# and the gamepad come through - so this covers all three at once.
	_press(&"shield")
	await _wait(2)
	_check("the button puts them up", _player.armored)
	_check("but not instantly", not _player.is_shielded())
	_say("one frame in, the ramp is at %.2f" % _player.shield)

	# --- and it takes the time it says it does -------------------------------
	var raising := 0
	while not _player.is_shielded() and raising < 200:
		raising += 1
		await physics_frame
	var took := raising / 60.0
	_say("plates up after %.2fs (raise time %.2fs)" % [took, _player.shield_raise_time])
	_check("they come up in about the time set", absf(took - _player.shield_raise_time) < 0.12)
	_check("and then you are covered", _player.is_shielded())

	# --- covered, a hit is survivable ---------------------------------------
	_player._invulnerable = 0.0
	var before: float = _player.health
	_player.take_damage(20.0, _player.global_position, Vector2.RIGHT)
	await _wait(2)
	_say("shielded, a 20 dmg hit left %.0f of %.0f health" % [_player.health, before])
	_check("a hit with the plates up is survivable", not _player.is_downed)
	_check("and it still costs you health", _player.health < before)

	# --- dropping them uncovers you immediately ------------------------------
	_press(&"shield")
	await _wait(2)
	_check("pressing again drops them", not _player.armored)
	_check("and you are uncovered before they are down", not _player.is_shielded())
	_check("with the ramp still on its way", _player.shield > 0.0)

	# --- and then the same round costs twice as much -------------------------
	#
	# This used to assert that one round of any size ended the fight. It does not
	# any more, and the replacement is the point of the rework: the plates gate
	# whether the vest applies rather than whether you live, so being caught out
	# is a doubled bill instead of a coin flip. Same decision, priced in health.
	var vest: ArmorData = load("res://resources/armor/medium_vest.tres")
	_player.inventory.set_worn(Inventory.Wear.VEST, Item.from_armor(vest))

	_player.health = _player.max_health
	_player.injuries = 0
	_press(&"shield")
	while not _player.is_shielded():
		await physics_frame
	_player._invulnerable = 0.0
	var plated_from: float = _player.health
	_player.take_damage(51.0, _player.global_position, Vector2.RIGHT)
	await _wait(2)
	var plated_cost: float = plated_from - _player.health

	_player.health = _player.max_health
	_player.injuries = 0
	_press(&"shield")
	while _player.is_shielded():
		await physics_frame
	_player._invulnerable = 0.0
	var bare_from: float = _player.health
	_player.take_damage(51.0, _player.global_position, Vector2.RIGHT)
	await _wait(2)
	var bare_cost: float = bare_from - _player.health

	_say("a rifle round costs %.0f plated, %.0f caught out" % [plated_cost, bare_cost])
	_check("plated, the vest takes its half", absf(plated_cost - 26.0) < 0.5)
	_check("caught out, the round lands whole", absf(bare_cost - 51.0) < 0.5)
	_check("neither of which is instantly fatal", not _player.is_downed)
	_check("but two of the second one would be", bare_cost * 2.0 >= _player.max_health)

	# --- two rounds, caught out, is the floor the model stands on ------------
	#
	# The section below needs a man on the floor, and this is now how one gets
	# there: the old one-round rule used to put him there as a side effect, and
	# with that gone the knockdown has to be earned. Which makes this the right
	# place to pin the rule that replaced it.
	_player.health = _player.max_health
	_player.injuries = 0
	_player._invulnerable = 0.0
	_player.take_damage(51.0, _player.global_position, Vector2.RIGHT)
	await _wait(2)
	_check("one round to an unplated body is survivable", not _player.is_downed)
	_player._invulnerable = 0.0
	_player.take_damage(51.0, _player.global_position, Vector2.RIGHT)
	await _wait(2)
	_check("the second one puts you down", _player.is_downed)
	_check("on the floor rather than out of the raid", _player.is_alive)

	# --- being down takes them away -----------------------------------------
	_press(&"shield")
	await _wait(4)
	_check("and you cannot put them back up from the floor", not _player.armored)

	# --- and a man on the floor can still be finished ------------------------
	#
	# The gate has to sit *below* the prone case, and this is why. A downed body
	# is never shielded, so routing it through the gate calls _go_down on someone
	# already down - which returns immediately and does nothing - and the round
	# is swallowed. It reads as nothing at all going wrong: the shot lands, the
	# body stays, and the raid can never end.
	var finishing := 0
	while _player.is_alive and finishing < 30:
		finishing += 1
		_player._invulnerable = 0.0
		_player.take_damage(90.0, _player.global_position, Vector2.RIGHT)
		await _wait(3)
	_say("took %d more hits on the floor to finish it" % finishing)
	_check("hits on a downed body still count", not _player.is_alive)

	_player.respawn()
	_player._revive()
	await _wait(4)
	_check("and the plates come back down on respawn", not _player.armored)

	# --- what they cost ------------------------------------------------------
	#
	# Measured as top speed rather than as ground covered. Distance is what the
	# player actually feels, but it is also whatever the nearest wall says: the
	# first draft of this ran the character into the yard's edge and read the
	# plates as infinitely heavy. Peak velocity is the speed cap itself.
	var home: Vector2 = _player.global_position
	var open_ground := await _top_speed(60)
	_player.global_position = home
	_player.velocity = Vector2.ZERO
	await _wait(10)
	_press(&"shield")
	while not _player.is_shielded():
		await physics_frame
	var plated := await _top_speed(60)
	_say("top speed: %.0f px/s open, %.0f px/s plated (%.0f%%)" % [
		open_ground, plated, 100.0 * plated / maxf(open_ground, 1.0)])
	# Loosened deliberately from "considerably" (it was under 70% of open ground).
	# The plates were priced against being the only thing between you and a
	# one-shot death; now that they gate the vest instead, most of that cost has
	# come off. Still a cost you can be caught out by - the window either side is
	# what makes the toggle a decision - but no longer a commitment to walking.
	_check("the plates still slow you", plated < open_ground * 0.95)
	_check("but nothing like as much as they did", plated > open_ground * 0.7)
	_check("and they do not stop you moving", plated > 10.0)

	# --- it travels ----------------------------------------------------------
	#
	# `armored` is the only part that is sent; the ramp is re-derived on every
	# machine from it. Asserted against the scene's own replication config rather
	# than by standing up a second peer, because what can go wrong here is
	# someone adding the property and forgetting the config.
	_check("the toggle is on the wire", _replicates(&"armored"))
	_check("and the ramp is not, being derived", not _replicates(&"shield"))

	# --- and it is reachable without a keyboard ------------------------------
	_check("there is a shield action at all", InputMap.has_action(&"shield"))
	_check("with a gamepad button on it", _has_joypad_binding(&"shield"))
	var pad_buttons := []
	for entry in load("res://scripts/touch_controls.gd").BUTTONS:
		pad_buttons.append(entry.action)
	_check("and a button on the touch pad", pad_buttons.has(&"shield"))

	# --- and you can see it on somebody -------------------------------------
	var outline: Node2D = _player.get_node_or_null("Body/ShieldOutline")
	_check("the body carries an outline node", outline != null)
	if outline:
		await _wait(2)
		_check("which is drawing while the plates are up", outline._drawn > 0.5)

	_finish()


## The fastest the character gets moving in `frames` with the stick held over.
func _top_speed(frames: int) -> float:
	var input: Node = root.get_node("PlayerInput")
	var fastest := 0.0
	input.touch_move_axis = 1.0
	for i in frames:
		await physics_frame
		fastest = maxf(fastest, absf(_player.velocity.x))
	input.touch_move_axis = 0.0
	await _wait(20)
	return fastest


func _press(action: StringName) -> void:
	Input.action_press(action)
	Input.action_release(action)


func _replicates(property: StringName) -> bool:
	var sync: MultiplayerSynchronizer = _player.get_node("Sync")
	for path in sync.replication_config.get_properties():
		if str(path).ends_with(":%s" % property):
			return true
	return false


func _has_joypad_binding(action: StringName) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return true
	return false


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("shield | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
