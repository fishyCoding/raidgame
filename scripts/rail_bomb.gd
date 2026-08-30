class_name RailBomb
extends StaticBody2D

## A charge you clamp to a zipline, point up or down, and let climb.
##
## It goes where the cable goes and cooks anybody hanging off it on the way past.
## It lets go of the rope for one of two reasons - it ran out of rope, or it saw
## somebody worth stopping for - and then holds station there, a thing in the air
## over the yard shooting whoever it can see until its cell runs flat. The cable
## is its rail and its ladder; where it gets off is wherever the shooting is. A
## zipline is the fastest way onto high ground, and this is the answer to
## somebody owning that high ground.
##
## ## Nothing about this is sent
##
## Not one byte, and not one rpc. Every machine builds its own copy off six
## numbers that are already replicated on the man who threw it - see
## Player.arc_at and the five beside it - and works out where the bomb is by
## arithmetic that comes out the same everywhere:
##
##   which cable   the cable whose midpoint is arc_at (Zipline.ARC_MATCH)
##   where planted arc_from, 0 at the bottom of that cable and 1 at the top
##   which way     arc_way, 0 while it waits for orders, +1 up, -1 down
##   how long left arc_left, counting down on its owner's clock
##   since when    arc_launch, the value arc_left had when it was sent
##   where it quit arc_stop, the clock reading at which it got off the rope
##
## Position is `arc_from + arc_way * (arc_launch - max(arc_left, arc_stop)) *
## speed / length`, clamped to the rope. A machine that has those six numbers
## has the bomb, and a machine that stops having them stops having it.
##
## arc_stop is what keeps "it stops when it sees somebody" from tearing the
## whole scheme apart. Deciding to get off is a judgement about sight lines, and
## two machines will not always make it on the same frame - so exactly one
## machine makes it, the one that owns the numbers, and every other machine is
## told the answer as a number rather than asked to reach it. Latched rather
## than re-evaluated, because a position that depends on what was true at some
## moment cannot be recovered from what is true now.
##
## This is the same trick the Live Rail used before it and it is the reason the
## whole feature adds no rpc to net.gd - which matters more than it sounds,
## because an rpc added there renumbers every other one and breaks any client
## that has not shipped with it.
##
## The host still decides all damage, the way it decides every other kind - see
## Net.deals_damage. Every machine draws the lightning; one of them charges for
## it.

## Seconds between jolts while it is holding station, shooting at range.
##
## Above Player.invulnerable_time, which is 0.35s of immunity after any hit,
## because at range this is a weapon like any other and the rule that stops a
## burst deleting you should apply to it. Anything below that number here would
## be thrown away silently, which is what the gadget this replaces did for a
## while - about a fiftieth of the damage it was asking for, and only visible
## because a networked test measured the health bar instead of trusting the call.
const JOLT_INTERVAL := 0.4

## Seconds between jolts against somebody on the rope with it, which is a
## different thing entirely and is priced as one.
##
## At range it is shooting at you. Here it is being dragged along a cable you
## are hanging off, holding a live contact against you, and there is nowhere on
## that rope to be that is not next to it. So it ticks nearly four times as
## fast, and it goes through the immunity window rather than waiting for it -
## see Net.relentless, which exists for this and is used by nothing else.
##
## The number this multiplies out to matters: at 0.11s and 34 a jolt, a man who
## stays on the rope is dead in about a second. That is the intended answer to
## "should I stay on this cable", and it is meant to be an easy question.
const ROPE_JOLT_INTERVAL := 0.11

## How long it looks at somebody before it opens up on them, in seconds.
##
## It is a machine, and a machine that fired on the same frame its sights
## crossed you was a machine you could not step out from behind cover at all -
## the round was already coming before the decision to lean out could be taken
## back. A fifth of a second is not a chance to dodge; it is the width of the
## gap between "it has seen me" and "it is shooting me", and that gap is what
## makes peeking a thing you can do rather than a thing that happens to you.
##
## Per target, and it goes back to zero the moment the line breaks - so a man
## who ducks behind a wall and out again buys the whole delay a second time,
## which is the entire trade being offered. Timed on every machine rather than
## replicated, the same as the arcs it gates: everyone runs the same clock off
## the same replicated positions and arrives at the same picture.
##
## Only the shooting waits. Riding the rope with it does not - see
## ROPE_JOLT_INTERVAL, which is a contact and not a sighting, and where a pass
## lasting under two tenths of a second would be nullified outright by making
## it wait two tenths of a second.
const REACTION := 0.2

## How close the bomb has to pass a rider to take a bite out of them.
##
## Generous next to the cable's own grab range, because a man on a rope and a
## bomb on the same rope are on the same line by definition - what this is
## really deciding is how long the window is as it goes by. At 600 px/s that is
## under two tenths of a second, which is why the tick inside it is what it is:
## the pass has to cost something even when the pass is that quick.
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

## What the ray is cast against. Solid geometry only, the same mask
## vision_system uses: a one-way catwalk and another player are both see-through
## to this. What stops light but is not geometry - smoke, screens - is asked
## about separately, because neither of them is a physics body at all.
const SIGHT_MASK := Layers.WORLD

## The body, in the local frame. Small and hard - it is a device, not a grenade.
const BODY := 9.0
const LAMP := 3.5

## What you have to hit to shoot it down, which is a little more generous than
## what you can see. A drone is a small fast thing crossing a yard and the
## difficulty is meant to be tracking it, not sub-pixel aim - and it is the same
## bargain a body gets, whose hitbox is also kinder than its outline.
const HITBOX := 13.0

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

## True once it has let go of the rope - either because it ran out of it, or
## because it saw somebody worth stopping for.
var hovering := false

## True on the machine that owns this bomb, once its sights have found somebody
## while it was still climbing. Read by the Zipline, which is what turns it into
## the replicated number every other machine stops the bomb by - see
## Zipline._carry_the_bomb and Player.arc_stop.
var wants_off := false

## What it is shooting at this frame, in world space, for the draw. Held rather
## than recomputed in _draw because the host works it out anyway and a client
## has to arrive at the same picture from the same rules.
var _arcs: Array[Vector2] = []

## When each victim is next due, by instance id.
var _next_jolt := {}

## How long it has had eyes on each victim, by instance id. An entry appears the
## frame the line comes clear and is dropped the frame it breaks; while it reads
## under REACTION the bomb is looking, not shooting.
var _seen_for := {}

var _phase := 0.0
var _damage := 0.0
var _reach := 0.0

## The sound of it. Held rather than fetched each frame, and null in a headless
## run, which is why every use of it is guarded.
@onready var _audio: Node = get_node_or_null(^"/root/Audio")

## Rounds it can still absorb. Counted on the host alone, because the host is
## the only machine that resolves a round - every other copy learns it is dead
## when the thrower's cell reads zero, which is the same way it learns anything.
var _hits_left := 0

## How hard it is flinching, 0 to 1. Local, cosmetic, and set on whichever
## machine saw the round land - a hit that only the host draws is still better
## than a hit nobody draws, and this is not worth a message.
var _struck := 0.0


func _ready() -> void:
	add_to_group(&"rail_bomb")
	# Solid enough to shoot at. Its own layer, and no mask at all: it is a thing
	# rounds can find, not a thing that goes looking for anything.
	collision_layer = Layers.GADGET
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HITBOX
	shape.shape = circle
	add_child(shape)
	# Taken by the dark, like a grapple line and a dash trail and for the same
	# reason: a thing that tells you where somebody's attention is should have to
	# be looked at to be learned. VisionSystem walks this group and turns each
	# one on or off by line of sight from wherever you are standing, so a bomb
	# working a yard on the far side of a wall is a bomb you have to go and see.
	#
	# "shadowed" rather than "hideable" - hideable means a body the recon arrow
	# can paint and pin a marker to, and a diamond hovering over somebody's
	# gadget is not what that arrow is for.
	add_to_group(&"shadowed")
	z_index = 40
	set_process(true)


## Told what it is and what it costs. The Zipline that owns it does this on the
## frame it builds it, from the gadget resource, so the numbers live in the
## .tres with the rest of the gadget's numbers rather than being typed here.
func arm(on: Zipline, by: int, damage: float, reach: float, toughness: int) -> void:
	cable = on
	owner_peer = by
	_damage = damage
	_reach = reach
	_hits_left = maxi(toughness, 1)


## Somebody shot it.
##
## Only ever called where the round was resolved, which is the host - see
## Bullet, which checks that before it goes looking for this method. So the
## count is kept in one place by construction rather than by being guarded.
##
## Nothing is freed here. The bomb exists because the thrower's cell reads above
## zero, so the way to end one is to make that read zero and let every machine
## reach the same conclusion it reaches for a bomb that simply ran flat. See
## Net.bring_down_rail_bomb.
func take_damage(_amount: float, _at: Vector2, _from: Vector2) -> void:
	_struck = 1.0
	_hits_left -= 1
	if _hits_left > 0:
		return
	Net.bring_down_rail_bomb(owner_peer)


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
	_struck = maxf(_struck - delta * 4.0, 0.0)
	_arcs.clear()
	if hovering:
		_work_the_air(delta)
	else:
		_work_the_rope(delta)
	_make_noise()
	queue_redraw()


## What it sounds like: a motor the whole time, and the rope while it is on one.
##
## Both sounds are positional and both are claimed by whoever is nearest - see
## Audio.drone and Audio.zipline - so this is safe to shout every frame. Keyed on
## the instance id, which is this machine's own handle for this bomb and is
## exactly what the claim wants: it never has to match anybody else's, because
## every machine is mixing for the person sitting in front of it.
##
## The rope noise is the same one a man makes riding, deliberately. Something is
## on that cable and it is coming - which of the two it is is a thing you work
## out by looking, and having to look is the point. Cut the moment it lets go,
## because at that instant the rope really is empty.
func _make_noise() -> void:
	if _audio == null:
		return
	var id := get_instance_id()
	_audio.drone(global_position, id)
	if way != 0 and not hovering:
		_audio.zipline(global_position, true, id)
	else:
		_audio.zipline_stopped(id)


## Shot down, run flat, or the level going away underneath it. However it ends,
## it has to stop making noise - a motor still humming over an empty yard is a
## thing players would walk into a room to find.
func _exit_tree() -> void:
	if _audio == null:
		return
	var id := get_instance_id()
	_audio.drone_stopped(id)
	_audio.zipline_stopped(id)


## On the way up or down: it only wants people who are on the rope with it.
##
## Riders, not everybody within reach. The thing is travelling inside a cable's
## worth of space and half the level is within fifty pixels of a rope somewhere -
## what makes this fair is that being on the rope is a thing you chose and can
## stop choosing.
func _work_the_rope(delta: float) -> void:
	wants_off = false
	for body in Net.players():
		if not _is_a_target(body):
			continue
		var at: Vector2 = body.global_position
		var rides: Variant = body.get(&"riding")
		var on_the_rope: bool = typeof(rides) == TYPE_BOOL and bool(rides)
		if on_the_rope and at.distance_to(global_position) <= STRIKE_RANGE:
			_arcs.append(at)
			_jolt(body, delta, ROPE_JOLT_INTERVAL, true)
			continue
		_next_jolt.erase(body.get_instance_id())
		# Anybody else it can see is a reason to stop climbing. It is a weapon
		# looking for a firing position, not a train with a timetable - and the
		# top of the rope is only where it goes when nothing better presents
		# itself on the way.
		if at.distance_to(global_position) <= _reach and _can_see(at):
			wants_off = true


## Holding station: anybody it can see, rider or not, once it has looked at them
## for REACTION seconds.
func _work_the_air(delta: float) -> void:
	for body in Net.players():
		if not _is_a_target(body):
			continue
		var at: Vector2 = body.global_position
		var key := body.get_instance_id()
		if at.distance_to(global_position) > _reach or not _can_see(at):
			# Lost him. Both clocks go, not just the jolt one: the next time it
			# finds him it starts from having just found him.
			_next_jolt.erase(key)
			_seen_for.erase(key)
			continue
		var looked: float = float(_seen_for.get(key, 0.0)) + delta
		_seen_for[key] = looked
		if looked < REACTION:
			# Seen but not yet shot at, and drawn as such - no arc, because the
			# arc is the shot and a bolt on the frame it spots you is the thing
			# this delay exists to remove.
			continue
		_arcs.append(at)
		_jolt(body, delta, JOLT_INTERVAL, false)


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


## Whether the bomb can actually see a point: geometry, smoke and screens.
##
## All three, because all three are things the rest of the game already agrees
## stop light, and a machine that can see through one of them is a machine that
## cannot be hidden from by the one thing built for hiding from it. A screen is
## a sheet somebody spent an ultimate raising precisely so they could not be
## looked at through it; a drone that shot straight through it would make the
## answer to a drone "there is no answer".
##
## Deliberately not VisionSystem.line_is_clear, which asks the same question and
## is the reason Smoke and Screen expose these at all. That one resolves the
## local player's eye first and answers `true` when there is not one - the right
## way to be wrong for a thing that decides what to *draw*, and exactly the wrong
## way for a thing that decides what to *shoot*, because the machine with no eye
## is the dedicated server, which is the machine that resolves every hit in the
## game. Borrowed logic, not borrowed answer.
func _can_see(at: Vector2) -> bool:
	var world := get_world_2d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(global_position, at, SIGHT_MASK)
	query.hit_from_inside = false
	if not world.direct_space_state.intersect_ray(query).is_empty():
		return false
	var tree := get_tree()
	if tree == null:
		return true
	if Smoke.blocks_sight(tree, global_position, at):
		return false
	return not Screen.blocks_sight(tree, global_position, at)


## One body's turn on the clock, and the hit if it is due.
##
## Host only. Everyone runs the loops above so that everyone draws the same
## lightning; only the host turns any of it into damage.
func _jolt(body: Node2D, delta: float, interval: float, through: bool) -> void:
	if not Net.deals_damage():
		return
	var key := body.get_instance_id()
	# Somebody who was not in reach a frame ago is hit now, this frame, with no
	# wait at all. Everyone else is on the clock.
	var due: float = _next_jolt.get(key, 0.0) - delta
	if due > 0.0:
		_next_jolt[key] = due
		return
	_next_jolt[key] = interval
	# Aimed at the body's own centre, which Damage.resolve reads as a body shot:
	# this is current, not a projectile, and should not be rolling headshots.
	Net.attributing_to = owner_peer
	Net.relentless = through
	body.take_damage(_damage, body.global_position,
		(body.global_position - global_position).normalized())
	Net.relentless = false
	Net.attributing_to = 0


func _draw() -> void:
	# The lightning first, so the body sits on top of its own arcs.
	for at in _arcs:
		_draw_bolt(to_local(at))
	var rim := IDLE_RIM if way == 0 else RIM
	# White for an instant where a round went in, so shooting at one tells you
	# whether you are hitting it. The count itself is the host's and is not
	# drawn - a health bar on a gadget would be reading somebody else's mail.
	if _struck > 0.0:
		rim = rim.lerp(Color.WHITE, _struck)
	draw_circle(Vector2.ZERO, BODY, HULL.lerp(Color.WHITE, _struck * 0.7))
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
