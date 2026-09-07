extends SceneTree

## How big the level actually is - the same block-collecting walk minimap.gd
## does - so a bullet's travel distance can be picked against a real number
## instead of guessed.
##
##   godot --headless --path . --script res://tools/map_size_probe.gd -- --level=res://scenes/quarry.tscn

func _initialize() -> void:
	_run()


func _collect(node: Node, blocks: Array) -> void:
	for child in node.get_children():
		var block := child as Node2D
		if block != null and typeof(block.get(&"size")) == TYPE_VECTOR2 \
				and typeof(block.get(&"one_way")) == TYPE_BOOL:
			blocks.append(block)
		elif child.get_child_count() > 0:
			_collect(child, blocks)


func _run() -> void:
	var level_path := "res://scenes/main.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_path = arg.get_slice("=", 1)

	var level: Node = (load(level_path) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	await physics_frame

	var blocks: Array = []
	_collect(level, blocks)

	var bounds := Rect2()
	var measured := false
	for block in blocks:
		var half: Vector2 = (block.get(&"size") as Vector2) * 0.5
		var at: Transform2D = block.global_transform
		for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			var p: Vector2 = at * corner
			bounds = Rect2(p, Vector2.ZERO) if not measured else bounds.expand(p)
			measured = true

	print("%s | %d blocks, bounds %s" % [level_path, blocks.size(), bounds])
	print("%s | size %s px, diagonal %.0f px" % [level_path, bounds.size, bounds.size.length()])

	var farthest := 0.0
	var points: Array = level.get_tree().get_nodes_in_group(&"spawn")
	for a in points:
		for b in points:
			if a != b:
				farthest = maxf(farthest, (a as Node2D).global_position.distance_to((b as Node2D).global_position))
	print("%s | furthest two spawn points: %.0f px" % [level_path, farthest])

	quit()
