extends SceneTree

## Photographs the in-game HUD with a full kit on, which is the only way to see
## the gadget strip along the bottom - the starting sidearm has no ultimate and
## nothing to throw, so an unkitted shot shows three empty tiles.
##
##   godot --path . --script res://tools/hud_shot.gd
##
## Not headless: it takes pictures.

const SHOP_SCRIPT := "res://scripts/shop.gd"


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
		print("hud_shot | never got a character")
		quit(1)
		return

	# Bought through the shop's own path, so what is photographed is a loadout the
	# game can actually produce rather than one assembled by hand here.
	var counter: Control = Control.new()
	counter.set_script(load(SHOP_SCRIPT))
	root.add_child(counter)
	counter.open(player.inventory)
	counter.credits = 12000
	for pick in [["backpack", 1], ["primary", 1], ["ultimate", 0],
			["throw0", 0], ["throw1", 1]]:
		counter._open = {"id": pick[0], "list": _list_for(counter, pick[0]),
			"label": "", "kind": "slot"}
		counter._buy(counter.CATALOGUE[_list_for(counter, pick[0])][pick[1]])
	counter.queue_free()
	await _wait(20)

	# A charged ultimate, so the tile reads READY rather than 0%.
	if player.inventory.ultimate:
		player.inventory.ultimate.charge = 1.0
	await _wait(10)
	await _save("res://tools/scr_hud.png")
	print("hud_shot | saved scr_hud.png")

	# And again with the ultimate running, which is when the tile stops showing a
	# charge and starts showing how long is left of it.
	player.overload_left = 5.4
	await _wait(10)
	await _save("res://tools/scr_hud_overload.png")
	print("hud_shot | saved scr_hud_overload.png")
	quit()


func _list_for(shop: Node, id: String) -> String:
	for slot in shop.SLOTS:
		if slot.id == id:
			return slot.list
	return "stow"


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
