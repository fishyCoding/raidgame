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


## The whole journey, as the corners it turns.
##
## Always starts at `from` and ends at `to`; every pair in between is one cable,
## boarded at the first and left at the second. `skip` is a cable to pretend does
## not exist, which is how a body that has just stepped off one plans its next
## leg without immediately getting back on.
static func plan(tree: SceneTree, from: Vector2, to: Vector2,
		skip: Zipline = null) -> PackedVector2Array:
	var points := PackedVector2Array([from])
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
		points.append(ends[0])
		points.append(ends[1])
		at = ends[1]
		used.append(line)

	points.append(to)
	return points
