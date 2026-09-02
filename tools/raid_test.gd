extends SceneTree

## Headless check for the ring map, spawns, extraction and the reworked
## Overload and grenades:
##   godot --headless --path <project> --script res://tools/raid_test.gd

var _main: Node
var _player: CharacterBody2D
var _input: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_player = _main.get_node("Player")
	_run()


func _run() -> void:
	await physics_frame
	await physics_frame
	var shop = _main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await physics_frame
	var screens = _main.get_node("HUD/Screens")
	print("-- deploying --")
	print("  phase after DEPLOY: %s (the map, before the raid)" % screens.Phase.keys()[screens.phase])
	screens._start_raid()
	await physics_frame
	_input = root.get_node("/root/PlayerInput")

	# Guards are not what is under test here. Park them up front rather than
	# half way through: parking them late still leaves their rounds in the air,
	# and one of those landing ends the raid before the exit hold completes.
	for guard in _main.get_node("Enemies").get_children():
		guard.process_mode = Node.PROCESS_MODE_DISABLED

	_the_ring()
	_insertion()
	await _overload()
	_grenades()
	await _extracting()
	quit()


func _the_ring() -> void:
	var world := _main.get_node("World")
	var bounds := Rect2()
	for block in world.get_children():
		var rect := Rect2(block.global_position - block.size * 0.5, block.size)
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	print("\n-- the complex --")
	print("  %d blocks spanning %.0f x %.0f px" % [
		world.get_child_count(), bounds.size.x, bounds.size.y])
	print("  %d cables, %d insertion points, %d guards" % [
		_main.get_node("Ziplines").get_child_count(),
		_main.get_node("Spawns").get_child_count(),
		_main.get_node("Enemies").get_child_count()])


func _insertion() -> void:
	print("\n-- where the raid starts --")
	var start: SpawnPoint = null
	var exits: Array[String] = []
	for node in get_nodes_in_group(&"spawn"):
		var point := node as SpawnPoint
		if point.is_extraction:
			exits.append("%s (%.0f px away)" % [
				point.display_name,
				point.global_position.distance_to(_player.global_position)])
		elif point.global_position.distance_to(_player.global_position) < 200.0:
			start = point
	print("  dropped at: %s" % (start.display_name if start else "somewhere off a point"))
	print("  exits open: %s" % ", ".join(exits))


func _overload() -> void:
	print("\n-- overload moves you, not the gun --")
	var kit: Inventory = _player.inventory
	kit.fit_default_power()
	kit.set_ultimate(Item.from_gadget(load("res://resources/gadgets/overload.tres")))
	kit.ultimates[0].charge = 1.0

	# Peak rather than final speed: the complex has no long straight runs any
	# more, so anything measured at the end of a fixed window is measured against
	# a wall. Reset to the same spot for each leg so both get the same runway.
	var normal := await _sprint(false)
	var boosted := await _sprint(true)
	print("  top speed %.0f -> %.0f px/s (%.0f%% faster)" % [
		normal, boosted, (boosted / maxf(normal, 1.0) - 1.0) * 100.0])
	print("  jump velocity %.0f -> %.0f" % [
		_player._jump_velocity, _player._jump_velocity * _player.overload_jump_scale])
	print("  the gun is untouched: no 'overloaded' flag on the weapon: %s" % [
		not ("overloaded" in _player.weapon)])
	_input.touch_move_axis = 0.0
	await _wait(20)


## Runs west along the east roof and reports the fastest it managed.
func _sprint(with_overload: bool) -> float:
	_player.global_position = Vector2(2300, -546)
	_player.velocity = Vector2.ZERO
	_input.touch_move_axis = 0.0
	await _wait(20)
	if with_overload:
		_player.inventory.ultimates[0].charge = 1.0
		_player._use_ultimate()

	_input.touch_move_axis = -1.0
	var peak := 0.0
	for i in 60:
		await physics_frame
		peak = maxf(peak, absf(_player.velocity.x))
	_input.touch_move_axis = 0.0
	return peak


func _grenades() -> void:
	print("\n-- grenades land on the cursor --")
	var kit: Inventory = _player.inventory
	kit.store(Item.from_gadget(load("res://resources/gadgets/frag.tres")))
	_player.global_position = Vector2(1760, -546) # open sky above the east roof

	# Aim at points near and far; the solved throw should land on each.
	for reach in [180.0, 420.0, 700.0, 1400.0]:
		# Aim at a spot, the way a mouse does - a direction alone cannot say how
		# far, which is the whole point of placing a grenade.
		_input.touch_aim_point = _player._muzzle.global_position + Vector2(reach, -30.0)
		var arc: PackedVector2Array = _player._simulate_throw(0.0)
		var landed: Vector2 = arc[arc.size() - 1]
		print("  asked for %4.0f px -> arc ends %4.0f px away (capped at %d)" % [
			reach, absf(landed.x - _player.global_position.x), roundi(_player.THROW_MAX_RANGE)])


func _extracting() -> void:
	print("\n-- getting out --")
	var exit_point: SpawnPoint = null
	for node in get_nodes_in_group(&"spawn"):
		var point := node as SpawnPoint
		if point.is_extraction:
			exit_point = point
			break
	if exit_point == null:
		print("  no exits open")
		return

	_player.global_position = exit_point.global_position
	_input.touch_move_axis = 0.0
	await _wait(30)
	print("  standing in %s: progress %.0f%%" % [
		exit_point.display_name, exit_point.progress() * 100.0])

	# Step out and it drains back.
	_player.global_position = exit_point.global_position + Vector2(600, 0)
	await _wait(20)
	print("  stepped away: progress %.0f%%" % (exit_point.progress() * 100.0))

	_player.global_position = exit_point.global_position
	for i in 400:
		await physics_frame
		if _player.extracted_out:
			break
	var screens = _main.get_node("HUD/Screens")
	print("  held it -> extracted: %s, phase %s" % [
		_player.extracted_out, screens.Phase.keys()[screens.phase]])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
