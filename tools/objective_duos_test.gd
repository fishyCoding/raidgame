extends SceneTree

## The one rule that cannot be checked solo: "at least one person has to have
## been to all three" means the squad's *combined* coverage of the three
## sites is not enough - peer 1 captures two, peer 2 captures the third, and
## the centre must stay locked. Only once the same peer has personally done
## all three does it unlock.
##
## Run against a real dedicated server holding the quarry, the same shape
## tools/duos_queue_test.gd uses to get two peers paired:
##
##   godot --headless --path . -- --level=quarry --server=27788
##   godot --headless --path . --script res://tools/objective_duos_test.gd -- --peer=1 --port=27788
##   godot --headless --path . --script res://tools/objective_duos_test.gd -- --peer=2 --port=27788
##
## server/test_objective_duos.ps1 does all three.

## World positions of the three CaptureSite nodes in scenes/quarry.tscn -
## kept here rather than looked up by group, because peer 2 has to walk to
## "whichever one peer 1 did not" and the two processes cannot compare notes
## except through the very state this test is trying to prove.
const SITES := {
	0: Vector2(3150, -3160),  # CaptureSiteA, "THE PLANT"
	1: Vector2(3850, 1805),   # CaptureSiteB, "THE PIT"
	2: Vector2(-4270, -1033), # CaptureSiteC, "THE YARD"
}
const HOLD_TIME := 6.0  # CapturePoint.hold_time

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27788
var _first := false
var _net: Node
var _ok := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_tag = "CLIENT%s" % arg.get_slice("=", 1)
			_first = arg.ends_with("1")
		elif arg.begins_with("--host="):
			_host = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
	_run()


func _run() -> void:
	_net = root.get_node("Net")
	await physics_frame

	_net.staged_kit = load("res://scripts/weapon.gd").starting_inventory()
	_net.wants_duos = true

	if _net.join(_host, _port) != OK:
		_say("FAILED: could not dial %s:%d" % [_host, _port])
		quit(1)
		return
	var waited := 0
	while not _net.in_session and waited < 600:
		await physics_frame
		waited += 1
	_check("connected", _net.in_session)
	if not _net.in_session:
		_finish()
		return

	var told := 0
	while not _net.level_settled() and told < 600:
		await physics_frame
		told += 1
	_check("server said which map", _net.level_settled())
	_check("and it is the quarry", str(_net.match_level).ends_with("quarry.tscn"))

	var level: Node = (load(_net.match_level) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	await physics_frame

	waited = 0
	while _net.teammate(_net.peer_id()) == 0 and waited < 1800:
		await physics_frame
		waited += 1
	_check("paired with a squadmate", _net.teammate(_net.peer_id()) != 0)

	waited = 0
	while _net.local_player == null and waited < 900:
		await physics_frame
		waited += 1
	_check("deployed once paired", _net.local_player != null)
	if _net.local_player == null:
		_finish()
		return

	var mine: Node2D = _net.local_player

	# --- coverage split between the two of you is not enough --------------------
	#
	# Peer 1 takes sites 0 and 1; peer 2 takes site 2. Both wait for the same
	# thing afterward - objective_captured showing all three true, but
	# objective_unlocked still false - which is only interesting because
	# neither of them personally did all three.
	var mine_sites: Array = [0, 1] if _first else [2]
	for id in mine_sites:
		await _capture(mine, id)

	# Wait for the slower side to finish too - not a fixed pause, since one
	# side has twice the walking and holding to do as the other.
	var settled := 0
	var all_shown_captured := false
	while settled < 1800:
		all_shown_captured = true
		for id in SITES:
			if not bool(_net.objective_captured[id]):
				all_shown_captured = false
		if all_shown_captured:
			break
		await physics_frame
		settled += 1
	_check("all three show captured", all_shown_captured)
	_check("but nobody has done all three alone", not _net.objective_unlocked)
	_say("captured=%s unlocked=%s" % [_net.objective_captured, _net.objective_unlocked])

	# --- the same person finishes the set ----------------------------------------
	#
	# Only peer 1 does this - going to a site already shown captured (by peer
	# 2) still has to count toward peer 1's own personal total, which is the
	# whole point of the rule.
	if _first:
		await _capture(mine, 2)
		await _wait(180)
	else:
		# Peer 2 just waits for the broadcast peer 1's capture triggers.
		waited = 0
		while not bool(_net.objective_unlocked) and waited < 900:
			await physics_frame
			waited += 1

	_check("one person finishing the set unlocks it", _net.objective_unlocked)

	_finish()


## Walks to a site and holds it the full hold_time plus a margin for the
## report to round-trip to the host and back.
##
## Deliberately does not exit early just because Net.objective_captured[id]
## is already true - a squadmate may have captured this exact site already,
## and this player's own hold still has to run its course for it to count
## toward *their* personal total (see Net._do_capture). Exiting on the
## global flag would make this a no-op the moment someone else got there
## first, which is exactly the case the "same person" rule is being tested
## against.
func _capture(player: Node2D, id: int) -> void:
	player.global_position = SITES[id]
	var frames := roundi(HOLD_TIME * 60.0) + 120
	for i in frames:
		await physics_frame
	_check("site %d shows captured" % id, bool(_net.objective_captured[id]))


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("%s | %s" % [_tag, text])


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	await _wait(30)
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
