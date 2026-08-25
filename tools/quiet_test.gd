extends SceneTree

## Checks the layout changes: fewer guards, fewer see-through catwalks, no guard
## breathing down your neck at insertion, and F preferring the nearer of a body
## or a cable.
##   godot --headless --path <project> --script res://tools/quiet_test.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run(main)


func _run(main: Node) -> void:
	await physics_frame
	await physics_frame
	var shop = main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	main.get_node("HUD/Screens")._start_raid()
	await physics_frame
	var input: Node = root.get_node("/root/PlayerInput")
	var player: CharacterBody2D = main.get_node("Player")

	var world := main.get_node("World")
	var see_through := 0
	for block in world.get_children():
		if block.one_way:
			see_through += 1
	print("-- the level --")
	print("  %d blocks, %d of them see-through catwalks (was 16)" % [
		world.get_child_count(), see_through])
	print("  %d guards (was 19)" % main.get_node("Enemies").get_child_count())

	var nearest := INF
	for guard in main.get_node("Enemies").get_children():
		nearest = minf(nearest, player.global_position.distance_to(guard.global_position))
	print("\n-- insertion --")
	print("  nearest guard to where you landed: %.0f px (wanted %.0f+)" % [
		nearest, player.safe_insertion_distance])
	if main.get_node("Enemies").get_child_count() == 0:
		print("  (guards pulled from the level - nothing to listen for)")
		quit(0)
		return
	print("  guard reaction time: %.1fs" % main.get_node("Enemies").get_child(0).reaction_time)
	print("  guards wearing helmets: %d" % _helmets(main))

	# A body dropped right beside a cable: F should still take the cable when it
	# is the nearer of the two.
	print("\n-- a body next to a cable --")
	var cable: Zipline = main.get_node("Ziplines/ZipCoreWest")
	var spot := cable.world_bottom() + Vector2(0, -30)
	var guard = main.get_node("Enemies").get_child(0)
	guard.global_position = spot + Vector2(70, 0)
	guard._health = 1.0
	guard.take_damage(50.0, guard.global_position + Vector2(0, 16), Vector2.RIGHT)
	await _wait(6)

	player.global_position = spot + Vector2(14, 0)
	await _wait(6)
	print("  body %.0f px away, cable %.0f px away" % [
		player.global_position.distance_to((get_nodes_in_group(&"lootable")[0] as Node2D).global_position),
		player.global_position.distance_to(cable.closest_point(player.global_position))])
	input.touch_interact_pressed = true
	await _wait(4)
	print("  pressed F -> on the cable: %s, screen open: %s" % [
		player.zipline != null, player.inventory_open])
	quit()


func _helmets(main: Node) -> int:
	var total := 0
	for guard in main.get_node("Enemies").get_children():
		if guard.weapon.inventory and guard.weapon.inventory.helmet:
			total += 1
	return total


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
