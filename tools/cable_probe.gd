extends SceneTree

## How far each cable's ends are above the floor a body would stand on.
##
## The routing rejects a cable whose usable end is more than FLOOR_REACH off its
## own height, on the reasoning that the end you board at has to be one you can
## walk to. If the ends hang well above the floor, that rule rejects every cable
## on the map - which would explain a decoy that never rides anything and ends up
## on the wrong floor.

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame

	var space: PhysicsDirectSpaceState2D = main.get_world_2d().direct_space_state
	var worst := 0.0
	var over := 0
	var total := 0
	print("cable            end        drop to floor")
	for node in get_nodes_in_group(&"zipline"):
		var line: Node2D = node
		for label in ["top", "bottom"]:
			var at: Vector2 = line.world_top() if label == "top" else line.world_bottom()
			var query := PhysicsRayQueryParameters2D.create(at, at + Vector2(0.0, 900.0))
			query.collision_mask = 3
			var hit: Dictionary = space.intersect_ray(query)
			total += 1
			if hit.is_empty():
				print("  %-14s %-9s no floor within 900" % [line.name, label])
				over += 1
				continue
			var drop: float = (hit.position as Vector2).y - at.y
			worst = maxf(worst, drop)
			if drop > 130.0:
				over += 1
			print("  %-14s %-9s %6.0f px%s" % [
				line.name, label, drop, "   <-- beyond FLOOR_REACH" if drop > 130.0 else ""])

	print("\n%d of %d ends are more than 130 px above their floor; worst is %.0f" % [
		over, total, worst])
	quit()
