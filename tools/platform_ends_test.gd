extends SceneTree

## The two ends of a Platform are derived, not stored, so this checks the
## derivation both ways: that reading them describes the block that is there,
## and that writing one moves the block without disturbing the other.
##
##   godot --headless --path . --script res://tools/platform_ends_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame

	var blocks: Array[Node] = []
	for node in main.get_node("World").get_children():
		if node.get(&"size") != null and node.has_method(&"world_thickness"):
			blocks.append(node)
	print("-- reading the ends of %d blocks --" % blocks.size())

	for block in blocks:
		var start: Vector2 = block.start
		var finish: Vector2 = block.finish
		var length: float = block.world_length()
		# World is at the origin, so the parent space the ends live in is world
		# space, and the ends must be the block's own centre plus half its run.
		_check(block.name, "midway between the ends is the block",
				start.lerp(finish, 0.5).distance_to(block.global_position) < 0.5)
		_check(block.name, "the ends are a block-length apart",
				absf(start.distance_to(finish) - length) < 0.5)

	print("\n-- moving one end --")
	# A scaled, rotated, mirrored block, to make sure none of that leaks in.
	var block: Node2D = main.get_node("World/ControlPart14")
	print("  %s: size=%s scale=%s rotation=%.3f" % [
			block.name, str(block.size), str(block.scale), block.rotation])
	var kept: Vector2 = block.start
	var thickness: float = block.world_thickness()
	var target := kept + Vector2(700, -260)
	block.finish = target

	_check(block.name, "the end went where it was put", block.finish.distance_to(target) < 0.5)
	_check(block.name, "the other end stayed put", block.start.distance_to(kept) < 0.5)
	_check(block.name, "the block is as long as the span",
			absf(block.world_length() - kept.distance_to(target)) < 0.5)
	_check(block.name, "and no thicker or thinner than it was",
			absf(block.world_thickness() - thickness) < 0.5)
	_check(block.name, "the scale was folded into the size",
			block.scale.is_equal_approx(Vector2.ONE))
	var shape: CollisionShape2D = block.get_node("CollisionShape2D")
	_check(block.name, "the collision shape followed the size",
			(shape.shape as RectangleShape2D).size.is_equal_approx(block.size))

	print("\n-- and the other one --")
	var far: Vector2 = block.finish
	var moved := far + Vector2(-380, 140)
	block.start = moved
	_check(block.name, "the start went where it was put", block.start.distance_to(moved) < 0.5)
	_check(block.name, "the end stayed put", block.finish.distance_to(far) < 0.5)

	print("\n-- dragging the ends together --")
	block.start = far
	_check(block.name, "a collapsed block stops at a square, not a sliver",
			block.world_length() >= block.world_thickness() - 0.5)

	if _failures > 0:
		print("\n%d FAILED" % _failures)
		quit(1)
		return
	print("\nOK")
	quit()


func _check(who: String, what: String, passed: bool) -> void:
	if passed:
		print("  ok   %s: %s" % [who, what])
		return
	_failures += 1
	print("  FAIL %s: %s" % [who, what])
