extends SceneTree

## Photographs the scanned banner over a live raid.
##
##   godot --path . --script res://tools/scanned_shot.gd
##
## Not headless: it takes pictures.


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(10)

	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await _wait(2)
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(30)

	var player: Node2D = net.local_player
	if player == null:
		print("scanned_shot | never got a character")
		quit(1)
		return

	# Raised through the player, so what is photographed is what an arrow does
	# rather than what the HUD can be talked into drawing on its own.
	player.mark_scanned()
	# A few frames in, so the pulse is caught mid-swing rather than at full.
	await _wait(12)
	await _save("res://tools/scr_scanned.png")
	print("scanned_shot | saved")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
