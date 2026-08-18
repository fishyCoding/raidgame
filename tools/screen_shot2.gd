extends SceneTree

## Throwaway: photographs the intro, the loot screen with armour, and the death
## screen. Run windowed.
##   godot --path <project> --script res://tools/screen_shot2.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(40)
	await _save("res://tools/scr_intro.png")
	await _wait(140) # let the intro finish before anything else is photographed

	var input: Node = root.get_node("/root/PlayerInput")
	var player: CharacterBody2D = main.get_node("Player")
	var kit: Inventory = player.inventory
	kit.helmet = Item.from_armor(load("res://resources/armor/heavy_helmet.tres"))
	kit.vest = Item.from_armor(load("res://resources/armor/light_vest.tres"), 22.0)
	kit.store(Item.from_medkit(2))
	kit.add_rounds(&"5.56", 80)

	var guard = main.get_node("Enemies/Enemy1")
	player.global_position = guard.global_position + Vector2(-150, 0)
	await _wait(40)
	guard._health = 1.0
	guard.take_damage(50.0, guard.global_position + Vector2(0, 20), Vector2.RIGHT)
	await _wait(20)
	var bodies := get_nodes_in_group(&"lootable")
	if bodies.size() > 0:
		player.global_position = (bodies[0] as Node2D).global_position
	await _wait(10)
	input.touch_interact_pressed = true
	await _wait(20)
	await _save("res://tools/scr_loot.png")

	input.touch_inventory_pressed = true
	await _wait(10)
	# Take the helmet off first: with it on, the same shot is survivable, which
	# is the point of the helmet and no use for photographing a death.
	kit.helmet = null
	var height: float = (player.get_node("CollisionShape2D").shape as RectangleShape2D).size.y
	player.take_damage(10.0, player.global_position + Vector2(0, -height * 0.4), Vector2.RIGHT)
	await _wait(105)
	await _save("res://tools/scr_death.png")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
