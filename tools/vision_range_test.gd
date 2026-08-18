extends SceneTree

## The sight cut-off must always fall outside the frame.
##
## There is still a cut-off - it is what stops every body on the map being
## raycast seventeen times a frame - but you must never be able to watch it
## work. The old fixed 880 px was inside the frame at the default zoom and well
## inside it through a scope, which is what made guards blink out in mid-air.
##
## Checked geometrically rather than by looking for a guard at a given spot: the
## property is "reach covers the corner of the screen at every zoom the game
## uses", and that is exactly what is measured here.

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	net.play_solo()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await physics_frame

	var waited := 0
	while net.local_player == null and waited < 600:
		await physics_frame
		waited += 1
	var player: Node2D = net.local_player
	if player == null:
		print("vision | FAILED: no character")
		quit(1)
		return

	# Deliberately untyped. Naming the VisionSystem class here forces that script
	# to compile while this one is being parsed, which is before the autoloads
	# are registered - and it references Net, so it fails to compile at all.
	var vision: Node = main.get_node("VisionSystem")
	var camera: Camera2D = player.get_node("Camera2D")
	var eye: Node2D = player.get_node("Vision")

	# Past the shop and the briefing. Without this the tree stays paused, the
	# vision system's _physics_process never runs, and it never even resolves
	# which node is the eye - every reading below comes back as zero.
	await _wait(15)
	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(20)

	var view: Vector2 = root.get_visible_rect().size
	print("vision | viewport %dx%d, floor %.0fpx" % [view.x, view.y, vision.vision_range])

	var reaches := {}
	# The zooms the game actually uses: hip, aimed, bow out, bow at full draw.
	for zoom in [player.base_zoom, 1.0, player.bow_zoom, player.bow_zoom_full]:
		camera.zoom = Vector2(zoom, zoom)
		# Measured in the same frame it is set, with no await. The player drives
		# the camera every physics tick from its own aim and bow state, so
		# waiting here would quietly hand back the player's current zoom and
		# report the same number four times.
		var reach: float = vision._sight_reach()
		reaches[zoom] = reach
		# Furthest point that can be on screen, measured from the eye - which is
		# not the camera, because aiming leans the lens off the body.
		var half_view := (view / camera.zoom) * 0.5
		var lens: float = eye.global_position.distance_to(camera.get_screen_center_position())
		var corner: float = half_view.length() + lens

		var covered := reach >= corner
		print("vision | zoom %.2f -> screen corner %.0fpx, reach %.0fpx  %s" % [
			zoom, corner, reach, "ok" if covered else "VISIBLE CUT-OFF"])
		if not covered:
			_ok = false

	# Scoping out has to widen it, or the whole thing is a constant wearing a
	# function's clothes.
	_check("wider view reaches further",
		reaches[player.bow_zoom_full] > reaches[player.base_zoom])
	# And the old fixed value has to be genuinely too small, or none of this was
	# worth doing.
	_check("the old 880 was not enough", reaches[player.base_zoom] > 880.0)

	print("vision | %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(what: String, passed: bool) -> void:
	print("vision | %-30s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
