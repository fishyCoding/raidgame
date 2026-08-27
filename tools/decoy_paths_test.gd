extends SceneTree

## Does the decoy actually get where it is sent? Asked many times, across the
## whole level, rather than once from wherever the spawn roll happened to drop it.
##
## Every previous check on this was a single journey from a single spawn, which
## is why five separate routing faults reached the person playing it: one sample
## cannot tell "the pathing works" from "the pathing works from here". This walks
## a real body between real places - cable ends, floor spots, up, down and across
## - and reports how many arrive.
##
## It also prints the ones that fail with their coordinates, because a pass rate
## on its own tells you nothing about what to fix.
##
## Guards are switched off for the duration. They are eleven bodies raycasting
## every frame, they make the run several times longer, and a decoy does not
## react to them anyway - so all they contribute is noise and time.

## Slack added to every journey's own distance-based budget, in physics frames.
## Four seconds, which covers walking to a rope, the ride itself, and the walk
## off the far end.
const JOURNEY_SLACK := 240

## How close counts as arrived. Generous horizontally - it is bait, not a taxi,
## and standing a body-width away from a clicked point is a success - but tight
## vertically, because landing on the wrong floor is the failure this exists to
## catch.
const ARRIVE_X := 140.0
const ARRIVE_Y := 100.0

## What fraction of journeys have to arrive. Not 100: the level has genuine
## dead ends, and a decoy that refuses an impossible errand and goes back to
## baiting is behaving correctly. Set where it is so a real regression moves it.
const WANT_RATE := 0.75

var _ok := true


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
	await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("no character - cannot run")
		quit(1)
		return

	# Quiet, and much faster.
	for guard in main.get_node("Enemies").get_children():
		guard.set_physics_process(false)
		guard.set_process(false)

	var spots := _places(main, player)
	print("-- %d places to walk between --" % spots.size())
	for spot in spots:
		print("   %s" % str(spot))

	var runs := _journeys(spots)
	print("\n-- %d journeys --" % runs.size())

	var ghost: Node2D = (load("res://scenes/projection.tscn") as PackedScene).instantiate()
	ghost.name = "Ghost_soak"
	main.get_node("Players").add_child(ghost)

	var arrived := 0
	var failures: Array = []
	for run in runs:
		# Budgeted on the distance rather than a flat count: a 1400 px walk with a
		# rope in the middle legitimately takes twice as long as a 300 px one.
		# Distance at the pace it actually walks, plus slack for ropes and
		# obstacles - but never more than the errand itself is allowed to last,
		# because past that the body correctly gives up and goes back to
		# baiting. Waiting longer than the game does would be measuring
		# something the player never sees.
		var budget := mini(int(run.span / 160.0 * 60.0) + JOURNEY_SLACK, 1140)
		var result := await _journey(ghost, run.from, run.to, budget)
		if result.arrived:
			arrived += 1
		else:
			failures.append(result)
		print("  %s %-28s -> %-28s  closest %5.0f px%s" % [
			"ok  " if result.arrived else "MISS",
			str(run.from.round()), str(run.to.round()),
			result.closest, "" if result.arrived else "   (%s)" % result.why])

	var rate := float(arrived) / float(maxi(runs.size(), 1))
	print("\n-- %d of %d arrived (%.0f%%) --" % [arrived, runs.size(), rate * 100.0])
	if not failures.is_empty():
		print("\nmissed:")
		for miss in failures:
			print("  from %s to %s: closest %.0f px, %s" % [
				str(miss.from.round()), str(miss.to.round()), miss.closest, miss.why])

	_check(rate >= WANT_RATE,
		"at least %.0f%% of journeys have to arrive" % (WANT_RATE * 100.0))
	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("  FAIL  %s" % what)


## Places worth walking between: both ends of every cable, plus a spot along the
## floor either side of each, so journeys are not all cable-end to cable-end.
func _places(main: Node, player: Node2D) -> Array[Vector2]:
	var space := player.get_world_2d().direct_space_state
	var found: Array[Vector2] = []
	for node in get_nodes_in_group(&"zipline"):
		var line: Node2D = node
		for end in [line.world_top(), line.world_bottom()]:
			for offset in [0.0, 180.0, -180.0]:
				var spot := _ground(space, (end as Vector2) + Vector2(offset, -20.0))
				if spot.is_finite() and not _near_any(found, spot, 90.0):
					found.append(spot)
	return found


## Dropped to the floor under it, the way a click is - so every place tested is
## somewhere a body could actually stand.
func _ground(space: PhysicsDirectSpaceState2D, at: Vector2) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(at, at + Vector2(0.0, 400.0))
	query.collision_mask = 3
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector2.INF
	return (hit.position as Vector2) - Vector2(0.0, 24.0)


func _near_any(places: Array[Vector2], spot: Vector2, gap: float) -> bool:
	for place in places:
		if place.distance_to(spot) < gap:
			return true
	return false


## Pairs to try. Deliberately a spread: same floor, one floor up, one floor down,
## and a couple of long hauls - the kinds of errand a player actually sends one
## on, rather than whichever pair happened to be nearest.
func _journeys(spots: Array[Vector2]) -> Array:
	var runs: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260827
	for i in 18:
		var from: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
		var to: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
		var span := from.distance_to(to)
		# Far enough to be a journey, near enough to be one the gadget could
		# actually complete. A decoy lives fourteen seconds and walks at about
		# 160 px/s, so anything past ~1500 px is further than it can go before it
		# expires - demanding those would be testing the clock, not the routing.
		if span < 200.0 or span > 1500.0:
			continue
		runs.append({"from": from, "to": to, "span": span})
	return runs


## One journey, run on a real body.
func _journey(ghost: Node2D, from: Vector2, to: Vector2, frames: int) -> Dictionary:
	ghost.global_position = from
	ghost.velocity = Vector2.ZERO
	ghost.life_left = 90.0
	ghost.hits = 0
	ghost._stand_down()
	await physics_frame
	var _sent: bool = ghost.order_to(to)

	# What the planner thinks it will do, so a failure can be pinned on the
	# plan or on the walking rather than guessed at.
	var route: Object = (load("res://scripts/decoy_route.gd") as GDScript).new()
	var legs: Array = route.plan(self, ghost.global_position, to)
	var planned_rides := 0
	for leg in legs:
		if leg.cable:
			planned_rides += 1

	var closest := INF
	var rode := false
	var picked := false
	# The dominant miss is a body ending a floor or more below a route it had
	# right, so the fall itself is what needs describing: how far, from where,
	# and whether it was on a rope at the time.
	var worst_fall := 0.0
	var fell_from := Vector2.INF
	var falling_from := Vector2.INF
	for i in frames:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		if ghost.riding:
			rode = true
		if ghost._leg_cable != null:
			picked = true

		# A fall is time spent off the floor and not on a rope.
		if ghost.is_on_floor() or ghost.riding:
			falling_from = ghost.global_position
		elif falling_from.is_finite():
			var drop: float = ghost.global_position.y - falling_from.y
			if drop > worst_fall:
				worst_fall = drop
				fell_from = falling_from
		var gap := ghost.global_position - to
		if absf(gap.x) <= ARRIVE_X and absf(gap.y) <= ARRIVE_Y:
			return {"from": from, "to": to, "arrived": true, "closest": 0.0,
				"why": "", "plan": planned_rides, "picked": picked, "rode": rode}
		closest = minf(closest, gap.length())

	# Why it did not get there, in the terms the body itself would use.
	var why := "still walking"
	if ghost._mind != 0:
		why = "errand expired" if ghost._orders_left <= 0.0 else "gave up on the order"
	if ghost._refusals > 0:
		why = "refused %d obstacles" % ghost._refusals
	if absf(ghost.global_position.y - to.y) > ARRIVE_Y:
		why += ", wrong floor by %.0f px" % absf(ghost.global_position.y - to.y)
	if not rode and absf(from.y - to.y) > 140.0:
		why += ", never took a rope"
	why += "  [plan %d ride(s), chose %s, rode %s]" % [
		planned_rides, picked, rode]
	if worst_fall > 150.0:
		why += "  FELL %.0f px from %s" % [worst_fall, str(fell_from.round())]
	return {"from": from, "to": to, "arrived": false, "closest": closest,
		"why": why, "plan": planned_rides, "picked": picked, "rode": rode}
