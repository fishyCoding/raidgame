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

## How long each journey is given, in physics frames. The decoy's own errand is
## eighteen seconds and it stands down at the end of it, so anything past that is
## measuring a body that has already stopped trying.
const JOURNEY_FRAMES := 1140

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

## How many journeys to walk. Enough that one unlucky pair does not move the
## rate by ten points, which nine did.
const WANT_JOURNEYS := 24

## The longest route worth demanding, measured along the route itself.
##
## An errand lasts eighteen seconds and the body walks at about 187 px/s, so
## three thousand pixels of ground is the theoretical ceiling - but a route costs
## noticeably more time than its length suggests. Climbing, waiting out a rope
## ride, and the pause after stepping off one all buy no horizontal distance, and
## measured across this soak they cost something like half as much again.
##
## Set from that rather than from a round number, because the alternative is
## demanding journeys the gadget cannot physically finish and calling the
## stopwatch a pathfinding fault. Routes longer than this do still get walked in
## the game - the decoy just stands down partway, which is what it is supposed to
## do when an errand outlasts it.
const REACHABLE := 1900.0

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
		# The errand's own length, for every journey. It used to be budgeted on
		# the distance at walking pace, which quietly cut long journeys short:
		# almost every failure came back "still walking" with errand time to
		# spare, meaning the body was fine and the stopwatch was wrong. Rope
		# rides, drops and the pause after stepping off all cost seconds that a
		# distance-over-speed sum does not know about. The game gives it
		# ORDERS_TIME and then gives up; so does this.
		var budget := JOURNEY_FRAMES
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
	var map: GDScript = load("res://scripts/decoy_map.gd")
	var runs: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260827
	for i in 90:
		if runs.size() >= WANT_JOURNEYS:
			break
		var from: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
		var to: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
		if from.distance_to(to) < 200.0:
			continue
		# Measured along the route, not across the room. A pair 1400 px apart
		# whose only way round is a 4000 px detour is not a pathfinding failure
		# when the body runs out of errand halfway - it is an errand nobody could
		# finish, and counting it says nothing about whether the route was
		# followed. Crow-flies distance was the old filter and it let a fistful
		# of those in, which is why the rate looked worse than the walking was.
		var legs: Array = map.route(self, from, to)
		if legs.is_empty():
			continue
		var span := 0.0
		for leg in legs:
			span += (leg.from as Vector2).distance_to(leg.to as Vector2)
		if span > REACHABLE:
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
	# A clean body. Cable memory in particular lasts nine seconds and journeys
	# take up to nineteen, so without this the second journey of every pair
	# starts forbidden from touching the rope it needs and the run measures the
	# test's own bookkeeping rather than the routing.
	# Off any rope first. `riding` survives being repositioned, and a body that
	# is still holding the previous journey's cable gets dragged along it from
	# wherever you put it - which showed up as a 659 px walk along one floor
	# finishing two thousand pixels away and three floors down.
	ghost._zipline = null
	ghost.riding = false
	ghost._last_cable = null
	ghost._cable_cooldown = 0.0
	ghost._refusals = 0
	ghost._detour_left = 0.0
	ghost._settle_left = 0.0
	ghost._legs = []
	ghost._replan = 0.0
	ghost._leg_cable = null
	ghost._leg_end = Vector2.INF
	ghost._target = Vector2.INF
	await physics_frame
	var _sent: bool = ghost.order_to(to)

	# What the map planned, so a failure can be pinned on the route or on the
	# walking rather than guessed at. This is the very plan the body is holding,
	# read back off it, not a second opinion that might not match.
	var legs: Array = ghost._legs
	var planned_rides := 0
	var shape: Array = []
	for leg in legs:
		if leg.kind == "cable":
			planned_rides += 1
		shape.append(leg.kind)

	var closest := INF
	var rode := false
	var picked := false
	for i in frames:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		if ghost.riding:
			rode = true
		if ghost._leg_cable != null:
			picked = true
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
	# Where along the plan it stalled is the single most useful number here: a
	# body that never finished leg 0 has a walking problem, and one that died on
	# the last leg has a route that was nearly right.
	# Read at the end, so this is the plan it held when it ran out of time.
	var last: Array = []
	for leg in ghost._legs:
		last.append(leg.kind)
	why += "  [%d legs left: %s]" % [last.size(),
		", ".join(PackedStringArray(last)) if not last.is_empty() else "no route"]
	why += "  rode %s" % rode
	return {"from": from, "to": to, "arrived": false, "closest": closest,
		"why": why, "plan": planned_rides, "picked": picked, "rode": rode}
