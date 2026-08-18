extends SceneTree

## Throwaway: photographs the shop, buying a loadout first so it is not empty.
##   godot --path <project> --script res://tools/shop_shot.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_capture(main)


func _capture(main: Node) -> void:
	await _wait(10)
	var shop = main.get_node("HUD/Shop")
	shop.credits = 12000  # a full loadout, so every slot is in shot

	# Buy the way a click would: select a slot, then take something off its list.
	for pick in [["backpack", 1], ["primary", 1], ["secondary", 0],
			["helmet", 1], ["vest", 0], ["ultimate", 0], ["throw0", 0], ["throw1", 1]]:
		_select(shop, pick[0])
		shop._buy(shop.CATALOGUE[_list_for(shop, pick[0])][pick[1]])

	for i in 3:
		_select(shop, "pocket%d" % i)
		shop._buy(shop.CATALOGUE["pocket"][1])
	_select(shop, "pack")
	for pick in [5, 5, 0, 2, 2]:
		shop._buy(shop.CATALOGUE["stow"][pick])

	# Leave a slot open so the picker panel is in shot, which is the whole point
	# of the new screen.
	_select(shop, "primary")
	await _wait(10)
	await _save("res://tools/scr_shop.png")
	quit()


func _list_for(shop, id: String) -> String:
	for slot in shop.SLOTS:
		if slot.id == id:
			return slot.list
	return "stow"


func _select(shop, id: String) -> void:
	var kind := "slot"
	var list := _list_for(shop, id)
	if id.begins_with("pocket"):
		kind = "pocket"
		list = "pocket"
	elif id == "pack":
		kind = "pack"
		list = "stow"
	shop._open = {"id": id, "list": list, "label": id.to_upper(), "kind": kind}


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
