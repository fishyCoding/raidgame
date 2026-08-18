extends SceneTree

## Throwaway: photographs the new level from a pulled-back camera, and a rider
## halfway up a cable.
##   godot --path <project> --script res://tools/map_shot.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(4)
	var shop = main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await _wait(180) # let the intro finish, or it fades over the shot
	await _wait(4)

	var player: CharacterBody2D = main.get_node("Player")
	var camera: Camera2D = player.get_node("Camera2D")
	var input: Node = root.get_node("/root/PlayerInput")

	# Ride a cable so the shot shows what one is for.
	var cable: Zipline = main.get_node("Ziplines/ZipEast")
	player.global_position = cable.world_bottom() + Vector2(10, -10)
	await _wait(10)
	input.touch_interact_pressed = true
	await _wait(4)
	input.touch_jump_held = true
	await _wait(50)
	input.touch_jump_held = false
	# Pull the camera right back to show the level around the rider.
	camera.zoom = Vector2(0.34, 0.34)
	await _wait(6)
	await _save("res://tools/scr_map.png")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
