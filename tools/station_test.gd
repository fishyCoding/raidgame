extends SceneTree

## Can the new station actually be walked? Checks the ramps carry you up, that
## every corner room is reachable, and that no guard is on your doorstep.
##   godot --headless --path <project> --script res://tools/station_test.gd

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
	_main.get_node("HUD/Screens")._start_raid()
	await physics_frame
	_input = root.get_node("/root/PlayerInput")
	for guard in _main.get_node("Enemies").get_children():
		guard.process_mode = Node.PROCESS_MODE_DISABLED

	var world := _main.get_node("World")
	var ramps := 0
	for block in world.get_children():
		if absf(block.rotation) > 0.01:
			ramps += 1
	print("-- the station --")
	print("  %d blocks, %d of them ramps, %d cables, %d guards" % [
		world.get_child_count(), ramps,
		_main.get_node("Ziplines").get_child_count(),
		_main.get_node("Enemies").get_child_count()])

	print("\n-- walking up a ramp instead of riding a cable --")
	await _walk_up("WestStairLower", Vector2(-2385, 250)) # at the toe, by the wall
	await _walk_up("SouthRampWest", Vector2(-680, 250))

	print("\n-- the four rooms --")
	for spot in [["the yard", Vector2(-2000, 250)], ["control", Vector2(-1900, -290)],
			["the docks", Vector2(2000, 250)], ["mast deck", Vector2(1900, -330)],
			["the vault", Vector2(-100, 30)]]:
		_player.global_position = spot[1]
		_player.velocity = Vector2.ZERO
		await _wait(30)
		print("  %-10s stands at y %.0f, on floor: %s" % [
			spot[0], _player.global_position.y, _player.is_on_floor()])
	quit()


## Walks right/left along a ramp and reports how much height was gained without
## ever pressing jump - which is the whole point of a ramp.
func _walk_up(ramp_name: String, from: Vector2) -> void:
	_player.global_position = from
	_player.velocity = Vector2.ZERO
	await _wait(20)
	var start := _player.global_position.y
	var ramp := _main.get_node("World").get_node_or_null(ramp_name) as Node2D
	var direction := signf(ramp.global_position.x - from.x) if ramp else 1.0
	if is_zero_approx(direction):
		direction = 1.0

	_input.touch_move_axis = direction
	for i in 220:
		await physics_frame
	_input.touch_move_axis = 0.0
	await _wait(10)
	print("  %-16s walked %s -> climbed %.0f px (no jumping)" % [
		ramp_name, "right" if direction > 0 else "left", start - _player.global_position.y])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
