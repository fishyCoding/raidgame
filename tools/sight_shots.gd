extends SceneTree

## Throwaway: poses the player and saves frames of the new sighting work to
## res://tools/. Run windowed (the renderer has to actually draw):
##   godot --path <project> --script res://tools/sight_shots.gd
##
## Untyped around Player for the same reason as screenshot.gd: a --script main
## loop compiles before autoloads register.

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(30)
	var input: Node = root.get_node("/root/PlayerInput")
	var player: CharacterBody2D = main.get_node("Player")

	# Hip fire, aim line and reticle over the dark half of the level.
	player.global_position = Vector2(-400, 200)
	input.touch_aim_direction = Vector2(1.0, -0.25).normalized()
	await _wait(60)
	await _save("res://tools/sight_hip.png")

	# Mid-burst: the cone should be visibly wider and the whole picture higher.
	input.touch_fire_held = true
	await _wait(45)
	await _save("res://tools/sight_burst.png")
	input.touch_fire_held = false
	await _wait(120)

	# Same pose, aimed: line brightens, cone closes right down, camera leans in.
	input.touch_aim_held = true
	await _wait(45)
	await _save("res://tools/sight_aimed.png")

	# Sniper scope: 2.35x.
	player.weapon.equip(4)
	await _wait(90)
	await _save("res://tools/sight_sniper.png")
	input.touch_aim_held = false

	# Under the one-way catwalk: the dummy above it should be visible through it,
	# and no shadow should be cast by it.
	var target: Node2D = main.get_node("Targets/Target2")
	target.global_position = Vector2(280, 124)
	target._reset()
	player.global_position = Vector2(280, 250)
	input.touch_aim_direction = Vector2.UP
	await _wait(90)
	await _save("res://tools/sight_one_way.png")

	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
