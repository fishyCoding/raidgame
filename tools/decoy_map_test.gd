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

	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("  FAIL  %s" % what)
