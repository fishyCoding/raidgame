extends SceneTree

## Does the survey actually see the level, and can it route across it?
##
## Checked before anything is wired to it: a graph that comes back empty, or that
## finds one enormous run covering the whole map, would still let a route search
## "succeed" while describing a level that is not there.

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 8:
		await physics_frame

	var nav: Object = (load("res://scripts/decoy_map.gd") as GDScript).new()
	var began := Time.get_ticks_msec()
	var size: Vector2i = nav.survey_size(self)
	var took := Time.get_ticks_msec() - began
	print("-- surveyed %d runs and %d links in %d ms --" % [size.x, size.y, took])
	_check(size.x > 8, "the level has to survey into a decent number of runs")
	_check(size.y > size.x, "and be joined up, not a pile of islands")
	_check(took < 900, "and be cheap enough to do on the first cast")

	# Every cable should join two different runs, or the only way up is missing.
	var cables: Array = get_nodes_in_group(&"zipline")
	var joined := 0
	for line in cables:
		var up: int = nav.run_at(self, line.world_top())
		var down: int = nav.run_at(self, line.world_bottom())
		if up >= 0 and down >= 0 and up != down:
			joined += 1
	print("  %d of %d cables join two runs" % [joined, cables.size()])
	_check(joined >= cables.size() - 2,
		"nearly every cable has to connect two floors, or there is no way up")

	# And routes between real places have to come back with something.
	var found := 0
	var rides := 0
	var tried := 0
	for a in cables.size():
		for b in cables.size():
			if a == b or (a + b) % 5 != 0:
				continue
			tried += 1
			var from: Vector2 = (cables[a] as Node2D).world_bottom()
			var to: Vector2 = (cables[b] as Node2D).world_top()
			var legs: Array = nav.route(self, from, to)
			if legs.is_empty():
				continue
			found += 1
			for leg in legs:
				if leg.kind == "cable":
					rides += 1
	print("  %d of %d routes found, %d cable legs in them" % [found, tried, rides])
	_check(found > tried * 0.8, "most places have to be reachable from most places")
	_check(rides > 0, "and routes between floors have to use the ropes")

	# --- and the line a player is shown has to be a line a body could walk ---
	#
	# The drawn route is a promise about the future, and one that runs through a
	# hillside is worse than no preview at all. Checked by walking the polyline
	# the HUD would draw and asking the world whether each step of it is inside
	# something solid.
	var space: PhysicsDirectSpaceState2D = (
		current_scene as Node2D).get_world_2d().direct_space_state
	var buried := 0
	var samples := 0
	for a in cables.size():
		for b in cables.size():
			if a == b or (a + b) % 7 != 0:
				continue
			var one: Vector2 = (cables[a] as Node2D).world_bottom()
			var two: Vector2 = (cables[b] as Node2D).world_top()
			for leg in nav.route(self, one, two):
				if leg.kind != "walk":
					continue
				for point in nav.walk_line(self, leg.from, leg.to):
					samples += 1
					# Lifted clear of the surface it is drawn on, because a line
					# along the floor legitimately touches the floor. Something
					# solid a body's knee above the ground is the line having
					# gone into the scenery.
					if _solid_at(space, point - Vector2(0.0, 20.0)):
						buried += 1
						if buried <= 8:
							var down := PhysicsRayQueryParameters2D.create(
								point - Vector2(0.0, 260.0),
								point + Vector2(0.0, 400.0))
							down.collision_mask = Layers.WORLD | Layers.ONE_WAY
							var real := space.intersect_ray(down)
							print("    buried at %s; true floor there is %s" % [
								str(point.round()),
								str((real.position as Vector2).round()) if real else "none"])
	print("  %d of %d points on the drawn route are inside geometry" % [
		buried, samples])
	_check(samples > 0, "there has to be a drawn route to check at all")
	_check(buried <= samples / 50,
		"the line players are shown cannot go through the floor")

	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("  FAIL  %s" % what)


## Whether a point is inside something solid.
func _solid_at(space: PhysicsDirectSpaceState2D, at: Vector2) -> bool:
	var probe := PhysicsPointQueryParameters2D.new()
	probe.position = at
	probe.collision_mask = Layers.WORLD
	return not space.intersect_point(probe, 1).is_empty()
