extends SceneTree

## The editor hides the ambient tint, the player and the air plane. At runtime
## all three must be back, or the game ships lit like a workshop.
##   godot --headless --path <project> --script res://tools/editorview_test.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run(main)


func _run(main: Node) -> void:
	await process_frame
	await process_frame
	print("-- with the game running --")
	for name in ["Ambient", "Player", "Air"]:
		var node := main.get_node_or_null(name) as CanvasItem
		print("  %-8s visible: %s" % [name, node.visible if node else "missing"])
	print("  editor hint (should be false in a build): %s" % Engine.is_editor_hint())
	quit()
