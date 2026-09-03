extends SceneTree

## One overheated muzzle flash, zoomed in close, for checking the layered
## glow/petal detail actually reads at a size a player would see it.
##
##   godot --path . --script res://tools/muzzle_flash_closeup.gd

const BG := Color(0.06, 0.07, 0.09)


func _initialize() -> void:
	_run()


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	var backdrop := ColorRect.new()
	backdrop.color = BG
	backdrop.size = Vector2(400, 400)
	backdrop.position = Vector2(-200, -200)
	world.add_child(backdrop)

	var cam := Camera2D.new()
	cam.zoom = Vector2(6.0, 6.0)
	world.add_child(cam)
	await process_frame
	cam.make_current()

	var flash_script := load("res://scripts/muzzle_flash.gd") as GDScript
	var data := WeaponData.new()
	data.loudness_trim = 10.0
	data.suppressed = false
	var flash: Node2D = flash_script.new()
	flash.lifetime = 5.0
	world.add_child(flash)
	flash.setup(data, 0.9)

	await _wait(4)
	await _save("res://tools/scr_muzzle_flash_closeup.png")
	print("muzzle_flash_closeup | saved")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
