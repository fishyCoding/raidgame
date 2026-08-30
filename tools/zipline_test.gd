extends SceneTree

## Riding a cable, and the ten seconds you owe for having done it.
##
##   godot --headless --path . --script res://tools/zipline_test.gd
##
## Nothing here names Zipline or Player. Both reach Net, and a --script tool is
## compiled before the autoloads are registered as script globals, so naming one
## compiles its file too early and leaves the *class* broken for the whole
## process - which reads as the level being empty rather than as a compile
## error. Taken from the group and duck-typed instead. The version of this file
## before this one did name them, and had also been asking for a node called
## "Ziplines/ZipEast" since some time before the map stopped having one.

var _net: Node
var _input: Node
var _level: Node
var _player: Node2D
var _ok := true


func _initialize() -> void:
	_run()


func _say(text: String) -> void:
	print("zip | %s" % text)


func _check(what: String, passed: bool) -> void:
	_say("%-46s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _run() -> void:
	await process_frame
	_net = root.get_node("Net")
	_input = root.get_node("PlayerInput")
	_net.solo_level = 0
	_level = (load(_net.solo_scene()) as PackedScene).instantiate()
	root.add_child(_level)
	current_scene = _level
	for i in 6:
		await physics_frame

	# Past the shop and the briefing, both of which pause the tree - and a paused
	# tree means no _physics_process, which means every wait below spins for ever.
	var shop: Node = _level.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	_player = _net.local_player
	_check("there is a character", _player != null)
	var cable := _pick_cable()
	_check("there is a cable to ride", cable != null)
	if _player == null or cable == null:
		_finish()
		return
	_say("%d cables in the level, riding a %.0f px one"
		% [get_nodes_in_group(&"zipline").size(), cable.cable_length()])

	# --- getting on it -------------------------------------------------------
	_say("")
	_say("-- riding --")
	await _stand_at(cable)
	_check("standing in reach of it", cable.in_reach(_player.global_position))
	var start_y: float = _player.global_position.y
	await _press_interact()
	_check("F grabs it", _player.get(&"zipline") != null)
	_check("and everyone else can see that you did", bool(_player.get(&"riding")))

	# A quarter of the way up, worked out from this cable's own speed rather than
	# fixed. Cables do not all run at the same rate - the one this picks does
	# nearly a thousand pixels a second - and a fixed number of frames rode
	# clean off the top, which starts the cooldown early and quietly turns every
	# check after it into a check of something else.
	var frames := maxi(roundi(15.0 * cable.cable_length() / cable.speed), 6)
	_input.touch_jump_held = true
	await _wait(frames)
	_input.touch_jump_held = false
	var climbed: float = start_y - _player.global_position.y
	_check("holding up climbs it", climbed > 100.0)
	_check("and does not ride off the end of it", _player.get(&"zipline") != null)
	_say("climbed %.0f px in %d frames" % [climbed, frames])

	# --- and off -------------------------------------------------------------
	#
	# The same key you grabbed with. Jump used to let go and does not any more -
	# held, it rides you *up* - so a test pressing it here would be watching a
	# player stay exactly where he was and calling it a release.
	await _press_interact()
	_check("F again lets go", _player.get(&"zipline") == null)
	_check("and the flag goes with it", not bool(_player.get(&"riding")))

	# --- the ten seconds you owe for it --------------------------------------
	_say("")
	_say("-- and you cannot get straight back on --")
	var cooldown: float = _player.get(&"zipline_cooldown")
	# Nearly full rather than exactly full: the press that let go was six frames
	# ago and the clock has been running since. Anything less than a tenth of a
	# second short of the whole thing means it started when he stepped off.
	var left: float = _player.get(&"zipline_cooldown_left")
	_check("stepping off starts the cooldown",
		left <= cooldown and left > cooldown - 0.2)
	_say("%.2fs of %.0f left, a few frames after letting go" % [left, cooldown])

	await _stand_at(cable)
	_check("still in reach of the rope", cable.in_reach(_player.global_position))
	await _press_interact()
	_check("the grab is refused", _player.get(&"zipline") == null)
	_check("and it says why", "too soon" in str(_player.get(&"loot_message")))

	# It runs down on its own. Measured over half a second rather than assumed:
	# a cooldown that never ticks is a cooldown you never get back.
	var before: float = _player.get(&"zipline_cooldown_left")
	await _wait(30)
	var spent: float = before - float(_player.get(&"zipline_cooldown_left"))
	_say("half a second later: %.2fs of it spent" % spent)
	_check("it counts down", spent > 0.4 and spent < 0.7)

	# Wound forward rather than waited out - ten seconds of headless frames
	# proves nothing the clock above has not already proved.
	_player.set(&"zipline_cooldown_left", 0.0)
	await _press_interact()
	_check("once it is up, a rope is a rope again", _player.get(&"zipline") != null)
	await _press_interact()

	# --- plated up, on a rope ------------------------------------------------
	#
	# The plates and the cable are two different hands' worth of commitment and
	# neither one cancels the other. Riding armoured is slow and loud and you
	# cannot stop, which is cost enough - being made to strip before you may
	# touch a rope would only mean nobody ever climbs one in a fight, which is
	# the exact moment the level's routes are worth having.
	_say("")
	_say("-- and you can ride it in your plates --")
	_player.set(&"zipline_cooldown_left", 0.0)
	_player.set(&"armored", true)
	# All the way up before we ask, because half-raised plates are not armour -
	# see Player.is_shielded.
	var raise_time: float = _player.get(&"shield_raise_time")
	await _wait(roundi(raise_time * 60.0) + 10)
	_check("the plates are up", bool(_player.call(&"is_shielded")))
	_say("they took %.1fs to raise" % raise_time)

	await _stand_at(cable)
	await _press_interact()
	_check("you can still catch a cable in them", _player.get(&"zipline") != null)
	await _wait(30)
	_check("and the ride does not knock them down",
		bool(_player.call(&"is_shielded")) and _player.get(&"zipline") != null)
	await _press_interact()

	# --- and it does not reach everywhere ------------------------------------
	_player.global_position = cable.world_bottom() + Vector2(400.0, 0.0)
	await _wait(6)
	_check("400 px away is not in reach", not cable.in_reach(_player.global_position))
	_finish()


## Puts the character at the bottom of a cable, standing still.
func _stand_at(cable: Node2D) -> void:
	_player.global_position = cable.world_bottom() + Vector2(20.0, -10.0)
	_player.velocity = Vector2.ZERO
	await _wait(4)


## One press of the grab key, and long enough for the body to act on it. Through
## the touch flag because that is the seam a headless run can reach - and it is
## consumed by the same is_interact_just_pressed() a keyboard goes through.
func _press_interact() -> void:
	_input.touch_interact_pressed = true
	await _wait(6)


## The longest cable in the level, which is the one with room to ride.
func _pick_cable() -> Node2D:
	var best: Node2D = null
	var longest := 0.0
	for node in get_nodes_in_group(&"zipline"):
		var line := node as Node2D
		if line == null:
			continue
		var length: float = line.cable_length()
		if length > longest:
			longest = length
			best = line
	return best


func _finish() -> void:
	print("")
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
