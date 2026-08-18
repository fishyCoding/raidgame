extends SceneTree

## Headless check for the bigger map and its cables:
##   godot --headless --path <project> --script res://tools/zipline_test.gd

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
	# The shop pauses the tree from a deferred call, so it has to be dismissed
	# rather than simply unpaused - otherwise the raid never starts.
	var shop = _main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await physics_frame
	_input = root.get_node("/root/PlayerInput")

	var world := _main.get_node("World")
	var bounds := Rect2()
	for block in world.get_children():
		var rect := Rect2(block.global_position - block.size * 0.5, block.size)
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	print("-- the level --")
	print("  %d blocks spanning %.0f x %.0f px (was 2260 x 1080)" % [
		world.get_child_count(), bounds.size.x, bounds.size.y])
	print("  %d guards, %d cables" % [
		_main.get_node("Enemies").get_child_count(),
		_main.get_node("Ziplines").get_child_count()])

	print("\n-- riding a cable --")
	var cable: Zipline = _main.get_node("Ziplines/ZipEast")
	_player.global_position = cable.world_bottom() + Vector2(20, -10)
	_player.velocity = Vector2.ZERO
	await _wait(10)
	print("  standing %.0f px from the cable, in reach: %s" % [
		cable.closest_point(_player.global_position).distance_to(_player.global_position),
		cable.in_reach(_player.global_position)])

	var start_y := _player.global_position.y
	_input.touch_interact_pressed = true
	await _wait(4)
	print("  pressed F -> riding: %s" % (_player.zipline != null))

	# Idle on a cable climbs; holding jump climbs too.
	_input.touch_jump_held = true
	await _wait(90)
	_input.touch_jump_held = false
	print("  1.5s later: climbed %.0f px, still on: %s" % [
		start_y - _player.global_position.y, _player.zipline != null])

	# And down again.
	var high_y := _player.global_position.y
	_input.touch_down_held = true
	await _wait(60)
	_input.touch_down_held = false
	print("  holding down: descended %.0f px" % (_player.global_position.y - high_y))

	_input.touch_jump_pressed = true
	await _wait(6)
	print("  tapped jump -> let go: %s, moving %.0f px/s" % [
		_player.zipline == null, absf(_player.velocity.y)])

	print("\n-- the cable does not reach everywhere --")
	_player.global_position = cable.world_bottom() + Vector2(400, 0)
	await _wait(6)
	print("  400 px away, in reach: %s" % cable.in_reach(_player.global_position))
	quit()


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
