extends SceneTree

## What pulling the camera back actually buys, in numbers.
##
##   godot --headless --path . --script res://tools/zoom_probe.gd
##
## The zoom is one exported number and everything else divides by it, so this
## reads the things that are supposed to follow it rather than trusting that
## they do: how much world is on screen, how far concealment bothers raycasting,
## and how big the light is.

func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame

	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	for i in 30:
		await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("zoom | FAILED: never got a character")
		quit(1)
		return

	# An override, so the old framing and the new one can be measured by the same
	# code on the same spawn rather than compared against arithmetic.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zoom="):
			player.base_zoom = float(arg.get_slice("=", 1))
			player._base_zoom = Vector2(player.base_zoom, player.base_zoom)
			for i in 20:
				await physics_frame

	var vision: Node = get_first_node_in_group(&"vision_system")
	var zoom: float = player.get_camera_zoom()
	var view: Vector2 = root.get_visible_rect().size / zoom

	print("zoom | base_zoom=%.2f  live zoom=%.2f" % [player.base_zoom, zoom])
	print("zoom | world on screen: %.0f x %.0f px (%.1f x %.1f characters wide)" % [
		view.x, view.y, view.x / 28.0, view.y / 48.0])
	print("zoom | concealment reach: %.0f px (floor is %.0f)" % [
		vision._reach if vision else 0.0, vision.vision_range if vision else 0.0])
	var light: Light2D = player.get_node("Vision")
	print("zoom | vision light scale: %.2f" % light.texture_scale)

	# The guards outrange what you can see, which is the reason the camera is
	# pulled back at all - so the useful number is how many of them are inside
	# the frame rather than how many pixels it is.
	var in_frame := 0
	for guard in main.get_node("Enemies").get_children():
		if not guard.has_method(&"is_brain"):
			continue
		var away: Vector2 = (guard as Node2D).global_position - player.global_position
		if absf(away.x) <= view.x * 0.5 and absf(away.y) <= view.y * 0.5:
			in_frame += 1
	print("zoom | guards inside the frame from here: %d" % in_frame)

	print("\nDONE")
	quit()
