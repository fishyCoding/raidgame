extends SceneTree

## How much further can you see with the bow out?
##   godot --headless --path <project> --script res://tools/bowzoom_test.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run(main)


func _run(main: Node) -> void:
	await physics_frame
	await physics_frame
	var shop = main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	main.get_node("HUD/Screens")._start_raid()
	await physics_frame

	var input: Node = root.get_node("/root/PlayerInput")
	var player: CharacterBody2D = main.get_node("Player")
	var camera: Camera2D = player.get_node("Camera2D")
	for guard in main.get_node("Enemies").get_children():
		guard.process_mode = Node.PROCESS_MODE_DISABLED

	var kit: Inventory = player.inventory
	kit.set_ultimate(Item.from_gadget(load("res://resources/gadgets/recon_bow.tres")))
	kit.ultimates[0].charge = 1.0
	player.global_position = Vector2(-1600, 200)
	input.touch_aim_direction = Vector2.RIGHT
	for i in 30:
		await physics_frame

	print("-- what you can see --")
	_report("gun in hand", player, camera)

	player._use_ultimate()
	for i in 20:
		await physics_frame
	_report("bow out", player, camera)

	input.touch_fire_held = true
	for i in 60:
		await physics_frame
	_report("bow at full draw", player, camera)
	print("  draw: %d%%" % roundi(player.bow_drawn * 100.0))
	input.touch_fire_held = false
	quit()


func _report(label: String, player: CharacterBody2D, camera: Camera2D) -> void:
	var half: float = player.get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var ahead: float = half + absf(camera.position.x)
	print("  %-18s zoom %.2fx | lean %4.0f px | %4.0f px of ground ahead" % [
		label, camera.zoom.x, absf(camera.position.x), ahead])
