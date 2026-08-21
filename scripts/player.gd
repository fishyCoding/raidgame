class_name Player
extends CharacterBody2D

## Prototype player: run, jump, and aim independently of movement.
## All input arrives through the PlayerInput autoload so touch controls can be
## swapped in without changing anything here.

@export_group("Run")
@export var max_speed := 260.0
@export var ground_accel := 2200.0
@export var ground_friction := 2600.0
@export var air_accel := 1500.0
@export var air_friction := 450.0

@export_group("Shield")
## Seconds to bring the plates up, and the same to drop them.
##
## The whole mechanic is in this number. Long enough that flicking it on as a
## round arrives does not save you - you are only protected once it is fully up -
## and short enough that switching stance mid-fight is a thing you do rather than
## a thing you commit to at the start of one.
@export var shield_raise_time := 0.3
## Top speed with the plates up, as a fraction of normal. Deliberately harsh:
## the shield is the only thing standing between you and a one-shot death, so
## the price of wearing it has to be one you feel every step.
@export_range(0.1, 1.0) var shield_speed_scale := 0.45
## And acceleration with it, so you lumber into motion rather than snapping to a
## slower top speed.
@export_range(0.1, 1.0) var shield_accel_scale := 0.55

@export_group("Jump")
## Peak height of a full-held jump, in pixels.
@export var jump_height := 100.0
## Seconds from leaving the ground to the top of the arc.
@export var jump_time_to_peak := 0.38
## Seconds from the top of the arc back to the ground (shorter = snappier).
@export var jump_time_to_fall := 0.28
@export var max_fall_speed := 1100.0
## Grace period to still jump just after walking off a ledge.
@export var coyote_time := 0.12
## Jump pressed this early before landing still fires on touchdown.
@export var jump_buffer_time := 0.12
## Releasing jump early cuts upward speed by this much (variable jump height).
@export var jump_cut := 0.45

@export_group("Aim")
## Fallback swing speed used only when no weapon is held; otherwise the
## equipped weapon's handling stat decides how fast the gun tracks.
@export var aim_smoothing := 20.0
## How far the aim swings per pixel of mouse movement. The weapon's own
## aim_speed_scale multiplies this, so a heavy gun costs more mouse travel for
## the same swing rather than lagging behind it.
@export_range(0.1, 6.0) var mouse_sensitivity := 1.6
## How fast camera shake bleeds off, pixels per second.
@export var shake_recovery := 46.0
## Ceiling on accumulated shake, so a long burst rattles hard without becoming
## unreadable. Fast guns reach it within a few rounds; single-shot weapons are
## felt as one hard jolt per trigger pull instead.
@export var max_shake := 12.0
## Shake left while fully aimed: bracing the gun steadies the picture too.
@export_range(0.0, 1.0) var ads_shake_scale := 0.65

## Rounds into a burst before holding the trigger starts costing you the picture.
## Below this a burst shakes like the sum of its rounds; past it the gun starts
## climbing away from you, which is what makes a controlled burst a decision
## rather than a formality.
@export var sustained_shake_after := 4
## Extra shake per round beyond that, as a fraction of the base jolt.
@export_range(0.0, 1.0) var sustained_shake_per_round := 0.09
## Ceiling on that growth, so a belt-fed gun becomes punishing rather than
## unplayable.
@export_range(1.0, 4.0) var sustained_shake_max := 1.6
## A gap this long resets the count - let off the trigger and the gun settles.
@export var sustained_reset_time := 0.32

@export_group("Aim down sights")
## Seconds to go from hip-fire to fully aimed (and back), before the weapon's
## own ads_speed_scale is applied.
@export var ads_time := 0.16
## Top speed while aiming, as a fraction of normal.
@export var ads_move_scale := 0.58
## How the gun tracks the cursor while aimed. Below 1 on purpose: a sight is for
## placing a shot, and a gun that snaps to wherever the mouse flicked cannot be
## placed. Aiming makes the swing heavy, which is what makes the small
## corrections possible - and what stops a twitch throwing the shot away.
@export_range(0.2, 2.0) var ads_aim_scale := 0.5
## Keeps the vision light wide enough to reach the corners of whatever the camera
## is showing. Turn it off to get the fixed-size light back.
@export var vision_fills_screen := true
## How far past the corners the light reaches, so its falloff has somewhere to
## happen instead of ending on a hard edge exactly at the screen boundary.
@export_range(1.0, 1.6) var vision_overscan := 1.12
## How far back the camera sits when you are just moving around, before aiming
## or the bow multiply it. Below 1 pulls back and shows more ground: the level is
## wide, the guards outrange what you can see, and being shot from off-screen is
## not a fight you were given a chance to lose. Everything else - ads_zoom,
## bow_zoom, the weapons' own glass - is a multiplier on top of this.
##
## 0.6 rather than 0.75 as of 2026-08-17: a quarter more world across the screen.
## Everything that should follow does, because it is all divided by this one
## number - how far the vision light throws (see _fit_vision_to_screen), how far
## the concealment raycasts bother reaching (VisionSystem._sight_reach), the
## reticle's size on screen, and how far the camera leans when you aim.
@export_range(0.4, 1.5, 0.01) var base_zoom := 0.6
## Base camera zoom while aiming, before the weapon's own ads_zoom multiplies
## it. 1.0 keeps the framing you had; the guns take it from there, and most of
## them pull back rather than push in - aiming is when you most want to see what
## you are shooting at.
@export var ads_zoom := 1.0
## And leans this far toward where you are pointing, as a fraction of the
## half-screen: 0.5 puts you halfway from the centre to the edge. Measured in
## screen space on purpose - a lean in world pixels shrinks as the zoom rises,
## which is exactly backwards, since a scope is when you most need to see ahead.
## The weapon's own ads_lead_scale multiplies it.
@export_range(0.0, 0.9) var ads_lead_fraction := 0.3
## The reticle sits further out when aimed, so the cone is easier to read.
@export var ads_reticle_scale := 1.3

@export_group("Crouch")
## Top speed while crouched, as a fraction of normal.
@export var crouch_speed_scale := 0.42
## How much of your standing height is left when crouched. Drives the collision
## box as well as the look, so crouching genuinely makes you a smaller target.
@export_range(0.4, 1.0) var crouch_height_scale := 0.68
## Seconds to drop into a crouch and to stand back up.
@export var crouch_time := 0.12

@export_group("Footsteps")
## Ground covered between footfalls, in pixels. Measured by distance rather than
## on a timer, so steps stay in step with the legs at any speed.
@export var step_distance := 46.0
## Crouched, you take shorter steps and place them quietly. This is the whole
## point of crouching: guards hear boots long before they see anyone.
@export var crouch_step_distance := 64.0
@export_range(0.0, 1.0) var crouch_step_volume := 0.25

@export_group("Ziplines")
## Ride speed lives on the cable, not here - see Zipline.speed. One cable being
## faster than another is a property of the cable.
## The hop you get for letting go, so stepping off lands you somewhere.
@export var zipline_release_hop := 220.0

@export_group("Slinging the gun")
## Seconds to get the gun out of the way when both hands are wanted for a rope.
## Short: this is the part you do not get to think about, and the cost is the
## draw at the other end, not this.
@export_range(0.05, 1.0) var stow_time := 0.16
## How far down and back the gun swings when it is slung, in degrees off
## straight down, and how much shorter it reads once it is there.
@export_range(0.0, 60.0) var stow_lean := 24.0
@export_range(0.3, 1.0) var stow_shorten := 0.68

@export_group("Shooting off the ground")
## Seconds for the cone to settle again after landing. Not instant on purpose:
## with a hard switch the way to shoot straight mid-fight would be to time the
## shot for the exact frame your boots touched, which is a worse game than
## either staying on the ground or accepting the penalty.
@export_range(0.0, 2.0) var air_settle_time := 0.4
## The shortest drop that gives you away, in pixels.
##
## A guard is 52 px tall and you are 48, so this is a shade under ten of him
## stacked up - well past a jump, well past stepping off a crate, and about
## what it costs to skip a ladder you should have used. Divide by 52 if you
## want to think about it in men rather than pixels.
@export var fall_ping_height := 510.0
## How far the landing carries. Between a footstep (900) and a gunshot (1500):
## far enough that dropping into a room is a decision, near enough that it does
## not hand the whole level your position.
@export var fall_ping_radius := 1150.0
## How long anyone who heard it can see you through the walls afterwards. Short
## on purpose - it says "he is over there, now", not "he is yours for the next
## ten seconds".
@export var fall_ping_time := 3.5

@export_group("Grapple")
## Hooks you carry. Everyone starts with these - the grapple is not kit you shop
## for, it is part of how you move, and a level built around reaching high ground
## cannot assume you decided to buy the means of getting there.
@export var grapple_charges := 1
## Seconds for one spent hook to come back. They recharge one at a time, so
## firing both means a long wait rather than two short ones.
@export var grapple_recharge := 25.0
## How hard the line reels you in, pixels per second squared.
@export var grapple_pull := 3400.0
## Ceiling on the speed it will reel you to.
@export var grapple_max_speed := 900.0
## Gravity still applies while you are on the line, at this fraction. Not zero:
## the sag is what turns a straight pull into a swing, and the swing is what you
## fling yourself out of.
@export_range(0.0, 1.0) var grapple_gravity_scale := 0.35
## Sideways control while hanging. Enough to steer the arc, not enough to fly.
@export var grapple_air_control := 900.0
## Stop reeling this close to the anchor and hang there instead. Not a release:
## the line stays on until you press the key.
@export var grapple_release_distance := 54.0
## How hard you are held still once you have arrived, pixels per second squared.
## High enough that hanging is steady rather than a wobble.
@export var grapple_hold_damping := 2600.0
## Speed added along your travel when you let go on purpose. This is the fling:
## releasing at the bottom of a swing is meant to be the fastest way to cross
## open ground in the game.
@export var grapple_fling_boost := 260.0

@export_group("Overload")
## Top speed multiplier while Overload is running.
@export var overload_speed_scale := 1.55
## Jump velocity multiplier. Height and distance both come out of this, since a
## longer hang time carries the extra speed further.
@export var overload_jump_scale := 1.3

@export_group("Recon bow")
## Seconds to pull the bow to a full draw.
@export var bow_draw_time := 0.7
## Camera zoom while the bow is merely out, and at a full draw. Below 1 pulls
## the view back: a reveal tool you cannot aim past the end of the room is no
## use, so the bow buys sight the moment it comes up and more as you pull it.
@export_range(0.3, 1.0) var bow_zoom := 0.78
@export_range(0.3, 1.0) var bow_zoom_full := 0.52
## And leans down range like a scope, scaled against the player's ads_lead.
@export var bow_lead_scale := 2.4
## Below this much draw, letting go does not loose the arrow - it is a flinch,
## not a shot, and it should not waste the ultimate.
@export_range(0.0, 1.0) var bow_min_draw := 0.18

@export_group("Looting")
## How close you have to stand to a body to go through its pockets.
@export var loot_range := 86.0
## How long the "took a rifle and 48 rounds" line stays on screen.
@export var loot_message_time := 2.6

@export_group("Insertion")
## No guard should be closer than this to where you land. Dropping into someone
## is not a stealth game, it is a coin flip.
@export var safe_insertion_distance := 900.0
## When no spawn on the map is that quiet, anywhere within this fraction of the
## quietest one is still fair game. Without it a crowded map has exactly one
## legal answer and every raid starts in the same corner. Lower means more
## variety and more risk.
@export_range(0.4, 1.0) var insertion_spread := 0.8

@export_group("Going down")
## Health runs out and you go down rather than out: on the ground, unable to
## shoot, able to crawl. A headshot without a helmet puts you here too instead of
## ending it outright.
##
## The point is that losing a fight is a situation rather than a screen. You are
## still in the raid, everything you were carrying is still on you, and getting
## out of sight is suddenly the only thing that matters.
@export var down_health := 16.0
## And it drains on its own, every second you are down. Between the two, being
## downed is a countdown rather than a state you can sit in: crawling somewhere
## has to be worth doing *now*, and a guard walking over does not have to finish
## you himself. Zero here turns the timer off and leaves only incoming fire.
@export var down_bleed_per_second := 0.8
## Top speed while crawling, as a fraction of normal. Slow enough that crawling
## out of a firefight is a gamble, not an escape.
@export_range(0.05, 0.6) var crawl_speed_scale := 0.28
## How much of your standing height is left on the ground. Lower than a crouch:
## you are flat, and a much smaller target for it.
@export_range(0.2, 0.8) var crawl_height_scale := 0.38

@export_group("Extraction")
## How many of the furthest insertion points open as exits. Two, so there is a
## choice of routes home rather than a single scripted one.
@export var extraction_count := 2

@export_group("Health")
@export var max_health := 100.0
## Seconds of immunity after being hit, so a burst cannot delete you instantly.
@export var invulnerable_time := 0.35
@export var respawn_time := 1.6

const DROP_THROUGH_TIME := 0.2
const GRENADE_SCENE := preload("res://scenes/grenade.tscn")
const RECON_BOLT_SCENE := preload("res://scenes/recon_bolt.tscn")
## How far a grenade can be placed. Past this the throw simply falls short -
## you cannot lob one across the level, and holding the key longer will not help.
const THROW_MAX_RANGE := 720.0
## Shortest and longest time a grenade spends in the air. Near throws are flat
## and quick, far ones loop - which is what makes the arc readable.
const THROW_TIME_NEAR := 0.42
const THROW_TIME_FAR := 1.15
## How far ahead the arc is simulated, in steps of a physics frame.
const ARC_STEPS := 90

## Distance out along the shot line at which recoil lifts the aim point. Aiming
## level, a kick of N degrees still rotates the aim by exactly N degrees, so this
## number does not change how strong recoil feels - only how it behaves near
## vertical. See _apply_kick().
const KICK_REFERENCE := 260.0

@onready var _aim_pivot: Node2D = $AimPivot
@onready var _arm: Polygon2D = $AimPivot/Arm
@onready var _ear: AudioListener2D = $Ear
@onready var _body: Node2D = $Body
@onready var _muzzle: Marker2D = $AimPivot/Arm/Muzzle
@onready var _camera: Camera2D = $Camera2D
@onready var _overlay: CanvasLayer = $Overlay
@onready var _vision: PointLight2D = $Vision
## The size the scene authored, kept as the floor so zooming in never shrinks the
## light below what it was designed to be.
var _vision_scale := 7.0
## Reticle and aim line live on a CanvasLayer above the world, so the darkness
## and the vision light's shadows never fall across them.
@onready var _reticle: Reticle = $Overlay/Reticle
@onready var _aim_line: AimLine = $Overlay/AimLine
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _torso: Polygon2D = $Body/Torso
@onready var weapon: Weapon = $Weapon
## By path, not as the `Audio` global - see the note in weapon.gd.
@onready var _audio: Node = get_node_or_null(^"/root/Audio")

signal health_changed(health: float, max_health: float)
## Back on your feet under your own steam, having spent a stim.
## Somebody else's recon arrow has swept over this body.
##
## Presentation only - being seen does not change what you can do about it - so
## nothing here acts on it and the HUD is the only listener. It matters because
## the reveal is otherwise entirely one-sided: the shooter watches you through a
## wall for eight seconds and the first you know of it is being shot.
signal scanned()

## Raised when a landing was heavy enough to carry. The reveal itself is Net's
## business - this is for anything local that wants to react to it.
signal landed_hard(drop: float)

signal revived()
signal died(knocked_out: bool)
## Went down but is still alive - crawling, unarmed, and one more burst from
## finished. The HUD listens for this to change what it is showing.
signal downed(from_headshot: bool)
signal extracted(from_point: SpawnPoint)

## Final aim, recoil included. Bullets and the reticle both use this.
var aim_angle := 0.0
var aim_direction := Vector2.RIGHT
var facing := 1

## 0 hip-fire, 1 fully aimed down sights. Ramps with ads_time.
var focus := 0.0
## 0 standing, 1 fully crouched.
var crouch := 0.0
## Whether the plates are *wanted* up. This is the toggle, and it is the only
## part of the shield that travels.
##
## Replicated rather than the animation below it, unlike `crouch` which sends
## the animated value. Two reasons: it is one bit against a float stream, and a
## dropped packet mid-transition would leave somebody else's outline stuck
## halfway up, where a dropped bool simply arrives a moment later and the ramp
## catches up on its own.
var armored := false
## 0 plates down, 1 plates up. Derived on every machine from `armored`, never
## sent - see _update_shield.
var shield := 0.0
## Which insertion point the host put this body at, or -1 to work it out here.
## Set by Net before the character enters the tree.
var insertion_index := -1
## The outline the vision system tests for cover against, kept in step with the
## collision box as it crouches and crawls. Deliberately the same property name
## the guards publish, so one piece of code conceals both - and going flat makes
## you genuinely harder to see, not merely harder to hit.
var size := Vector2(28.0, 48.0)

var health := 0.0
var is_alive := true
## On the ground but not finished. Still alive, still carrying everything, but
## the gun is out of the question and the only move left is to crawl.
var is_downed := false
## How much more damage there is in you while down. Runs on its own rather than
## on health, so the bar the HUD shows while down is a different thing entirely.
var down_health_left := 0.0
## The body currently in reach, for the HUD to prompt with. Null when there is
## nothing within arm's length.
var loot_target: Lootable = null
## The body this player has open. Held so that closing the screen - or dying, or
## walking off - hands it back to whoever else wants to search it.
var _searching: Lootable = null
## A body we have asked the host for and not yet heard about. Opening one is a
## round trip now, so a second press while the first is in flight must not send a
## second request, and an answer that never arrives must not wedge the key.
var _asking: Lootable = null
var _asking_left := 0.0
## Something moved on or off the body we are going through, and the host has not
## been told yet. Flushed once a frame rather than on the signal itself: a single
## drag fires `changed` on both inventories several times over, and the host only
## needs the answer, not the working.
var _search_dirty := false
## How long to wait for the host's answer before giving up on it.
const SEARCH_ANSWER_TIME := 1.5
## Everything the player is carrying. The weapon node reads from this.
var inventory: Inventory
## What was on you when you died, as text. Kept because the body takes the kit
## itself the instant you fall and the screen that reports the loss is drawn
## afterwards - see _leave_the_kit_behind.
var lost_kit := ""
## How far down to look for ground on a replica. A few pixels: enough to catch
## the floor under a standing body, not enough to catch one mid-fall.
const GROUND_PROBE := 4.0
## Set when something is looted, for the HUD to report. Counts down on its own.
var loot_message := ""
var loot_message_left := 0.0
## True while the inventory screen is up.
var inventory_open := false
## Whether the last hit taken was to the head, for the death screen to report.
var last_hit_headshot := false
## The cable currently being ridden, or null. While riding, gravity and running
## are suspended and the body is pinned to the line.
var zipline: Zipline = null
## Replicated, because a copy of you on somebody else's machine has no idea you
## are hanging off a cable - the rope sound was driven from _update_zipline,
## which only ever runs on the machine doing the riding, so nobody else heard it.
## A bool rather than the cable itself: which rope it is does not travel, and the
## position already does.
var riding := false
## Where a replica was last frame, to tell a rider who is moving from one who is
## hanging still. A rider's velocity is pinned to zero, so it cannot be read off
## that the way a walk can.
var _ride_last := Vector2.INF
## Which throwable slot is being wound up, or -1 for none.
var throw_slot := -1
## How far it is wound up, 0 to 1.
var throw_charge := 0.0
## True while the bow is in your hands instead of a gun.
var bow_out := false
## How far it is drawn, 0 to 1.
var bow_drawn := 0.0
## The exit currently being stood in, and how far through the hold it is.
var extracting: SpawnPoint = null
var extracted_out := false
## This player's way home, chosen from where it came in. Per-player, because two
## people inserted at opposite ends have opposite exits.
var _exits: Array[SpawnPoint] = []
## Seconds this player has stood in one of them.
var _extract_held := 0.0
## Seconds of Overload left. It is a movement ultimate: while it runs you are
## faster and you jump further. The gun is untouched - spending it is about
## crossing ground you could not otherwise cross, or leaving somewhere fast.
var overload_left := 0.0

## Where the player is pointing before recoil is added.
var _aim_base := 0.0
## Where the scope's wander has got to. Only advanced while aimed, so lowering
## the gun and bringing it back up does not resume mid-swing.
var _sway_phase := 0.0

## Both hands busy - on a cable, or on the hook. Replicated, because a character
## seen with his gun up while hanging off a rope is a lie the other player will
## act on, and this is the one bit of it the other machine cannot work out for
## itself.
var stowed := false
## How far the gun is out of the way: 0 up and ready, 1 slung. Not replicated -
## it is a sixth of a second of ramp either way, and every machine can run it off
## `stowed` more cheaply than it could be sent.
var stow := 0.0
## Where the gun is actually pointing, once the sling has had its say. The aim
## angle while the gun is up; swung down with it while it is not. The reticle
## rides this rather than the aim, so the crosshair follows the muzzle down and
## comes back up with it.
var gun_angle := 0.0
## 1 with both feet off the ground. Eased rather than switched - see
## _get_air_factor().
var _air_spread := 0.0
var _jump_velocity: float
var _jump_gravity: float
var _fall_gravity: float
var _coyote_timer := 0.0
var _buffer_timer := 0.0
var _drop_timer := 0.0
var _jumping := false
var _shake := 0.0
## Rounds in the burst being fired right now, and how long is left before a lull
## counts as the end of it. See _sustained_scale.
var _burst_rounds := 0
var _burst_gap := 0.0
## Hooks left right now, and how far along the next one is coming back.
var grapple_left := 0
var _grapple_recharge_timer := 0.0
## The hook in the air or biting into something, and where it bit.
var _hook: GrappleHook = null
var _grapple_anchor := Vector2.INF
## How much of your steering authority is left once you are hanging still at the
## anchor. Some, so you can shuffle along a ledge, not enough to swim about.
const GRAPPLE_HOLD_CONTROL := 0.45

## Radius the aim crosshair orbits at. Only the direction is used; the radius is
## fixed so mouse movement always turns into rotation and never saturates at the
## edge of some box.
const AIM_ORBIT := 220.0
## Where the crosshair currently sits relative to you.
var _aim_reach := Vector2(AIM_ORBIT, 0.0)
var _spawn := Vector2.ZERO
var _invulnerable := 0.0
var _reticle_radius := 0.0
var _base_zoom := Vector2.ONE
var _step_travel := 0.0
var _was_on_floor := true
## The highest point since your boots left the ground, as a Y - so the smallest
## number is the top of the arc. What the drop is measured from.
var _fall_apex := 0.0
## Last frame's height, only so a teleport can be told from a fall.
var _fall_last_y := 0.0
## Set when the cable check reads the interact key but does not take it, so the
## loot check can act on the same press instead of it being swallowed.
var _interact_spent := false
var _stand_height := 48.0
var _stand_pivot_y := -6.0


func _ready() -> void:
	_recalculate_jump()
	# The weapon node builds the starting kit (a sidearm and rounds for it) if
	# nobody hands it one, so the player simply adopts what it made.
	inventory = weapon.inventory
	weapon.shot_fired.connect(_on_shot_fired)
	_reticle_radius = _reticle.radius
	_base_zoom = Vector2(base_zoom, base_zoom)
	# The collision shape is shared between instances unless made local, and
	# crouching writes to it - so take a copy and remember the standing size.
	_shape.shape = _shape.shape.duplicate()
	_stand_height = (_shape.shape as RectangleShape2D).size.y
	_stand_pivot_y = _aim_pivot.position.y
	if _vision:
		_vision_scale = _vision.texture_scale
	grapple_left = grapple_charges

	Net.note_player(self)
	# One camera, one set of crosshairs and one light per machine. Every character
	# carries all three, because a character does not know whose it is until it is
	# in the tree - so they are switched off on arrival for everyone but their
	# owner.
	var mine := is_local()
	_camera.enabled = mine
	if mine:
		_camera.make_current()
		# Sound is panned from the listener, and without one that is the camera -
		# which leans down range while you aim, by most of a half-screen with the
		# scope's ads_lead_scale on it. That put a shot fired at your own feet out
		# to one side while scoped. The ear belongs on the head.
		_ear.make_current()
	_overlay.visible = mine
	# The lamp especially. It is a shadow-casting light, and a second one walking
	# about the level throws a second set of shadows off every wall from a place
	# you are not standing - so the darkness stops meaning "what I can see" and
	# starts meaning "what either of us can see", which is the one thing this
	# light exists to say. Seeing where somebody else's torch is pointing from
	# across the map would also be a fine way to find them.
	if _vision:
		_vision.enabled = mine

	# Other people obey the same cover rules the guards do. Drawn through walls,
	# another player is a permanent free answer to the only question this level
	# asks - is there anybody in that room - and every wall, catwalk and container
	# on the map stops meaning anything the moment there are two of you.
	#
	# Never your own body: hiding yourself from yourself is the one thing this
	# group must not do, and you always have line of sight on where you are.
	if not mine and not is_in_group(&"hideable"):
		add_to_group(&"hideable")

	# Where you come in is the host's decision: two players rolling their own
	# spawn independently would each pick from a different idea of where the
	# guards are, and the extractions they opened would not agree either. In a
	# match the host has already picked, and sent the index with the spawn, so
	# every machine puts this body in the same place on the frame it appears.
	if insertion_index >= 0:
		_choose_insertion(insertion_index)
	elif Net.is_host:
		_choose_insertion()
	_spawn = global_position
	health = max_health
	health_changed.emit(health, max_health)


func _exit_tree() -> void:
	Net.forget_player(self)


## Hands this character a kit that was filled in before it existed.
##
## In a match you shop during the countdown, which is minutes before there is a
## body to put anything on - so the shop fills an inventory of its own and it is
## handed over here, replacing the default sidearm outright (the shop's kit was
## built from the same starting kit, so nothing is lost by doing so).
func give_kit(kit: Inventory) -> void:
	if kit == null:
		return
	weapon.set_inventory(kit)
	inventory = weapon.inventory


## Rolls where this raid starts, and opens the exits furthest from it.
##
## Extractions are simply the insertion points on the other side of the ring, so
## every raid is a crossing: you land somewhere, and home is as far away as the
## map allows.
func _choose_insertion(index := -1) -> void:
	var points: Array = get_tree().get_nodes_in_group(&"spawn")
	if points.is_empty():
		return
	# Same order on every machine, or an index handed out by the host means a
	# different corner of the map on each of them.
	points.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)

	var start: SpawnPoint = points[index] if index >= 0 and index < points.size() \
		else _quietest_insertion(points)
	global_position = start.global_position + Vector2(0.0, -20.0)

	var others: Array = []
	for node in points:
		var point := node as SpawnPoint
		if point == null or point == start:
			continue
		others.append(point)

	others.sort_custom(func(a: SpawnPoint, b: SpawnPoint) -> bool:
		return a.global_position.distance_squared_to(start.global_position) \
			> b.global_position.distance_squared_to(start.global_position))

	# Kept here rather than flagged on the points themselves. There is one set of
	# spawn points and several players standing at different corners of them, so
	# a flag on the node is a flag the next player to spawn overwrites - and the
	# point furthest from them is exactly where somebody else is standing.
	_exits.clear()
	for i in mini(extraction_count, others.size()):
		_exits.append(others[i] as SpawnPoint)
	_show_exits()


## Marks up the rings on the ground and the briefing map - but only for the
## person at this screen. A remote body doing this would redraw the level with
## somebody else's way home on it.
func _show_exits() -> void:
	if not is_local():
		return
	for node in get_tree().get_nodes_in_group(&"spawn"):
		var point := node as SpawnPoint
		if point:
			point.is_extraction = _exits.has(point)


## Picks where to come in: at random among the points quiet enough to land at,
## never one with a guard on top of it.
##
## Rolled from every acceptable point rather than by taking the first one that
## clears the bar. Taking the first meant that on a map where exactly one spawn
## was quiet enough, that spawn won every single raid - and the old fallback
## (the single furthest-from-trouble point) was deterministic too, so a map where
## none of them cleared the bar also started in the same place every time. Either
## way the shuffle above it did nothing.
func _quietest_insertion(points: Array) -> SpawnPoint:
	var guards := get_tree().get_nodes_in_group(&"hideable")
	var clearances := {}
	var quietest := 0.0

	for node in points:
		var point := node as SpawnPoint
		if point == null:
			continue
		var clearance := INF
		for guard in guards:
			var body := guard as Node2D
			if body:
				clearance = minf(clearance, point.global_position.distance_to(body.global_position))
		clearances[point] = clearance
		quietest = maxf(quietest, clearance)

	if clearances.is_empty():
		return null

	# The bar is the lower of "far enough from anyone" and "nearly as quiet as the
	# best there is". Taking the lower of the two on purpose: an absolute
	# threshold alone decides nothing on a map where one spawn happens to clear it
	# and the rest sit just under - which is the same single answer every raid,
	# only arrived at more slowly. Relative to the quietest point there is always
	# a field to choose from, and the absolute distance still rules out the ones
	# that are genuinely dangerous.
	var bar := minf(safe_insertion_distance, quietest * insertion_spread)

	var candidates: Array[SpawnPoint] = []
	for point in clearances:
		if clearances[point] >= bar:
			candidates.append(point)
	return candidates[randi() % candidates.size()]


## Standing in a live exit long enough ends the raid - with everything you are
## carrying, which is the only way to keep any of it.
func _update_extraction(delta: float) -> void:
	if extracted_out or not is_alive:
		return

	# Only this player's own exits, and only this player's own clock. Both used
	# to live on the spawn point, where two people could fill one countdown
	# between them and either could be standing in the other's doorway.
	extracting = null
	for point in _exits:
		if is_instance_valid(point) and point.in_range(global_position):
			extracting = point
			break

	if extracting:
		_extract_held += delta
	else:
		# Stepping out drains twice as fast as standing in it fills.
		_extract_held = maxf(_extract_held - delta * 2.0, 0.0)

	if is_local():
		for point in _exits:
			if is_instance_valid(point):
				point.show_hold(_extract_held if point == extracting else 0.0)

	if extracting and _extract_held >= extracting.hold_time:
		extracted_out = true
		extracted.emit(extracting)


## Derived from the designer-friendly height/time values above, so tuning the
## arc never means guessing at a gravity number.
func _recalculate_jump() -> void:
	_jump_velocity = -2.0 * jump_height / jump_time_to_peak
	_jump_gravity = 2.0 * jump_height / (jump_time_to_peak * jump_time_to_peak)
	_fall_gravity = 2.0 * jump_height / (jump_time_to_fall * jump_time_to_fall)


## True on the machine driving this character. Everyone else is watching a
## replica: its position, aim and state arrive over the wire, and simulating it
## locally would only fight what the synchroniser is writing.
func _enter_tree() -> void:
	# Whose character this is, taken from the node's name - see Net.spawn_player
	# for why it has to be done here and not anywhere later.
	var owner_id := str(name).to_int()
	if owner_id > 0:
		set_multiplayer_authority(owner_id)


## The middle of this body in world space, for anything working out whether it
## can be seen. Not the node origin: the collision box shrinks from the top when
## you crouch, so the origin ends up near your feet and rays aimed around it would
## be testing the air above your head. See VisionSystem._sample_points.
func sight_centre() -> Vector2:
	return global_position + _shape.position


func is_local() -> bool:
	# Playing alone there is no peer to ask, and asking anyway is an error -
	# so the answer is simply yes, everything here is yours.
	return not Net.is_networked() or is_multiplayer_authority()


func _physics_process(delta: float) -> void:
	if not is_local():
		_update_replica(delta)
		return
	if not is_alive:
		return
	_update_timers(delta)
	weapon.tick(delta)
	if _update_zipline(delta):
		# Riding is a whole movement mode: no running, no gravity, no jumping -
		# and deliberately no move_and_slide either. The rider's position is set
		# straight onto the cable, and sliding would fight it: floor snapping
		# pulls you back down onto whatever you launched from, and the cables run
		# past floors that would otherwise stop you halfway up.
		_update_shield(delta)
		_update_aim(delta)
		_update_stow(delta)
		_update_weapon()
		_update_reticle()
		_update_shake(delta)
		return
	_update_grapple(delta)
	_update_extraction(delta)
	_update_shield(delta)
	_update_crouch(delta)
	_update_loot(delta)
	_update_inventory_keys()
	_update_aim(delta)
	_update_stow(delta)
	# On the line, _reel_in owns the velocity: running would fight the pull with
	# ground friction, and the jump step applies its own full gravity on top of
	# the scaled sag that makes the swing. Steering is handled in _reel_in, so
	# you can still move - it just goes through the rope.
	if not is_grappling():
		_update_run(delta)

	if is_downed:
		_bleed_out(delta)
		# The one thing still available on the floor. Same key as a medkit,
		# because down is the only state in which a medkit is not the answer.
		if PlayerInput.is_heal_just_pressed():
			_use_revive()
	# On the floor there is no gun, no jump, no ultimate and no aiming down
	# sights - only crawling. Everything skipped here is deliberate: being down
	# has to take the fight away from you, or it is just a slower walk.
	if not is_downed:
		_charge_ultimate(delta)
		_update_focus(delta)
		if not is_grappling():
			_update_jump(delta)
		_update_weapon()
	_update_reticle()
	_update_shake(delta)
	move_and_slide()
	_update_footsteps(delta)


## Somebody else's character, seen from here. Position, aim and stance arrive
## replicated; everything derived from them is rebuilt locally so the body reads
## right without any of it going over the wire.
func _update_replica(delta: float) -> void:
	_apply_stance()
	_aim_pivot.rotation = aim_angle
	_aim_pivot.scale.y = facing
	_body.scale.x = facing
	# Their gun goes away too. `stowed` came over the wire; the ramp off it is
	# run here rather than sent.
	_update_stow(delta)
	# Their plates, the same way: `armored` came over the wire, the ramp is local.
	_ramp_shield(delta)
	# Their rope. Riding pins velocity to zero and moves the body by position, so
	# "are they actually travelling" has to come from the position itself.
	if riding:
		var moving := _ride_last.is_finite() 			and _ride_last.distance_to(global_position) > 0.5
		_ride_last = global_position
		if _audio:
			_audio.zipline(global_position, moving, get_instance_id())
	elif _ride_last.is_finite():
		_ride_last = Vector2.INF
		if _audio:
			_audio.zipline_stopped(get_instance_id())

	# Their boots, from their replicated velocity - so you hear other players
	# moving through exactly the same footstep path as guards.
	if is_alive and not is_downed:
		_step_travel += absf(velocity.x) * delta
		if _step_travel >= step_distance:
			_step_travel = 0.0
			# Tested here rather than gating the accumulation, so it costs one
			# shape check per step taken instead of one per frame.
			if _audio and _replica_grounded():
				# A person, not a patrol. Same recording, its own pitch, and a
				# few dB up - somebody who can shoot back is worth hearing over
				# eleven men who are only walking.
				_audio.player_footstep(global_position)


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


func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
		_jumping = false
		_air_spread = move_toward(_air_spread, 0.0, delta / maxf(air_settle_time, 0.01))
	else:
		_coyote_timer -= delta
		# Straight to full the moment your boots leave: the cost of jumping into
		# a fight has to land while you are in the air, not a beat later.
		_air_spread = 1.0

	_buffer_timer -= delta
	_invulnerable = maxf(_invulnerable - delta, 0.0)

	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			set_collision_mask_value(Layers.ONE_WAY_BIT, true)


## Crouching: slower, quieter, and a physically smaller target. The collision
## box shrinks from the top so your feet stay where they were.
## The toggle, and the ramp it drives.
##
## Split the way the crouch is: this half reads the button and only ever runs on
## the machine holding it, `_ramp_shield` runs everywhere and turns whatever
## `armored` currently says into the animation. A replica gets the second half
## and never pretends to read a key.
func _update_shield(delta: float) -> void:
	if PlayerInput.is_shield_just_pressed() and not is_downed:
		armored = not armored
	# Nothing to put the plates up for, and nothing holding them there.
	if is_downed or not is_alive:
		armored = false
	_ramp_shield(delta)


func _ramp_shield(delta: float) -> void:
	var wanted := 1.0 if armored else 0.0
	shield = move_toward(shield, wanted, delta / maxf(shield_raise_time, 0.001))


## True only with the plates all the way up.
##
## The transition protects you from nothing, in either direction, and that is
## deliberate: it is the entire cost of the toggle. Being able to tap the button
## as a round arrives would make the shield free, and being covered on the way
## back down would make dropping it free.
func is_shielded() -> bool:
	return shield >= 1.0


func _update_crouch(delta: float) -> void:
	# Down is not a posture you can stand up out of, so the input is ignored and
	# the crouch is pinned at full.
	var wanted := 1.0 if (PlayerInput.is_crouch_held() and is_on_floor()) else 0.0
	if is_downed:
		wanted = 1.0
	crouch = move_toward(crouch, wanted, delta / maxf(crouch_time, 0.001))
	_apply_stance()


## Turns however crouched you are into a collision box and a posture. Split from
## the input above so a replicated character can apply the crouch that arrived
## over the wire without pretending to read a crouch key.
func _apply_stance() -> void:
	# Flatter on the floor than in a crouch: a crawling target is a small one,
	# which is most of what makes crawling for cover worth trying.
	var low := crawl_height_scale if is_downed else crouch_height_scale
	var height := lerpf(_stand_height, _stand_height * low, crouch)
	var shape := _shape.shape as RectangleShape2D
	shape.size.y = height
	_shape.position.y = (_stand_height - height) * 0.5
	# What anyone looking for you has to find. Tracks the box rather than being
	# set alongside it, so a stance that makes you smaller cannot forget to.
	size = Vector2(shape.size.x, height)

	# The body squashes and the gun comes down with it.
	_body.scale.y = lerpf(1.0, low, crouch)
	_body.position.y = (_stand_height - height) * 0.5
	_aim_pivot.position.y = _stand_pivot_y + (_stand_height - height) * 0.5


# --- grapple -----------------------------------------------------------------


func is_grappling() -> bool:
	return _grapple_anchor.is_finite()


## Seconds until the next hook is back, or 0 when you are already full.
func grapple_recharge_left() -> float:
	if grapple_left >= grapple_charges:
		return 0.0
	return _grapple_recharge_timer


## Fires, holds, and lets go. One key does all three: pressed with nothing out it
## shoots, pressed again it lets go - which matters because letting go at the
## right moment is the skill in it, and that has to be one button under your
## thumb rather than something you go looking for.
func _update_grapple(delta: float) -> void:
	# Spent hooks come back one at a time.
	if grapple_left < grapple_charges:
		_grapple_recharge_timer -= delta
		if _grapple_recharge_timer <= 0.0:
			grapple_left += 1
			_grapple_recharge_timer = grapple_recharge if grapple_left < grapple_charges else 0.0

	if is_downed or not is_alive:
		if _hook:
			_let_go_of_grapple(false)
		return

	# Jump lets go too. Hanging off a line, "jump" is what your hands reach for
	# when you want to be off it, and making people learn a second key for the
	# same instinct is how a mechanic ends up unused.
	var wants_off := PlayerInput.is_grapple_just_pressed() \
		or (is_grappling() and PlayerInput.is_jump_just_pressed())
	if wants_off:
		if _hook:
			# Deliberate release: this is the fling.
			_let_go_of_grapple(true)
		elif grapple_left > 0:
			_fire_grapple()
		else:
			_say_loot("no hooks - %.0fs" % ceilf(_grapple_recharge_timer))

	if is_grappling():
		_reel_in(delta)


func _fire_grapple() -> void:
	grapple_left -= 1
	if _grapple_recharge_timer <= 0.0:
		_grapple_recharge_timer = grapple_recharge

	# Thrown through Net, which puts the same hook in the same hand on every
	# machine and hands this one back. Built here it was a line only the thrower
	# could see - see Net.fire_grapple.
	var hook := Net.fire_grapple(_muzzle.global_position, aim_direction, Net.peer_id())
	if hook == null:
		return
	hook.attached.connect(_on_grapple_attached)
	hook.missed.connect(_on_grapple_missed)
	_hook = hook
	if _audio:
		_audio.dry_fire(_muzzle.global_position)


func _on_grapple_attached(anchor: Vector2) -> void:
	_grapple_anchor = anchor
	# Whatever you were doing on the ground, you are on the line now.
	_jumping = false
	# Everyone else's copy of this hook is a frame or so behind and about to bite
	# slightly further along the same wall. This is the point it really caught.
	Net.grapple_news(anchor)
	if _audio:
		_audio.reload_finished(global_position)


func _on_grapple_missed() -> void:
	_grapple_anchor = Vector2.INF
	_hook = null


## Being reeled in. A velocity pull rather than a position lerp, so the speed you
## build is real speed: it is still in you when the line comes off, which is what
## makes flinging yourself out of a swing work at all.
func _reel_in(delta: float) -> void:
	var to_anchor := _grapple_anchor - global_position
	var distance := to_anchor.length()

	# Arrived. You hold on rather than being dropped: hanging off the anchor is a
	# position worth being in - under a ledge, above a patrol, off the floor - and
	# it lasts until you decide to let go. The line used to detach itself the
	# moment you got here, which turned every grapple into a fixed arc you had no
	# say in.
	if distance <= grapple_release_distance:
		velocity = velocity.move_toward(Vector2.ZERO, grapple_hold_damping * delta)
		# Still steerable, gently, so you can shift along the surface you are on.
		var shift := PlayerInput.get_move_axis()
		if not is_zero_approx(shift):
			velocity.x += shift * grapple_air_control * GRAPPLE_HOLD_CONTROL * delta
		return

	var along := to_anchor / distance
	velocity += along * grapple_pull * delta
	# Steering, not flying: enough to swing wide of a corner or tuck in close.
	var steer := PlayerInput.get_move_axis()
	if not is_zero_approx(steer):
		velocity.x += steer * grapple_air_control * delta
	# The sag that makes it a swing instead of a winch. Uses the fall gravity
	# rather than the jump one: you are not jumping, you are hanging.
	velocity.y += _fall_gravity * grapple_gravity_scale * delta
	velocity = velocity.limit_length(grapple_max_speed)


## `flung` is true when you chose to let go, false when the line ran out or you
## arrived. Choosing to release pays a little extra speed along your travel -
## timing the release is the whole technique, and it should be worth something.
func _let_go_of_grapple(flung: bool) -> void:
	if _hook:
		_hook.release()
		_hook = null
		# The line comes off everywhere, or it is left hanging out of thin air on
		# every screen but this one. INF means "off" - see Net.grapple_news.
		Net.grapple_news(Vector2.INF)
	if flung and _grapple_anchor.is_finite() and velocity.length() > 40.0:
		velocity += velocity.normalized() * grapple_fling_boost
	_grapple_anchor = Vector2.INF


## Riding a cable. Returns true while attached, which takes over movement.
##
## Grabbing is on the same key as looting, and a body in reach wins: you are far
## more often standing over someone you shot than under a cable, and losing the
## loot prompt to a mis-grab would be worse than the reverse.
func _update_zipline(delta: float) -> bool:
	if zipline:
		if not is_alive:
			_leave_zipline(false)
			return false
		# Let go with the same key you grabbed with. Jump used to do it, which was
		# unusable: pressing SPACE to climb registered as a press on the first frame
		# and dropped you off before you had moved an inch.
		if PlayerInput.is_interact_just_pressed():
			_leave_zipline(true)
			return false

		var ride := 0.0
		if PlayerInput.is_jump_held():
			ride -= 1.0
		if PlayerInput.is_down_held():
			ride += 1.0

		velocity = Vector2.ZERO
		# Along the cable, not straight down. Stepping vertically and snapping back
		# to the line loses the horizontal part of the step, so a diagonal cable
		# used to ride slower the flatter it got - and a level one not at all.
		var travel := ride * zipline.speed * delta
		var wanted := global_position - zipline.direction() * travel
		var pinned := zipline.clamp_to_cable(wanted)

		# Riding into either end steps you off there rather than parking you on the
		# last inch of cable. Going down at the bottom drops you onto the floor with
		# no hop; going up at the top lifts you onto whatever the cable is bolted to.
		if ride > 0.0 and pinned.distance_to(zipline.world_bottom()) < 1.0:
			global_position = pinned
			_leave_zipline(false)
			return false
		if ride < 0.0 and pinned.distance_to(zipline.world_top()) < 1.0:
			global_position = pinned
			_leave_zipline(true)
			return false

		global_position = pinned
		# The ride has its own continuous sound now, rather than borrowing the
		# footstep every so often - you are hanging off a rope, not walking. It
		# stops while you hang still, so idling on a cable is silent.
		if _audio:
			_audio.zipline(global_position, not is_zero_approx(ride), get_instance_id())
		return true

	# You cannot pull yourself up a rope from the floor.
	if is_downed:
		return false

	if PlayerInput.is_interact_just_pressed():
		# A body and a cable can both be in reach. F used to always mean the body,
		# which made any cable next to a corpse unusable - so whichever is
		# actually nearer wins, and the loot path is told the press was spent.
		var cable := Zipline.nearest(get_tree(), global_position)
		if cable and loot_target:
			var to_body := global_position.distance_to(loot_target.global_position)
			var to_cable := global_position.distance_to(cable.closest_point(global_position))
			if to_body < to_cable:
				cable = null
		if cable:
			zipline = cable
			riding = true
			global_position = cable.clamp_to_cable(global_position)
			velocity = Vector2.ZERO
			_say_loot("on the cable - UP and DOWN to ride, LET GO to step off"
				if PlayerInput.is_touch()
				else "on the cable - W up, S down, F to let go")
			return true
		_interact_spent = true
	return false


## Stepping off. The hop is for letting go mid-cable or at the top, where you
## want to land on something; dropping off the bottom should just be a drop.
func _leave_zipline(hop := true) -> void:
	zipline = null
	riding = false
	# However far down the cable brought you, the fall starts here.
	_fall_apex = global_position.y
	_fall_last_y = global_position.y
	velocity.y = -zipline_release_hop if hop else 0.0
	if _audio:
		_audio.zipline_stopped(get_instance_id())


## Going through a body: F opens the two-sided screen with his kit on one side
## and yours on the other. Taking things is a matter of dragging them across,
## which is the whole point of a grid - what fits is a decision, not a formality.
func _update_loot(delta: float) -> void:
	loot_message_left = maxf(loot_message_left - delta, 0.0)
	loot_target = _nearest_body()

	# A request that never came back must not leave the key dead forever.
	_asking_left = maxf(_asking_left - delta, 0.0)
	if _asking_left <= 0.0:
		_asking = null

	# Walked away from what you were going through. Left open, the body stays
	# claimed on the host and nobody - including you - can ever search it again.
	if _searching and (not is_instance_valid(_searching)
			or global_position.distance_to(_searching.global_position) > loot_range * 1.5):
		_close_screen()

	# Keep the host level with what is actually left on the body, so that losing
	# this machine mid-search does not leave a copy of everything already taken
	# lying on the floor for the next person. See Net.searching_progress.
	if _search_dirty:
		_search_dirty = false
		if _searching and is_instance_valid(_searching) and _searching.inventory:
			Net.searching_progress(_body_path(_searching), _searching.inventory.to_wire())

	# The cable check runs first each frame and reads the same key. If it took
	# the press - or spent it deciding the body was nearer - this must not act on
	# it a second time.
	var pressed := PlayerInput.is_interact_just_pressed() or _interact_spent
	_interact_spent = false
	if zipline != null or not pressed:
		return
	if inventory_open:
		_close_screen()
	elif loot_target:
		_begin_search(loot_target)


## Kneeling over somebody is exclusive, so this asks rather than opens. The host
## hands a body to one searcher at a time - see Net.ask_to_search - and the answer
## arrives at on_body_answer a round trip later.
func _begin_search(body: Lootable) -> void:
	if _asking != null or body == null:
		return
	_asking = body
	_asking_left = SEARCH_ANSWER_TIME
	Net.ask_to_search(_body_path(body))


## The host's answer. `holder` is the peer now going through it: us, or whoever
## got their hands on it first.
func on_body_answer(path: NodePath, holder: int) -> void:
	var body := _asking
	_asking = null
	_asking_left = 0.0
	if body == null or not is_instance_valid(body) or _body_path(body) != path:
		return
	if holder != Net.peer_id():
		_say_loot("someone else is going through that body")
		return
	_searching = body
	if body.inventory and not body.inventory.changed.is_connected(_body_emptied):
		body.inventory.changed.connect(_body_emptied)
	_open_screen(body.inventory, "BODY")


## Something came off - or went back on - the body we are kneeling over.
func _body_emptied() -> void:
	_search_dirty = true


## Hands a searched body back, along with what is left on it. Sent from here
## rather than worked out by the host because this machine is the only one that
## knows what was taken - it is the one that did the taking.
func _release_body() -> void:
	if _searching == null:
		return
	var body := _searching
	_searching = null
	# The final word on this body is the one below, so the running commentary
	# stops here - not least because the host is about to hand the body to
	# somebody else and will refuse anything more from us anyway.
	_search_dirty = false
	if is_instance_valid(body) and body.inventory:
		if body.inventory.changed.is_connected(_body_emptied):
			body.inventory.changed.disconnect(_body_emptied)
		Net.done_searching(_body_path(body), body.inventory.to_wire())


## A body's name for the wire: relative to the level, so it means the same thing
## on every machine. See Net._make_body, which lays them out to match.
func _body_path(body: Node) -> NodePath:
	var scene := get_tree().current_scene
	return scene.get_path_to(body) if scene else NodePath()


func _say_loot(text: String) -> void:
	loot_message = text
	loot_message_left = loot_message_time


func _open_screen(other: Inventory, title: String) -> void:
	inventory_open = true
	var ui := _find_screen()
	if ui:
		ui.open(inventory, other, title)


func _close_screen() -> void:
	inventory_open = false
	var ui := _find_screen()
	if ui:
		ui.close()
	# After the screen, not before: closing it puts a half-dragged item back on
	# whichever side it came from, and that has to have happened before the body
	# is described to everybody else.
	_release_body()
	# What you were holding may have been dragged out, swapped, or replaced with
	# something off a body while the screen was up, so the gun is re-read rather
	# than trusted.
	weapon.refresh()


func _find_screen() -> Node:
	return get_tree().get_first_node_in_group(&"inventory_ui")


func _nearest_body() -> Lootable:
	var best: Lootable = null
	var best_distance := loot_range * loot_range
	for node in get_tree().get_nodes_in_group(&"lootable"):
		var body := node as Lootable
		if body == null or not is_instance_valid(body) or not body.has_loot():
			continue
		var distance := global_position.distance_squared_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = body
	return best


## Weapon handling that is about the kit rather than the shooting: swapping
## hands, pulling a gun out of the bags, and opening the inventory screen.
func _update_inventory_keys() -> void:
	if Input.is_action_just_pressed(&"map"):
		var map := get_tree().get_first_node_in_group(&"map_screen")
		if map:
			map.toggle()

	if PlayerInput.is_inventory_just_pressed():
		if inventory_open:
			_close_screen()
		else:
			_open_screen(null, "")

	var requested := PlayerInput.get_weapon_slot()
	if requested < 0:
		return
	# Only the two hands are on hotkeys. A gun in a bag is cargo: to shoot it you
	# have to open the inventory and put it in a hand, which takes time you may
	# not have. Swapping weapons is meant to be a decision, not a keypress.
	if requested <= Inventory.Slot.SECONDARY:
		weapon.equip(requested)
	else:
		_say_loot("that gun is in your bag - TAB to move it to a hand")


## Holding the aim button walks `focus` up to 1: a tighter cone (weapon.gd), a
## slower walk, a steadier swing, and a camera that leans toward the shot.
func _update_focus(delta: float) -> void:
	var wanted := 1.0 if (PlayerInput.is_aim_held() and not inventory_open
		and not bow_out) else 0.0
	var ramp := ads_time * (weapon.data.ads_speed_scale if weapon.data else 1.0)
	focus = move_toward(focus, wanted, delta / maxf(ramp, 0.001))
	weapon.focus = focus


## Total magnification right now: the player's own ADS push-in, multiplied by
## whatever glass the current gun has on it. Can land below 1.0 - a long-range
## scope pulls the view back rather than pushing it in.
func get_zoom_factor() -> float:
	if bow_out:
		# The bow overrides the gun's own glass entirely: it is the sight now.
		return lerpf(bow_zoom, bow_zoom_full, bow_drawn)
	var glass := weapon.data.ads_zoom if weapon.data else 1.0
	return lerpf(1.0, ads_zoom * glass, focus)


## What the camera is actually set to, base framing included. Anything sizing
## itself against the screen wants this rather than get_zoom_factor(): the factor
## alone is only the part that moves when you aim.
func get_camera_zoom() -> float:
	return base_zoom * get_zoom_factor()


## Aiming is a crosshair orbiting you, steered by how far the mouse moved -
## not a gun chasing wherever the pointer landed.
##
## The old model read the cursor's world position and rotated the gun toward it
## at a speed, which put lag between the mouse and the muzzle. Heavier guns had
## more of it, so making the sniper heavy made the lag intolerable. Worse, the
## camera leans off centre while aiming, so the character is not under a fixed
## point on screen and the same cursor position meant different angles at
## different moments.
##
## Steering an orbit fixes both. The angle is the input rather than a target to
## converge on, so there is no momentum at any weight, and nothing depends on
## where the character sits on screen. A heavy weapon now costs mouse travel
## instead of costing response - see WeaponData.aim_speed_scale.
func _update_aim(delta: float) -> void:
	if not inventory_open:
		var motion := PlayerInput.consume_aim_motion()
		if not motion.is_zero_approx():
			var scale := weapon.data.aim_speed_scale if weapon.data else 1.0
			# Aiming down sights slows the swing, as bracing a gun should.
			scale *= lerpf(1.0, ads_aim_scale, focus)
			var moved := _aim_reach + motion * mouse_sensitivity * scale
			# Pushed through the middle the direction is meaningless, so the last
			# one stands rather than snapping to whatever the noise says.
			if moved.length() > 8.0:
				if throw_slot >= 0:
					# Winding up a throw, the crosshair is a spot being placed
					# rather than an angle being held, so it moves in and out as
					# well as around. Grenades were aimed by cursor distance for
					# a reason: "how long did I hold the key" is no way to put
					# one through a doorway.
					_aim_reach = moved.limit_length(THROW_MAX_RANGE)
				else:
					_aim_reach = moved.normalized() * AIM_ORBIT
		# A stick points absolutely; it has no relative motion to integrate.
		var stick := PlayerInput.get_stick_aim()
		if not stick.is_zero_approx():
			_aim_reach = stick.normalized() * AIM_ORBIT

	_aim_base = wrapf(_aim_reach.angle(), -PI, PI)

	# Which way the gun points, taken from the direction rather than from the size
	# of the angle: an |angle| > PI/2 test reports the wrong side once the angle
	# has wrapped. Used for mirroring the body, nothing else.
	facing = 1 if cos(_aim_base) >= 0.0 else -1
	# Sway rides on top of the angle you are steering rather than being part of
	# it: you hold the gun where you want it and the gun wanders, which is what
	# makes riding the wander down onto a target a thing you can do. Applied
	# after facing, so a wobble across the vertical cannot turn the body round.
	aim_angle = _apply_kick(_aim_base + _scope_sway(delta), weapon.kick)
	aim_direction = Vector2.RIGHT.rotated(aim_angle)

	_aim_pivot.rotation = aim_angle
	# Mirror instead of letting the arm hang upside down when aiming left.
	_aim_pivot.scale.y = facing
	_body.scale.x = facing


## Slinging the gun and bringing it back up.
##
## Both hands are wanted for a cable or a hook, so the gun goes away while you
## are on one - and the cost is not the putting away, it is the draw at the far
## end, which is the weapon's own equip time. That is the whole point of it:
## stepping off a rope leaves you holding nothing for as long as swapping to
## that gun would take, so riding across the level to reposition mid-fight is a
## decision with a bill attached rather than a free ride.
##
## Runs on every machine, off `stowed`, so what you see somebody else holding is
## what they are actually able to shoot with.
func _update_stow(delta: float) -> void:
	if is_local():
		stowed = riding or _hook != null or is_grappling()

	# Away quickly, back at whatever the gun weighs - so the pose finishes coming
	# up on the same frame the trigger starts working again.
	var ramp := stow_time
	if not stowed:
		ramp = weapon.data.get_equip_time() if weapon.data else stow_time
	stow = move_toward(stow, 1.0 if stowed else 0.0, delta / maxf(ramp, 0.01))
	if is_local():
		# One clock for the draw, and it is the animation. The gun works again on
		# the frame the arm finishes bringing it up and not before - a separate
		# equip timer running alongside is how it ends up firing from a pose that
		# is still halfway down.
		if stow > 0.0:
			weapon.put_away()
		elif weapon.stowed:
			weapon.bring_up()

	gun_angle = aim_angle
	if is_zero_approx(stow) and is_zero_approx(_arm.rotation):
		return

	# Slung is a pose on the *body*, not on the gun: down and a little behind,
	# wherever the aim happens to be pointing. The pivot is turned by aim_angle
	# and mirrored by facing, and a mirror maps a local angle t to aim_angle +
	# facing * t - so that is inverted here to land the arm on a world angle.
	var rest := Vector2(-facing * tan(deg_to_rad(stow_lean)), 1.0).angle()
	_arm.rotation = wrapf((rest - aim_angle) * facing, -PI, PI) * stow
	_arm.scale.x = lerpf(1.0, stow_shorten, stow)
	# Back out to world, by the same mirror rule, so the crosshair can be hung
	# off the muzzle wherever the sling has taken it.
	gun_angle = aim_angle + facing * _arm.rotation


## How far off the wander has taken the sight this frame, in radians.
##
## Two turns at an irrational ratio rather than one, so the drift never comes
## back round on a beat you can count - it wanders instead of ticking. Scaled by
## focus so it eases in with the sight instead of punching in the moment the
## button goes down, and so a gun that is not scoped never sways at all.
func _scope_sway(delta: float) -> float:
	var data := weapon.data
	if data == null or data.ads_sway <= 0.0 or focus <= 0.0:
		return 0.0
	# Deliberately not wrapped. The two turns are at an irrational ratio, so no
	# wrap point exists that leaves both of them continuous, and one that leaves
	# only the first continuous puts a visible flick in the sight every time it
	# comes round. A GDScript float is a double; it can count radians all day.
	_sway_phase += delta * data.ads_sway_speed * TAU
	var wander := sin(_sway_phase) * 0.62 + sin(_sway_phase * 1.618 + 1.1) * 0.38
	return deg_to_rad(data.ads_sway) * wander * focus


## Applies the weapon's climb to an aim angle by LIFTING THE AIM POINT rather
## than rotating the angle by a signed amount.
##
## Rotating needs a sign for "up", and that sign has to flip as the gun crosses
## vertical. Near the top of the arc the smallest wobble flips it, and the aim
## jumps by twice the kick - which with a big gun is a 50 degree oscillation
## rather than a wobble. Picking a point out along the shot line and pushing it
## up in world space is continuous everywhere instead. It also behaves correctly
## at the extremes for free: aimed straight up, lifting the point changes nothing
## because there is no higher to climb; aimed straight down, the climb walks the
## muzzle back toward level.
func _apply_kick(base: float, kick: float) -> float:
	if is_zero_approx(kick):
		return base
	# tan() runs away near a quarter turn, and a rise past the reference distance
	# would swing the aim through vertical rather than up to it.
	var rise := minf(tan(kick), 0.95) * KICK_REFERENCE
	var point := Vector2.RIGHT.rotated(base) * KICK_REFERENCE + Vector2.UP * rise
	return point.angle()


func _update_run(delta: float) -> void:
	var input_axis := PlayerInput.get_move_axis()
	var on_floor := is_on_floor()
	# Heavy weapons (low handling) cap your speed and blunt your acceleration.
	var speed_cap := max_speed
	var accel_scale := 1.0
	if weapon.data:
		speed_cap *= weapon.data.get_move_multiplier()
		accel_scale = weapon.data.get_accel_multiplier()
	# Aiming walks you down to a shooting pace; crouching slows you further.
	speed_cap *= lerpf(1.0, ads_move_scale, focus)
	speed_cap *= lerpf(1.0, crouch_speed_scale, crouch)
	# And the plates, which cost more than either. Scaled by the ramp rather than
	# by the toggle, so the weight arrives as they come up instead of landing on
	# you in one frame.
	speed_cap *= lerpf(1.0, shield_speed_scale, shield)
	accel_scale *= lerpf(1.0, shield_accel_scale, shield)
	# A crawl replaces the crouch scale rather than stacking on it, so the speed
	# is a number you can reason about instead of two fractions multiplied.
	if is_downed:
		speed_cap = max_speed * crawl_speed_scale
		accel_scale = 0.6
	if overload_left > 0.0:
		speed_cap *= overload_speed_scale
		accel_scale *= overload_speed_scale

	if is_zero_approx(input_axis):
		var friction := ground_friction if on_floor else air_friction
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	else:
		var accel := (ground_accel if on_floor else air_accel) * accel_scale
		velocity.x = move_toward(velocity.x, input_axis * speed_cap, accel * delta)


func _update_jump(delta: float) -> void:
	if PlayerInput.is_jump_just_pressed():
		_buffer_timer = jump_buffer_time

	if _buffer_timer > 0.0 and _coyote_timer > 0.0:
		if PlayerInput.is_down_held() and _is_standing_on_one_way():
			_drop_through()
		else:
			velocity.y = _jump_velocity * (overload_jump_scale if overload_left > 0.0 else 1.0)
			_jumping = true
		_buffer_timer = 0.0
		_coyote_timer = 0.0

	# Short hop: let go early and the rise is cut short.
	if _jumping and velocity.y < 0.0 and not PlayerInput.is_jump_held():
		velocity.y *= jump_cut
		_jumping = false

	var gravity := _jump_gravity if velocity.y < 0.0 else _fall_gravity
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _update_weapon() -> void:
	if PlayerInput.is_heal_just_pressed():
		_use_medkit()

	# Debug: Y fills the meter, so an ultimate can be tried without playing a
	# whole raid to charge it. If none is equipped it hands one over too -
	# testing a gadget should not first require shopping for it.
	if Input.is_action_just_pressed(&"debug_charge") and inventory:
		if inventory.ultimate == null:
			inventory.set_ultimate(Item.from_gadget(
				load("res://resources/gadgets/overload.tres") as GadgetData))
			_say_loot("debug: Overload equipped and charged")
		else:
			_say_loot("debug: %s charged" % inventory.ultimate.gadget.short_name)
		inventory.ultimate.charge = 1.0

	if PlayerInput.is_ultimate_just_pressed():
		if bow_out:
			bow_out = false
			bow_drawn = 0.0
			_say_loot("bow away")
		else:
			_use_ultimate()
	_update_throw(get_physics_process_delta_time())

	if PlayerInput.is_reload_just_pressed():
		weapon.reload()

	# With the bow in hand the trigger belongs to it, not to the gun.
	if bow_out:
		_draw_bow(get_physics_process_delta_time())
		return

	# The mouse belongs to the inventory screen while it is up, so the trigger is
	# not read at all - clicking an item must never also fire the gun.
	weapon.try_fire(
		_muzzle.global_position,
		aim_angle,
		PlayerInput.is_fire_just_pressed() and not inventory_open,
		PlayerInput.is_fire_held() and not inventory_open,
		_get_move_factor(),
		_get_air_factor(),
	)


## Ultimates fill as the raid goes on and empty in one press. Charge is time
## plus trouble: standing around fills it slowly, a fight fills it faster.
func _charge_ultimate(delta: float) -> void:
	overload_left = maxf(overload_left - delta, 0.0)
	var ult := inventory.ultimate if inventory else null
	if ult == null or ult.charge >= 1.0:
		return
	ult.charge = minf(ult.charge + delta / maxf(ult.gadget.charge_time, 1.0), 1.0)


## Adds charge for doing something worth charging for - landing hits.
func add_ultimate_charge(fraction: float) -> void:
	var ult := inventory.ultimate if inventory else null
	if ult:
		ult.charge = minf(ult.charge + fraction, 1.0)


func _use_ultimate() -> void:
	var ult := inventory.ultimate if inventory else null
	if ult == null:
		_say_loot("no ultimate equipped")
		return
	if ult.charge < 1.0:
		_say_loot("ultimate at %d%%" % roundi(ult.charge * 100.0))
		return

	var keep_charge := ult.charge
	ult.charge = 0.0
	match ult.gadget.kind:
		GadgetData.Kind.OVERLOAD:
			overload_left = ult.gadget.active_time
			_say_loot("OVERLOAD")
		GadgetData.Kind.RECON_BOW:
			# Q only brings the bow out. The charge is not spent until an arrow
			# actually leaves it, so thinking better of the shot costs nothing.
			ult.charge = keep_charge
			bow_out = true
			bow_drawn = 0.0
			_say_loot("bow out - hold fire to draw, release to loose")
	if _audio:
		_audio.reload_finished(global_position)


## The bow, while it is out: hold the trigger to pull it back, let go to shoot.
##
## A gun fires the moment you click; a bow makes you commit to the shot and hold
## still for it, which is exactly the trade an ultimate should ask for.
func _draw_bow(delta: float) -> void:
	if inventory_open or not is_alive:
		return

	if PlayerInput.is_fire_held():
		bow_drawn = minf(bow_drawn + delta / maxf(bow_draw_time, 0.01), 1.0)
		return

	if bow_drawn <= 0.0:
		return # not drawn yet: the trigger has simply not been touched

	if bow_drawn < bow_min_draw:
		bow_drawn = 0.0 # a twitch on the trigger, not a shot
		return

	_loose_arrow(bow_drawn)


func _loose_arrow(power: float) -> void:
	var ult := inventory.ultimate if inventory else null
	if ult == null:
		bow_out = false
		return

	_fire_recon(ult.gadget, power)
	# Now the charge is spent: an arrow has left the bow.
	ult.charge = 0.0
	bow_out = false
	bow_drawn = 0.0
	_shake = minf(_shake + 4.0, max_shake)
	_say_loot("arrow away at %d%% draw" % roundi(power * 100.0))
	if _audio:
		_audio.dry_fire(_muzzle.global_position)


## Looses an arrow. It flies, it drops, and it paints whatever it lands near -
## so a recon shot is a shot you have to aim and lead, not a button that reveals
## the room.
func _fire_recon(gadget: GadgetData, power := 1.0) -> void:
	var bolt: ReconBolt = RECON_BOLT_SCENE.instantiate()
	bolt.setup(gadget, power)
	bolt.global_position = _muzzle.global_position
	bolt.velocity = aim_direction * bolt.launch_speed()
	bolt.rotation = aim_direction.angle()
	get_parent().add_child(bolt)


## Grenades are aimed with the mouse and thrown on release.
##
## Holding the key shows the arc; the cursor sets where it lands, near or far,
## and the throw is solved to put it there. Winding up on a timer meant the only
## control you had was "how long did I hold it", which is no way to place a
## grenade in a doorway.
func _update_throw(delta: float) -> void:
	if throw_slot < 0:
		for slot in Inventory.THROWABLE_SLOTS:
			if not PlayerInput.is_throw_just_pressed(slot):
				continue
			if inventory and inventory.get_throwable(slot):
				throw_slot = slot
			else:
				_say_loot("nothing in slot %d" % (slot + 1))
		return

	if inventory_open or not is_alive:
		_cancel_throw()
		return

	if PlayerInput.is_throw_held(throw_slot):
		var target := _throw_target()
		throw_charge = clampf(_muzzle.global_position.distance_to(target) / THROW_MAX_RANGE,
			0.0, 1.0)
		_aim_line.arc_points = _simulate_throw(throw_charge)
		_aim_line.arc_power = throw_charge
		_aim_line.showing_arc = true
		return

	_release_throw()


## Where the cursor is asking for, clamped to what an arm can manage.
func _throw_target() -> Vector2:
	var from := _muzzle.global_position
	# The crosshair is the landing spot: where you have pushed it out to is where
	# the grenade is solved to land.
	var wanted := PlayerInput.get_aim_point(global_position, _aim_reach)
	var offset := wanted - from
	if offset.length() > THROW_MAX_RANGE:
		offset = offset.normalized() * THROW_MAX_RANGE
	return from + offset


func _cancel_throw() -> void:
	throw_slot = -1
	throw_charge = 0.0
	_aim_line.showing_arc = false


func _release_throw() -> void:
	var item := inventory.get_throwable(throw_slot) if inventory else null
	if item == null:
		_cancel_throw()
		return

	# Through Net, same as a round: thrown here at once, and on every other
	# machine a moment later.
	Net.throw_gadget(item.gadget.resource_path, _muzzle.global_position,
		_throw_velocity(throw_charge), Layers.PLAYER_SHOT,
		get_multiplayer_authority())

	item.count -= 1
	if item.count <= 0:
		inventory.set_throwable(throw_slot, null)
	_say_loot("%s away" % item.gadget.short_name)
	_cancel_throw()


## Solves the throw that lands on the cursor: pick a flight time from how far it
## is, then work out the velocity that gets there in that time under gravity.
func _throw_velocity(_power: float) -> Vector2:
	var from := _muzzle.global_position
	var to := _throw_target()
	var offset := to - from
	var reach := clampf(offset.length() / THROW_MAX_RANGE, 0.0, 1.0)
	var flight := lerpf(THROW_TIME_NEAR, THROW_TIME_FAR, reach)

	return Vector2(
		offset.x / flight,
		(offset.y - 0.5 * Grenade.GRAVITY * flight * flight) / flight)


## Runs the grenade forward with the same numbers the grenade itself uses, and
## stops at the first thing it would hit. What is drawn is what will happen.
func _simulate_throw(power: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var at := _muzzle.global_position
	var vel := _throw_velocity(power)
	var step := 1.0 / 60.0
	var space := get_world_2d().direct_space_state
	points.append(at)

	for i in ARC_STEPS:
		vel.y += Grenade.GRAVITY * step
		var next := at + vel * step
		var query := PhysicsRayQueryParameters2D.create(at, next)
		query.collision_mask = Layers.WORLD
		var hit := space.intersect_ray(query)
		if hit:
			points.append(hit.position)
			break
		at = next
		points.append(at)
	return points


## Spends one use of the first medkit in the bags. Nothing fancy: standing
## still to patch up is the cost, and running out is the danger.
func _use_medkit() -> void:
	if health >= max_health:
		_say_loot("already patched up")
		return
	for grid in inventory.grids():
		for item in grid.items:
			if not item.is_medkit():
				continue
			health = minf(health + item.heal, max_health)
			item.count -= 1
			if item.count <= 0:
				grid.remove(item)
			health_changed.emit(health, max_health)
			_say_loot("patched up +%d" % roundi(item.heal))
			if _audio:
				_audio.reload_finished(global_position)
			return
	_say_loot("no medkit")


## Sticks a stim in yourself and gets up, at full health.
##
## Nobody has to come for you, which is the whole point of carrying one - it
## turns going down from the end of your raid into an expense. Runs on your own
## machine, and only ever on your own body: health and is_downed replicate
## outwards from the owner, so standing up here is standing up everywhere without
## a single line of network code.
func _use_revive() -> void:
	if not is_downed:
		return
	for grid in inventory.grids():
		for item in grid.items:
			if not item.is_revive():
				continue
			item.count -= 1
			if item.count <= 0:
				grid.remove(item)
			_revive()
			_say_loot("back up - %d stim%s left" % [revives_left(),
				"" if revives_left() == 1 else "s"])
			if _audio:
				_audio.reload_finished(global_position)
			inventory.changed.emit()
			return
	_say_loot("no stim")


## Back on your feet. The mirror of _go_down: everything that was taken away
## comes back, and the brief invulnerability is what stops the round that is
## already in the air from putting you straight back down.
func _revive() -> void:
	is_downed = false
	down_health_left = 0.0
	health = max_health
	crouch = 0.0
	_invulnerable = invulnerable_time
	health_changed.emit(health, max_health)
	revived.emit()


func revives_left() -> int:
	var total := 0
	if inventory == null:
		return 0
	for grid in inventory.grids():
		for item in grid.items:
			if item.is_revive():
				total += item.count
	return total


## 0 standing still, 1 at full sprint. Feeds the run-and-gun accuracy penalty.
func _get_move_factor() -> float:
	return clampf(absf(velocity.x) / maxf(max_speed, 1.0), 0.0, 1.0)


## 1 with both feet off the ground, easing back to 0 over air_settle_time once
## they are back on it. Feeds a cone several times wider than running does -
## being in the air is the one place you cannot brace against anything, and a
## jump that dodges a shot should not also land one.
func _get_air_factor() -> float:
	return _air_spread


func _update_reticle() -> void:
	# No gun, no reticle. Leaving it up while crawling would read as though you
	# could still shoot something.
	_reticle.visible = not is_downed
	if is_downed:
		return
	# Radius, not just position: the reticle sizes its cone from its own radius,
	# so pushing it out without telling it would draw the wrong spread.
	# Dividing by the zoom keeps it the same size on screen whatever the
	# magnification: a 2x scope would otherwise draw a reticle twice as big. The
	# full camera zoom, not just the aiming part - pulling the base framing back
	# would otherwise shrink the reticle along with the world.
	_reticle.radius = _reticle_radius * lerpf(1.0, ads_reticle_scale, focus) / get_camera_zoom()
	# Gone on the rope, and faded back in over the draw rather than snapped on
	# at the end of it - so the sight picture arrives with the muzzle. Done with
	# alpha rather than by hiding the nodes, because everything below still has
	# to be kept current: a crosshair that stopped tracking while invisible
	# would pop back in wherever it was left.
	var up := 1.0 - stow
	_reticle.modulate.a = up
	# A grenade you can still throw keeps its arc, whatever the gun is doing.
	_aim_line.modulate.a = 1.0 if _aim_line.showing_arc else up
	# The overlay layer follows the viewport, so positions on it are world
	# positions - hence global_position rather than an offset from the player.
	# Hung off the gun rather than off the aim, so slinging it takes the
	# crosshair down with the muzzle and the draw carries it back up. They are
	# the same angle whenever the gun is actually in your hands.
	var pointing := Vector2.RIGHT.rotated(gun_angle)
	_reticle.global_position = global_position + pointing * _reticle.radius
	_reticle.rotation = gun_angle

	_reticle.spread = weapon.get_spread(_get_move_factor(), _get_air_factor())
	_reticle.is_reloading = weapon.is_reloading()
	_reticle.reload_progress = weapon.get_reload_progress()
	_reticle.is_empty = weapon.get_mag() <= 0

	# Fed the finished reticle values, so the arc and the reticle ticks always
	# describe the same cone.
	_aim_line.from = _muzzle.global_position
	_aim_line.to = _reticle.global_position
	_aim_line.spread = _reticle.spread
	_aim_line.focus = focus


## Footfalls, plus a step on landing so a jump ends with a sound rather than in
## silence. Running off a ledge and touching down again counts as a landing.
func _update_footsteps(delta: float) -> void:
	var on_floor := is_on_floor()

	if on_floor and not _was_on_floor:
		# A landing that carried makes its own noise, and a much bigger one - it
		# should not also click like an ordinary step.
		if not _land(global_position.y - _fall_apex):
			_step()
		_step_travel = 0.0
	elif on_floor:
		_step_travel += absf(velocity.x) * delta
		if _step_travel >= lerpf(step_distance, crouch_step_distance, crouch):
			_step_travel = 0.0
			_step()
	else:
		# Land on the front foot rather than half a stride in.
		_step_travel = step_distance * 0.5

	# Where the drop is counted from. Reset whenever you are being carried
	# rather than falling: riding the mast cable down is not a fall, and a swing
	# on the line only starts counting from the moment you let go of it.
	#
	# The last case is a jump in height no fall could have produced - a spawn,
	# an extraction, a revive, or the frame after a cable ride, during which
	# this function is not called at all. Anything moved rather than dropped
	# starts counting again from where it was put.
	var moved := absf(global_position.y - _fall_last_y)
	_fall_last_y = global_position.y
	if on_floor or riding or is_grappling() or moved > max_fall_speed * delta * 2.0 + 8.0:
		_fall_apex = global_position.y
	else:
		_fall_apex = minf(_fall_apex, global_position.y)

	_was_on_floor = on_floor


## Hitting the ground. True if the drop was far enough to be heard, in which
## case it has already made its own noise.
##
## Handed to Net rather than played here, because unlike a footstep this is not
## a sound you make on your own machine and replicate for flavour - it is a
## reveal, and the whole of its effect happens on other people's screens.
func _land(drop: float) -> bool:
	if drop < fall_ping_height or not is_alive:
		return false
	Net.fall_heard(global_position, drop)
	landed_hard.emit(drop)
	_say_loot("that landing carried")
	return true


func _step() -> void:
	if _audio:
		_audio.footstep(global_position, true, lerpf(1.0, crouch_step_volume, crouch))


## How much harder the gun is kicking for having been held down. 1.0 until the
## burst passes sustained_shake_after, then climbing per round to a ceiling.
func _sustained_scale() -> float:
	var over := _burst_rounds - sustained_shake_after
	if over <= 0:
		return 1.0
	return minf(1.0 + over * sustained_shake_per_round, sustained_shake_max)


func _update_shake(delta: float) -> void:
	# Let off the trigger for long enough and the count goes with it.
	if _burst_gap > 0.0:
		_burst_gap -= delta
		if _burst_gap <= 0.0:
			_burst_rounds = 0
	_shake = move_toward(_shake, 0.0, shake_recovery * delta)
	if _shake > 0.0:
		_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	else:
		_camera.offset = Vector2.ZERO

	# Offset is spoken for by shake, so the aim lean rides on position instead.
	_camera.position = _camera.position.lerp(_get_lead_offset(), 1.0 - exp(-10.0 * delta))
	_camera.zoom = _base_zoom * get_zoom_factor()
	_fit_vision_to_view()


## Grows the vision light to cover whatever the camera is currently showing.
##
## The light is a fixed 896 px circle, which comfortably overshot the screen at
## the framing this was built with. It does not any more: pulling back to 0.75
## put the corners near the edge of it, and a sniper's scope pulls back further
## still - 0.75 base times 0.75 glass leaves a visible half-screen of 1138 px
## against 896 px of light, so the far corners sit in a ring of black that is not
## darkness or cover, just the edge of the texture.
##
## Only ever grown, never shrunk below what the scene authored, so zooming in
## keeps the light exactly as tight as it was designed to be. Purely cosmetic
## either way - concealment is raycast against collision shapes and has never
## consulted this light.
func _fit_vision_to_view() -> void:
	if not vision_fills_screen or _vision == null or _vision.texture == null:
		return
	# Half the diagonal: the corners are the furthest part of the screen from you
	# and the first place the light stops reaching.
	var half := get_viewport_rect().size * 0.5 / get_camera_zoom()
	var reach := half.length() * vision_overscan
	var texture_radius := _vision.texture.get_height() * 0.5
	if texture_radius <= 0.0:
		return
	_vision.texture_scale = maxf(_vision_scale, reach / texture_radius)


## Where the camera sits relative to the player while aiming: pushed along the
## aim line so you stand off to one side and see further down range. Worked out
## per axis from what is actually on screen at the current zoom, so a heavy
## scope leans further rather than less.
func _get_lead_offset() -> Vector2:
	var reach := 0.0
	if focus > 0.0:
		var scale := weapon.data.ads_lead_scale if weapon.data else 1.0
		reach = ads_lead_fraction * scale * focus
	if bow_out:
		# Leaning matters more with the bow than with any scope: the whole point
		# is seeing where an arrow can reach, and that is all down range.
		reach = maxf(reach, ads_lead_fraction * bow_lead_scale * lerpf(0.55, 1.0, bow_drawn))
	if reach <= 0.0:
		return Vector2.ZERO

	reach = clampf(reach, 0.0, 0.9)
	var half := get_viewport_rect().size * 0.5 / get_camera_zoom()
	return Vector2(aim_direction.x * half.x, aim_direction.y * half.y) * reach


func _on_shot_fired(shake: float, knockback: float) -> void:
	# Rounds fired without a meaningful pause. Kept here rather than on the weapon
	# because it is about what holding the trigger does to *you* - a burst counts
	# the same whether it came from one magazine or spanned a reload.
	_burst_rounds += 1
	_burst_gap = sustained_reset_time

	var jolt := shake * lerpf(1.0, ads_shake_scale, focus)
	jolt *= _sustained_scale()
	# The cap limits what a stream of shots can pile up to, but one heavy round
	# is allowed to exceed it: clamping a hand cannon down to the same rattle a
	# submachine gun reaches after ten rounds throws away the whole point of it.
	# Sustained fire raises the ceiling as well as the jolt, or the growth would
	# be swallowed by the clamp the moment it started to matter.
	_shake = minf(_shake + jolt, maxf(max_shake * _sustained_scale(), jolt))
	# Horizontal only: a downward shot should not launch the player.
	velocity.x -= aim_direction.x * knockback


## One of your rounds landed on something. Called by whatever took the hit - see
## Damage.report_hit - so this fires for bullets and grenade blasts alike without
## either of them knowing the marker exists.
##
## A kill is confirmed twice on purpose, in the eye and in the ear. Shooting
## someone you cannot see the health bar of is most of this game, and the
## difference between "he is hurt" and "he is down" decides whether you break
## cover.
func on_hit_dealt(headshot := false, killed := false) -> void:
	if _reticle:
		var mark := Reticle.Mark.HIT
		if killed:
			mark = Reticle.Mark.KILL
		elif headshot:
			mark = Reticle.Mark.HEADSHOT
		_reticle.flash(mark)
	if _audio:
		if killed:
			_audio.kill()
		else:
			_audio.hit(headshot)


func _drop_through() -> void:
	set_collision_mask_value(Layers.ONE_WAY_BIT, false)
	_drop_timer = DROP_THROUGH_TIME
	global_position.y += 1.0
	velocity.y = 0.0


func _is_standing_on_one_way() -> bool:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is CollisionObject2D:
			if (collider as CollisionObject2D).collision_layer & Layers.ONE_WAY:
				return true
	return false


## Where bullets spawn from.
func get_muzzle_position() -> Vector2:
	return _muzzle.global_position


# --- damage -------------------------------------------------------------------


## Same signature the practice dummies use, so a bullet does not care what it hit.
func take_damage(amount: float, at: Vector2, direction: Vector2) -> void:
	# A hit is worked out where the round is - on the host - but a body belongs
	# to the machine sitting behind it, and health replicates outwards from
	# there. Applying it here, on a copy the owner is authoritative for, would be
	# overwritten by that owner's next sync a frame later and the shot would
	# simply not have happened. So the host decides you were hit and says so
	# (through Net, which is the only thing here that talks to the network); your
	# own machine decides what your body does about it.
	#
	# The cost is honest: a modified client could ignore this. That is the same
	# trade the rest of the file makes - it is a game for people you know, and
	# the alternative is moving health onto a second, host-owned synchroniser.
	if Net.is_networked() and not is_local():
		Net.tell_owner_hit(get_multiplayer_authority(), amount, at, direction,
			Net.attributing_to)
		return
	if not is_alive or _invulnerable > 0.0:
		return

	# Already on the ground: this is someone finishing the job. Armour is not
	# consulted - it did not save you the first time and it is not going to now.
	#
	# Nor is the head/body split. Prone, the collision box is a flat sliver, and
	# Damage carves its top quarter out as "head" the same as it would standing -
	# so almost every round that landed anywhere near you counted as a headshot
	# and executed you on the spot, which made going down a coin flip that ended
	# before you could crawl anywhere. A man lying flat, seen from the side, does
	# not have a head you can distinguish from the rest of him. Every hit costs
	# the same, and it is the count that finishes you.
	if is_downed:
		down_health_left = maxf(down_health_left - amount, 0.0)
		velocity.x += direction.x * 30.0
		_shake = minf(_shake + 4.0, 12.0)
		if down_health_left <= 0.0:
			_die(false)
		# Flat, like the damage: prone there is no head to report.
		Damage.report_hit(get_tree(), false, not is_alive)
		return

	# Caught without the plates up, anything that reaches you ends the fight.
	#
	# Below the prone case and above Damage.resolve, and both halves of that
	# matter.
	#
	# Below, because somebody already on the floor is being finished off and the
	# shield has nothing to say about it: sending that through here would call
	# _go_down on a body that is already down, which does nothing at all, and
	# leave them unkillable.
	#
	# Above, because no vest or helmet is consulted - and so none should be spent
	# either. resolve() burns durability on whatever it absorbs, and armour has
	# no business wearing out stopping a round that was never going to be
	# stopped. The shield was what was supposed to be between you and this.
	#
	# Nor does it matter where the round landed, so no head is reported - the
	# same reasoning the prone case above uses. It is not a damage number at all:
	# not a bonus you accumulate but a state you are in or out of, and being
	# caught out of it is fatal rather than expensive.
	#
	# Routed through _go_down rather than _die for the reason an unprotected
	# headshot already is - "lethal" here means you are on the floor with a
	# bleed-out clock and somebody can still come and get you. See _go_down.
	if not is_shielded():
		last_hit_headshot = false
		_go_down(true)
		Damage.report_hit(get_tree(), false, true)
		return

	var height: float = (_shape.shape as RectangleShape2D).size.y
	var hit := Damage.resolve(amount, at, global_position + _shape.position, height, inventory)
	last_hit_headshot = hit.headshot


	if hit.knockout:
		# A round through an unprotected head puts you down rather than out. It
		# still ends the fight - you cannot shoot back from the floor - which is
		# what a helmet is really buying you: the chance to stay standing.
		_go_down(true)
		# Reported as a kill: from the shooter's side putting someone on the
		# floor is the shot landing, and they cannot see the bleed-out timer.
		Damage.report_hit(get_tree(), true, true)
		return

	amount = hit.amount
	health = maxf(health - amount, 0.0)
	_invulnerable = invulnerable_time
	health_changed.emit(health, max_health)

	# A hit shoves you and rattles the camera, so incoming fire is felt even when
	# the shooter is somewhere off screen.
	velocity.x += direction.x * 60.0
	_shake = minf(_shake + 6.0, 16.0)

	var tween := create_tween()
	_torso.color = Color(1.0, 0.45, 0.45)
	tween.tween_property(_torso, "color", Color(0.831373, 0.85098, 0.878431), 0.22)

	if health <= 0.0:
		_go_down(false)

	# Told from the body that was hit rather than from the round that hit it -
	# same rule guards follow, and the only place that knows whether the shot
	# finished anyone. Net routes the mark back to whoever pulled the trigger.
	Damage.report_hit(get_tree(), hit.headshot, is_downed or not is_alive)


## The clock that runs while you are on the floor. Nobody has to shoot you again
## for this to end badly - which is what makes the crawl urgent rather than a
## place to hide.
func _bleed_out(delta: float) -> void:
	if down_bleed_per_second <= 0.0:
		return
	down_health_left = maxf(down_health_left - down_bleed_per_second * delta, 0.0)
	if down_health_left <= 0.0:
		_die(false)


## Told by Net that another player's arrow has painted us. Only ever called on
## the machine the body belongs to - the message is addressed to that peer.
func mark_scanned() -> void:
	if not is_alive:
		return
	scanned.emit()
	# The same thump a grenade makes, small and close. You should hear it as well
	# as read it: the point of the warning is that you are probably looking at
	# something else at the time.
	if _audio:
		_audio.explosion(global_position, 0.2)


## Seconds left before bleeding out, ignoring anything further shot into you.
## The HUD shows this: a bar draining on its own reads as time, where a bar that
## only moves when you are hit reads as health.
func seconds_down_left() -> float:
	if down_bleed_per_second <= 0.0:
		return INF
	return down_health_left / down_bleed_per_second


## Down, not out. The gun is gone, the aim is gone, and what is left is a slow
## crawl and whatever cover you can reach before someone walks over.
func _go_down(from_headshot: bool) -> void:
	if is_downed:
		return
	is_downed = true
	down_health_left = down_health
	health = 0.0
	health_changed.emit(health, max_health)

	# Everything that involves the gun stops here.
	focus = 0.0
	weapon.focus = 0.0
	bow_out = false
	bow_drawn = 0.0
	_cancel_throw()
	if zipline:
		_leave_zipline(false)
	velocity.x = 0.0
	# Flat on the floor immediately rather than easing into it - going down is a
	# thing that happens to you, not a posture you adopt.
	crouch = 1.0
	_invulnerable = invulnerable_time
	downed.emit(from_headshot)


## There is no respawn. This is an extraction run: you go in, you take what you
## can carry, and dying is the end of it - everything on you is lost with you.
func _die(knocked_out := false) -> void:
	is_alive = false
	is_downed = false
	# Whatever you were going through goes back for somebody else to find - along
	# with anything you had already moved onto yourself, which is now on your own
	# body wherever you fell.
	_release_body()
	_let_go_of_grapple(false)
	_leave_the_kit_behind()
	velocity = Vector2.ZERO
	_shape.set_deferred(&"disabled", true)
	died.emit(knocked_out)


## Everything you were carrying, on the floor where you fell.
##
## This is what makes killing somebody worth doing. A raid is a bet - you buy a
## kit, you go in, and what you carry out is yours - and a player who died with a
## full pack and left nothing behind made the other half of that bet free. The
## body is the payout, and it holds exactly what you had: the rifle you bought,
## the magazine you had half spent, and every guard you had already been through.
##
## Only ever run on your own machine, because only your own machine ever calls
## _die on you (see take_damage). Net puts the same body on every other floor.
func _leave_the_kit_behind() -> void:
	if inventory == null:
		return
	# Read before it is taken away, because the death screen is the one place it
	# is worth naming - being told exactly what you have just lost is most of
	# what makes the next kit screen a decision.
	lost_kit = inventory.summary()
	Net.drop_kit(inventory,
		global_position + Vector2(0.0, size.y * 0.5 - 8.0),
		_torso.color, size)
	# It is not yours any more. Left attached, the inventory screen would still be
	# offering the kit lying on the floor behind you, and a revive would hand it
	# all back - two copies of a pack that is the whole point of shooting you for.
	inventory = Inventory.new()
	weapon.set_inventory(inventory)


func respawn() -> void:
	global_position = _spawn
	velocity = Vector2.ZERO
	armored = false
	shield = 0.0
	health = max_health
	_invulnerable = invulnerable_time
	focus = 0.0
	weapon.focus = 0.0
	_shape.set_deferred(&"disabled", false)
	visible = true
	is_alive = true
	health_changed.emit(health, max_health)
