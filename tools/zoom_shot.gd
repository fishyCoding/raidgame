extends SceneTree

## Photographs the raid at two camera settings from the same spot, so a framing
## change can be looked at rather than argued about in numbers.
##
##   godot --path . --script res://tools/zoom_shot.gd
##
## Not headless: it takes pictures. Fills the gap left by screen_shot2.gd and
## screenshot.gd, which both still ask the level for a node called Main/Player
## and have not worked since characters became per-peer.

const SHOTS := [[0.75, "res://tools/scr_zoom_before.png"],
	[0.60, "res://tools/scr_zoom_after.png"]]


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
	await _wait(40)

	var player: Node2D = net.local_player
	if player == null:
		print("zoom_shot | never got a character")
		quit(1)
		return

	for shot in SHOTS:
		player.base_zoom = shot[0]
		player._base_zoom = Vector2(shot[0], shot[0])
		# The camera eases rather than snaps, and the vision light is resized off
		# it, so both need a moment to settle before the shutter.
		await _wait(40)
		await _save(shot[1])
		print("zoom_shot | saved %s at zoom %.2f" % [String(shot[1]).get_file(), shot[0]])

	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
