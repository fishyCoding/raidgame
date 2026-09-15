extends SceneTree

## Photographs the quarry's briefing map with the three capture sites and the
## central object marked on it.
##   godot --path <project> --script res://tools/objective_map_shot.gd

func _initialize() -> void:
	var quarry: Node = load("res://scenes/quarry.tscn").instantiate()
	root.add_child(quarry)
	current_scene = quarry
	_capture(quarry)


func _capture(quarry: Node) -> void:
	await _wait(8)
	var shop = quarry.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await _wait(20)
	await _save("res://tools/scr_objective_map.png")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
