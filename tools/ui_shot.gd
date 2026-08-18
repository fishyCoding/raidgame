extends SceneTree

## Throwaway: photographs the shop tiles, and the in-raid HUD with Overload
## running plus the gadget panel.
##   godot --path <project> --script res://tools/ui_shot.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(6)
	var shop = main.get_node("HUD/Shop")
	for entry in [shop.STOCK[1], shop.STOCK[6], shop.STOCK[8], shop.STOCK[11],
			shop.STOCK[9], shop.STOCK[10], shop.STOCK[14], shop.STOCK[18]]:
		shop._buy(entry)
	await _wait(6)
	await _save("res://tools/scr_shop.png")

	shop.visible = false
	shop.deployed.emit()
	await _wait(180)

	var player: CharacterBody2D = main.get_node("Player")
	var kit: Inventory = player.inventory
	kit.set_ultimate(Item.from_gadget(load("res://resources/gadgets/overload.tres")))
	kit.ultimate.charge = 1.0
	player.global_position = Vector2(-500, 200)
	await _wait(10)
	player._use_ultimate()
	await _wait(30)
	await _save("res://tools/scr_overload.png")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
