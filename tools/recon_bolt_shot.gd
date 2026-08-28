extends SceneTree

## Photographs the recon dart, close up: in flight, just landed, and nearly out.
##
##   godot --path . --script res://tools/recon_bolt_shot.gd
##
## Not headless: it takes pictures. The dart is about thirty pixels long and the
## game is played at 0.75 zoom, so the camera is pushed right in here - what is
## being checked is the object, and at playing distance every version of it looks
## like the same three pixels.

const BOLT := "res://scenes/recon_bolt.tscn"
const GADGET := "res://resources/gadgets/recon_bow.tres"


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
		print("recon_bolt_shot | never got a character")
		quit(1)
		return

	# Blown up by scaling the dart rather than by pulling the camera in, because
	# the player rewrites its own zoom every frame and quietly undid it. Scaling
	# the node takes the line widths with it, which is what a magnifying glass
	# does and what is wanted here.
	const BIG := 7.0

	var gadget: Resource = load(GADGET)
	var scene: PackedScene = load(BOLT)

	# In the air, held there rather than fired: a dart in flight crosses the
	# frame in a couple of frames at three thousand pixels a second.
	var flying: Node2D = scene.instantiate()
	flying.setup(gadget, 1.0)
	main.add_child(flying)
	flying.global_position = player.global_position + Vector2(0.0, -150.0)
	flying.rotation = -0.35
	flying.scale = Vector2(BIG, BIG)
	flying.set_physics_process(false)
	await _wait(6)
	await _save("res://tools/scr_recon_flight.png")
	print("recon_bolt_shot | saved scr_recon_flight.png (in the air)")
	flying.queue_free()

	# And stuck, which is when it does its job: struts out, strip full, then the
	# same dart with the paint nearly gone.
	var stuck: Node2D = scene.instantiate()
	stuck.setup(gadget, 1.0)
	main.add_child(stuck)
	stuck.global_position = player.global_position + Vector2(0.0, -150.0)
	stuck.rotation = -0.35
	stuck.scale = Vector2(BIG, BIG)
	stuck.set_physics_process(false)
	stuck._stuck = true
	stuck._age = 0.0
	await _wait(14)
	await _save("res://tools/scr_recon_stuck.png")
	print("recon_bolt_shot | saved scr_recon_stuck.png (just bitten, %.0f%% paint)"
		% (stuck._charge_left() * 100.0))

	stuck._age = gadget.active_time * 0.82
	await _wait(4)
	await _save("res://tools/scr_recon_spent.png")
	print("recon_bolt_shot | saved scr_recon_spent.png (%.0f%% paint left)"
		% (stuck._charge_left() * 100.0))
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
