extends RefCounted

## How a decoy gets from one place to another, and the only thing that knows.
##
## Both the ghost that walks the route and the red line drawn over the level
## while you are choosing one come out of here. That is the entire reason this is
## its own file: a preview computed separately from the behaviour is a preview
## that lies, and a line promising a cable ride the body then does not take is
## worse than drawing no line at all.
##
## Not a path search. The level is a handful of floors joined by ropes, so the
## route is "walk there", or "walk to a rope, ride it, walk there", or that twice
## - and each hop is chosen from where the last one ended. Anything more would be
## a lot of machinery for a body that lives fourteen seconds.
##
## Deliberately has no `class_name`: it reaches Zipline, which reaches Net, and a
## global that reaches Net is one a `--script` tool can poison for a whole
## process by naming it. Preloaded by the two files that want it.

## How far off a body's own height an end of a cable can be and still be
## something it could walk to. About a storey, so a ramp or a step does not
## disqualify a rope but the floor above does.
const FLOOR_REACH := 130.0

## Height difference that makes a cable worth taking rather than walking.
const WORTH_A_CABLE := 140.0

## How far it will walk to reach a cable that is on its way.
const CABLE_SEARCH := 900.0

## Most hops one plan will string together. Three is two rides and the walks
## either side, which is the whole height of this level twice over.
const MAX_HOPS := 3

## How finely a walking leg is followed along the ground, and how far below each
## sample to look for a floor before calling it a gap.
const TRACE_STEP := 26.0
const TRACE_DROP := 280.0
## How far above the sample the downward probe starts, so a probe that lands on
## the exact lip of a step is not a coin flip about which side it hits.
const TRACE_LIFT := 44.0
## How big a step up a decoy can take without being stopped by it.
##
## The canonical figure, shared with the body that does the climbing, because the
## drawn route and the walked route have to agree about what counts as a wall.
## Under the 100 px its jump actually reaches, so something it decides it can
## clear is something it clears with room rather than scrapes.
const STEP_UP := 68.0

## Headroom checked above the higher of two adjacent ground samples, to catch
## real walls and overhangs. Measured from the floor it would be standing on
## rather than from a fixed height, or every crate reads as a wall - which is
## exactly what it used to do.
const TRACE_CLEAR := 26.0


## A cable's two ends, ordered: the one on this floor first.
##
## By height, never by straight-line distance. A rope running through the ceiling
## directly overhead has its far end closer to you in a straight line than its
## near end is - so picking by distance sends a body to stand underneath a cable
## it has no way of reaching, which is exactly what it used to do.
static func ends_of(line: Zipline, from: Vector2) -> Array:
	var top := line.world_top()
	var bottom := line.world_bottom()
	if absf(top.y - from.y) < absf(bottom.y - from.y):
		return [top, bottom]
	return [bottom, top]


## The cable that gets you closest to a height for the least walking, or null.
##
## Three rules: the end you get on at has to be on this floor, walking to it is
## measured across the ground rather than through the air, and riding it has to
## actually buy height towards where you are going.
static func best_cable(tree: SceneTree, from: Vector2, goal_y: float,
		used: Array) -> Zipline:
	var climb := absf(from.y - goal_y)
	var best: Zipline = null
	var best_score := -INF
	for node in tree.get_nodes_in_group(&"zipline"):
		var line := node as Zipline
		if line == null or line in used:
			continue
		var ends := ends_of(line, from)
		var near: Vector2 = ends[0]
		var far: Vector2 = ends[1]
		if absf(near.y - from.y) > FLOOR_REACH:
			continue
		var gain := climb - absf(far.y - goal_y)
		if gain < WORTH_A_CABLE:
			continue
		var walk := absf(near.x - from.x)
		if walk > CABLE_SEARCH:
			continue
		var score := gain - walk * 0.8
		if score > best_score:
			best_score = score
			best = line
	return best


## The whole journey, leg by leg.
##
## Each entry is `{from, to, cable}` - `cable` true for the ones spent hanging
## off a rope. Legs rather than a flat list of corners because the two kinds are
## drawn and walked completely differently: a rope really is a straight line
## through the air, and a walk really is not, and something reading this plan has
## to be able to tell them apart without counting indices.
##
## `skip` is a cable to pretend does not exist, which is how a body that has just
## stepped off one plans its next leg without immediately getting back on.
static func plan(tree: SceneTree, from: Vector2, to: Vector2,
		skip: Zipline = null) -> Array:
	var legs: Array = []
	var used: Array = []
	if skip:
		used.append(skip)

	var at := from
	for hop in MAX_HOPS:
		if absf(to.y - at.y) <= FLOOR_REACH:
			break
		var line := best_cable(tree, at, to.y, used)
		if line == null:
			break
		var ends := ends_of(line, at)
		legs.append({"from": at, "to": ends[0], "cable": false})
		legs.append({"from": ends[0], "to": ends[1], "cable": true})
		at = ends[1]
		used.append(line)

	legs.append({"from": at, "to": to, "cable": false})
	return legs


## One walking leg, followed along the ground it would actually be walked on.
##
## A straight line between two points on different floors - or across a gap, or
## through a wall - is a line drawn through mid-air, which is what a route
## preview must never do: it promises a walk nothing can take. So the ground is
## sampled every TRACE_STEP along the way and the line bends over whatever is
## under it.
##
## Returns `{line, blocked}`. `blocked` means the walk does not get there: either
## the floor ran out from under a sample, or something solid stands between one
## sample and the next. The line stops at the last place it could actually reach,
## so what is drawn is the part of the journey that is real.
static func trace_walk(space: PhysicsDirectSpaceState2D, from: Vector2,
		to: Vector2) -> Dictionary:
	var line := PackedVector2Array([from])
	var steps := maxi(1, int(absf(to.x - from.x) / TRACE_STEP))
	var at := from
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var aim := Vector2(lerpf(from.x, to.x, t), lerpf(from.y, to.y, t))

		var down := PhysicsRayQueryParameters2D.create(
			aim - Vector2(0.0, TRACE_LIFT),
			aim + Vector2(0.0, TRACE_DROP))
		down.collision_mask = Layers.WORLD | Layers.ONE_WAY
		var floor_hit := space.intersect_ray(down)
		if floor_hit.is_empty():
			return {"line": line, "blocked": true}

		var spot: Vector2 = floor_hit.position
		# A step up it can climb is not a wall. This was a flat ray at ankle
		# height, so every crate on the map read as impassable and the preview
		# stopped dead at things a body walks straight over.
		if at.y - spot.y > STEP_UP:
			return {"line": line, "blocked": true}

		# Headroom over the higher of the two, which catches genuine walls and
		# overhangs without catching the crate itself.
		var head := minf(at.y, spot.y) - TRACE_CLEAR
		var wall := PhysicsRayQueryParameters2D.create(
			Vector2(at.x, head), Vector2(spot.x, head))
		wall.collision_mask = Layers.WORLD
		if not space.intersect_ray(wall).is_empty():
			return {"line": line, "blocked": true}

		at = spot
		line.append(spot)

	# Finish on the point that was asked for rather than on the last sample, so
	# a destination standing a few pixels off a sample does not read as a miss.
	line.append(to)
	return {"line": line, "blocked": false}
