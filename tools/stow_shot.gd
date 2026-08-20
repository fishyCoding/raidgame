extends SceneTree

## Photographs the gun up, slung, and halfway back up again.
##
##   godot --path . --script res://tools/stow_shot.gd
##
## Not headless: it takes pictures.


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var input: Node = root.get_node("PlayerInput")
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
	await _wait(20)
	main.get_node("HUD").visible = false

	var player: Node2D = net.local_player
	var cable: Node2D = main.get_node("Ziplines/ZipYard")
	var perch: Vector2 = cable.world_top() - cable.direction() * 90.0
	# Aimed level and to the right, so the pose is read against a known aim.
	player._aim_reach = Vector2(220, 0)
	# Its own camera rather than the player's: player.gd rewrites that one's zoom
	# and lean every frame, so anything set on it is gone by the next.
	var cam := Camera2D.new()
	main.add_child(cam)
	cam.zoom = Vector2(0.9, 0.9)
	cam.make_current()
	player.global_position = perch
	player.velocity = Vector2.ZERO
	cam.global_position = perch + Vector2(0, -10)
	await _wait(6)
	cam.global_position = player.global_position + Vector2(0, -10)
	await _save("res://tools/scr_stow_up.png")
	print("stow_shot | up")

	# Put back on the cable first - he has been falling off it since the last
	# picture. One-shot flag, so it has to be set against a physics frame.
	player.global_position = perch
	player.velocity = Vector2.ZERO
	await physics_frame
	input.touch_interact_pressed = true
	await physics_frame
	await _wait(30)
	cam.global_position = player.global_position + Vector2(0, -10)
	print("stow_shot | riding=%s stow=%.2f" % [player.riding, player.stow])
	await _save("res://tools/scr_stow_slung.png")
	print("stow_shot | slung")

	input.touch_interact_pressed = true
	await physics_frame
	await _wait(4)
	cam.global_position = player.global_position + Vector2(0, -10)
	print("stow_shot | stow=%.2f crosshair=%.2f mid-draw" % [
			player.stow, player._reticle.modulate.a])
	await _save("res://tools/scr_stow_drawing.png")
	print("stow_shot | drawing")

	await _wait(5)
	cam.global_position = player.global_position + Vector2(0, -10)
	print("stow_shot | stow=%.2f crosshair=%.2f late draw" % [
			player.stow, player._reticle.modulate.a])
	await _save("res://tools/scr_stow_drawn.png")
	print("stow_shot | drawn")

	# And the cone with both feet off the ground, which the crosshair draws.
	await _wait(40)
	var ground: Node2D = main.get_node("World/Ground")
	player.global_position = Vector2(-900, ground.global_position.y - 90.0)
	player.velocity = Vector2.ZERO
	await _wait(30)
	cam.global_position = player.global_position + Vector2(0, -10)
	cam.zoom = Vector2(0.9, 0.9)
	await _wait(4)
	await _save("res://tools/scr_air_grounded.png")
	print("stow_shot | grounded, cone %.2f deg" % rad_to_deg(
			player.weapon.get_spread(player._get_move_factor(), player._get_air_factor())))

	input.touch_jump_pressed = true
	await physics_frame
	await _wait(8)
	cam.global_position = player.global_position + Vector2(0, -10)
	await _save("res://tools/scr_air_jumping.png")
	print("stow_shot | airborne, cone %.2f deg" % rad_to_deg(
			player.weapon.get_spread(player._get_move_factor(), player._get_air_factor())))
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
