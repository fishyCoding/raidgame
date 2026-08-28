extends SceneTree

## Photographs the streak a dash leaves: mid-move, and once it has faded.
##
##   godot --path . --script res://tools/dash_trail_shot.gd
##
## Not headless: it takes pictures. Only the dashing player ever sees this, so
## the shot is taken through their own camera - which is the only camera there
## is, and the whole point of where the trail is drawn.

const DASH := "res://resources/gadgets/dash.tres"


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
		print("dash_trail_shot | never got a character")
		quit(1)
		return

	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var ult: Object = maker.from_gadget(load(DASH))
	ult.charge = 1.0
	player.inventory.set_ultimate(ult)
	player._use_ultimate()
	while not player.is_on_floor():
		await process_frame
	await _wait(20)

	# Whichever way there is room. The spawn moves between runs, and a dash into
	# a wall photographs the wall.
	var way := _open_way(player)
	var input: Node = root.get_node("PlayerInput")
	player.dash_ready = true
	await _wait(2)
	input.touch_dash = true
	input.touch_dash_way = Vector2(way, 0.0)

	var trail: Node2D = player.get_parent().get_node("DashTrail_%s" % player.name)
	# Caught while the body is still moving, which is the only moment the streak
	# has a body on the end of it.
	while not player.is_dashing():
		await process_frame
	while player.is_dashing() and trail._marks.size() < 5:
		await process_frame
	await _save("res://tools/scr_dash_trail.png", trail)

	# And again once the move is over and the streak is going. What is worth
	# seeing here is that it is behind you rather than on you.
	await _wait(4)
	await _save("res://tools/scr_dash_fading.png", trail)
	quit()


## Which way there is room to dash, as -1 or 1.
func _open_way(player: Node2D) -> float:
	var space := player.get_world_2d().direct_space_state
	var best := 1.0
	var best_room := -1.0
	for way in [1.0, -1.0]:
		var from: Vector2 = player.global_position - Vector2(0.0, 14.0)
		var probe := PhysicsRayQueryParameters2D.create(
			from, from + Vector2(way * 400.0, 0.0), 1)
		var hit := space.intersect_ray(probe)
		var room: float = 400.0 if hit.is_empty() else from.distance_to(hit.position)
		if room > best_room:
			best_room = room
			best = way
	return best


func _save(path: String, trail: Node2D) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("dash_trail_shot | saved %s (%d marks)" % [
		path.get_file(), trail._marks.size()])


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
