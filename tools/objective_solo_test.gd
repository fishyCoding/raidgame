extends SceneTree

## Solo run through the whole objective chain: capture all three sites,
## watch the central object unlock, pick it up, and confirm extraction is
## gated on actually carrying it.
##
##   godot --headless --path . --script res://tools/objective_solo_test.gd
##
## Loaded the same way tools/quarry_test.gd is - the level opens its own
## session on _ready, so there is no lobby/menu step to drive through here.

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var quarry: Node = (load("res://scenes/quarry.tscn") as PackedScene).instantiate()
	root.add_child(quarry)
	current_scene = quarry
	for i in 6:
		await physics_frame

	var player: Node2D = net.local_player
	_check("a character in the quarry", player != null)
	if player == null:
		_finish()
		return

	# Past the shop and the briefing, the preamble every solo tool here shares.
	var shop: Node = quarry.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	var sites := get_nodes_in_group(&"objective")
	_check("three capture sites", sites.size() == 3)

	# --- capture all three, one at a time -------------------------------------
	for site in sites:
		var point: Node2D = site
		player.global_position = point.global_position
		var held := 0
		var cap_id: int = point.id
		while not bool(net.objective_captured[cap_id]) and held < 600:
			await physics_frame
			held += 1
		_check("%s captured" % point.display_name, bool(net.objective_captured[cap_id]))

	_check("all three captured unlocks the centre", net.objective_unlocked)

	# --- pick it up -------------------------------------------------------------
	var centre: Node2D = get_first_node_in_group(&"central_objective")
	_check("a central object exists", centre != null)
	if centre == null:
		_finish()
		return
	player.global_position = centre.global_position
	var waited := 0
	while not bool(player.carrying_objective) and waited < 60:
		await physics_frame
		waited += 1
	_check("picked it up", player.carrying_objective)
	_check("Net agrees who has it", net.objective_carrier == net.peer_id())

	# --- extraction is gated on carrying it -------------------------------------
	var exits: Array = player._exits
	_check("this run has an exit to test against", not exits.is_empty())
	if exits.is_empty():
		_finish()
		return
	var exit_point: Node2D = exits[0]

	# Drop it (as if the carrier had died) and confirm standing in the exit
	# fills the ring but never actually extracts without it. Moved away in
	# the same beat as the drop, with no physics frame in between - still
	# standing on it, _update_carry would simply pick it straight back up,
	# which is correct there (a live player standing on an unclaimed,
	# unlocked object should) and just the wrong thing to do in this test.
	net.tell_dropped_objective(player.global_position)
	player.global_position = exit_point.global_position
	await physics_frame
	_check("dropping it clears the carry flag", net.objective_carrier == 0)
	for i in roundi(exit_point.hold_time * 60.0) + 30:
		await physics_frame
	_check("holding the ring without the object never extracts", not player.extracted_out)
	_say("held %.2fs, extracting=%s, extracted_out=%s" %
		[player._extract_held, str(player.extracting), player.extracted_out])

	# Pick it back up and confirm the same ring now finishes the job.
	player.global_position = centre.global_position
	waited = 0
	while not bool(player.carrying_objective) and waited < 60:
		await physics_frame
		waited += 1
	_check("picked it back up", player.carrying_objective)
	player.global_position = exit_point.global_position
	player._extract_held = 0.0
	for i in roundi(exit_point.hold_time * 60.0) + 30:
		await physics_frame
	_check("carrying it, the same hold does extract", player.extracted_out)

	_finish()


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("objective | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
