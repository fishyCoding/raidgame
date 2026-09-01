extends SceneTree

## Photographs both halves of the Headcount: the dial the man running one reads,
## and the mark on the glass of somebody caught in it.
##
##   godot --path . --script res://tools/headcount_shot.gd
##
## Not headless: it takes pictures. The two shots are deliberately taken from the
## same viewpoint, because the whole design is in the difference between them.

const HEADCOUNT := "res://resources/gadgets/headcount.tres"

var _stand_ins: Array[Node2D] = []


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
	await _wait(60)

	var player: Node2D = net.local_player
	if player == null:
		print("headcount_shot | never got a character")
		quit(1)
		return
	var hud: Node = main.get_node("HUD/WeaponHUD")

	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var ult: Object = maker.from_gadget(load(HEADCOUNT))
	ult.charge = 1.0
	player.inventory.set_ultimate(ult)

	# Three of them, spread round the compass, so the dial has something to say
	# in more than one wedge.
	var roster: Dictionary = net._players
	for spread in [[2, Vector2(420.0, -60.0)], [3, Vector2(-380.0, -300.0)],
			[4, Vector2(90.0, 700.0)]]:
		var body := Node2D.new()
		body.name = "StandIn%d" % spread[0]
		body.global_position = player.global_position + (spread[1] as Vector2)
		root.add_child(body)
		_stand_ins.append(body)
		roster[spread[0]] = body

	player._use_ultimate()
	await _wait(30)
	await _save("res://tools/scr_headcount.png")
	print("headcount_shot | saved scr_headcount.png - the dial and the tally")

	# And the other end of it. Nothing on this screen names the gadget, says a
	# number, or points anywhere: a swell at the edges and a line crossing it.
	player.count_left = 0.0
	for body in _stand_ins:
		roster.erase(int(str(body.name).right(1)))
		body.queue_free()
	_stand_ins.clear()
	await _wait(10)
	# Tapped every frame, the way a count that is still running does every half
	# second, so the shot is of the effect at full rather than half faded out.
	for i in 90:
		player.mark_counted()
		await process_frame
	await _save("res://tools/scr_headcount_watched.png")
	print("headcount_shot | saved scr_headcount_watched.png - being counted")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
