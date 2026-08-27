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
## It behaves like somebody who knows they are outgunned. Left alone it wanders,
## takes cables to get about, and generally goes somewhere. Caught in the open it
## breaks line of sight and gets behind something, which is what a real player
## does and is also, usefully, what keeps it alive long enough to be worth
## casting.
##
## Deliberately has no `class_name`. It reaches Net, and a global that reaches
## Net is a global a `--script` tool can poison for a whole process by so much as
## naming it - see the headless-test notes. Nothing needs it as a type: Net
## instantiates the scene and duck-types it, and the tools find it by group.

## Group everything that wants to find one of these looks in.
const GROUP := &"projection"

## Run, taken from Player so the gait reads as the same person. A ghost that
## moved at its own speed would be a tell you could measure with a stopwatch.
const MAX_SPEED := 260.0
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

## How close to a target counts as arrived.
const ARRIVED := 48.0

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
## How far from where it was cast it is willing to be sent. Only bounds the
## caster's aimed order - once it is loose it goes wherever the bait takes it.
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
## Where the caster told it to go, in world space, or INF for "your own way".
var _orders := Vector2.INF
## Rising while it is walking into something it cannot get past, so a ghost
## jammed in a corner eventually tries elsewhere instead of leaning on the wall
## for the rest of its life.
var _stuck := 0.0
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
	# Where the caster was pointing when they spent it, if anywhere. This is the
	# only steering anybody gets: after it arrives it is on its own.
	var sent: Variant = look.get("orders", null)
	if sent != null and (sent as Vector2).is_finite():
		_orders = sent
		_mind = Mind.ORDERS
		_target = _orders
		# Long enough to walk a screen, short enough that a ghost wedged against
		# a crate gives up and starts working instead of leaning on it.
		_rethink = 8.0

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
		_orders = Vector2.INF
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
		var alive: Variant = body.get(&"is_alive")
		if typeof(alive) == TYPE_BOOL and not alive:
			continue
		var eye: Vector2 = body.global_position
		if body.has_method(&"sight_centre"):
			eye = body.sight_centre()
		if eye.distance_to(here) < WATCH_RANGE:
			found.append(eye)
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(here) < b.distance_squared_to(here))
	return found


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
		return eye
	return Vector2.INF


# --- making up its mind -------------------------------------------------------


func _think(delta: float) -> void:
	_rethink -= delta
	_cable_cooldown = maxf(_cable_cooldown - delta, 0.0)
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
			# Walking to wherever the caster pointed. Nothing interrupts this
			# except arriving or being seen on the way - if you sent it somewhere
			# you had a reason, and second-guessing you halfway there would make
			# the aim pointless.
			if not _orders.is_finite():
				_mind = Mind.LURE
			elif _arrived() or _rethink <= 0.0:
				_orders = Vector2.INF
				_mind = Mind.LURE
				_target = Vector2.INF
				_rethink = 0.0
			else:
				_target = _orders
		Mind.LURE:
			if _rethink <= 0.0 or not _target.is_finite() or _arrived():
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
	if not _target.is_finite():
		return false
	if absf(_target.x - global_position.x) > ARRIVED:
		return false
	return absf(_target.y - global_position.y) <= WORTH_A_CABLE


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
	var back := signf(velocity.x)
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
	if not _target.is_finite():
		velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
		return

	var way := signf(_target.x - global_position.x)
	if is_zero_approx(way):
		way = float(facing)
	facing = 1 if way > 0.0 else -1

	# A cable beats a ladder it does not have. If the target is well above or
	# below and there is a rope within arm's reach - and it is not the rope it
	# just got off - take it.
	if absf(_target.y - global_position.y) > WORTH_A_CABLE:
		var cable := _cable_here()
		if cable:
			_grab(cable)
			return

	var blocked := test_move(global_transform, Vector2(way * 20.0, 0.0))
	var ledge := not test_move(global_transform, Vector2(way * 24.0, 14.0))
	if is_on_floor():
		if blocked:
			# Something in the way. Try to get over it; if it has been trying for
			# a while, it is a wall, not a crate.
			velocity.y = _jump_velocity
			_stuck += delta * 3.0
		elif ledge and _mind != Mind.BREAK:
			# Roaming, a drop is not worth taking. Turn around and go the other
			# way, which is also how it stops walking off every catwalk it meets.
			_target = Vector2(global_position.x - way * 400.0, global_position.y)
			return
		elif _target.y < global_position.y - WORTH_A_CABLE * 0.5 and not ledge:
			velocity.y = _jump_velocity
		else:
			_stuck = maxf(_stuck - delta, 0.0)
	if _stuck > 2.0:
		_stuck = 0.0
		_target = Vector2.INF
		_rethink = 0.0

	# The caster's own top speed, arrived at through the same chain of
	# multipliers Player._update_run walks: the weight of the gun and any wounds
	# come in on speed_scale, the plates and the crouch are applied here off this
	# body's own ramps. Aiming is the only term left out, and it is left out
	# because a ghost never aims down sights - it has nothing to aim.
	var cap := MAX_SPEED * speed_scale
	cap *= lerpf(1.0, CROUCH_SPEED_SCALE, crouch)
	cap *= lerpf(1.0, SHIELD_SPEED_SCALE, shield)
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, way * cap, accel * delta)
	_aim_along(delta, way)


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
	# Which way along it. Toward the end that gets it nearer to wherever it was
	# going, which is the whole reason it got on.
	var to_top := INF
	var to_bottom := 0.0
	if _target.is_finite():
		to_top = absf(_target.y - cable.world_top().y)
		to_bottom = absf(_target.y - cable.world_bottom().y)
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
	# Level with where it was going: step off here rather than riding to the end
	# of the rope, which is what a person does.
	if _target.is_finite() and absf(global_position.y - _target.y) < 40.0:
		_let_go(true)
	return true


func _let_go(hop: bool) -> void:
	# Remembered, and off limits for a while. See CABLE_MEMORY and _cable_here.
	_last_cable = _zipline
	_cable_cooldown = CABLE_MEMORY
	_zipline = null
	riding = false
	velocity.y = -220.0 if hop else 0.0
	# Wherever the rope let it out, that is a new place with new sightlines. The
	# target it was walking to before it got on is on the floor it has just left.
	_target = Vector2.INF
	_rethink = 0.0


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
	_orders = Vector2.INF
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
