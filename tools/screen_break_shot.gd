extends SceneTree

## Photographs a screen coming apart: standing, halfway through, and nearly out.
##
##   godot --path . --script res://tools/screen_break_shot.gd
##
## Not headless: it takes pictures. The break is the one moment a screen is not
## a secret, so it is the only part of the gadget worth photographing - standing,
## it is two faint lines that nobody but its caster can see at all.


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
		print("screen_break_shot | never got a character")
		quit(1)
		return

	# Raised straight through Net rather than through the placing view: what is
	# being photographed is the sheet, not the control that puts one up.
	var mid: Vector2 = player.global_position + Vector2(150.0, -40.0)
	var sheet: Node2D = net.raise_screen(
		mid + Vector2(0.0, -110.0), mid + Vector2(0.0, 110.0), net.peer_id())
	if sheet == null:
		print("screen_break_shot | no sheet went up")
		quit(1)
		return
	await _wait(10)
	await _save("res://tools/scr_screen_up.png", sheet)

	sheet.take_damage(10.0, mid + Vector2(0.0, -40.0), player.global_position)
	# Waited out against the animation's own clock rather than in frames. This
	# window runs nowhere near 60 fps, and four frames of it turned out to be
	# most of the break - the first picture came back with the sheet already
	# half gone and the rest of them came back empty.
	await _until(sheet, 0.6)
	await _save("res://tools/scr_screen_breaking.png", sheet)
	await _until(sheet, 0.25)
	await _save("res://tools/scr_screen_broken.png", sheet)
	quit()


## Waits until the break has this much of itself left.
func _until(sheet: Node2D, left: float) -> void:
	while is_instance_valid(sheet) and sheet._breaking > sheet.BREAK_TIME * left:
		await process_frame


func _save(path: String, sheet: Node2D) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("screen_break_shot | saved %s (%.2fs of the break left)" % [
		path.get_file(), sheet._breaking if is_instance_valid(sheet) else 0.0])


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
