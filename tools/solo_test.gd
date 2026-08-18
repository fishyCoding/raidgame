extends SceneTree

## Single player still has to work, unchanged, on the multiplayer path: a
## session of one, hosted by you.

func _initialize() -> void:
	_run()


func _run() -> void:
	# Fetched by path, not as the global: --script compiles before autoloads
	# are registered as script globals, which is why every tool here does this.
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	# The character is spawned now, not placed, so give it a couple of frames.
	for i in 6:
		await physics_frame

	print("-- the session --")
	print("  in_session=%s  is_host=%s  networked=%s  peer_id=%d" % [
		net.in_session, net.is_host, net.is_networked(), net.peer_id()])
	assert(net.in_session, "starting the game should open a session")

	var player: Node2D = net.local_player
	print("  local player: %s" % (player.name if player else "NONE"))
	assert(player != null, "solo play must still put a character in the world")
	assert(player.is_local(), "and it must be ours to drive")
	print("  spawned at %s (authored position was -800, 200)" % str(player.global_position))
	assert(player.global_position.x != -800.0, "the insertion roll should have moved it")

	var camera: Camera2D = player.get_node("Camera2D")
	print("  camera enabled=%s current=%s, overlay visible=%s" % [
		camera.enabled, camera.is_current(), player.get_node("Overlay").visible])
	assert(camera.enabled, "our own camera has to be live")

	# The screens that used to grab "the player" from the tree must have found it.
	var hud: Node = main.get_node("HUD/WeaponHUD")
	var screens: Node = main.get_node("HUD/Screens")
	print("  HUD bound to %s, screens bound to %s" % [
		hud._player.name if hud._player else "NONE",
		screens._player.name if screens._player else "NONE"])
	assert(hud._player == player, "the HUD must be showing our character")
	assert(screens._player == player, "and the run screens must be watching it")

	print("\n-- guards --")
	var guards: Array = main.get_node("Enemies").get_children()
	var thinking := 0
	for g in guards:
		if g.is_brain():
			thinking += 1
	print("  %d guards, %d of them thinking here (host)" % [guards.size(), thinking])
	assert(thinking == guards.size(), "the host thinks for every guard")

	# Let it run and check the world is actually alive.
	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	var was: Vector2 = guards[0].global_position
	for i in 60:
		await physics_frame
	print("  a guard moved %.0f px in a second" % was.distance_to(guards[0].global_position))
	assert(was.distance_to(guards[0].global_position) > 5.0, "guards should be patrolling")

	print("\n-- the player still plays --")
	var input: Node = root.get_node("PlayerInput")
	var start: float = player.global_position.x
	input.touch_move_axis = 1.0
	for i in 30:
		await physics_frame
	input.touch_move_axis = 0.0
	print("  walked %.0f px on input" % absf(player.global_position.x - start))
	assert(absf(player.global_position.x - start) > 10.0, "input must still drive it")

	print("\nOK")
	quit()
