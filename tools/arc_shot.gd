extends SceneTree

## Throwaway: photographs a grenade arc at full wind-up.
##   godot --path <project> --script res://tools/arc_shot.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(6)
	var shop = main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await _wait(180)

	var input: Node = root.get_node("/root/PlayerInput")
	var player: CharacterBody2D = main.get_node("Player")
	var kit: Inventory = player.inventory
	kit.store(Item.from_gadget(load("res://resources/gadgets/frag.tres")))
	kit.store(Item.from_gadget(load("res://resources/gadgets/smoke.tres")))
	kit.set_ultimate(Item.from_gadget(load("res://resources/gadgets/recon_bow.tres")))
	kit.ultimates[0].charge = 0.6

	player.global_position = Vector2(-1000, 250)
	input.touch_aim_direction = Vector2(1.0, -0.3).normalized()
	await _wait(20)

	# Nothing is holding the key in a script, so the throw would release on the
	# next physics frame. Freeze the player and pose the arc instead.
	player.set_physics_process(false)
	player.throw_slot = 0
	player.throw_charge = 1.0
	player._aim_line.arc_points = player._simulate_throw(1.0)
	player._aim_line.arc_power = 1.0
	player._aim_line.showing_arc = true
	await _wait(2)
	await _save("res://tools/scr_arc.png")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
