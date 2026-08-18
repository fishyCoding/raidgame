extends SceneTree

## Throwaway: photographs the briefing map shown after DEPLOY.
##   godot --path <project> --script res://tools/map_brief_shot.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(8)
	var shop = main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await _wait(20)
	await _save("res://tools/scr_map_brief.png")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
