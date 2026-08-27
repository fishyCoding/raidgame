extends RefCounted

## A walkable map of the level, built once, and a route search over it.
##
## This replaces a pile of local rules - probe for a ledge, guess whether a drop
## helps, grab a rope if one is near - that each traded one failure for another.
## A soak across the level had them arriving 37% of the time, and every fix moved
## the failures around rather than removing them. The reason is that all of those
## rules answer "what is directly in front of me", and the question the body
## actually has is "how do I get from here to there", which nothing local can
## answer.
##
## So the geometry is surveyed once into **runs** - horizontal stretches of floor
## you can walk end to end - joined by **links** that say how to get from one run
## to the next: step across, drop down, or ride a cable. Routing is then a search
## over a few dozen runs, which is instant and, more importantly, either finds a
## way or tells you there is not one.
##
## Deliberately no `class_name`: it reaches Zipline, which reaches Net, and a
## global that reaches Net is one a `--script` tool can poison by naming it.

## How finely the floor is sampled, in pixels. Fine enough to catch a crate-sized
## ledge, coarse enough that surveying the whole level is a few hundred rays.
const STEP := 32.0

## Floor samples within this of each other vertically are the same run. A gentle
## ramp stays one run; a step up becomes two.
const SAME_RUN := 22.0

## The heights a body is checked for clearance at when deciding whether one
## stretch of floor really continues into the next. Ankle and chest: a lip that
## only catches the ankles is a step it can walk up, but a slab across the chest
## is a wall, and floor found either side of a wall is not one run.
const WALK_HEIGHTS := [18.0, 44.0]

## How high a body can get itself, and how far it can cross. Runs closer than
## this are linked as a step rather than left disconnected.
const STEP_UP := 68.0
const STEP_ACROSS := 90.0

## How far down a drop may be taken, and how far out from the lip the landing may
## be. Falling is free in this game, so the only cost of a drop is that it is one
## way - you cannot climb back.
const DROP_REACH := 900.0
const DROP_OUT := 140.0

## What each kind of link costs, over and above the ground covered. A cable is
## cheap because it is fast; a drop is cheap because it is free; a step costs a
## little so a route made of twenty hops loses to one long walk.
const COST_CABLE := 60.0
const COST_DROP := 40.0
const COST_STEP := 90.0

## Rebuilt when the level changes underneath it, which in practice means never -
## the geometry is static. Held per scene so a test that loads main.tscn twice
## does not inherit the first one's survey.
static var _runs: Array = []
static var _links: Dictionary = {}
static var _surveyed_for: int = 0


## Where a body standing here belongs on the map, or -1 if nowhere does.
static func run_at(tree: SceneTree, at: Vector2) -> int:
	_survey(tree)
	var best := -1
	var best_gap := INF
	for i in _runs.size():
		var run: Dictionary = _runs[i]
		if at.x < run.from - STEP or at.x > run.to + STEP:
			continue
		# Below the feet, not above the head: the run you are on is the one you
		# are standing on top of.
		var gap: float = run.y - at.y
		if gap < -60.0 or gap > 120.0:
			continue
		if absf(gap) < best_gap:
			best_gap = absf(gap)
			best = i
	return best


## The run closest to a point that is not standing on one, or -1 if the level
## has none at all. Floors below the point are preferred over floors above it,
## because things fall.
static func _nearest_run(at: Vector2) -> int:
	var best := -1
	var best_gap := INF
	for i in _runs.size():
		var run: Dictionary = _runs[i]
		var on := Vector2(clampf(at.x, run.from, run.to), run.y)
		var gap := at.distance_to(on)
		if on.y < at.y:
			gap += 400.0
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


## The corners of a journey, or an empty list if there is no way.
##
## Every pair after the first is one link: a step, a drop, or - the pair that
## matters - the two ends of a cable, which is what tells a body to get on.
static func route(tree: SceneTree, from: Vector2, to: Vector2) -> Array:
	_survey(tree)
	# Falling back to the nearest floor when a point is not on one. A body in
	# mid-air belongs to the floor under it, and a target out over open ground
	# means the floor nearest to it - which is what a player clicking a rooftop
	# and missing by thirty pixels meant as well. Answering "no route" for those
	# leaves the body with no plan at all, and a body with no plan refuses every
	# edge it meets and paces.
	var start := run_at(tree, from)
	if start < 0:
		start = _nearest_run(from)
	var finish := run_at(tree, to)
	if finish < 0:
		finish = _nearest_run(to)
	if start < 0 or finish < 0:
		return []
	if start == finish:
		return [{"from": from, "to": to, "kind": "walk"}]

	var came := _search(start, finish, from)
	if came.is_empty():
		return []

	# Unwind the search into runs, then into the places where it crosses.
	var chain: Array = [finish]
	var at := finish
	while at != start:
		at = came[at].run
		chain.push_front(at)

	var legs: Array = []
	var here := from
	for i in chain.size() - 1:
		var link: Dictionary = came[chain[i + 1]].link
		legs.append({"from": here, "to": link.at, "kind": "walk"})
		legs.append({"from": link.at, "to": link.lands, "kind": link.kind,
			"cable": link.get("cable", null), "way": link.get("way", 0.0)})
		here = link.lands
	legs.append({"from": here, "to": to, "kind": "walk"})
	return legs


## Dijkstra over the runs. A few dozen nodes, so the simplest thing that cannot
## be wrong is the right thing.
##
## The ground covered walking along each run is part of the cost, measured from
## where the route entered that run to where it leaves it. Without that every way
## off a run costs the same, and the two ends of the floor a body is standing on
## tie - so a re-plan a moment later can pick the other one for no reason, and
## the body turns round. It did exactly that: walk right towards one edge, flip,
## walk left towards the other, flip, never reaching either. Counting the walk
## breaks the tie in favour of the edge it is nearest, and walking towards that
## edge only makes the preference stronger.
static func _search(start: int, finish: int, from: Vector2) -> Dictionary:
	var best := {start: 0.0}
	var came := {}
	# Where the route steps onto each run, which is what the walk is measured
	# from. For the run it starts on, that is the body itself.
	var entry := {start: from}
	var open: Array = [start]
	while not open.is_empty():
		# Cheapest open run.
		var pick := 0
		for i in open.size():
			if best[open[i]] < best[open[pick]]:
				pick = i
		var at: int = open[pick]
		open.remove_at(pick)
		if at == finish:
			break
		var stood: Vector2 = entry[at]
		for link in _links.get(at, []):
			var walk: float = absf((link.at as Vector2).x - stood.x)
			var cost: float = best[at] + walk + link.cost
			if best.has(link.to) and best[link.to] <= cost:
				continue
			best[link.to] = cost
			came[link.to] = {"run": at, "link": link}
			entry[link.to] = link.lands
			if not open.has(link.to):
				open.append(link.to)
	return came if came.has(finish) or start == finish else {}


## Walks the level once and writes down every stretch of floor and every way
## between them.
static func _survey(tree: SceneTree) -> void:
	var scene := tree.current_scene
	var stamp: int = scene.get_instance_id() if scene else 0
	if stamp == _surveyed_for and not _runs.is_empty():
		return
	_surveyed_for = stamp
	_runs = []
	_links = {}

	var space := _space(tree)
	if space == null:
		return
	var box := _bounds(tree)
	if box.size.x <= 0.0:
		return

	# --- the floors ----------------------------------------------------------
	# One column at a time, top to bottom, recording every surface. A column can
	# have several: a catwalk over a floor over a basement.
	var columns: Array = []
	var x := box.position.x
	while x <= box.end.x:
		var found: Array = []
		var y := box.position.y
		while y < box.end.y:
			var probe := PhysicsRayQueryParameters2D.create(
				Vector2(x, y), Vector2(x, box.end.y))
			probe.collision_mask = Layers.WORLD | Layers.ONE_WAY
			var hit := space.intersect_ray(probe)
			if hit.is_empty():
				break
			var top: float = (hit.position as Vector2).y
			found.append(top)
			# Down past this surface and out the underside of whatever it is.
			y = top + 8.0
			var through := PhysicsRayQueryParameters2D.create(
				Vector2(x, y), Vector2(x, box.end.y))
			through.collision_mask = Layers.WORLD | Layers.ONE_WAY
			through.hit_from_inside = true
			var out := space.intersect_ray(through)
			y = ((out.position as Vector2).y + 8.0) if out else (y + 40.0)
		columns.append({"x": x, "tops": found})
		x += STEP

	# --- stitched into runs --------------------------------------------------
	# A surface continues into the next column if it is at much the same height.
	var open_runs: Array = []
	for column in columns:
		var carried: Array = []
		for top in column.tops:
			var joined := false
			for run in open_runs:
				if run.used or absf(run.y - top) > SAME_RUN:
					continue
				# Floor on both sides of a wall is not one stretch of floor.
				if not _walkable_between(space, run.to, run.y, column.x, top):
					continue
				run.to = column.x
				run.y = top
				run.used = true
				carried.append(run)
				joined = true
				break
			if not joined:
				carried.append({"from": column.x, "to": column.x, "y": top,
					"used": true})
		for run in open_runs:
			if not run.used:
				_keep(run)
		for run in carried:
			run.used = false
		open_runs = carried
	for run in open_runs:
		_keep(run)

	_link_runs(space)
	_link_cables(tree)


## Whether a body can actually get from one floor sample to the next.
##
## Sampling downwards finds floor on both sides of a wall and calls it one run,
## and a run that crosses a wall is a promise the body cannot keep: it walks at
## the far half, meets the wall, refuses it, turns round, meets the near edge,
## refuses that, and paces between the two until the errand expires. That pacing
## was the single biggest cause of failed journeys - the route was right, and the
## floor it named was not walkable.
static func _walkable_between(space: PhysicsDirectSpaceState2D, from_x: float,
		from_y: float, to_x: float, to_y: float) -> bool:
	for height in WALK_HEIGHTS:
		var probe := PhysicsRayQueryParameters2D.create(
			Vector2(from_x, from_y - height), Vector2(to_x, to_y - height))
		probe.collision_mask = Layers.WORLD
		if not space.intersect_ray(probe).is_empty():
			return false
	return true


## Runs shorter than a body are not places, they are noise off a corner.
static func _keep(run: Dictionary) -> void:
	if run.to - run.from >= STEP:
		_runs.append({"from": run.from, "to": run.to, "y": run.y})


## Steps between neighbouring runs, and drops off their ends.
static func _link_runs(space: PhysicsDirectSpaceState2D) -> void:
	for a in _runs.size():
		var one: Dictionary = _runs[a]
		for b in _runs.size():
			if a == b:
				continue
			var two: Dictionary = _runs[b]

			if absf(one.y - two.y) <= STEP_UP:
				# Overlapping in x: a ledge that begins partway along this run,
				# which is the commonest shape there is - a crate against a wall,
				# a step up onto a walkway. Linked at the overlap, because there
				# is no gap to cross at all.
				var over_from: float = maxf(one.from, two.from)
				var over_to: float = minf(one.to, two.to)
				if over_from <= over_to:
					var mid := (over_from + over_to) * 0.5
					_join(a, b, {"to": b, "kind": "step",
						"at": Vector2(mid, one.y),
						"lands": Vector2(mid, two.y),
						"cost": COST_STEP})
				else:
					# Not overlapping: a gap, jumpable if it is short enough.
					for pair in [[one.to, two.from], [one.from, two.to]]:
						var gap: float = absf(pair[0] - pair[1])
						if gap > STEP_ACROSS:
							continue
						_join(a, b, {"to": b, "kind": "step",
							"at": Vector2(pair[0], one.y),
							"lands": Vector2(pair[1], two.y),
							"cost": gap + COST_STEP})

	_link_drops()


## One drop off each lip, onto the first thing under it.
##
## The first thing is the whole point. Linking a lip to every run below it inside
## falling range looks harmless - falling is free, so why not - but it lets the
## search pick a landing two floors down when there is a walkway in between. The
## body then steps off exactly where it was told, lands on the walkway it was
## never told about, and re-plans from a place its route did not have in it. Two
## lips on that walkway, two equally wrong links, and it bounces between them
## until the errand expires. Every drop now names the floor the body will really
## be standing on.
static func _link_drops() -> void:
	for a in _runs.size():
		var one: Dictionary = _runs[a]
		for lip in [one.from, one.to]:
			var best := -1
			var best_y := INF
			for b in _runs.size():
				if a == b:
					continue
				var two: Dictionary = _runs[b]
				if two.y <= one.y + STEP_UP or two.y > one.y + DROP_REACH:
					continue
				if lip < two.from - DROP_OUT or lip > two.to + DROP_OUT:
					continue
				# Highest of the candidates: the one it meets first on the way
				# down.
				if two.y < best_y:
					best_y = two.y
					best = b
			if best < 0:
				continue
			var land: Dictionary = _runs[best]
			var at := clampf(lip, land.from, land.to)
			# Which way is off the edge. Recorded because the landing spot is
			# very often directly below the lip, and a body told to walk to a
			# point straight down has no direction to walk at all - it stands on
			# the brink shuffling until the errand expires. This is the
			# difference between "go there" and "step off this side".
			var way := 1.0 if is_equal_approx(lip, one.to) else -1.0
			_join(a, best, {"to": best, "kind": "drop", "way": way,
				"at": Vector2(lip, one.y),
				"lands": Vector2(at, land.y),
				"cost": absf(at - lip) + COST_DROP})


## Cables, which are the only way back up.
static func _link_cables(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(&"zipline"):
		var line := node as Zipline
		if line == null:
			continue
		var top := line.world_top()
		var bottom := line.world_bottom()
		var up := run_at(tree, top)
		var down := run_at(tree, bottom)
		if up < 0 or down < 0 or up == down:
			continue
		_join(down, up, {"to": up, "kind": "cable", "cable": line,
			"at": bottom, "lands": top, "cost": COST_CABLE})
		_join(up, down, {"to": down, "kind": "cable", "cable": line,
			"at": top, "lands": bottom, "cost": COST_CABLE})


static func _join(a: int, b: int, link: Dictionary) -> void:
	if not _links.has(a):
		_links[a] = []
	_links[a].append(link)


static func _space(tree: SceneTree) -> PhysicsDirectSpaceState2D:
	var scene := tree.current_scene as Node2D
	if scene == null:
		return null
	return scene.get_world_2d().direct_space_state


## The box worth surveying, taken from where the cables are plus a wide margin.
## Derived rather than written down, so a level that grows is still covered.
static func _bounds(tree: SceneTree) -> Rect2:
	var box := Rect2()
	var first := true
	for node in tree.get_nodes_in_group(&"zipline"):
		var line := node as Zipline
		if line == null:
			continue
		for end in [line.world_top(), line.world_bottom()]:
			if first:
				box = Rect2(end, Vector2.ZERO)
				first = false
			else:
				box = box.expand(end)
	if first:
		return Rect2()
	return box.grow(1400.0)


## Thrown away between levels, and by tests that want a fresh survey.
static func forget() -> void:
	_runs = []
	_links = {}
	_surveyed_for = 0


## How many runs and links the survey found, for a test that wants to know the
## map was actually read rather than silently empty.
static func survey_size(tree: SceneTree) -> Vector2i:
	_survey(tree)
	var edges := 0
	for key in _links:
		edges += (_links[key] as Array).size()
	return Vector2i(_runs.size(), edges)
