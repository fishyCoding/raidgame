extends SceneTree

## Photographs the kit screen - which is now the menu, and is the first thing
## anybody sees:
##
##   godot --path . --script res://tools/kit_shot.gd
##
## Not headless: it takes pictures. No server and no second player any more -
## kitting out happens before you queue, so the screen exists on its own.


func _initialize() -> void:
	_run()


func _run() -> void:
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _wait(20)

	var shop: Node = lobby._shop
	if shop == null:
		print("kit_shot | no kit screen in the menu - nothing to photograph")
		quit(1)
		return

	# A loadout, so the screen is not a column of empty boxes. The power source
	# comes before the gadget on purpose: an ultimate has nowhere to go until
	# there is a rack to put it in, and buying them the other way round is a
	# refusal rather than a shot.
	shop.credits = 16000
	for pick in [["backpack", 1], ["primary", 1], ["secondary", 0],
			["helmet", 1], ["vest", 0], ["power", 1], ["throw0", 0]]:
		_select(shop, pick[0])
		shop._buy(shop.CATALOGUE[_list_for(shop, pick[0])][pick[1]])
	# Two gadgets into the rack, which is what fills the middle column.
	for which in [6, 3]:
		_select(shop, "rack")
		shop._buy(shop.CATALOGUE["ultimate"][which])
	for i in 2:
		_select(shop, "pocket%d" % i)
		shop._buy(shop.CATALOGUE["pocket"][1])
	# A slot left open, so the picker panel is in shot - it is most of the screen.
	_select(shop, "primary")
	shop._message = ""

	await _wait(20)
	await _save("res://tools/scr_kit_menu.png")

	# Scrolled, so the masking at both ends of the shelf is in shot. A card is
	# taller than the gap above the band and will overhang it.
	shop._scroll = 150.0
	await _wait(5)
	await _save("res://tools/scr_kit_scrolled.png")
	shop._scroll = 0.0

	# And the ammunition button, which builds its shelf out of the guns bought
	# above rather than out of the catalogue.
	shop._open = {"id": "ammo", "list": "ammo", "label": "AMMUNITION", "kind": "slot"}
	await _wait(5)
	await _save("res://tools/scr_kit_ammo.png")

	# The two new shelves. The power sources, which is where the whole decision
	# starts, and the gadgets, which is where it is spent - both worth a picture
	# because a shelf that says what a thing costs in *cells* is the point.
	_select(shop, "power")
	shop._scroll = 0.0
	await _wait(5)
	await _save("res://tools/scr_kit_power.png")

	_select(shop, "rack")
	shop._scroll = 0.0
	await _wait(5)
	await _save("res://tools/scr_kit_rack.png")

	print("kit_shot | saved")
	quit()


func _list_for(shop: Node, id: String) -> String:
	for slot in shop.SLOTS:
		if slot.id == id:
			return slot.list
	return "stow"


func _select(shop: Node, id: String) -> void:
	var kind := "slot"
	var list := _list_for(shop, id)
	if id.begins_with("pocket"):
		kind = "pocket"
		list = "pocket"
	# The rack is a container in the middle column rather than a slot on the
	# left, so it names its own list the way the pockets do.
	if id == "rack":
		kind = "pack"
		list = "ultimate"
	shop._open = {"id": id, "list": list, "label": id.to_upper(), "kind": kind}


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
