extends SceneTree

## Photographs the workshop:
##
##   godot --path . --script res://tools/gunsmith_shot.gd
##
## Not headless: it takes pictures. Four of them, because the screen has four
## states worth looking at - a bare gun, a shelf open with a part being weighed
## up, a finished build, and a sidearm, which is the one that proves the diagram
## is drawn from the gun rather than from one hardcoded rifle.

const ATT := "res://resources/attachments/%s.tres"


func _initialize() -> void:
	_run()


func _run() -> void:
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _wait(20)

	var shop: Node = lobby._shop
	if shop == null:
		print("gunsmith_shot | no kit screen - nothing to photograph")
		quit(1)
		return
	shop.credits = 16000

	# A rifle bought the ordinary way, so the gun in the workshop is one the shop
	# actually sold.
	_select(shop, "primary")
	shop._buy(shop.CATALOGUE["primary"][1])
	_select(shop, "secondary")
	shop._buy(shop.CATALOGUE["secondary"][0])
	shop._open = {}
	await _wait(4)
	await _save("res://tools/scr_kit_modify.png")
	print("gunsmith_shot | saved scr_kit_modify.png - the way in, on the kit screen")

	var rifle: Object = shop._inventory.primary
	shop._open_gunsmith(rifle)
	await _wait(6)
	var smith: Node = shop._smith
	await _save("res://tools/scr_gunsmith_bare.png")
	print("gunsmith_shot | saved scr_gunsmith_bare.png - a gun with nothing on it")

	# A slot open, and a part being weighed up: the shelf on the right, and the
	# bars underneath showing what it would do.
	smith._slot = AttachmentData.Slot.OPTIC
	smith._hover = load(ATT % "marksman_4x")
	await _wait(4)
	await _save("res://tools/scr_gunsmith_shelf.png")
	print("gunsmith_shot | saved scr_gunsmith_shelf.png - weighing up a 4x")

	# And built out. Bought through the screen's own path rather than fitted
	# behind its back, so the credits in the corner are the real ones.
	for part in ["marksman_4x", "suppressor", "drum_mag", "vertical_grip", "heavy_stock"]:
		smith._fit(load(ATT % part))
	smith._slot = -1
	smith._hover = null
	await _wait(4)
	await _save("res://tools/scr_gunsmith_built.png")
	print("gunsmith_shot | saved scr_gunsmith_built.png - everything bolted on")

	# The sidearm, which takes a can and a dot and refuses the rest.
	smith.open(shop, shop._inventory.secondary)
	smith._fit(load(ATT % "suppressor"))
	smith._fit(load(ATT % "red_dot"))
	smith._fit(load(ATT % "laser_sight"))
	smith._slot = AttachmentData.Slot.STOCK
	await _wait(4)
	await _save("res://tools/scr_gunsmith_pistol.png")
	print("gunsmith_shot | saved scr_gunsmith_pistol.png - a sidearm, and a slot it has no use for")
	quit()


func _select(shop: Node, id: String) -> void:
	for region in shop._regions:
		if region.get("kind", "") == "slot" and region.get("id", "") == id:
			shop._open = region.duplicate()
			return
	shop._open = {"id": id, "list": id}


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
