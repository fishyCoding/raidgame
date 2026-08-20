extends SceneTree

## Photographs the tiled wall panelling: once as the player sees it, lit, and
## then from a free camera at a few zooms to check the tiling holds up.
##
##   godot --path . --script res://tools/wall_shot.gd
##
## Not headless: it takes pictures.

const SHOTS := [
	["wall_ground", Vector2(-800, 380), 1.0],
	["wall_close", Vector2(1703, 396), 3.0],
	["wall_east", Vector2(1889, -200), 1.0],
	["wall_control", Vector2(-1000, -300), 0.55],
	["wall_wide", Vector2(-300, -300), 0.16],
]


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

	# The HUD would sit on top of every frame.
	main.get_node("HUD").visible = false
	await _wait(2)
	await _save("res://tools/scr_wall_lit.png")
	print("wall_shot | wall_lit")

	var player: Node2D = net.local_player
	if player:
		print("wall_shot | player at %s" % str(player.global_position))

	var cam := Camera2D.new()
	main.add_child(cam)
	for shot in SHOTS:
		cam.global_position = shot[1]
		cam.zoom = Vector2.ONE * shot[2]
		cam.make_current()
		await _wait(4)
		await _save("res://tools/scr_%s.png" % shot[0])
		print("wall_shot | %s" % shot[0])
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
