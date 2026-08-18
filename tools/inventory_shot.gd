extends SceneTree

## Throwaway: kills a guard, stands over the body and opens the loot screen, so
## the grid UI can be looked at. Run windowed - the renderer has to draw.
##   godot --path <project> --script res://tools/inventory_shot.gd

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(6)
	# Past the shop, then past the map briefing - which holds the tree paused
	# until a key is pressed, and hangs anything that only dismisses the shop.
	var shop: Node = main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await _wait(2)
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	await _wait(20)

	var input: Node = root.get_node("/root/PlayerInput")
	var player: CharacterBody2D = main.get_node("Player")

	# Give the player some kit of their own, so both sides have something in
	# them and the screen is worth photographing.
	var kit: Inventory = player.inventory
	kit.set_backpack(Item.from_backpack(load("res://resources/backpacks/sling_bag.tres")))
	kit.store(Item.from_weapon(load("res://resources/weapons/assault_rifle.tres")))
	kit.add_rounds(&"5.56", 120)
	kit.add_rounds(&"12g", 20)

	var guard: Node2D = null
	for node in main.get_node("Enemies").get_children():
		guard = node
		break
	player.global_position = guard.global_position + Vector2(-150, 0)
	input.touch_aim_direction = Vector2.RIGHT
	await _wait(40)
	guard._health = 1.0
	guard.take_damage(50.0, guard.global_position, Vector2.RIGHT)
	await _wait(20)

	var bodies := get_nodes_in_group(&"lootable")
	if bodies.size() > 0:
		player.global_position = (bodies[0] as Node2D).global_position
	await _wait(10)
	input.touch_interact_pressed = true
	await _wait(20)
	await _save("res://tools/grid_loot.png")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
