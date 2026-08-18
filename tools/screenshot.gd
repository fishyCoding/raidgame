extends SceneTree

## Throwaway: opens the game, poses the player, and saves frames to
## res://tools/. Lets frames be inspected without a human holding the mouse.
##   godot --path <project> --script res://tools/screenshot.gd

## Deliberately untyped where it touches Player: a --script main loop is
## compiled before autoloads register, so statically referencing Player (which
## uses PlayerInput) would fail to compile here.
func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(30)
	var input: Node = root.get_node("/root/PlayerInput")
	var player: CharacterBody2D = main.get_node("Player")

	# Right of the crate, looking back at the target it conceals.
	player.global_position = Vector2(350, 200)
	input.touch_aim_direction = Vector2(-1.0, 0.0)
	await _wait(60)
	await _save("res://tools/shot_hidden.png")

	# Same target, clear line, from the left.
	player.global_position = Vector2(-400, 200)
	input.touch_aim_direction = Vector2(-1.0, 0.0)
	await _wait(60)
	input.touch_fire_held = true
	await _wait(20)
	input.touch_fire_held = false
	await _wait(2)
	await _save("res://tools/shot_seen.png")

	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
