extends CharacterBody2D

## The Projection: a copy of you that walks off on its own and cannot fight.
##
## It is built out of the same four polygons the character is, wears the plates
## the caster had up when it was cast, carries the same slung or shouldered
## rifle, crouches, runs, jumps and rides cables. Everything a person watching
## from across the yard can read off a body, it has.
##
## What it does not have is a Weapon node, and it never touches the Audio
## autoload. Those two omissions are the whole design. A decoy that could be
## picked apart by looking at it is worth nothing - you would learn the tell once
## and never be fooled again - so the only thing that gives it away is that it
## does not make a sound. It has no boots, no rope, no breathing and no gun, and
## the yard is quiet enough that a man running past you in silence is something
## you can notice if you are listening for it. That is the counterplay, and it is
## deliberately a hard one: it asks you to trust your ears over your eyes.
##
## It is bait, and it plays like bait rather than like a survivor. Left alone it
## goes looking for somewhere a rival can see it, as far from its caster as it
## can get - because the whole job is that somebody follows it *somewhere else*.
## Found, it holds their eye for the better part of a second, then runs. Shot at,
## it skips the holding and just runs.
##
## An earlier version hid when it was seen, which is what a real player does and
## made a beautifully convincing ghost nobody ever looked at twice: it broke line
## of sight at exactly the moment it had somebody's attention, which is the one
## moment the gadget is paid for.
##
## Its caster sends it somewhere by clicking the level - see order_to. Getting
## there is this body's problem, cables included.
##
## Deliberately has no `class_name`. It reaches Net, and a global that reaches
## Net is a global a `--script` tool can poison for a whole process by so much as
## naming it - see the headless-test notes. Nothing needs it as a type: Net
## instantiates the scene and duck-types it, and the tools find it by group.

## Group everything that wants to find one of these looks in.
const GROUP := &"projection"

## How it works out where to walk. Shared with the HUD, which draws the same
## route as a line while the caster is choosing one - see decoy_route.gd.
const ROUTE := preload("res://scripts/decoy_route.gd")

## The surveyed level and the route search over it. Where it goes is decided
## here, once per order, instead of being guessed at a lip one frame at a time.
const MAP := preload("res://scripts/decoy_map.gd")

## Run, taken from Player so the gait reads as the same person.
const MAX_SPEED := 260.0

## What it does relative to the person it is copying.
##
## Under one, deliberately, and this reverses an earlier decision. The argument
## for matching the caster exactly was that speed is the easiest thing to read
## off a body at distance, so a decoy moving at its own pace is one you identify
## with a stopwatch. That is true and it turned out not to be the point: a decoy
## nobody can follow is not bait. At full pelt it crossed the yard faster than
## anybody chasing it could commit to a corner, which makes it a thing you glimpse
## rather than a thing you follow - and being followed is the entire job.
##
## Slower is also what a man moving carefully through somewhere dangerous looks
## like, which is what it is pretending to be.
const DECOY_PACE := 0.72
const GROUND_ACCEL := 2200.0
const GROUND_FRICTION := 2600.0
const AIR_ACCEL := 1500.0
const AIR_FRICTION := 450.0
const MAX_FALL_SPEED := 1100.0

## Jump, solved the way Player solves it: a height and two half-times rather than
## a velocity and a gravity, so the arc is the same arc.
const JUMP_HEIGHT := 100.0
const JUMP_TIME_TO_PEAK := 0.38
const JUMP_TIME_TO_FALL := 0.28

const CROUCH_SPEED_SCALE := 0.42
const CROUCH_HEIGHT_SCALE := 0.68
const CROUCH_TIME := 0.12
const SHIELD_SPEED_SCALE := 0.82
const SHIELD_RAISE_TIME := 0.3
const STOW_TIME := 0.16
const STOW_LEAN := 24.0
const STOW_SHORTEN := 0.68

## How long it holds still once it knows it has been seen.
##
## This is the peek, and it is the whole gadget. A decoy that breaks the instant
## it is spotted is a shape somebody glimpsed; a decoy that stands there for the
## better part of a second, facing you, is a *player* you have found - long
## enough to raise a gun at, commit to, and start walking towards. What it buys
## its caster is the second and third of those.
const PEEK_TIME := 0.75

## How long it runs for after a peek before it goes looking to be seen again.
const BREAK_TIME := 2.6

## How often the "is anybody looking at me" sweep runs. Once a frame is a raycast
## per player per frame for a body that lives fourteen seconds, and the answer
## does not change that fast.
const WATCH_INTERVAL := 0.15

## How far away somebody has to be before being seen by them stops mattering.
## Past this they cannot tell a ghost from a smudge anyway.
const WATCH_RANGE := 1500.0

## Distances tried when it goes looking for somewhere to stand out of sight, and
## when it is picking somewhere to wander to. One list for both: a good place to
## wander to and a good place to hide are the same kind of place, and the only
## difference between the two searches is how badly it wants one.
const COVER_STEPS := [160.0, 280.0, 420.0, 560.0, 720.0]

## How far from its caster it wants to be, and how hard it works at it.
##
## The point of the thing is that somebody follows it *somewhere else*. A decoy
## that baits an enemy into the room its caster is standing in has done the
## opposite of its job, so distance from the caster is the largest term in every
## route it picks - larger than being seen, which is worth nothing if it is being
## seen next to you.
const AWAY_FROM_CASTER := 900.0

## How long after stepping off a cable before it will consider that same cable
## again. Long enough to have walked somewhere: without it a ghost that arrives
## at the top of a rope immediately finds the same rope in reach, decides the
## other end is worth going to, and spends its whole life riding one cable up and
## down in front of everybody.
const CABLE_MEMORY := 9.0

## How close to a target counts as arrived, across and vertically.
##
## The vertical figure used to be WORTH_A_CABLE, which is 140 - more than a
## storey - so a ghost sent upstairs counted as arrived while it was still
## standing on the floor below, dropped its orders and wandered off. Arriving is
## a tighter question than "is this worth a cable".
const ARRIVED := 48.0
const ARRIVED_Y := 90.0

## How far off this body's own height an end of a cable can be and still count as
## something it could walk to. About a storey, so a ramp or a step up does not
## disqualify a rope, but the floor above does.
const FLOOR_REACH := 130.0

## How far ahead it feels for a wall.
const WALL_PROBE := 20.0

## How far past its leading edge it looks for floor, and how far down it looks
## before calling the absence of floor a fall rather than a step.
##
## The depth is the part that matters. At sixteen pixels a step down of any size
## read as a cliff, so the body refused stairs, kerbs and crate tops - all the
## small drops a route is made of - and paced at the top of them instead. At
## ninety it only refuses an edge with nothing catchable underneath, which is the
## only kind worth refusing.
const LEDGE_PROBE := 16.0
const LEDGE_DROP := 90.0

## How long after stepping off a cable before it will drive itself sideways
## again. Just long enough to land: a body that steers while airborne cannot see
## the ledge it is steering over.
const SETTLE_TIME := 0.45

## Least time between two jumps.
##
## There was none, and the jump was driven straight off "is something in front of
## me" - so a body walking into a wall hopped against it every single frame for
## as long as it took to give up. That is the single most obvious thing a player
## reported about this gadget, and it is not a tuning problem, it is a missing
## cooldown and a missing question: *can* it get over that.
## How often the route is worked out again. Cheap - a search over a few dozen
## runs - so this is about the body not twitching between two equal routes
## rather than about the cost of asking.
##
## Tried at one second and two while chasing a body that changed its mind at a
## lip and walked seven hundred pixels the wrong way. Both measured worse than
## this across the soak, and not in a straight line either - eighteen journeys is
## a small enough sample that a few points of difference is noise. Left where the
## evidence puts it rather than where the story about flip-flopping wanted it.
const REPLAN_TIME := 0.5

## How far from a planned lip still counts as being at it. Wide enough to cover
## the gap between where the survey says the floor ends and where the body's own
## width says it does.
const DROP_NEAR := 170.0

## How far past a lip to aim when the route wants a drop that lands straight
## below it. Comfortably more than a body's width, so the direction is never in
## doubt at the edge itself.
const OFF_THE_EDGE := 80.0

## How many obstacles it will back away from before deciding the errand is not
## on. Higher than it was, because each refusal now buys a fresh route rather
## than another run at the same wall.
const GIVE_UP_AFTER := 5

## How long after stepping off a rope before it may take one again. Long enough
## that it cannot re-catch the one it is standing on, short enough that a fall
## does not strand it under the rope it needs.
const REGRAB_GUARD := 0.8

const JUMP_COOLDOWN := 0.55

## How high it will try to climb. Taken from the planner so the red line drawn
## over the level and the body walking it agree about what counts as a wall.
const STEP_UP := ROUTE.STEP_UP

## How far it turns back when it meets something it cannot pass, and how long it
## sticks with that decision. Without the commitment it turns round, immediately
## re-scores the route it just abandoned, and walks back into the same wall.
const TURN_BACK := 420.0
const TURN_COMMIT := 1.8

## How long it has to make no headway before it stops believing in the route.
const STUCK_TIME := 1.4

## How long it works towards where it was sent before going back to baiting on
## its own. Click again to renew it.
##
## Raised from 11 when a soak across the level showed the errand expiring
## underneath perfectly good routing: a fifteen-hundred pixel walk takes nine
## seconds at the pace it now moves, and anything with a rope in the middle takes
## longer, so most journeys were being abandoned a few strides short. Slowing the
## body down without lengthening its errand was half a change.
const ORDERS_TIME := 18.0

## How far it will walk to reach a cable that is on its way. Beyond this the
## detour costs more than the climb is worth and it would rather take the long
## way round on foot.
const CABLE_SEARCH := 900.0

## Height difference that makes a cable worth taking rather than walking.
const WORTH_A_CABLE := 140.0

## Seconds of tearing after one round goes through it.
const TEAR_TIME := 0.42

## Seconds of coming apart at the end, whether that end is the third round or the
## clock running out.
##
## Longer than a fade needs to be, because this is not a fade. It is a signal
## going: the body cuts in and out, faster and sparser as it goes, and the whole
## point is that somebody who shot it gets long enough to watch it happen and
## know what they shot at.
const DEATH_TIME := 0.78

## How long one on-or-off slot of the death strobe lasts, at the start and at the
## end. Stepped in slots rather than rolled per frame so the flicker is the same
## flicker at 30 fps and at 240 - a per-frame roll is a frame-rate readout.
const BLINK_SLOW := 0.075
const BLINK_FAST := 0.022

## How likely the body is drawn in any one slot, at the start and at the end. It
## does not fade out, it stops being there more and more of the time.
const BLINK_ON_FIRST := 0.85
const BLINK_ON_LAST := 0.06

## Slots of stutter a single round buys, on top of the tear. A hit is not a
## death, so it drops one or two frames rather than coming apart.
const HIT_BLINKS := 3

## Matched to Player's Torso, so the resting colour of a ghost and the colour a
## real body tweens back to after a hit flash cannot drift apart.
const TORSO_COLOUR := Color(0.831373, 0.85098, 0.878431)

# --- replicated ---------------------------------------------------------------
#
# The owner simulates; everybody else watches. Which half a machine is running is
# decided exactly the way Player decides it - by who has authority - so a ghost
# and a character take the same path through the network and there is no second
# set of rules to keep true.

## Which way the body is mirrored, and which way it is walking.
var facing := 1
## Where the arm is pointing, in world radians.
var aim_angle := 0.0
## 0 standing, 1 crouched.
var crouch := 0.0
## Plates up, copied off the caster at the moment of casting.
var armored := false
## Rifle slung, which is what riding a cable does to it.
var stowed := false
## Hanging off a cable.
var riding := false
## Rounds that have gone through it.
var hits := 0
## Set by the owner when it is finished, so every copy comes apart together
## rather than each waiting out its own clock.
var gone := false

# --- local --------------------------------------------------------------------

## How torn the picture is, 0 to 1. Derived from `hits` on every machine rather
## than sent, the same way the shield ramp is.
var glitch := 0.0
## Changes on every hit. The tear is drawn from this, so one hit holds its shape
## while it fades instead of boiling for half a second. See ProjectionGlitch.
var glitch_seed := 0
## 0 plates down, 1 plates up. What ShieldOutline actually draws from.
var shield := 0.0
## 0 gun up, 1 gun slung.
var stow := 0.0
## What anything working out whether it can be seen measures against. Tracks the
## collision box, exactly as Player.size does.
var size := Vector2(28.0, 48.0)

## How many rounds it takes, and how long it lasts. Set from the gadget.
var max_hits := 3
var life_left := 14.0
## Unused as a bound now that orders are a direction rather than a place. Kept
## because the gadget resource still carries a radius and the shop prints it.
var roam_range := 900.0

## Everything the caster's own top speed was multiplied by that this body cannot
## work out for itself: the weight of the gun they were carrying, and whatever
## they were still bleeding from. Sent with the cast rather than guessed.
##
## Without it a ghost runs at the flat 260 while its caster - carrying an LMG,
## or nursing two wounds - does 190, and the difference is not subtle. Speed is
## the single easiest thing to read off a body at distance, and a decoy that
## moves faster than any real player can is one you identify from across the map
## without looking at it twice.
var speed_scale := 1.0

## What it is doing.
##
## ORDERS is where it starts if the caster pointed somewhere; everything else is
## the bait loop, which it runs for the rest of its life: find somewhere an enemy
## can see you, stand there until one does, hold their eye, run, repeat.
##
## This replaces an earlier version that hid when it was seen. Hiding is what a
## real player does and it made a beautifully convincing ghost that nobody ever
## looked at twice - it would break line of sight at exactly the moment it had
## somebody's attention, which is the one moment the whole gadget is paid for.
## A decoy is not trying to survive. It is trying to be followed.
enum Mind { ORDERS, LURE, PEEK, BREAK }

var _mind := Mind.LURE
## Where it is trying to get to. INF means "nowhere in particular yet".
var _target := Vector2.INF
## Seconds until it picks somewhere new, whether or not it arrived.
var _rethink := 0.0
## Where the last person who could see it was standing.
var _threat := Vector2.INF
## Counts down while it is holding somebody's eye, and again while it is running
## away from them afterwards.
var _hold := 0.0

## Where its caster clicked, in world space. INF is "your own devices".
##
## A place and not a heading. Pointing it "left" needed no aiming budget but also
## carried no information - the useful thing to say to a decoy is *which floor*,
## which is exactly what a heading cannot express and what the pulled-back view
## exists to let you choose. Getting there is this body's problem, cables
## included; see _next_leg.
var destination := Vector2.INF
## The route from where it is standing to where it was sent, leg by leg. A leg is
## a walk, a drop, or a cable ride - see DecoyMap.route.
##
## Worked out again every so often rather than once at the start. Following a
## thirteen leg plan by index only survives while nothing goes wrong, and things
## go wrong constantly - a fall lands it a floor below leg four, and it spends
## the rest of the errand walking to a lip that is now above its head. Re-asking
## from where it actually is makes every mishap self correcting: the answer is
## always a route from here, so there is no stale plan left to drift off.
var _legs: Array = []
## Counts down to the next re-ask.
var _replan := 0.0
## Stops it catching hold of a rope again on the frame after letting go.
var _regrab := 0.0
## The cable of the current leg, if the current leg is a ride, and the end of it
## the route wants it to reach.
var _leg_cable: Zipline = null
var _leg_end := Vector2.INF
## Somewhere to get to first, because the direct way is blocked. See _turn_back.
var _detour := Vector2.INF
var _detour_left := 0.0
## Seconds of working towards it before it goes back to baiting on its own.
var _orders_left := 0.0
## Rising while it is making no headway, so a ghost jammed in a corner eventually
## tries elsewhere instead of leaning on the wall for the rest of its life.
## Driven by whether it is actually moving, not by whether something is in front
## of it - a body can be against a wall and still walking usefully along it.
var _stuck := 0.0
var _was_at := INF
## Seconds until the next jump is allowed, and until it will reconsider a route
## it has just committed to.
var _jump_cool := 0.0
var _commit := 0.0
## Counts down after a cable release. See _let_go.
var _settle_left := 0.0
## How many times it has backed away from something on the current order.
var _refusals := 0
## The last direction it actually travelled, -1 or 1, kept across rides and
## stops. Not read off velocity: stepping off a rope zeroes that, so a body that
## has just spent a ride getting somewhere arrives with no memory of which way it
## was going - and the route scorer's "carrying on beats turning round" term goes
## with it. That is the coin flip that had it get off a cable and walk straight
## back the way it came.
var _went := 0.0
var _watch_timer := 0.0
## Where the rivals were at the last sweep. Refreshed by _watch, read by the
## route search, so choosing somewhere to walk costs no extra raycasts against
## bodies that have not moved since.
var _eyes: Array[Vector2] = []
var _dying := 0.0
## 0 alive, 1 the instant it started coming apart. Read by ProjectionGlitch,
## which draws the echoes that are left behind while the body itself is off.
var dying_at := 0.0
var _tear := 0.0
var _seen_hits := 0
var _cast_from := Vector2.ZERO
var _zipline: Zipline = null
## Which way along the cable it is travelling: -1 up, 1 down.
var _ride_way := 0.0
## The cable it just got off, and how long it stays off limits. See CABLE_MEMORY.
var _last_cable: Zipline = null
var _cable_cooldown := 0.0

var _jump_velocity := 0.0
var _jump_gravity := 0.0
var _fall_gravity := 0.0

var _rng := RandomNumberGenerator.new()

@onready var _body: Node2D = $Body
@onready var _torso: Polygon2D = $Body/Torso
@onready var _head: Polygon2D = $Body/Head
@onready var _face: Polygon2D = $Body/Face
@onready var _outline: Node2D = $Body/ShieldOutline
@onready var _arm: Polygon2D = $AimPivot/Arm
@onready var _aim_pivot: Node2D = $AimPivot
@onready var _shape: CollisionShape2D = $CollisionShape2D

var _stand_height := 48.0
var _stand_pivot_y := -6.0


func _enter_tree() -> void:
	# Whose ghost this is, read off the node's name before the synchroniser is
	# handed its network id. Same rule, and same reason, as Net.spawn_player:
	# authority set any later leaves the spawn without one and every client
	# silently drops it.
	var owner_id := _owner_from_name()
	if owner_id > 0:
		set_multiplayer_authority(owner_id)


func _ready() -> void:
	add_to_group(GROUP)
	_jump_velocity = -2.0 * JUMP_HEIGHT / JUMP_TIME_TO_PEAK
	_jump_gravity = 2.0 * JUMP_HEIGHT / (JUMP_TIME_TO_PEAK * JUMP_TIME_TO_PEAK)
	_fall_gravity = 2.0 * JUMP_HEIGHT / (JUMP_TIME_TO_FALL * JUMP_TIME_TO_FALL)
	# Shared between instances unless made local, and crouching writes to it.
	_shape.shape = _shape.shape.duplicate()
	_stand_height = (_shape.shape as RectangleShape2D).size.y
	_stand_pivot_y = _aim_pivot.position.y
	_rng.randomize()
	_cast_from = global_position
	_torso.color = TORSO_COLOUR

	# Everyone but the caster has to find it the way they find each other: by
	# looking. A ghost drawn through walls would be worse than useless - it would
	# be a beacon saying "here is a thing that is not a person". The caster's own
	# copy is never hidden, for the same reason your own body never is.
	if not is_mine() and not is_in_group(&"hideable"):
		add_to_group(&"hideable")

	_apply_stance()
	_shield_ramp(1000.0)
	# Only if nobody told it where to go. setup() runs before this and may
	# already have handed it a destination.
	if _mind != Mind.ORDERS:
		_pick_lure_target()


## Set by Net as it builds one, before it goes into the tree.
func setup(gadget: GadgetData, look: Dictionary) -> void:
	max_hits = maxi(gadget.hit_points, 1)
	life_left = gadget.active_time
	roam_range = maxf(gadget.radius, 200.0)
	# What the caster looked like at the moment they spent the charge. Sent
	# rather than read off their body, because the two are not the same thing:
	# the point of a decoy is that it wears the kit you had when you cast it, and
	# goes on wearing it after you have dropped your plates and run.
	# Where the caster clicked when they spent it.
	var _sent := order_to(Vector2(
		float(look.get("send_x", INF)), float(look.get("send_y", INF))))

	facing = int(look.get("facing", 1))
	aim_angle = float(look.get("aim_angle", 0.0))
	stowed = bool(look.get("stowed", false))
	crouch = float(look.get("crouch", 0.0))
	speed_scale = maxf(float(look.get("speed_scale", 1.0)), 0.1)

	# Plates up, always, whatever the caster had on.
	#
	# Not a copy of their state, and deliberately not. A ghost is a body somebody
	# is going to decide whether to shoot at, and the plates are the one thing
	# about a body that changes that decision - blue rim, four rounds; no rim,
	# two. Cast with them down it reads as an easy kill, which is the opposite of
	# what a decoy is for: nobody breaks position over a target they think they
	# can drop in a burst from where they are already standing.
	#
	# It also costs it the speed. is_shielded() has no meaning here, so this is
	# the entire price - it moves at the plated pace, which is what makes the
	# rim honest rather than free.
	armored = true
	shield = 1.0
	stow = 1.0 if stowed else 0.0


## True on the machine driving this ghost. Everybody else is watching a replica.
func is_mine() -> bool:
	return not Net.is_networked() or is_multiplayer_authority()


## The peer this ghost belongs to, taken from the node name. Net names them
## "Ghost_<peer id>" so the two ends agree without a lookup.
func _owner_from_name() -> int:
	var text := str(name)
	var cut := text.rfind("_")
	return text.substr(cut + 1).to_int() if cut >= 0 else 0


## The middle of the body in world space. Not the node origin: the box shrinks
## from the top when it crouches, so the origin ends up near its feet and rays
## aimed at it would be testing the air above its head. Player answers the same
## question the same way, and VisionSystem asks both.
func sight_centre() -> Vector2:
	return global_position + _shape.position


func _physics_process(delta: float) -> void:
	_tick_looks(delta)
	if _dying > 0.0:
		_die_off(delta)
		return
	if not is_mine():
		# A replica is written by the synchroniser. Simulating it here would only
		# fight what is arriving, and `gone` is the owner saying it is over.
		if gone:
			_begin_dying()
		return

	life_left -= delta
	if life_left <= 0.0 or hits >= max_hits:
		_finish()
		return

	_watch(delta)
	if _ride(delta):
		return
	_think(delta)
	_walk(delta)
	move_and_slide()


# --- what it looks like -------------------------------------------------------


## Everything derived rather than sent, run on every machine: the plate ramp, the
## sling ramp, the crouch, the mirror and the tear. Exactly the split Player
## makes between what crosses the wire and what is rebuilt from it.
func _tick_looks(delta: float) -> void:
	_shield_ramp(delta)
	_stow_ramp(delta)
	_apply_stance()
	_aim_pivot.rotation = aim_angle
	_aim_pivot.scale.y = facing
	_body.scale.x = facing

	# A round landing is replicated as a number, and the tear is started from a
	# change in that number - so the owner's copy and everybody else's come apart
	# off the same event without a second message chasing the first.
	if hits != _seen_hits:
		_seen_hits = hits
		_tear = TEAR_TIME
		glitch_seed = _rng.randi()
	if _tear > 0.0:
		_tear = maxf(_tear - delta, 0.0)
		glitch = _tear / TEAR_TIME
		# The body itself jumps as well as tearing. A tear that only happens
		# inside the silhouette reads as an effect drawn on top of a character;
		# moving the character says the character *is* the effect.
		_body.position.x = _rng.randf_range(-3.0, 3.0) * glitch
		# And drops a frame or two while it does. A round going through it
		# should cost the picture something you can see, not just paint a
		# tear on an otherwise perfectly solid body - the stutter is what
		# says "this is a projection" to somebody who has never shot one.
		var slot := int((TEAR_TIME - _tear) / (TEAR_TIME / float(HIT_BLINKS * 2)))
		_show_body(slot % 2 == 0 or _tear < TEAR_TIME * 0.45)
	elif _dying <= 0.0:
		glitch = 0.0
		_body.position.x = 0.0
		_show_body(true)


func _shield_ramp(delta: float) -> void:
	shield = move_toward(shield, 1.0 if armored else 0.0, delta / SHIELD_RAISE_TIME)


## The rifle going down onto the sling and back up, copied from Player so a ghost
## stepping onto a cable puts its gun away with the same movement a person does.
func _stow_ramp(delta: float) -> void:
	if is_mine():
		stowed = riding
	stow = move_toward(stow, 1.0 if stowed else 0.0, delta / STOW_TIME)
	if is_zero_approx(stow) and is_zero_approx(_arm.rotation):
		return
	var rest := Vector2(-facing * tan(deg_to_rad(STOW_LEAN)), 1.0).angle()
	_arm.rotation = wrapf((rest - aim_angle) * facing, -PI, PI) * stow
	_arm.scale.x = lerpf(1.0, STOW_SHORTEN, stow)


func _apply_stance() -> void:
	var height := lerpf(_stand_height, _stand_height * CROUCH_HEIGHT_SCALE, crouch)
	var shape := _shape.shape as RectangleShape2D
	shape.size.y = height
	_shape.position.y = (_stand_height - height) * 0.5
	size = Vector2(shape.size.x, height)
	_body.scale.y = lerpf(1.0, CROUCH_HEIGHT_SCALE, crouch)
	_body.position.y = (_stand_height - height) * 0.5
	_aim_pivot.position.y = _stand_pivot_y + (_stand_height - height) * 0.5


# --- being watched ------------------------------------------------------------


## Whether anybody who is not the caster currently has a clear line to it.
##
## Asked from here rather than read off VisionSystem, which answers only for the
## machine it is running on and only about the local player's eye. This has to be
## answered about *other* people, on the owner's machine, and every other body's
## position is already replicated - so it is a raycast per player per sweep and
## needs nothing new over the wire.
func _watch(delta: float) -> void:
	_watch_timer -= delta
	if _watch_timer > 0.0:
		return
	_watch_timer = WATCH_INTERVAL

	# Kept for the route search, which runs between sweeps and would otherwise
	# have to gather the same list again.
	_eyes = _watchers()
	var watcher := _seen_from(_eyes, sight_centre())
	if watcher.is_finite():
		_spotted_by(watcher)


## Somebody has a clear line to it.
##
## Split out from the sweep above so the event has a name and can be raised
## without one: the sweep can only find people who are actually there, and this
## is also what a round arriving means (see hit()) and what a test needs to be
## able to say out loud.
func _spotted_by(watcher: Vector2) -> void:
	_threat = watcher
	# Found. Stop whatever it was doing - including the caster's orders, which
	# have just been overtaken by the thing they were issued for - and hold.
	if _mind == Mind.LURE or _mind == Mind.ORDERS:
		destination = Vector2.INF
		_leg_cable = null
		_orders_left = 0.0
		_mind = Mind.PEEK
		_hold = PEEK_TIME
		_target = Vector2.INF


## Where every rival who is near enough to matter is standing, nearest first.
##
## Line of sight is not consulted here - that is the next question, asked once
## per place it is thinking about standing rather than once per person. Gathered
## as a list because the route search asks it about half a dozen candidate spots
## in a row, and walking Net.players() six times to get the same six positions
## would be the expensive half of the whole thing.
func _watchers() -> Array[Vector2]:
	var mine := get_multiplayer_authority()
	var here := global_position
	var found: Array[Vector2] = []
	for body in Net.players():
		if body == null or not is_instance_valid(body):
			continue
		# Never the caster. Being looked at by the person who cast it is not
		# being caught, and a ghost that dived into cover the moment its owner
		# glanced at it would be unusable.
		if body.get_multiplayer_authority() == mine:
			continue
		# Nobody who cannot do anything about it. A decoy exists to be followed,
		# and a man who is dead or on the floor bleeding out is not going to
		# follow anything - so peeking at him, holding still for three quarters
		# of a second and then sprinting off is a whole cycle of the gadget spent
		# on an audience of one who cannot come.
		#
		# Worse than wasted: the ghost breaks away from where it was working and
		# runs, which is exactly the behaviour that reads as "it panics at
		# corpses". Downed counts as out of it as much as dead does. Somebody
		# revived is a rival again on the next sweep, a fraction of a second
		# later, which is soon enough.
		if not _can_be_lured(body):
			continue
		var eye: Vector2 = body.global_position
		if body.has_method(&"sight_centre"):
			eye = body.sight_centre()
		if eye.distance_to(here) < WATCH_RANGE:
			found.append(eye)
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(here) < b.distance_squared_to(here))
	return found


## Whether a body is somebody worth playing to.
##
## Guards are excluded by construction rather than by a test here: this sweep
## walks Net.players() and a guard is never on it, alive or dead. That is
## deliberate and load-bearing - a decoy that spent its life peeking at a patrol
## would never draw the one person it was cast for - and `tools/projection_test`
## checks it against a yard full of them, living and killed.
##
## What has to be tested is the state of the people who *are* on that list. Dead
## is obvious; downed matters just as much and is easy to miss, because a man on
## the floor is still `is_alive`. He cannot chase anything, cannot shoot much,
## and will most likely be dead shortly - baiting him is a cycle of the gadget
## thrown away, and running from him is worse, because it takes the ghost off the
## floor where it was working.
func _can_be_lured(body: Node) -> bool:
	var alive: Variant = body.get(&"is_alive")
	if typeof(alive) == TYPE_BOOL and not alive:
		return false
	var downed: Variant = body.get(&"is_downed")
	if typeof(downed) == TYPE_BOOL and downed:
		return false
	return true


## Which of those eyes, if any, has a clear line to a point. INF for none.
func _seen_from(eyes: Array[Vector2], point: Vector2) -> Vector2:
	if eyes.is_empty():
		return Vector2.INF
	var space := get_world_2d().direct_space_state
	for eye in eyes:
		var query := PhysicsRayQueryParameters2D.create(eye, point)
		query.collision_mask = Layers.WORLD
		if not space.intersect_ray(query).is_empty():
			continue
		# Geometry is not the only thing that hides people, and a ghost standing
		# in somebody's smoke is as hidden as they would be.
		if Smoke.blocks_sight(get_tree(), eye, point):
			continue
		if Screen.blocks_sight(get_tree(), eye, point):
			continue
		return eye
	return Vector2.INF


# --- making up its mind -------------------------------------------------------


func _think(delta: float) -> void:
	_rethink -= delta
	_cable_cooldown = maxf(_cable_cooldown - delta, 0.0)
	_replan = maxf(_replan - delta, 0.0)
	_regrab = maxf(_regrab - delta, 0.0)
	_hold = maxf(_hold - delta, 0.0)

	match _mind:
		Mind.PEEK:
			# Standing in the open, facing whoever found it, not moving. This is
			# the second it is buying its caster, and it has to look like a
			# player who has seen you and is deciding what to do - which is
			# exactly what a player who has seen you looks like.
			velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
			crouch = move_toward(crouch, 0.0, delta / CROUCH_TIME)
			_face_the_threat()
			if _hold <= 0.0:
				_mind = Mind.BREAK
				_hold = BREAK_TIME
				_target = _bolt_from(_threat)
			return
		Mind.BREAK:
			# Off, at a run, away from the man who just looked at it. Whether he
			# follows is his decision - all this can do is be worth following and
			# then be somewhere else.
			if _hold <= 0.0 or not _target.is_finite():
				_mind = Mind.LURE
				_target = Vector2.INF
				_rethink = 0.0
		Mind.ORDERS:
			# Working towards where it was sent. The leg is recomputed rather
			# than fixed, so a cable it decides to take becomes the next thing it
			# walks to and the destination is picked up again on the far side.
			_orders_left -= delta
			_detour_left = maxf(_detour_left - delta, 0.0)
			if not destination.is_finite() or _orders_left <= 0.0:
				_stand_down()
			elif _arrived_at(destination):
				# There. Standing on the spot would be a decoy doing nothing, so
				# it goes back to baiting - from where you put it, which is the
				# whole point of having put it there.
				_stand_down()
			else:
				_target = _next_leg()
		Mind.LURE:
			_commit = maxf(_commit - delta, 0.0)
			# A route it has just committed to is left alone, unless it has no
			# route at all - see _turn_back for why re-scoring too eagerly walks
			# it back into whatever it just backed away from.
			var loose := _rethink <= 0.0 or _arrived()
			if not _target.is_finite() or (_commit <= 0.0 and loose):
				_pick_lure_target()

	# Never crouched while luring. An earlier version crouch-walked whenever a
	# rival was near, on the theory that it moved like somebody being careful -
	# which it did, and which made it small, slow and easy to miss. It is not
	# trying to get away with anything. It wants to be the most obvious thing in
	# the room.
	crouch = move_toward(crouch, 0.0, delta / CROUCH_TIME)
	_steer(delta)


## Whether it has got where it was going.
##
## Both axes, and that is not fussiness. Measured on x alone - which it was - the
## far end of a zipline counts as "arrived" the moment it is chosen, because a
## cable runs almost straight up and its top is directly above its bottom. The
## target was therefore thrown away on the frame after it was picked, and the
## only cables it ever rode were the ones it happened to already be standing on.
func _arrived() -> bool:
	return _arrived_at(_target)


func _arrived_at(spot: Vector2) -> bool:
	if not spot.is_finite():
		return false
	if absf(spot.x - global_position.x) > ARRIVED:
		return false
	return absf(spot.y - global_position.y) <= ARRIVED_Y


## Send it somewhere. INF lets it go back to its own devices.
##
## Answers false if it is in no state to be sent anywhere - which is how the
## caster's own click tells "re-point the one that is out" from "cast a new one".
##
## Public and callable at any point in its life: the caster owns this body, so
## re-pointing one already out is a local call on a node this machine is
## authoritative for. Nothing goes over the wire and no RPC exists for it - the
## walk that results replicates like any other movement, which is what makes
## re-pointing cheap enough to be free and repeatable.
func order_to(spot: Vector2) -> bool:
	if _dying > 0.0 or gone:
		return false
	destination = spot
	if not destination.is_finite():
		_stand_down()
		return true
	_mind = Mind.ORDERS
	_orders_left = ORDERS_TIME
	_leg_cable = null
	# The whole journey, worked out once. An empty answer means the map says
	# there is no way from here to there - in which case it walks at the spot
	# anyway and gives up when the errand runs out, which is a better answer
	# than standing still and a much better one than pretending.
	_legs = []
	_replan = 0.0
	_refusals = 0
	# A fresh order is a clean slate, cable grudge included. CABLE_MEMORY
	# stops it riding one rope up and down in front of everybody while it is
	# baiting on its own; under orders it is the wrong rule entirely, because
	# the rope it just used is very often the only way back to where it has
	# now been asked to go. Refusing it means standing at the bottom for nine
	# seconds, which reads as the routing being broken.
	_last_cable = null
	_cable_cooldown = 0.0
	_commit = 0.0
	_stuck = 0.0
	_was_at = INF
	# Net calls setup() - and so this - *before* the node is in the tree, so
	# there is no scene tree to search for cables in yet. The leg is worked out
	# on the first physics frame instead; walking straight at the spot is the
	# right thing to be doing until then anyway.
	_target = _next_leg() if is_inside_tree() else spot
	return true


## Back to working for itself.
func _stand_down() -> void:
	destination = Vector2.INF
	_leg_cable = null
	_legs = []
	_replan = 0.0
	_detour = Vector2.INF
	_detour_left = 0.0
	_orders_left = 0.0
	_mind = Mind.LURE
	_target = Vector2.INF
	_rethink = 0.0


## The next thing to walk to on the way to where it was sent.
##
## Either the destination itself, or the near end of a cable that gets it onto
## the right floor first. This is the whole of its route-finding and it is
## deliberately one step deep: the level is a handful of floors joined by ropes,
## so "walk there" and "walk to a rope, ride it, then walk there" covers almost
## everything, and a real path search would be a lot of machinery for a body that
## lives fourteen seconds.
##
## Without this the cables were decorative. It would only ever grab one that
## happened to be within arm's reach as it walked past, so a decoy sent to the
## floor above simply walked to the wall underneath the place you clicked and
## stood there - which is what "it doesn't really factor the ziplines in" looks
## like from the outside.
func _next_leg() -> Vector2:
	if not destination.is_finite():
		_leg_cable = null
		return Vector2.INF
	# The plan, re-asked from here when it is stale. Only on solid ground and
	# only when not on a rope: asked in mid air the map cannot say which floor
	# it is on, and would answer "nowhere", throwing away a route that is fine.
	#
	# Worked out before the detour below, not after. With the detour first, a
	# body that kept meeting obstacles kept pushing its detour forward, never
	# reached this line, and walked on with no plan at all - which made every
	# edge an edge to refuse, which produced another detour. It paced a hundred
	# pixels of floor until it died, having had a perfectly good route until the
	# first obstacle.
	if _replan <= 0.0 and is_on_floor() and not riding:
		_replan = REPLAN_TIME
		_legs = MAP.route(get_tree(), global_position, destination)

	# Backing out of something it could not get past, for a moment. Only where
	# it is walking, not what it knows - the plan above stands.
	if _detour_left > 0.0 and _detour.is_finite():
		_leg_cable = null
		_leg_end = Vector2.INF
		return _detour

	# No route: the map says there is no way from here to there. Walk at it and
	# let the errand expire, which at least takes it somewhere.
	if _legs.is_empty():
		_leg_cable = null
		return destination

	# Standing on the end of the first leg already - take the next one.
	while _legs.size() > 1 and _arrived_at(_legs[0].to):
		_legs.remove_at(0)

	var leg: Dictionary = _legs[0]
	# A drop whose landing spot is straight down gives the body nothing to walk
	# at. Aimed past the lip instead, on the side the map says leaves the floor,
	# so "fall off here" is expressed as somewhere to walk to.
	if leg.kind == "drop" and not is_zero_approx(float(leg.get("way", 0.0))):
		var lip: Vector2 = leg.from
		var land: Vector2 = leg.to
		if absf(land.x - global_position.x) < OFF_THE_EDGE:
			_leg_cable = null
			_leg_end = Vector2.INF
			return Vector2(lip.x + float(leg.way) * OFF_THE_EDGE, land.y)

	# The rope it is heading for, read one leg ahead as well as from this one.
	# The walk that ends at a rope's near end is still a walk, so waiting for the
	# ride leg to become current means the body has to land within a few dozen
	# pixels of the end before it will even consider catching hold. Held early,
	# the rope's own `in_reach` is what decides the moment - which is the same
	# rule the player's own grab uses.
	_leg_cable = null
	_leg_end = Vector2.INF
	for i in mini(2, _legs.size()):
		var ahead: Dictionary = _legs[i]
		if ahead.kind == "cable":
			_leg_cable = ahead.cable as Zipline
			_leg_end = ahead.to
			break
	return leg.to


## Whether the route wants it to walk right up to this edge.
##
## Asked by nearness rather than by "is the current leg a drop", because those
## two disagree in exactly the place that matters. The map records a run of floor
## reaching to its last good sample, but a body twenty-eight pixels wide runs out
## of floor before the sampler does - so it meets the edge while the plan still
## says "walk to the lip". Refusing there is a loop: walk at the lip, refuse,
## turn back, walk at the lip again. That loop was most of the soak's failures -
## bodies pacing a hundred pixels of floor for a whole errand with a correct
## route in hand.
##
## Ropes count as well as drops, and for the same reason. A cable's lower end
## sits at the lip of the platform it serves, so the walk that ends at it ends at
## an edge - and a body that refuses edges turns round two steps short of the
## rope every time. Riding up and then immediately walking back off the platform
## it was delivered to was this, not the ride.
func _edge_is_planned(way: float) -> bool:
	for i in mini(2, _legs.size()):
		var leg: Dictionary = _legs[i]
		if leg.kind != "drop" and leg.kind != "cable":
			continue
		# In front of it, or as good as underfoot. A planned edge behind it is
		# one it has already used.
		var lip: Vector2 = leg.from
		var along: float = (lip.x - global_position.x) * way
		if along < -DROP_NEAR or along > DROP_NEAR:
			continue
		return true
	return false


## What the current leg is: "walk", "drop", or "cable". Steering asks, because a
## lip it is meant to walk off and a lip it must not are the same lip.
func _leg_kind() -> String:
	if _legs.is_empty():
		return "walk"
	return _legs[0].kind


## Somewhere to run when it has been seen: away from the watcher, and further
## away from its caster than it already is.
##
## Both terms matter and the second is the one that is easy to forget. Running
## from the man who spotted it, on its own, is as likely to take it back past its
## caster as anywhere else - and a decoy that leads a firefight home has cost its
## owner the raid rather than saved it.
func _bolt_from(watcher: Vector2) -> Vector2:
	var home := _caster_at()
	var away := signf(global_position.x - watcher.x)
	if is_zero_approx(away):
		away = 1.0
	# If running from him would take it towards the caster, run the other way and
	# accept being chased past him - the caster is what it is protecting.
	if home.is_finite() and signf(home.x - global_position.x) == away:
		var room := absf(home.x - global_position.x)
		if room < AWAY_FROM_CASTER:
			away = -away
	return Vector2(global_position.x + away * 620.0, global_position.y)


## Where its caster is standing now, or INF if they are gone.
##
## Asked live rather than remembered from the cast. The whole job is to be
## somewhere its owner is not, and its owner is running - a decoy that measured
## its distance from a spot they left ten seconds ago would happily bait somebody
## into the room they are hiding in now.
func _caster_at() -> Vector2:
	var body := Net.player_for(get_multiplayer_authority())
	if body == null or not is_instance_valid(body):
		return Vector2.INF
	return body.global_position


## Somewhere to stand where somebody might see it, chosen rather than rolled.
##
## Scored on three things, in this order of weight:
##
## 1. **Distance from the caster.** Largest term by a wide margin. Everything
##    else this body does is worthless if it does it next door to the person it
##    is covering for.
## 2. **Whether a rival can see the spot.** This is the inversion of what this
##    function used to do - it used to score cover, and produced a ghost that was
##    superb at not being noticed. A decoy nobody notices is a decoy that did
##    nothing.
## 3. **Not doubling back**, so it reads as somebody going somewhere.
##
## If nobody is on the map to be seen by, the visibility term drops out and it
## simply travels - which is right: with no audience there is nothing to play to,
## and putting distance between itself and its caster is still worth doing.
func _pick_lure_target() -> void:
	_rethink = _rng.randf_range(2.2, 4.2)

	var cable := _a_cable_worth_taking()
	if cable.is_finite():
		_target = cable
		return

	var home := _caster_at()
	var here := global_position.x
	var back := _went
	var best := Vector2.INF
	var best_score := -INF

	for way in [-1.0, 1.0]:
		for step in COVER_STEPS:
			var spot := Vector2(here + way * step, global_position.y)
			var score := _rng.randf() * 30.0

			# Away from whoever cast it. Scored on the *gain*, so a ghost already
			# far away is not dragged further and further off the map, but one
			# still standing next to its caster will take almost any route out.
			if home.is_finite():
				var was := absf(here - home.x)
				var now := absf(spot.x - home.x)
				score += clampf((now - was) / 200.0, -3.0, 3.0) * 90.0
				if now < AWAY_FROM_CASTER * 0.5:
					score -= 160.0

			# Somewhere it can be seen from. The eye height offset matters: a
			# spot tested at floor level is behind every railing on the map.
			if not _seen_from(_eyes, spot + Vector2(0.0, _shape.position.y)).is_finite():
				score -= 150.0
			else:
				score += 150.0

			if not is_zero_approx(back) and signf(way) == back:
				score += 40.0

			# Not back to the rope it has just got off. Riding somewhere and then
			# immediately walking back to the foot of the same cable undoes the
			# journey in front of whoever it was trying to interest, and the cable
			# grudge only stops it getting *on* again, not from wandering back.
			if _last_cable and _cable_cooldown > 0.0 and is_instance_valid(_last_cable):
				var rope: Vector2 = (ROUTE.ends_of(_last_cable, global_position) as Array)[0]
				if absf(spot.x - rope.x) < absf(here - rope.x):
					score -= 120.0

			if score > best_score:
				best_score = score
				best = spot

	if not best.is_finite():
		var way := 1.0 if _rng.randf() < 0.5 else -1.0
		best = Vector2(here + way * COVER_STEPS[0], global_position.y)
	_target = best


## The far end of a cable in reach, if taking it would actually get it somewhere.
##
## Never the cable it has just been on. Nothing else in here stops a ghost that
## has ridden to the top of a rope from noticing the same rope is now in reach,
## deciding the bottom is worth a look, and riding back down - forever, in full
## view, which is about as far from a convincing person as it is possible to get.
func _a_cable_worth_taking() -> Vector2:
	if _rng.randf() > 0.45:
		return Vector2.INF
	var cable := _cable_here()
	if cable == null:
		return Vector2.INF
	var top := cable.world_top()
	var bottom := cable.world_bottom()
	var far := bottom
	if global_position.distance_to(bottom) < global_position.distance_to(top):
		far = top
	if absf(far.y - global_position.y) < WORTH_A_CABLE:
		return Vector2.INF
	return far


## The nearest cable it is allowed to get on right now.
##
## Zipline.nearest answers "which rope is in reach", which is a different
## question from "which rope should I take" for the whole CABLE_MEMORY seconds
## after it stepped off one. Asked in both places that grab a cable, so the two
## cannot disagree about what is off limits.
func _cable_here() -> Zipline:
	var cable := Zipline.nearest(get_tree(), global_position)
	if cable == null:
		return null
	if cable == _last_cable and _cable_cooldown > 0.0:
		return null
	return cable


## Turns a target into a heading, a jump and a cable.
func _steer(delta: float) -> void:
	_jump_cool = maxf(_jump_cool - delta, 0.0)
	# Freshly off a rope and still in the air: let it land before it starts
	# driving itself anywhere.
	if _settle_left > 0.0:
		_settle_left = maxf(_settle_left - delta, 0.0)
		if not is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
			return
		_settle_left = 0.0
	if not _target.is_finite():
		velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
		return

	var way := signf(_target.x - global_position.x)
	if is_zero_approx(way):
		way = float(facing)
	facing = 1 if way > 0.0 else -1

	# The cable this leg was walking to, once it is close enough to catch hold.
	# Checked before the opportunistic grab below, because the one it chose is
	# the one that goes where it is going.
	if _leg_cable and is_instance_valid(_leg_cable):
		# Not the rope it let go of half a second ago. The plan is re-asked from
		# where the body stands, and while it is still standing at the end of the
		# rope it stepped off, the answer is "take that rope" - so without a
		# guard it gets straight back on.
		#
		# Deliberately its own short timer rather than CABLE_MEMORY. That grudge
		# is nine seconds long and exists for a decoy baiting on its own, so it
		# does not ride one rope up and down in front of an audience. Applied to
		# a route it is simply wrong: a body that falls off a platform needs the
		# rope it just used to get back up, and forbidding it for nine seconds
		# left it pacing underneath until the errand expired.
		if _regrab <= 0.0 and _leg_cable.in_reach(global_position):
			_grab(_leg_cable)
			return
	elif _mind != Mind.ORDERS and absf(_target.y - global_position.y) > WORTH_A_CABLE:
		# Baiting on its own: take a rope that happens to be in reach if the
		# target is on another floor.
		#
		# Never while under orders, and that exclusion is the whole point. On an
		# errand the only rope worth taking is the one the plan chose; grabbing
		# whatever is nearby sends it somewhere the route never mentioned. It
		# fired most often after a stumble - a body that has slipped off a lip is
		# suddenly a long way below its target, which is exactly the condition
		# this used to read as "time to take a cable" - and the ride then carried
		# it further from the errand than the fall had.
		var cable := _cable_here()
		if cable:
			_grab(cable)
			return

	if is_on_floor():
		var blocked := test_move(global_transform, Vector2(way * WALL_PROBE, 0.0))
		var ledge := not test_move(global_transform,
			Vector2(way * LEDGE_PROBE, LEDGE_DROP))
		if blocked:
			# Something in the way. Ask whether it can actually be got over
			# before trying - the old version jumped at everything, every frame,
			# which against a two storey wall is a body bouncing on the spot.
			var lift := _clearance_over(way)
			# And only if there is something on the far side to come down on.
			# A crate sitting at the lip of a platform is climbable and still the
			# wrong thing to climb: the hop clears it and the body lands in open
			# air, falls a floor or two, and the errand is finished. Falls are
			# how a decoy ends up a thousand pixels off a route it had right.
			if lift >= 0.0 and _can_land_across(way):
				_hop()
				# Over it, not up at it. Pressed against a crate the collision has
				# already scrubbed its horizontal speed to nothing, so a standing
				# jump goes straight up and lands back on the same side - which is
				# the "struggles to get over boxes" report. The nudge is what
				# carries it across, and it is only applied on the frame it
				# actually leaves the ground.
				if is_zero_approx(_jump_cool - JUMP_COOLDOWN):
					velocity.x = way * MAX_SPEED * speed_scale * 0.9
			else:
				_turn_back(way)
				return
		elif ledge:
			# A drop. Three different right answers, and picking the wrong one is
			# what produced the pacing:
			if _mind == Mind.ORDERS and _edge_is_planned(way):
				# The route says this edge is the way down, so take it. Nothing
				# here hurts a body that falls. This used to be guessed from
				# whether the destination was lower, which is right at the lip
				# you meant and wrong at every other lip on the way - the body
				# would step off the first edge it met and land a floor below
				# its route. Now only a lip the map chose is walked off.
				pass
			elif _mind == Mind.BREAK and _can_land_across(way):
				_hop()
			else:
				_turn_back(way)
				return
		_watch_for_headway(delta)

	# The caster's own top speed, arrived at through the same chain of
	# multipliers Player._update_run walks: the weight of the gun and any wounds
	# come in on speed_scale, the plates and the crouch are applied here off this
	# body's own ramps. Aiming is the only term left out, and it is left out
	# because a ghost never aims down sights - it has nothing to aim.
	var cap := MAX_SPEED * speed_scale * DECOY_PACE
	cap *= lerpf(1.0, CROUCH_SPEED_SCALE, crouch)
	cap *= lerpf(1.0, SHIELD_SPEED_SCALE, shield)
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, way * cap, accel * delta)
	_went = way
	_aim_along(delta, way)


## A jump, if it is allowed one. Everything that wants to jump goes through here,
## so the cooldown cannot be forgotten at one of the call sites.
func _hop() -> void:
	if _jump_cool > 0.0:
		return
	velocity.y = _jump_velocity
	_jump_cool = JUMP_COOLDOWN


## How high it would have to be to get past what is in front of it, or -1 if
## nothing it can manage would do.
##
## Probed at a ladder of heights rather than tested once at the top of its reach.
## One test at full height answers "could it get over this if it were already up
## there", which is the wrong question twice over: under a low ceiling it says no
## to a knee-high crate, and it gives no idea how far it actually has to rise -
## so every obstacle got the same maximum-effort hop.
func _clearance_over(way: float) -> float:
	var reach := Vector2(way * (WALL_PROBE + 10.0), 0.0)
	for step in [14.0, 26.0, 38.0, 50.0, 62.0, STEP_UP]:
		# Is there room to be at that height at all? A girder overhead rules out
		# everything above it, however short the thing in front is.
		if test_move(global_transform, Vector2(0.0, -step)):
			return -1.0
		var lifted := global_transform
		lifted.origin.y -= step
		if not test_move(lifted, reach):
			return step
	return -1.0


## Whether the thing in front of it is a crate or a wall.
func _can_step_over(way: float) -> bool:
	return _clearance_over(way) >= 0.0


## Whether there is anything to land on across the gap ahead.
##
## Three reaches rather than one, so a narrow gap and a wide one are told apart:
## the near sample catches a step down it can hop, the far one catches the other
## side of a real gap. Nothing at any of them is a drop, and a drop is not a
## route.
func _can_land_across(way: float) -> bool:
	var space := get_world_2d().direct_space_state
	for reach in [90.0, 150.0, 215.0]:
		var from := global_position + Vector2(way * reach, -12.0)
		var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, 80.0))
		query.collision_mask = Layers.WORLD | Layers.ONE_WAY
		if not space.intersect_ray(query).is_empty():
			return true
	return false


## Gives up on the direction it was walking and commits to the other one.
##
## The commitment is the point. Turning round on its own is not enough: the route
## scorer immediately re-scores the way it just came from, likes it for the same
## reasons it liked it the first time, and sends it straight back into the wall.
func _turn_back(way: float) -> void:
	velocity.x = 0.0
	var spot := Vector2(global_position.x - way * TURN_BACK, global_position.y)
	# Under orders the leg is recomputed from the destination every frame, so a
	# plain turn-back is overwritten before it can take a single step and the
	# body walks into the same wall until it dies. So it is held as a detour
	# instead, which _next_leg honours for a moment before going back to working
	# towards where it was sent. Giving up outright on the first obstacle would
	# be worse: most walls on this map have a way round.
	if _mind == Mind.ORDERS:
		# Twice *without getting anywhere in between* is a barrier rather than an
		# obstacle. Backing off, walking forward, backing off again is the pacing
		# people see - so the second refusal ends the order rather than starting
		# another lap of it. The counter is cleared by any real headway; see
		# _watch_for_headway.
		_refusals += 1
		if _refusals >= GIVE_UP_AFTER:
			_stand_down()
			return
		_detour = spot
		_detour_left = TURN_COMMIT
		_leg_cable = null
		_leg_end = Vector2.INF
		# Ask the map again once the detour is done. A refusal means the body's
		# own eyes disagree with the route it was given, and the map knows about
		# walls - so the honest response is a different route, not another
		# attempt at the same one. It used to give up on the second refusal
		# because there was nothing better to do with the information.
		#
		# The plan it is holding is left alone in the meantime. Throwing it away
		# here blinds the very checks that decide whether the next edge is one
		# the route wanted, and a blind body refuses everything.
		_replan = TURN_COMMIT
	_target = spot
	_commit = TURN_COMMIT
	_rethink = maxf(_rethink, TURN_COMMIT)
	_stuck = 0.0
	_was_at = global_position.x


## Notices when it has stopped getting anywhere.
##
## Measured on distance covered rather than on whether something is in front of
## it, which is what it used to be. A body can be pressed against a wall and
## still walking usefully along it, and a body in clear air can be going nowhere
## because it is wedged on a corner - only one of those is worth reacting to and
## the old test got both of them wrong.
func _watch_for_headway(delta: float) -> void:
	if not is_finite(_was_at) or absf(global_position.x - _was_at) > 3.0:
		_was_at = global_position.x
		_stuck = 0.0
		# Ground covered clears the refusal count as well. Two refusals means
		# "this is a barrier, not an obstacle" only if nothing was achieved
		# between them - counted across a whole order it meant that any journey
		# long enough to pass two crates was abandoned halfway, which a soak
		# across the level showed was very nearly every journey there is.
		_refusals = 0
		return
	_stuck += delta
	if _stuck > STUCK_TIME:
		_turn_back(signf(_target.x - global_position.x))


## Where the arm points. Down range of wherever it is walking, wandering a little
## the way a person's does - and levelled at whoever it is running from, because
## a body sprinting away with its gun trained back over its shoulder is a body
## you follow rather than one you let go.
func _aim_along(delta: float, way: float) -> void:
	var wanted := 0.0 if way > 0.0 else PI
	if _mind == Mind.BREAK and _threat.is_finite():
		wanted = sight_centre().angle_to_point(_threat)
	else:
		wanted += sin(Time.get_ticks_msec() * 0.0011) * 0.22
	aim_angle = lerp_angle(aim_angle, wanted, clampf(delta * 6.0, 0.0, 1.0))


func _face_the_threat() -> void:
	if not _threat.is_finite():
		return
	facing = 1 if _threat.x > global_position.x else -1
	aim_angle = lerp_angle(aim_angle, sight_centre().angle_to_point(_threat), 0.2)


func _walk(delta: float) -> void:
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0
	var gravity := _jump_gravity if velocity.y < 0.0 else _fall_gravity
	velocity.y = minf(velocity.y + gravity * delta, MAX_FALL_SPEED)
	if is_zero_approx(velocity.x):
		var friction := GROUND_FRICTION if is_on_floor() else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


# --- cables -------------------------------------------------------------------


func _grab(cable: Zipline) -> void:
	_zipline = cable
	riding = true
	global_position = cable.clamp_to_cable(global_position)
	velocity = Vector2.ZERO
	# Which way along it. Toward the end that gets it nearer to wherever it is
	# actually going, which is the whole reason it got on - and that is the
	# destination when it has one, not the leg, because the leg is the cable
	# itself and measuring against it would answer nothing.
	# Toward the end the route asked for, when there is a route. Comparing the
	# final destination's height instead - which is what this did - picks the
	# wrong end of every rope on a journey that goes up before it comes down.
	# Standing at the bottom of a rope it was meant to ride up, it would decide
	# the bottom was nearer its goal, let go on the frame it grabbed, and catch
	# hold again immediately: a body frozen on the spot for a whole errand.
	var goal := _leg_end if _leg_end.is_finite() else (
		destination if destination.is_finite() else _target)
	var to_top := INF
	var to_bottom := 0.0
	if goal.is_finite():
		to_top = absf(goal.y - cable.world_top().y)
		to_bottom = absf(goal.y - cable.world_bottom().y)
	_ride_way = -1.0 if to_top < to_bottom else 1.0


## Riding, and the same ride the player gets: position set straight onto the
## cable, no gravity, no running, no move_and_slide. Returns true while it is on
## the rope, which is a whole movement mode and skips everything else.
##
## Silent, like the rest of it. A rider is the one thing on this map with a
## continuous sound attached to it - Player calls Audio.zipline every frame it is
## moving - and a ghost on a rope is therefore the single best chance anybody
## gets to catch one by ear.
func _ride(delta: float) -> bool:
	if _zipline == null:
		return false
	if not is_instance_valid(_zipline):
		_let_go(false)
		return false

	var travel := _ride_way * _zipline.speed * delta
	var wanted := global_position - _zipline.direction() * travel
	var pinned: Vector2 = _zipline.clamp_to_cable(wanted)

	if _ride_way > 0.0 and pinned.distance_to(_zipline.world_bottom()) < 1.0:
		global_position = pinned
		_let_go(false)
		return false
	if _ride_way < 0.0 and pinned.distance_to(_zipline.world_top()) < 1.0:
		global_position = pinned
		_let_go(true)
		return false

	global_position = pinned
	# Level with where it is going: step off here rather than riding to the end
	# of the rope, which is what a person does.
	#
	# Measured against the destination, never against _target. Under orders
	# _target is the cable's own near end - the thing it walked here to get on -
	# so testing that means the body is already level with it the instant it
	# grabs hold, and it steps straight back off. Thirty-four pixels of climb out
	# of seven hundred, which reads as the rope not working at all.
	# Where this ride is supposed to end: the route's own answer when it has one,
	# and the destination only when it is riding on its own initiative. Stepping
	# off level with the final destination is right for a single rope and wrong
	# for every rope on a longer journey - the route often climbs past the
	# destination's height on purpose, and getting off there drops the body onto
	# a floor the plan never wanted it on.
	# Only when it is riding on its own initiative. A ride the route asked for
	# runs to the end of the rope, because the route chose that end: getting off
	# forty pixels early puts it short of the platform the rope serves, which is
	# often past a lip it then refuses - so it walks away from the very ledge it
	# was delivered to and the journey unravels from there.
	if _leg_end.is_finite():
		return true
	var goal := destination if destination.is_finite() else _target
	if goal.is_finite() and absf(global_position.y - goal.y) < 40.0:
		_let_go(true)
	return true


func _let_go(hop: bool) -> void:
	# Remembered, and off limits for a while. See CABLE_MEMORY and _cable_here.
	_last_cable = _zipline
	_cable_cooldown = CABLE_MEMORY
	_regrab = REGRAB_GUARD
	_zipline = null
	riding = false
	velocity.x = 0.0
	velocity.y = -220.0 if hop else 0.0
	# Nothing horizontal until its feet are down. Stepping off the top of a
	# rope leaves it in the air for a moment, and _steer only looks for
	# ledges when it is standing on something - so it would accelerate
	# straight at a target that is very often back the way it came, drift
	# off the narrow platform it had just been delivered to, and fall. That
	# is the "rides up and then walks backwards off the edge" report.
	_settle_left = SETTLE_TIME
	# That leg is done. Under orders the next one is worked out from where it has
	# ended up - which is usually "now just walk there" - and otherwise the floor
	# it has arrived on is a new place with new sightlines, so it picks again.
	_leg_cable = null
	_leg_end = Vector2.INF
	_target = Vector2.INF
	# A new floor is a new set of options: ask again rather than walking on with
	# a plan drawn up from the other end of the rope.
	_replan = 0.0
	_rethink = 0.0
	if _mind == Mind.ORDERS:
		_target = _next_leg()


# --- being shot ---------------------------------------------------------------


## A round has reached it. Three of them and it is finished.
##
## Routed to the owner exactly the way a hit on a character is (see
## Player.take_damage): the host works out that the round connected, but the
## machine that owns the body is the one that decides what the body does about
## it, or the owner's next sync would overwrite the answer a frame later.
func take_damage(_amount: float, at: Vector2, direction: Vector2) -> void:
	if _dying > 0.0:
		return
	if Net.is_networked() and not is_mine():
		Net.tell_ghost_hit(get_multiplayer_authority(), at, direction,
			Net.attributing_to)
		return
	hit(at, direction)


## The owner's half of the above, and the one place `hits` goes up.
func hit(at: Vector2, direction: Vector2) -> void:
	if _dying > 0.0 or hits >= max_hits:
		return
	hits += 1
	# Shoved, like a person. It is the cheapest thing that makes a round landing
	# read as a round landing rather than as a number changing.
	velocity.x += direction.x * 60.0

	# Being shot at counts as being seen, and has to. The sweep in _watch only
	# finds people with a clear line to it, which is exactly the set of people a
	# round arriving proves you have missed - somebody prone in the dark, or on a
	# catwalk the ray happened not to reach. A decoy that walked on whistling
	# while it was being hit would be the one tell nobody could miss.
	#
	# Where the shooter is, inferred from the round rather than looked up: the
	# body that fired is not on this machine's list of things to ask, and the
	# direction of travel is a good enough answer to "which way do I not want to
	# be standing".
	_threat = at - direction.normalized() * 600.0
	destination = Vector2.INF
	_leg_cable = null
	_orders_left = 0.0
	# Straight to the run, with no peek. It has already been found and shot at,
	# and standing there holding somebody's eye is a thing you do to be noticed -
	# a man who is already being fired on and stays put is not baiting anybody,
	# he is being killed. Running is also what buys the third round the time to
	# arrive somewhere its caster is not.
	_mind = Mind.BREAK
	_hold = BREAK_TIME
	_target = _bolt_from(_threat)

	# Whoever fired gets their hitmarker. A decoy you could tell from a person by
	# the absence of a tick on your own screen would be no decoy at all - and it
	# is the same call a real body makes, through the same route, so the mark
	# arrives from the same place with the same timing.
	var height := size.y
	var top := sight_centre().y - height * 0.5
	var headshot := at.y <= top + height * Damage.HEAD_FRACTION
	Damage.report_hit(get_tree(), headshot, hits >= max_hits)

	if hits >= max_hits:
		_finish()


## The owner calling it. `gone` is replicated, so every other copy comes apart on
## the same event rather than each running out its own clock a few frames apart.
func _finish() -> void:
	if _dying > 0.0:
		return
	gone = true
	_begin_dying()


func _begin_dying() -> void:
	if _dying > 0.0:
		return
	_dying = DEATH_TIME
	dying_at = 1.0
	glitch_seed = _rng.randi()
	# Out of the way of anything still being fired at it, and out of the group
	# that decides what is drawn - from here it is an animation, not a body.
	collision_layer = 0
	collision_mask = 0
	remove_from_group(&"hideable")
	visible = true


## Coming apart.
##
## Not a fade. A fade is what a thing made of matter does, and the one thing this
## body has to say on its way out is that it was never made of anything - so it
## cuts out instead. The silhouette is drawn in stuttering slots that get shorter
## and rarer as it goes: at the start it is there most of the time and dropping
## the odd frame, at the end it is a couple of stray frames a quarter of a second
## apart, and then it is not there at all. Between the flashes the tear keeps
## drawing where the body was, so the shape is still legible while the body
## itself is missing.
##
## Stepped in fixed slots rather than rolled per frame, which matters more than
## it sounds: a per-frame roll flickers at whatever the frame rate happens to be,
## so the same death reads as a shiver on a 240 Hz monitor and a strobe on a
## 30 fps phone. In slots it is the same animation on both.
func _die_off(delta: float) -> void:
	_dying -= delta
	var left := clampf(_dying / DEATH_TIME, 0.0, 1.0)
	var through := 1.0 - left
	dying_at = left

	# The tear runs the whole way out at full strength and reshuffles constantly.
	# During a hit it holds one shape, because a hit is damage to a picture;
	# here the picture itself is failing, and it should never settle.
	glitch = 1.0
	glitch_seed = _blink_slot(through) * 2654435761

	var on := _blink_on(through)
	_show_body(on)
	if on:
		# Every time it comes back it comes back somewhere slightly else, and
		# further off as it gets worse. Cutting back in exactly where it left is
		# what makes a strobe read as a lamp rather than a picture breaking up.
		_body.position.x = _rng.randf_range(-9.0, 9.0) * through
		_body.position.y = _rng.randf_range(-4.0, 4.0) * through
	if _dying <= 0.0:
		queue_free()


## Which stutter slot the animation is in, given how far through it is.
##
## Slots shorten as it goes, so this is the integral of a shrinking interval
## rather than a division - stepping a shrinking beat with `time / beat` makes
## the slot number run *backwards* when the beat shrinks faster than time moves.
func _blink_slot(through: float) -> int:
	var elapsed := DEATH_TIME * through
	var beat := lerpf(BLINK_SLOW, BLINK_FAST, through)
	return int(elapsed / maxf(beat, 0.001))


## Whether the body is drawn in the current slot. Hashed off the slot number, so
## every machine watching the same ghost die sees the same stutter, and so one
## slot holds its answer for its whole length instead of shimmering.
func _blink_on(through: float) -> bool:
	var slot := _blink_slot(through)
	# A cheap integer hash to 0..1. randf() would give a different pattern on
	# every machine, and the tear is the one part of this that is worth agreeing
	# on: two players watching the same body should see the same thing fail.
	var mixed := (slot * 374761393 + 668265263) & 0x7fffffff
	mixed = (mixed ^ (mixed >> 13)) * 1274126177 & 0x7fffffff
	var roll := float(mixed % 1000) / 1000.0
	return roll < lerpf(BLINK_ON_FIRST, BLINK_ON_LAST, through)


## The character itself, on or off. Not the whole Body node: the tear and the
## echoes behind it are children of Body and have to keep drawing while the
## silhouette they are drawn from is missing, which is the entire effect.
func _show_body(on: bool) -> void:
	_torso.visible = on
	_head.visible = on
	_face.visible = on
	_arm.visible = on
	if _outline:
		_outline.visible = on
