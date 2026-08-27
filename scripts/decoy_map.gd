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
const STEP := 24.0

## Floor samples within this of each other vertically are the same run. A gentle
## ramp stays one run; a step up becomes two.
const SAME_RUN := 22.0

## The heights a body is checked for clearance at when deciding whether one
## stretch of floor really continues into the next. Ankle and chest: a lip that
## only catches the ankles is a step it can walk up, but a slab across the chest
## is a wall, and floor found either side of a wall is not one run.
const WALK_HEIGHTS := [14.0, 30.0, 46.0]

## How much clear air a surface needs above it before it counts as somewhere to
## stand. About half a body: enough to throw out the insides of solid blocks
## without throwing out genuinely low headroom a decoy could still walk under.
const STAND_ROOM := 46.0

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
		var gap: float = _height(run, at.x) - at.y
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
		var across := clampf(at.x, run.from, run.to)
		var on := Vector2(across, _height(run, across))
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
			# Only if a body could stand on it. Descending through a thick slab
			# turns up faces that are inside it - the underside of the floor you
			# are standing on is a surface in every sense the raycast cares
			# about, and none that a person does. Those became runs, routes were
			# planned along them, and the preview line was drawn half a body
			# below the floor it was describing. That is the "path goes right
			# through the floor" report, and it is this.
			if _headroom(space, Vector2(x, top)):
				found.append(top)
			# Down past this surface and out the underside of whatever it is.
			y = top + 8.0
			var through := PhysicsRayQueryParameters2D.create(
				Vector2(x, y), Vector2(x, box.end.y))
			through.collision_mask = Layers.WORLD | Layers.ONE_WAY
			through.hit_from_inside = true
			var out := space.intersect_ray(through)
			# Always further down than it started. A ray fired from inside a
			# shape reports the point it started at, so without this the scan
			# creeps eight pixels at a time through anything solid, finding a
			# fresh "surface" at every step of the way.
			y = maxf(((out.position as Vector2).y + 8.0) if out else (y + 40.0),
				top + STAND_ROOM)
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
				run.tops.append(top)
				run.used = true
				carried.append(run)
				joined = true
				break
			if not joined:
				carried.append({"from": column.x, "to": column.x, "y": top,
					"used": true, "tops": [top]})
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


## Whether there is room to stand on a surface, as opposed to it merely being a
## face the physics engine can name.
static func _headroom(space: PhysicsDirectSpaceState2D, on: Vector2) -> bool:
	var probe := PhysicsRayQueryParameters2D.create(
		on - Vector2(0.0, 6.0), on - Vector2(0.0, STAND_ROOM))
	probe.collision_mask = Layers.WORLD
	# Reported even when the probe begins inside something, which is the whole
	# point: a face found part way down a solid block has its headroom checked
	# from a spot buried in that same block, and a ray that ignores the shape it
	# starts in comes back saying the air is clear.
	probe.hit_from_inside = true
	return space.intersect_ray(probe).is_empty()


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
		_runs.append({"from": run.from, "to": run.to, "y": run.y,
			"tops": PackedFloat32Array(run.tops)})


## How high the floor is at a point along a run.
##
## Runs used to carry a single height - whatever the last column sampled - and
## every point along one was treated as being at it. On level ground that is
## true and on a ramp it is nonsense: the route would place a link halfway up a
## slope at the height of its foot, the body would walk to a spot inside the
## hill, and the drawn line would cut straight through the floor it was
## describing. Both of those were reported. The floor is now remembered column by
## column and read back by interpolation, so a slope is a slope.
static func _height(run: Dictionary, x: float) -> float:
	var tops: PackedFloat32Array = run.tops
	if tops.is_empty():
		return run.y
	var along: float = (x - run.from) / STEP
	var i := int(floorf(along))
	if i < 0:
		return tops[0]
	if i >= tops.size() - 1:
		return tops[tops.size() - 1]
	return lerpf(tops[i], tops[i + 1], along - float(i))


## The floor under a point, followed along its actual shape.
##
## Handed to the preview line so it draws the ground rather than a straight
## segment between two points that happen to be on it - which over a ramp or a
## dip is a line through solid rock.
static func walk_line(tree: SceneTree, from: Vector2, to: Vector2) -> PackedVector2Array:
	_survey(tree)
	var line := PackedVector2Array()
	var step: float = STEP if to.x >= from.x else -STEP
	var x: float = from.x
	# Carried from the last sample, so the line follows one continuous surface
	# instead of jumping to whichever floor happens to be nearest in the
	# absolute. Under a catwalk the nearest floor changes twice on the way past
	# it, and a line that took the bait would dive through the walkway and come
	# back out.
	var y: float = _surface_near(x, from.y)
	line.append(Vector2(x, y))
	while absf(to.x - x) > STEP:
		x += step
		y = _surface_near(x, y)
		line.append(Vector2(x, y))
	line.append(Vector2(to.x, _surface_near(to.x, y)))
	return line


## The height of the floor at a point, taking the surface nearest the one the
## line is already following.
##
## Walking a single run's profile from end to end was not enough: a leg can run
## off the end of the run it started on, and past that the profile has nothing
## to say, so it held the last height it knew and drew a level line into the side
## of whatever came next. Eleven per cent of the drawn route was inside solid
## geometry, which is the "path goes right through the floor" report.
static func _surface_near(x: float, hint: float) -> float:
	var best := hint
	var best_gap := INF
	for run in _runs:
		if x < run.from - STEP or x > run.to + STEP:
			continue
		var high: float = _height(run, clampf(x, run.from, run.to))
		var gap: float = absf(high - hint)
		if gap < best_gap:
			best_gap = gap
			best = high
	return best


## Steps between neighbouring runs, and drops off their ends.
static func _link_runs(space: PhysicsDirectSpaceState2D) -> void:
	for a in _runs.size():
		var one: Dictionary = _runs[a]
		for b in _runs.size():
			if a == b:
				continue
			var two: Dictionary = _runs[b]

			# Overlapping in x: a ledge that begins partway along this run,
			# which is the commonest shape there is - a crate against a wall, a
			# step up onto a walkway. Linked at the overlap, because there is no
			# gap to cross at all.
			#
			# Heights are read at the place they are compared, not off the run
			# as a whole. Two ramps can be a body's height apart at one end and
			# touching at the other, and asking "how far apart are these runs"
			# has no answer for them - only "how far apart are they here" does.
			var over_from: float = maxf(one.from, two.from)
			var over_to: float = minf(one.to, two.to)
			if over_from <= over_to:
				var mid := (over_from + over_to) * 0.5
				var up: float = _height(one, mid)
				var down: float = _height(two, mid)
				if absf(up - down) <= STEP_UP:
					_join(a, b, {"to": b, "kind": "step",
						"at": Vector2(mid, up),
						"lands": Vector2(mid, down),
						"cost": COST_STEP})
			else:
				# Not overlapping: a gap, jumpable if it is short enough.
				for pair in [[one.to, two.from], [one.from, two.to]]:
					var gap: float = absf(pair[0] - pair[1])
					if gap > STEP_ACROSS:
						continue
					var lip: float = _height(one, pair[0])
					var far: float = _height(two, pair[1])
					if absf(lip - far) > STEP_UP:
						continue
					_join(a, b, {"to": b, "kind": "step",
						"at": Vector2(pair[0], lip),
						"lands": Vector2(pair[1], far),
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
			var lip_y: float = _height(one, lip)
			var best := -1
			var best_y := INF
			for b in _runs.size():
				if a == b:
					continue
				var two: Dictionary = _runs[b]
				if lip < two.from - DROP_OUT or lip > two.to + DROP_OUT:
					continue
				# Measured under the lip itself. A run that is far below this one
				# on average can still rise to meet it, and on a ramp that is the
				# difference between a step and a two storey fall.
				var under: float = _height(two, clampf(lip, two.from, two.to))
				if under <= lip_y + STEP_UP or under > lip_y + DROP_REACH:
					continue
				# Highest of the candidates: the one it meets first on the way
				# down.
				if under < best_y:
					best_y = under
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
				"at": Vector2(lip, lip_y),
				"lands": Vector2(at, _height(land, at)),
				"cost": absf(at - lip) + COST_DROP})


## Cables, which are the only way back up.
static func _link_cables(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(&"zipline"):
		var line := node as Zipline
		if line == null:
			continue
		var top := line.world_top()
		var bottom := line.world_bottom()
		# The nearest floor when an end is not sitting on one. A rope anchored a
		# little above its platform, or over the lip of it, otherwise joins
		# nothing at all - which is two of this level's twenty-two ropes simply
		# missing from the map, and a decoy that cannot see the only way up.
		var up := run_at(tree, top)
		if up < 0:
			up = _nearest_run(top)
		var down := run_at(tree, bottom)
		if down < 0:
			down = _nearest_run(bottom)
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
