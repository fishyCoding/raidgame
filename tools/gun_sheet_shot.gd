extends SceneTree

## Every gun in the game, bare and loaded, on one sheet.
##
##   godot --path . --script res://tools/gun_sheet_shot.gd
##
## Not headless: it takes a picture. The workshop only ever shows the gun you
## happen to be working on, which means a silhouette that is wrong for one weapon
## can sit there for weeks - the profiles are seven rows of numbers and nothing
## compares them. This draws all of them at once, each with every mount under
## load, so a part that has come unstuck is obvious in one glance rather than in
## seven visits.

const CANVAS := preload("res://tools/gun_sheet_canvas.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var sheet := Control.new()
	sheet.set_script(CANVAS)
	root.add_child(sheet)
	current_scene = sheet
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/scr_gun_sheet.png")
	print("gun_sheet_shot | saved scr_gun_sheet.png - every gun, bare and loaded")
	quit()
