class_name Enemy
extends CharacterBody2D

## Patrolling guard that shoots back.
##
## Deliberately simple: it walks a beat around where it was placed, and once it
## has line of sight on the player it stops, takes a moment to react, then fires
## its rifle in bursts while shuffling to keep a comfortable distance. Losing
## sight makes it hold and watch for a few seconds before going back on patrol,
## so ducking behind cover buys time instead of instantly resetting the fight.
##
## It shoots through the same Weapon node the player uses, so ammo, reloads,
## recoil bloom and damage falloff all behave the way they do for the player -
## only the loadout and the hit mask differ.

enum State { PATROL, ALERT, SEARCH }

@export_group("Body")
@export var max_health := 90.0
## Outline used by the vision system to decide whether the player can see this
## guard, and by the health bar for placement.
@export var size := Vector2(30, 52)
@export var respawn_time := 6.0

@export_group("Movement")
@export var walk_speed := 84.0
## Half-width of the beat walked around the spawn point. Wide on purpose: a
## guard who paces a long beat is a guard you can hear moving about and place
## in the dark, where one shuffling on the spot is just an occasional noise.
@export var patrol_range := 300.0
## Seconds spent standing still at each end of the beat. Short - the pause is
## there to make the turn read, not to park him.
@export var patrol_pause := 0.5
## Distance the guard tries to hold once it has seen the player.
@export var preferred_range := 320.0
## Only steps to correct the range once it is off by more than this, so it does
## not jitter back and forth on the spot.
@export var range_deadzone := 90.0
## Combat shuffling is slower than a patrol walk.
@export var combat_speed_scale := 0.55
@export var gravity := 1500.0
## Ground covered between footfalls, in pixels. A guard's boots are the warning
## you get before you can see them, so this is deliberately audible.
@export var step_distance := 42.0

@export_group("Senses")
@export var sight_range := 760.0
## Total delay between spotting the player and the first shot. Long enough that
## being seen is the start of a problem rather than the end of one - you can
## still break line of sight, or shoot first. This is the main dial on how
## punishing a guard is: at a second it was a coin flip whether you got to react.
@export var reaction_time := 1.7
## Spread on that delay, rolled per guard when he spots you. Without it a room
## full of guards all open up on the same frame, which reads as scripted rather
## than as several people noticing you at slightly different moments.
@export_range(0.0, 1.0) var reaction_variance := 0.35
## The first beat of the delay: he plants his feet and swings the gun onto you.
## Held still on purpose - a guard who keeps side-stepping while he "reacts"
## never looks like he reacted at all, and the pause you are being given stops
## reading as a pause. The rest of reaction_time is spent levelled at you,
## closing the distance but not shooting.
@export var notice_time := 0.45
## Muzzle speed during that beat, in radians per second. Faster than his normal
## tracking: noticing you is sharp, keeping up with you afterwards is not.
@export var notice_aim_speed := 11.0

## What the eye says he is doing. The tell matters as much as the delay - a
## window to react is worth nothing if you cannot see that it has opened.
const EYE_CALM := Color(1.0, 0.85, 0.5)
const EYE_SPOTTED := Color(1.0, 0.99, 0.92)
const EYE_FIRING := Color(1.0, 0.36, 0.3)
const EYE_SEARCHING := Color(1.0, 0.72, 0.38)
## How long the guard keeps watching the last known position after losing sight.
@export var search_time := 3.0

@export_group("Aim")
## Radians per second the muzzle swings toward the player. Slower than yours:
## a guard should be beatable to the first shot if you saw him coming.
@export var aim_speed := 4.2
## Worst-case aim error, in degrees. Re-rolled each burst, so a guard is not
## permanently wide or permanently dead-on.
@export var aim_error := 5.0
@export var burst_time := 0.55
@export var burst_pause := 0.85

@export_group("Loadout")
## Each guard is issued one of these at random. This is the only way the player
## gets anything better than the starting sidearm, so the pool is the real
## weapon progression: kill someone carrying what you want.
@export var weapon_pool: PackedStringArray = [
	"res://resources/weapons/assault_rifle.tres",
	"res://resources/weapons/smg.tres",
	"res://resources/weapons/shotgun.tres",
	"res://resources/weapons/lmg.tres",
	"res://resources/weapons/sniper.tres",
	"res://resources/weapons/enemy_rifle.tres",
]
## Guards fire the same guns for a fraction of the damage - see Weapon's
## damage_scale for why.
@export_range(0.05, 1.0) var damage_scale := 0.4
## Chance a guard also carries a sidearm, which he never draws but you can take.
@export_range(0.0, 1.0) var sidearm_chance := 0.5
## Chance of a spare gun in his pack. Rare, so finding one is worth something.
@export_range(0.0, 1.0) var spare_chance := 0.2
## Spare magazines in his pockets, before the pocket limit is applied.
@export var spare_mags := 3
## Chance of a helmet, and separately of a vest. Half the helmets found are
## already half-broken, which is what makes a headshot worth trying anyway.
@export_range(0.0, 1.0) var armor_chance := 0.45
@export_range(0.0, 1.0) var medkit_chance := 0.35
## Chance he is wearing a proper pack instead of a chest rig. The bag itself is
## the loot here - taking it is how you get more room to carry everything else.
@export_range(0.0, 1.0) var pack_chance := 0.25

## Solid geometry only, matching vision_system.gd: guards see under and over the
## one-way catwalks exactly as the player does, so cover means the same thing to
## both sides.
const SIGHT_MASK := Layers.WORLD
const SIDEARM := "res://resources/weapons/pistol.tres"
const CHEST_RIG := "res://resources/backpacks/chest_rig.tres"
const PATROL_PACK := "res://resources/backpacks/patrol_pack.tres"
const VESTS := [
	"res://resources/armor/light_vest.tres",
	"res://resources/armor/heavy_vest.tres",
]

@onready var _visual: Polygon2D = $Visual
@onready var _eye_dot: Polygon2D = $Body/Eye
@onready var _body: Node2D = $Body
@onready var _muzzle: Marker2D = $AimPivot/Muzzle
@onready var _aim_pivot: Node2D = $AimPivot
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _health_fill: Polygon2D = $HealthBar/Fill
@onready var _floor_probe: RayCast2D = $FloorProbe
@onready var weapon: Weapon = $Weapon
## By path, not as the `Audio` global - see the note in weapon.gd.
@onready var _audio: Node = get_node_or_null(^"/root/Audio")

var state := State.PATROL
var facing := 1

var _health: float
var _home := Vector2.ZERO
var _aim_angle := 0.0
var _player: Node2D
var _last_seen := Vector2.ZERO
var _pause_timer := 0.0
var _react_timer := 0.0
## The delay rolled for this sighting, so the notice beat can be measured from
## the start of it rather than from a fixed number.
var _react_total := 0.0
## Drives the pulse on the eye while he has you but has not fired yet.
var _eye_clock := 0.0
var _search_timer := 0.0
var _burst_timer := 0.0
var _shooting := false
var _error := 0.0
var _alive := true
## How far down to look for ground on a replica. See _replica_grounded.
const GROUND_PROBE := 4.0
var _step_travel := 0.0

## The slice of a guard that travels to other machines. Plain fields because a
## SceneReplicationConfig names properties, and the ones the AI actually uses are
## private or derived - keeping the wire format separate means changing how a
## guard thinks does not silently change what the network sends.
var net_aim := 0.0
var net_health := 0.0
var net_alive := true


func _ready() -> void:
	# Alone, yes. In a match, not yet.
	#
	# Temporary, and only for testing: a raid against other players is easier to
	# work on with nothing else shooting at anybody, and eleven guards is a lot of
	# noise to debug a netcode problem through. Playing alone gets the level it is
	# supposed to have.
	#
	# Safe to decide here, and this is the one thing worth checking if it ever
	# stops being true. is_networked() reads the multiplayer peer itself, and the
	# peer is assigned by host(), join() or serve() *before* the level is loaded -
	# the lobby dials first and opens the map second, deliberately, because doing
	# it the other way tore down the socket mid-handshake. So every machine in a
	# match answers this the same way on the same frame, and a level where one
	# peer kept its guards and another did not is not a state this can reach.
	if Net.is_networked():
		queue_free()
		return
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD | Layers.ONE_WAY
	_home = global_position
	_issue_weapon()
	_shape_up()
	_reset()


## Kits this guard out: a rifle, maybe a sidearm, maybe a spare in the pack, and
## rounds in his pockets for whatever he is carrying. Rolled here rather than
## placed in the scene, so every guard in the level differs - and so looting one
## is always worth walking over to find out.
func _issue_weapon() -> void:
	weapon.damage_scale = damage_scale
	if weapon_pool.is_empty():
		return

	# A chest rig, not a rucksack: guards carry little, and what they carry is
	# what you get. The grid is small enough that a spare rifle crowds out the
	# spare magazines, which is where the variety in loot comes from.
	#
	# It is a real bag rather than bare grid space, which means you can take the
	# whole thing off him - kit, space and all - instead of emptying it a cell at
	# a time. Early on, a guard's rig is where your carrying capacity comes from.
	var kit := Inventory.new()
	var bag := PATROL_PACK if randf() < pack_chance else CHEST_RIG
	kit.set_backpack(Item.from_backpack(load(bag)))

	var main := load(weapon_pool[randi() % weapon_pool.size()]) as WeaponData
	kit.primary = Item.from_weapon(main)
	kit.add_rounds(main.ammo_type, main.mag_size * spare_mags)

	if randf() < sidearm_chance:
		var pistol := load(SIDEARM) as WeaponData
		kit.secondary = Item.from_weapon(pistol)
		kit.add_rounds(pistol.ammo_type, pistol.mag_size * 2)

	# No helmets. A guard is one clean headshot, always - which is what makes
	# taking the time to line one up worth more than spraying at his chest.
	# Helmets stay in the shop for the player, who has more to lose.
	if randf() < armor_chance:
		kit.vest = Item.from_armor(load(VESTS[randi() % VESTS.size()]))
	if randf() < medkit_chance:
		kit.store(Item.from_medkit(randi_range(1, 3)))

	if randf() < spare_chance:
		var spare := load(weapon_pool[randi() % weapon_pool.size()]) as WeaponData
		kit.store(Item.from_weapon(spare))
		kit.add_rounds(spare.ammo_type, spare.mag_size)

	weapon.set_inventory(kit)


## Resizes the visuals and collision to match `size`, the same way the practice
## dummies do, so a guard can be scaled from the inspector without editing
## polygons by hand.
func _shape_up() -> void:
	var half := size * 0.5
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	(_shape.shape as RectangleShape2D).size = size
	$HealthBar.position = Vector2(0.0, -half.y - 12.0)
	_floor_probe.position = Vector2(half.x, half.y - 4.0)


## Guards think on the host and nowhere else.
##
## Two machines running the same patrol drift apart within seconds - a different
## random turn, a different frame where the player came into view - and then they
## disagree about where a guard is standing and who he is shooting. One authority
## decides, everyone else is shown the result.
func is_brain() -> bool:
	return not Net.is_networked() or is_multiplayer_authority()


func _physics_process(delta: float) -> void:
	if not is_brain():
		_show_replica()
		return
	if not _alive:
		return

	_publish_state()

	weapon.tick(delta)
	_look(delta)

	match state:
		State.PATROL:
			_patrol(delta)
		State.ALERT:
			_fight(delta)
		State.SEARCH:
			_search(delta)

	velocity.y = minf(velocity.y + gravity * delta, 1200.0)
	_face()
	move_and_slide()
	_update_footsteps(delta)
	_update_eye(delta)

	_aim_pivot.rotation = _aim_angle
	# Mirror rather than let the arm hang upside down when aiming left.
	_aim_pivot.scale.y = facing


## Copies out the slice of this guard that goes over the wire. The real fields
## are private and some are derived, so this is a deliberate wire format rather
## than whatever the AI happens to be holding.
##
## Called from the damage path as well as from the frame loop, and that is the
## whole point. Dying stops a guard's physics process, so a state published only
## from _physics_process is published one frame *before* the killing shot and
## never again: every other machine is left holding "alive, and nearly dead",
## for the rest of the raid. It reads as bullets not registering. It is actually
## the last word never being said.
## Whether this body is standing on something, for a copy that never runs
## move_and_slide.
##
## `is_on_floor()` is set by move_and_slide and by nothing else, and a replica
## does not call it - so on every machine but the owner's it reads false forever.
## That is why nobody else's footsteps ever played: the check that gated them
## could not be true on the machine that needed to hear them. Tested against the
## body's own shape and mask instead, which needs no new synced property and
## therefore no agreement between the two ends.
func _replica_grounded() -> bool:
	return test_move(global_transform, Vector2(0.0, GROUND_PROBE))


func _publish_state() -> void:
	net_aim = _aim_angle
	net_health = _health
	net_alive = _alive


## A guard as seen from a machine that is not thinking for him. Position and aim
## arrive replicated; the look of him is rebuilt from those locally so none of the
## presentation has to travel.
func _show_replica() -> void:
	_aim_pivot.rotation = net_aim
	_aim_pivot.scale.y = facing
	_body.scale.x = facing
	_aim_angle = net_aim

	# Dying is a state change, not an event, so it arrives as a flag rather than
	# as a call - act on the edge.
	if _alive and not net_alive:
		_alive = false
		_health = 0.0
		visible = false
		_shape.set_deferred(&"disabled", true)
		# Out of the vision system too, exactly as _die does it on the host.
		# Left in, a dead guard keeps being lit and un-lit by the light and pops
		# back into view - a corpse nobody can shoot, standing where he fell.
		remove_from_group(&"hideable")
	elif not _alive and net_alive:
		_alive = true
		visible = true
		_shape.set_deferred(&"disabled", false)
		if not is_in_group(&"hideable"):
			add_to_group(&"hideable")

	if _alive:
		_health = net_health
		_health_fill.scale.x = clampf(_health / maxf(max_health, 1.0), 0.0, 1.0)
		_visual.color = _color_for_health()
		_update_eye(get_physics_process_delta_time())
		# Their boots, from their replicated velocity, through the same footstep
		# path everyone else uses.
		_step_travel += absf(velocity.x) * get_physics_process_delta_time()
		if _step_travel >= step_distance:
			_step_travel = 0.0
			if _audio and _replica_grounded():
				_audio.guard_footstep(global_position)


## What the guard's eye is doing, which is the only way the reaction window is
## visible from across a room. Amber on patrol, flashing white the moment he has
## you, then red once he is actually shooting - so "he has seen me" and "he is
## firing" are two different things you can see, at the distance you would have
## to make the decision from.
func _update_eye(delta: float) -> void:
	if not _alive:
		return
	if state == State.PATROL:
		_eye_clock = 0.0
		_eye_dot.color = EYE_CALM
		return
	if state == State.SEARCH:
		_eye_clock = 0.0
		_eye_dot.color = EYE_SEARCHING
		return

	if is_holding_fire():
		# Pulsing rather than solid: a steady colour change is easy to miss on a
		# small sprite, a blinking one is not.
		_eye_clock += delta
		var beat := 0.5 + 0.5 * sin(_eye_clock * 18.0)
		_eye_dot.color = EYE_CALM.lerp(EYE_SPOTTED, beat)
	else:
		_eye_clock = 0.0
		_eye_dot.color = EYE_FIRING


## Boots on the ground, at the same distance-based cadence the player uses but
## a lighter sound, so you can tell whose footsteps you are hearing.
func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	_step_travel += absf(velocity.x) * delta
	if _step_travel >= step_distance:
		_step_travel = 0.0
		if _audio:
			_audio.guard_footstep(global_position)


# --- senses -------------------------------------------------------------------


func _look(delta: float) -> void:
	var seen := _can_see_player()

	if seen:
		_last_seen = _player.global_position
		if state != State.ALERT:
			_enter_alert()
	elif state == State.ALERT:
		state = State.SEARCH
		_search_timer = search_time
		_shooting = false

	# Swing the muzzle toward wherever the guard currently believes the player is.
	# On patrol it just points the way it is walking.
	var aim_target := _last_seen
	if state == State.PATROL:
		aim_target = global_position + Vector2(facing * 100.0, 0.0)
	var wanted := _eye_position().angle_to_point(aim_target) + _error
	# The gun comes up fast at the moment of noticing and tracks slowly after -
	# which is what makes the first beat look like a reaction and the rest look
	# like a man trying to keep a sight on someone who is moving.
	var swing := notice_aim_speed if is_noticing() else aim_speed
	_aim_angle = rotate_toward(_aim_angle, wanted, swing * delta)


## True during the opening beat of a sighting: he has seen you and is bringing
## the gun round, and has not started closing or shooting.
func is_noticing() -> bool:
	return state == State.ALERT and _react_timer > _react_total - notice_time


## True while he has you but has not opened fire - the window you are given.
func is_holding_fire() -> bool:
	return state == State.ALERT and _react_timer > 0.0


func _can_see_player() -> bool:
	if not is_instance_valid(_player):
		_player = Net.nearest_player(global_position)
		if _player == null:
			return false
	if not _player_is_alive():
		return false

	var eye := _eye_position()
	var to_player := _player.global_position - eye
	if to_player.length() > sight_range:
		return false

	# Two probes: centre of mass and head height. One is enough to spot someone
	# whose legs are behind a crate.
	for offset in [Vector2.ZERO, Vector2(0.0, -18.0)]:
		var target: Vector2 = _player.global_position + offset
		var query := PhysicsRayQueryParameters2D.create(eye, target)
		query.collision_mask = SIGHT_MASK
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		# Smoke works both ways: what hides them from you hides you from them.
		if Screen.blocks_sight(get_tree(), eye, target):
			continue
		if Smoke.blocks_sight(get_tree(), eye, target):
			continue
		return true
	return false


func _player_is_alive() -> bool:
	var alive: Variant = _player.get(&"is_alive")
	return alive if typeof(alive) == TYPE_BOOL else true


func _eye_position() -> Vector2:
	return global_position + Vector2(0.0, -size.y * 0.25)


# --- states -------------------------------------------------------------------


## Something loud happened over there - somebody hitting the ground hard, so
## far. Deliberately not a sighting: the guard walks over to look rather than
## opening fire at a noise, and goes back to his beat if nothing is there. A
## guard already in a fight is not distracted by it.
##
## Only ever called on the machine that thinks for this guard - see
## Net._fall_landed.
func heard(at: Vector2) -> void:
	if not is_brain() or _health <= 0.0 or state == State.ALERT:
		return
	_last_seen = at
	state = State.SEARCH
	_search_timer = search_time


func _enter_alert() -> void:
	if state != State.ALERT:
		_react_total = reaction_time * randf_range(
			1.0 - reaction_variance, 1.0 + reaction_variance)
		_react_timer = _react_total
		_burst_timer = 0.0
		_shooting = false
		_roll_error()
	state = State.ALERT


func _patrol(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 8.0 * delta)
		return

	if _should_turn():
		facing = -facing
		_pause_timer = patrol_pause
		velocity.x = 0.0
		return

	velocity.x = move_toward(velocity.x, walk_speed * facing, walk_speed * 6.0 * delta)


## Turns at the end of the beat, at a wall, or at the edge of a drop.
func _should_turn() -> bool:
	if absf(global_position.x - _home.x) > patrol_range and signf(global_position.x - _home.x) == signf(facing):
		return true
	if is_on_wall():
		return true
	_floor_probe.position.x = absf(_floor_probe.position.x) * facing
	_floor_probe.force_raycast_update()
	return is_on_floor() and not _floor_probe.is_colliding()


## Seeing you, then shooting you, are two separate beats with a gap between them.
##
## The gap was always there, but the guard spent it walking to his preferred
## range, so nothing about him changed at the moment he spotted you and there was
## no way to tell the pause had started. Now he stops dead and brings the gun
## round first - that is the part you are supposed to read - and only then
## resumes closing, still holding fire until the delay is out.
func _fight(delta: float) -> void:
	if _react_timer > 0.0:
		_react_timer -= delta
		if is_noticing():
			# Planted. Weight off the feet and onto the gun.
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 10.0 * delta)
		else:
			_hold_range(delta)
		return

	_hold_range(delta)

	# Alternate between squeezing off a burst and letting the gun settle.
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_shooting = not _shooting
		_burst_timer = burst_time if _shooting else burst_pause
		if _shooting:
			_roll_error()

	if weapon.get_mag() <= 0:
		weapon.reload()

	var firing := _shooting and not weapon.is_reloading()
	weapon.try_fire(_muzzle.global_position, _aim_angle, firing, firing)


## Steps toward or away from the player to sit near preferred_range, but only
## once it is meaningfully off - otherwise the guard holds still and shoots.
func _hold_range(delta: float) -> void:
	var speed := walk_speed * combat_speed_scale
	var gap := _last_seen.x - global_position.x
	var step := 0.0
	if absf(gap) > preferred_range + range_deadzone:
		step = signf(gap)
	elif absf(gap) < preferred_range - range_deadzone:
		step = -signf(gap)

	if not is_zero_approx(step) and not _should_turn_toward(step):
		velocity.x = move_toward(velocity.x, speed * step, speed * 6.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 10.0 * delta)


## Same edge/wall check as the patrol, asked about an arbitrary direction so the
## guard does not back off a ledge while fighting.
func _should_turn_toward(dir: float) -> bool:
	_floor_probe.position.x = absf(_floor_probe.position.x) * signf(dir)
	_floor_probe.force_raycast_update()
	return is_on_floor() and not _floor_probe.is_colliding()


func _search(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, walk_speed * 8.0 * delta)
	_search_timer -= delta
	if _search_timer <= 0.0:
		state = State.PATROL
		_pause_timer = patrol_pause


func _roll_error() -> void:
	_error = deg_to_rad(randf_range(-aim_error, aim_error))


## Faces the player in a fight, and the way it is walking otherwise.
func _face() -> void:
	if state == State.PATROL:
		if not is_zero_approx(velocity.x):
			facing = 1 if velocity.x > 0.0 else -1
	else:
		facing = 1 if _last_seen.x >= global_position.x else -1
	_body.scale.x = facing


# --- damage -------------------------------------------------------------------


func take_damage(amount: float, at: Vector2, direction: Vector2) -> void:
	if not _alive:
		return
	# A guard is the host's, and so is what happens to him. Only rounds that
	# count reach here in the first place, but saying it out loud means a machine
	# that is merely watching this guard can never be talked into killing its own
	# copy of him and then disagreeing with everyone else about it.
	if not is_brain():
		return

	# Same rule as the player's, and it no longer needs a branch of its own: a
	# head hit is worth double before any helmet subtracts from it, so an
	# unhelmeted guard takes 102 from a rifle round and a guard has 90. He still
	# drops to one round through the head, and now a helmet buys him a specific
	# amount of not-dropping rather than a yes.
	var hit := Damage.resolve(amount, at, global_position, size.y, weapon.inventory,
		Net.piercing)
	amount = hit.amount
	_health = maxf(_health - amount, 0.0)
	_health_fill.scale.x = _health / max_health

	# Being shot from out of nowhere still gives the position away.
	_last_seen = at + direction * 200.0
	if state == State.PATROL:
		_enter_alert()

	_spawn_damage_number(amount, at)

	var tween := create_tween()
	_visual.color = Color(1, 1, 1)
	tween.tween_property(_visual, "color", _color_for_health(), 0.16)

	# Before report_hit, not after: the mark travels to the shooter's machine,
	# and the health it is a mark for should already be on its way there too.
	_publish_state()
	Damage.report_hit(get_tree(), hit.headshot, _health <= 0.0)
	if _health <= 0.0:
		_die()


func _color_for_health() -> Color:
	return Color(0.78, 0.29, 0.32).lerp(Color(0.85, 0.5, 0.35), _health / max_health)


func _die() -> void:
	_alive = false
	# The last thing said about this guard, and it has to be said here. The line
	# below switches his physics process off, so nothing after this frame will
	# ever publish again - see _publish_state.
	_publish_state()
	velocity = Vector2.ZERO
	_drop_weapon()
	remove_from_group(&"hideable")
	visible = false
	_shape.set_deferred(&"disabled", true)
	# Dead is dead. A guard who respawns on the spot you shot him turns a
	# cleared room back into a fight and makes clearing one pointless, which is
	# exactly wrong for a raid you are trying to get out of alive.
	set_physics_process(false)


## Leaves the body where it fell with everything still on it. Nothing is
## dropped and nothing is generated: the inventory the guard was carrying is
## handed straight to the corpse, half-empty magazine and all.
##
## Through Net, because only this machine watched him spend that magazine. Every
## other machine has been showing a replica that never fired a shot, and left to
## roll its own version of his kit it would put a full rifle on the floor next to
## the host's empty one.
func _drop_weapon() -> void:
	var scene := get_tree().current_scene
	Net.drop_body(weapon.inventory,
		global_position + Vector2(0.0, size.y * 0.5 - 8.0),
		_visual.color, size,
		scene.get_path_to(self) if scene else NodePath())
	# The guard no longer owns any of it - a fresh kit is issued on respawn.
	weapon.inventory = null


func _reset() -> void:
	_alive = true
	_health = max_health
	_health_fill.scale.x = 1.0
	_visual.color = _color_for_health()
	_eye_dot.color = Color(1.0, 0.85, 0.5)
	global_position = _home
	velocity = Vector2.ZERO
	state = State.PATROL
	_pause_timer = patrol_pause
	_shape.set_deferred(&"disabled", false)
	if not is_in_group(&"hideable"):
		add_to_group(&"hideable")
	var vision := get_tree().get_first_node_in_group(&"vision_system") as VisionSystem
	visible = vision.is_seen(self) if vision else true


func _spawn_damage_number(amount: float, at: Vector2) -> void:
	if not visible:
		return

	var label := Label.new()
	label.text = str(roundi(amount))
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.93, 0.6))
	label.z_index = 10
	# Onto the overlay layer if the level has one, so the number is readable
	# instead of being tinted down with the rest of the world. See target.gd.
	var overlay := get_tree().get_first_node_in_group(&"world_overlay")
	(overlay if overlay else get_parent()).add_child(label)
	label.global_position = at + Vector2(randf_range(-8, 8), -10)

	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position",
		label.global_position + Vector2(randf_range(-14, 14), -34), 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
