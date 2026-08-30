class_name RailBomb
extends Node2D

## A charge you clamp to a zipline, point up or down, and let climb.
##
## It goes where the cable goes, kills anybody hanging off it on the way past,
## and when it runs out of rope it lets go and holds station there - a thing in
## the air over the yard that shoots whoever it can see until its cell runs
## flat. The cable is its rail and its ladder; the ledge at the top is where it
## ends up, and that is the point of it. A zipline is the fastest way onto high
## ground, and this is the answer to somebody owning that high ground.
##
## ## Nothing about this is sent
##
## Not one byte, and not one rpc. Every machine builds its own copy off five
## numbers that are already replicated on the man who threw it - see
## Player.arc_at and the four beside it - and works out where the bomb is by
## arithmetic that comes out the same everywhere:
##
##   which cable   the cable whose midpoint is arc_at (Zipline.ARC_MATCH)
##   where planted arc_from, 0 at the bottom of that cable and 1 at the top
##   which way     arc_way, 0 while it waits for orders, +1 up, -1 down
##   how long left arc_left, counting down on its owner's clock
##   since when    arc_launch, the value arc_left had when it was sent
##
## Position is `arc_from + arc_way * (arc_launch - arc_left) * speed / length`,
## clamped to the rope. A machine that has those five numbers has the bomb, and
## a machine that stops having them stops having it. This is the same trick the
## Live Rail used before it and it is the reason this whole feature adds no rpc
## to net.gd - which matters more than it sounds, because an rpc added there
## renumbers every other one and breaks any client that has not shipped with it.
##
## The host still decides all damage, the way it decides every other kind - see
## Net.deals_damage. Every machine draws the lightning; one of them charges for
## it.

## Seconds between jolts, and this is not a feel dial - it is a constraint.
## Player.invulnerable_time is 0.35s of immunity after any hit, there so a burst
## cannot delete you. Spread damage across frames instead and all but the first
## jolt inside every 0.35s window is swallowed: the gadget this replaces did
## exactly that and delivered about a fiftieth of what it was asking for,
## silently. Anything below invulnerable_time here throws damage away again.
const JOLT_INTERVAL := 0.4

## How close the bomb has to pass a rider to take a bite out of them.
##
## Generous next to the cable's own grab range, because a man on a rope and a
## bomb on the same rope are on the same line by definition - what this is
## really deciding is how long the window is as it goes by, and at 200 px/s this
## is about half a second of being shot at.
const STRIKE_RANGE := 54.0

## How far above the end of the cable it climbs once the rope runs out, and how
## far it drifts up and down while it sits there.
##
## It has to leave the rail visibly. Parked exactly on the anchor it read as a
## fitting somebody had bolted there, and a threat that looks like scenery is a
## threat nobody shoots at.
const HOVER_RISE := 46.0
const HOVER_BOB := 7.0
const HOVER_HZ := 1.6

## What it is cast against, both for the shot and for deciding it can see you.
## Solid geometry only, the same mask vision_system uses: a one-way catwalk and
## another player are both see-through to this.
const SIGHT_MASK := Layers.WORLD

## The body, in the local frame. Small and hard - it is a device, not a grenade.
const BODY := 9.0
const LAMP := 3.5

const HULL := Color(0.20, 0.24, 0.30, 1.0)
const RIM := Color(0.62, 0.92, 1.0, 1.0)
const SPARK := Color(0.75, 0.95, 1.0, 1.0)
const CORE := Color(1.0, 1.0, 1.0, 0.92)
const IDLE_RIM := Color(1.0, 0.72, 0.28, 1.0)

## The cable this is clamped to. Set once, by the Zipline that built it.
var cable: Zipline = null

## Whose bomb it is, as a peer id. Decides who it will not bite and who gets
## credited for what it does.
var owner_peer := 0

## 0 while it waits to be pointed, +1 up the cable, -1 down it.
var way := 0

## Where it is along the cable, 0 at the bottom and 1 at the top.
var along := 0.0

## True once it has run out of rope and let go.
var hovering := false

## What it is shooting at this frame, in world space, for the draw. Held rather
## than recomputed in _draw because the host works it out anyway and a client
## has to arrive at the same picture from the same rules.
var _arcs: Array[Vector2] = []

## When each victim is next due, by instance id.
var _next_jolt := {}

var _phase := 0.0
var _damage := 0.0
var _reach := 0.0


func _ready() -> void:
	add_to_group(&"rail_bomb")
	z_index = 40
	set_process(true)


## Told what it is and what it costs. The Zipline that owns it does this on the
## frame it builds it, from the gadget resource, so the numbers live in the
## .tres with the rest of the gadget's numbers rather than being typed here.
func arm(on: Zipline, by: int, damage: float, reach: float) -> void:
	cable = on
	owner_peer = by
	_damage = damage
	_reach = reach


## Where it should be, given the state it was handed this frame.
##
## `at_along` is the derived position along the cable and `is_hovering` says the
## rope has run out. Both are worked out by the caller from replicated numbers,
## which is what keeps every machine's copy in the same place - see the note at
## the top.
func place(at_along: float, which_way: int, is_hovering: bool) -> void:
	along = at_along
	way = which_way
	hovering = is_hovering
	if cable == null or not is_instance_valid(cable):
		return
	var on_rope := cable.world_bottom().lerp(cable.world_top(), along)
	if not hovering:
		global_position = on_rope
		return
	# Off the rope and holding station. Straight up from where the cable ended,
	# not along its angle: it is flying now, and a drone that kept leaning at
	# the angle of the rope it came off still reads as attached to it.
	var bob := sin(_phase * TAU * HOVER_HZ) * HOVER_BOB
	global_position = on_rope + Vector2(0.0, -(HOVER_RISE + bob))


func _process(delta: float) -> void:
	_phase += delta
	_arcs.clear()
	if hovering:
		_work_the_air(delta)
	else:
		_work_the_rope(delta)
	queue_redraw()


## On the way up or down: it only wants people who are on the rope with it.
##
## Riders, not everybody within reach. The thing is travelling inside a cable's
## worth of space and half the level is within fifty pixels of a rope somewhere -
## what makes this fair is that being on the rope is a thing you chose and can
## stop choosing.
func _work_the_rope(delta: float) -> void:
	for body in Net.players():
		if not _is_a_target(body):
			continue
		var rides: Variant = body.get(&"riding")
		if typeof(rides) != TYPE_BOOL or not rides:
			_next_jolt.erase(body.get_instance_id())
			continue
		if body.global_position.distance_to(global_position) > STRIKE_RANGE:
			_next_jolt.erase(body.get_instance_id())
			continue
		_arcs.append(body.global_position)
		_jolt(body, delta)


## Holding station: anybody it can see, rider or not.
func _work_the_air(delta: float) -> void:
	for body in Net.players():
		if not _is_a_target(body):
			continue
		var at: Vector2 = body.global_position
		if at.distance_to(global_position) > _reach:
			_next_jolt.erase(body.get_instance_id())
			continue
		if not _can_see(at):
			_next_jolt.erase(body.get_instance_id())
			continue
		_arcs.append(at)
		_jolt(body, delta)


## Whether a body is something this bomb is willing to shoot.
##
## Your own does not bite you, which is the same rule the Live Rail had and for
## the same reason: it is a tool you place on a route, and one that punished you
## for standing near your own trap would be a tool nobody placed anywhere useful.
func _is_a_target(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body.get_multiplayer_authority() == owner_peer:
		return false
	if not body.has_method(&"take_damage"):
		return false
	var alive: Variant = body.get(&"is_alive")
	return typeof(alive) != TYPE_BOOL or bool(alive)


## Whether there is anything solid between the bomb and a point.
func _can_see(at: Vector2) -> bool:
	var world := get_world_2d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(global_position, at, SIGHT_MASK)
	query.hit_from_inside = false
	return world.direct_space_state.intersect_ray(query).is_empty()


## One body's turn on the clock, and the hit if it is due.
##
## Host only. Everyone runs the loops above so that everyone draws the same
## lightning; only the host turns any of it into damage.
func _jolt(body: Node2D, delta: float) -> void:
	if not Net.deals_damage():
		return
	var key := body.get_instance_id()
	# Somebody who was not in reach a frame ago is hit now, this frame, with no
	# wait at all. Everyone else is on the clock.
	var due: float = _next_jolt.get(key, 0.0) - delta
	if due > 0.0:
		_next_jolt[key] = due
		return
	_next_jolt[key] = JOLT_INTERVAL
	# Aimed at the body's own centre, which Damage.resolve reads as a body shot:
	# this is current, not a projectile, and should not be rolling headshots.
	Net.attributing_to = owner_peer
	body.take_damage(_damage, body.global_position,
		(body.global_position - global_position).normalized())
	Net.attributing_to = 0


func _draw() -> void:
	# The lightning first, so the body sits on top of its own arcs.
	for at in _arcs:
		_draw_bolt(to_local(at))
	var rim := IDLE_RIM if way == 0 else RIM
	draw_circle(Vector2.ZERO, BODY, HULL)
	draw_arc(Vector2.ZERO, BODY, 0.0, TAU, 20, rim, 2.0, true)
	# A lamp that pulses, so a bomb waiting for orders is visibly waiting rather
	# than visibly stuck.
	var pulse := 0.55 + 0.45 * sin(_phase * TAU * (0.9 if way == 0 else 2.4))
	draw_circle(Vector2.ZERO, LAMP, Color(rim.r, rim.g, rim.b, pulse))
	if hovering:
		# Rotors, of a sort: two short strokes that turn, so a thing holding
		# station in the air is not a thing that has simply stopped.
		var spin := _phase * 9.0
		for i in 2:
			var arm := Vector2.RIGHT.rotated(spin + PI * i) * (BODY + 5.0)
			draw_line(arm * 0.45, arm, Color(rim.r, rim.g, rim.b, 0.7), 2.0, true)
	elif way != 0:
		# A tail of sparks off the back while it climbs, which is also the only
		# cue for which way it is going if you catch sight of it side on.
		var back := Vector2(0.0, 1.0 if way > 0 else -1.0) * (BODY + 6.0)
		draw_line(Vector2.ZERO, back, Color(SPARK.r, SPARK.g, SPARK.b, 0.55), 2.0, true)


## One bolt, drawn as a crooked line rather than a straight one - current does
## not travel in a straight line and a straight line reads as a laser, which is
## a different weapon in this game and already has a colour.
func _draw_bolt(to: Vector2) -> void:
	var span := to
	var length := span.length()
	if length < 1.0:
		return
	var along_way := span / length
	var side := along_way.orthogonal()
	var points := PackedVector2Array()
	var steps := 7
	for i in steps + 1:
		var t := float(i) / float(steps)
		var wobble := 0.0
		if i > 0 and i < steps:
			wobble = sin(t * 19.0 + _phase * 30.0) * 6.0
		points.append(along_way * (length * t) + side * wobble)
	draw_polyline(points, Color(SPARK.r, SPARK.g, SPARK.b, 0.85), 2.5, true)
	draw_line(Vector2.ZERO, to, CORE, 1.0, true)
