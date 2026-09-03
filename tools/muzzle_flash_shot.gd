extends SceneTree

## Photographs a few muzzle flashes side by side - loud, quiet, suppressed,
## overheated - so the size/colour differences the header comment on
## muzzle_flash.gd promises can actually be checked by eye.
##
##   godot --path . --script res://tools/muzzle_flash_shot.gd
##
## Not headless: it takes a picture.

const BG := Color(0.08, 0.09, 0.11)


func _initialize() -> void:
	_run()


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	var backdrop := ColorRect.new()
	backdrop.color = BG
	backdrop.size = Vector2(900, 260)
	backdrop.position = Vector2(-30, -130)
	world.add_child(backdrop)

	var cam := Camera2D.new()
	cam.position = Vector2(400, 0)
	cam.zoom = Vector2(1.4, 1.4)
	world.add_child(cam)
	await process_frame
	cam.make_current()

	# One flash per case, spaced out in a row and each labelled underneath.
	var cases := [
		{"name": "quiet (pistol, suppressed)", "loud": -18.0, "sup": true, "heat": 0.0},
		{"name": "ordinary (AR, stock cell)", "loud": 0.0, "sup": false, "heat": 0.0},
		{"name": "loud (LMG, overtiered)", "loud": 10.0, "sup": false, "heat": 0.0},
		{"name": "overheated (heat 0.9)", "loud": 10.0, "sup": false, "heat": 0.9},
	]
	var flash_script := load("res://scripts/muzzle_flash.gd") as GDScript
	var x := 0.0
	for c in cases:
		var data := WeaponData.new()
		data.loudness_trim = c.loud
		data.suppressed = c.sup
		var flash: Node2D = flash_script.new()
		flash.position = Vector2(x, 0.0)
		flash.rotation = 0.0
		flash.lifetime = 5.0 # held open long enough to screenshot
		world.add_child(flash)
		flash.setup(data, c.heat)

		var label := Label.new()
		label.text = c.name
		label.position = Vector2(x - 60.0, 60.0)
		label.size = Vector2(160.0, 40.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.add_theme_color_override("font_color", Color(0.85, 0.89, 0.94))
		world.add_child(label)
		x += 220.0

	await _wait(4)
	await _save("res://tools/scr_muzzle_flash.png")
	print("muzzle_flash_shot | saved")
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
