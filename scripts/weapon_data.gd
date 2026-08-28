class_name WeaponData
extends Resource

## One gun's tuning. The four headline stats are 0-100 dials; every getter below
## turns a dial into exactly one gameplay effect, so a change to a stat is always
## felt in a specific, explainable way.
##
##   accuracy  -> how tight the cone is before you fire (reticle size at rest)
##   handling  -> aim swing speed, swap time, reload speed, move speed, hip penalty
##   recoil    -> how far the muzzle climbs, straight up, per shot
##   stability -> how much the cone scatters per shot, and how fast climb and
##                scatter settle back down
##
## Recoil and stability are deliberately two different kinds of error. Recoil is
## the predictable one: it is always up, so it can be pulled back down and
## learned. Stability is the unpredictable one: it widens the cone, and no amount
## of skill tells you where inside that cone a round will go. A gun that climbs
## hard but scatters little rewards control; one that barely climbs but sprays is
## a different problem entirely.
##
## --- the damage model -------------------------------------------------------
##
## Every gun is tuned against one benchmark, the assault rifle, and against one
## body: 100 health, a medium vest, and a medium helmet. Three numbers describe
## a gun in that world and all three are readable off the stats below:
##
##   rounds to kill  = ceil(100 / (damage * 0.51))   through a medium vest
##   time to kill    = (rounds - 1) * get_shot_interval()
##   range           = get_half_damage_range(), where damage has halved
##
## The AR sits at 620 rpm and 51 damage, which is 26 through a medium vest, four
## rounds, and 290 ms - and two rounds flat against someone with no vest on,
## because 51 twice is over a full bar. That last part is the floor the whole
## model is built on: nobody dies to one body shot, and everybody dies to two if
## they are caught with nothing on.
##
## Range is quoted as the distance at which damage has halved, not as the point
## the falloff starts or stops. It is the only one of the three that describes
## the gun rather than the curve, so it is the one worth comparing across guns,
## and get_half_damage_range() reads it straight back out of the curve. To place
## a new gun at a chosen half-damage range R, pick where full damage should stop
## (S) and what the far floor is (m), then:
##
##   falloff_end = S + 2 * (1 - m) * (R - S)
##
## which is just the linear falloff solved for factor(R) = 0.5.

@export var display_name := "Weapon"
@export var short_name := "GUN"

@export_group("Stats")
## Tight cone at 100, buckshot at 0.
@export_range(0.0, 100.0) var accuracy := 70.0
## Light and quick at 100, heavy at 0.
@export_range(0.0, 100.0) var handling := 60.0
## Multiplier on the aim swing, on top of handling - effectively this weapon's
## own mouse sensitivity. Below 1 makes the gun heavy to point: a scoped rifle
## that whips around as fast as a pistol is a quickscoping weapon, and slowing
## the swing is what turns it back into a positioning one.
@export_range(0.1, 2.0) var aim_speed_scale := 1.0
## How far the muzzle climbs per shot. HIGHER = more climb (the only "high is
## bad" stat). Always straight up, so it can be fought by pulling down.
@export_range(0.0, 100.0) var recoil := 40.0
## Multiplies everything the recoil dial drives - climb, ceiling and shove - for
## weapons that need to sit off the end of the 0-100 scale. A hand cannon is not
## just "100 recoil"; it is a different weight class.
@export_range(0.1, 4.0) var kick_scale := 1.0
## How steady the gun is: how little the cone scatters per shot, and how quickly
## both the scatter and the climb settle. Higher = steadier.
@export_range(0.0, 100.0) var stability := 60.0
## Multiplies the screen shake that stability works out, for guns whose shot
## should hit the screen harder than their scatter suggests - a heavy single
## round that jolts the camera without spraying rounds around.
@export_range(0.0, 4.0) var shake_scale := 1.0

@export_group("Firing")
@export var rounds_per_minute := 620.0
## Automatic guns fire while held; semi needs a fresh click per shot.
@export var automatic := true
@export var pellets := 1
## How wide the buckshot patterns, in degrees either side of the shell's line.
##
## The inner of two cones, and only meaningful above one pellet. The outer cone
## is the gun's aim spread - accuracy, bloom, movement - and it decides where the
## *shell* goes; this one decides how the pellets sit around that, because nine
## pellets leaving one barrel do not leave it in exactly the same direction.
##
## Keeping them apart is what makes buckshot behave like buckshot. Spread the
## pellets evenly across the aim cone instead and the middle of the pattern is
## nailed to the crosshair however badly you were moving - bloom and sprint stop
## costing a shotgun anything at all, because the one pellet that mattered was
## always dead centre. Rolled once for the shell and then patterned inside it,
## a bad shot misses as a whole rather than politely keeping its centre.
@export_range(0.0, 12.0) var pellet_spread := 2.5
@export var damage := 26.0
@export var bullet_speed := 2800.0
## How much of a plate this round ignores, 0 to 1.
##
## The only way to be good against armour. Protection is a fraction, so a plate
## takes the same *proportion* off a slug as it does off a pellet - which means
## no amount of damage on the sheet makes a gun an armour gun, and a shotgun
## firing nine small pieces is in exactly the same position as one firing a big
## one. This is the dial that changes that: it thins the plate rather than
## fattening the round.
##
## Zero on everything that was here before it existed, so nothing already in the
## game changed the day it arrived.
@export_range(0.0, 1.0) var armor_pierce := 0.0

## How hard this round is on the plate it hits, as a multiple of the wear every
## round does. 1 is ordinary; 0 barely marks it; 2 tears it apart.
##
## The other half of what a round does about armour, and deliberately a separate
## dial from armor_pierce. Piercing is about *this* round getting through - it
## ignores the plate. This is about the plate afterwards, which is a different
## question and often the opposite answer: a submachine gun round is stopped by
## a vest and does not do much to it either, while a machine gun belt chews the
## plate to pieces on its way to being stopped by it.
##
## It travels with the shot, the same way piercing does and for the same reason:
## the machine working out what happened to your armour is yours, not the one
## holding the gun. See Net.armor_wear.
@export_range(0.0, 4.0) var armor_wear_scale := 1.0
@export var bullet_range := 2000.0

@export_group("Range")
## Full damage out to this distance, in pixels.
@export var falloff_start := 600.0
## Damage has bottomed out by this distance.
@export var falloff_end := 1500.0
## Fraction of damage left at falloff_end and beyond.
@export_range(0.0, 1.0) var min_damage_factor := 0.45

@export_group("Carrying")
## Footprint in inventory cells, width x height. A rifle costs eight cells of
## backpack; a sidearm costs two. This is the real cost of a heavy loadout -
## what you take off a body is limited by what you can find room for.
@export var grid_size := Vector2i(2, 1)
## Whether this is small enough to ride in the secondary slot. Only a sidearm
## goes on the hip: the second slot is a backup you can draw in a hurry, not a
## second place to hang a rifle.
@export var sidearm := false

@export_group("Ammo")
## Calibre. Ammunition is carried loose by type, not per gun, so two weapons
## sharing this feed from the same pockets - which is half of what makes one
## loadout better than another.
@export var ammo_type := &"9mm"
@export var mag_size := 30
## Rounds this weapon is found with, on top of the one in the magazine. Used
## when a guard is issued it, and when the player starts with it.
@export var reserve_ammo := 180
## Base reload seconds, before the handling multiplier.
@export var reload_time := 2.1

@export_group("Sights")
## Whether this weapon's glass throws a glint back at whoever it is pointed at.
##
## Only true of a scope worth the name. It is the price of the sniper's reach:
## the same lens that lets you take a shot from outside anyone's ability to
## answer it is a mirror pointed at the person you are about to take it on, and
## it only shows while you are actually looking down it. See Player.scoped and
## Hud._draw_sniper_glints.
@export var scope_glint := false
## Magnification while aimed, on top of the player's own ADS push-in. Above 1
## pushes the camera in for a closer look at a nearby target; BELOW 1 pulls it
## back so more of the level fits on screen.
##
## A long-range weapon wants the second kind. Magnifying does not let you shoot
## further - it shows you a smaller slice of the world, so a target that was on
## screen at 1x can end up outside the view entirely. The sniper's reach comes
## from pulling back and leaning hard down range, not from pushing in.
@export_range(0.4, 4.0) var ads_zoom := 1.0
## What the cone shrinks to while fully aimed. Lower = a harder-earned, tighter
## shot, which is what makes a scope worth the movement penalty.
@export_range(0.05, 1.0) var ads_spread_scale := 0.42
## Scopes take longer to settle on the eye than irons do. Multiplies the
## player's ads_time.
@export_range(0.5, 3.0) var ads_speed_scale := 1.0
## How far the camera leans down range while aimed, multiplying the player's
## ads_lead_fraction. This is what buys back the ground a scope takes away:
## magnify 2x and you see half as far ahead unless the camera stands off.
@export_range(0.0, 3.0) var ads_lead_scale := 1.0
## How far the sight wanders while you are scoped, in degrees either side of
## where you are pointing.
##
## The other three ADS dials all make a scope better; this is the one that costs
## something. A braced rifle does not sit perfectly still, and at the range this
## gun reaches, a fraction of a degree is metres - so the wander is the thing you
## are timing the shot against rather than a nuisance laid over it. It moves the
## aim itself, not the reticle, so the round goes where the sight was.
##
## Zero for everything else on purpose. Irons at the range they are used at would
## only feel broken.
@export_range(0.0, 8.0) var ads_sway := 0.0
## How quickly that wander goes round, in cycles per second. Slow enough to ride
## down onto a target; fast enough that waiting out a bad one costs you the shot.
@export_range(0.05, 4.0) var ads_sway_speed := 0.5

@export_group("Sound")
## Which recorded report this weapon fires with, named by its key in
## Audio.RECORDINGS - "rifle", "suppressed", and so on. Leave it empty and the
## report is synthesised from the stats above instead, which is the fallback for
## anything without a recording of its own. Assigning a sample here is how a new
## sound file gets onto a gun without touching any code.
@export var report_sound := ""
## A suppressed weapon is quiet, dull and short - it does not carry, which is
## the whole reason to take one into a place you would rather not wake up.
## Implies the "suppressed" recording unless report_sound names another.
@export var suppressed := false
## Trim or boost on top of what the stats work out, in decibels.
@export_range(-24.0, 12.0) var loudness_trim := 0.0

@export_group("Look")
@export var bullet_color := Color(1.0, 0.85, 0.45)
@export var bullet_length := 16.0
@export var bullet_width := 2.5


func get_shot_interval() -> float:
	return 60.0 / maxf(rounds_per_minute, 1.0)


## Damage per projectile if it lands this far from the muzzle.
func get_damage_at(distance: float) -> float:
	return damage * get_damage_factor(distance)


func get_damage_factor(distance: float) -> float:
	if distance <= falloff_start:
		return 1.0
	if distance >= falloff_end:
		return min_damage_factor
	var t := (distance - falloff_start) / maxf(falloff_end - falloff_start, 0.001)
	return lerpf(1.0, min_damage_factor, t)


## Where this gun's damage has halved, in pixels. The headline range number.
##
## Derived rather than stored, so it cannot drift away from the curve it is
## describing - change any of the three falloff dials and this follows. Returns
## INF for a gun whose floor never reaches half, which is a real answer: a
## weapon that still does 60% of its damage at the edge of the map does not have
## a half-damage range, it just has a range.
func get_half_damage_range() -> float:
	if min_damage_factor > 0.5:
		return INF
	if falloff_start >= falloff_end:
		return falloff_start
	var span := falloff_end - falloff_start
	return falloff_start + span * (0.5 / maxf(1.0 - min_damage_factor, 0.001))


## What one trigger pull does at point blank, buckshot included.
func get_burst_damage() -> float:
	return damage * pellets


# --- accuracy ---------------------------------------------------------------

## Half-angle of the resting cone, in radians.
func get_base_spread() -> float:
	return deg_to_rad(lerpf(9.0, 0.12, accuracy * 0.01))


## Half-angle of the buckshot pattern, in radians. Zero for anything that fires
## a single round, which has no pattern to have.
func get_pellet_spread() -> float:
	return deg_to_rad(pellet_spread) if pellets > 1 else 0.0


# --- recoil (the climb) -------------------------------------------------------

## Applied on top of every weapon's own numbers, so guns read closer to lasers.
##
## Deliberately here rather than typed into seven .tres files. Scaling the dials
## in one place keeps what each gun is *relative* to the others - a sniper still
## climbs four times an SMG, they are both just calmer - and leaves the numbers
## a designer reads on the resource meaning what they say.
const RECOIL_SCALE := 0.5
const STABILITY_SCALE := 1.7

## Screen shake is scaled on its own, upward, and reads the raw stability dial
## rather than the steadied one. Calming the guns quietened the picture along
## with them, and a gun that barely moves the screen stops reading as a gun -
## the shot loses the weight the climb used to give it.
const SHAKE_BOOST := 1.7


## The recoil dial as the curves below see it.
func _climb() -> float:
	return recoil * RECOIL_SCALE


## The stability dial as the curves below see it.
##
## Held inside the range the curves interpolate across. Past 100 the lerps run
## off the end of their own curve and come back with negative scatter, which is
## not "extremely stable", it is a cone that inverts.
func _steadiness() -> float:
	return minf(stability * STABILITY_SCALE, 100.0)


## Upward aim kick per shot, in radians. The whole of the recoil stat: point the
## gun higher, every shot, by an amount you can predict and correct for.
func get_kick_per_shot() -> float:
	return deg_to_rad(lerpf(0.25, 6.0, _climb() * 0.01)) * kick_scale


## Ceiling on accumulated climb, so a long burst tops out instead of pointing at
## the sky. Set high enough that a full magazine walks the reticle well clear of
## where it started - the climb is meant to be fought, not shrugged off.
func get_max_kick() -> float:
	return deg_to_rad(lerpf(4.0, 42.0, _climb() * 0.01)) * kick_scale


## Shove applied to the shooter, px/s of horizontal velocity.
func get_knockback() -> float:
	return lerpf(0.0, 42.0, _climb() * 0.01) * kick_scale




# --- stability (the scatter) --------------------------------------------------

## Camera shake per shot, in pixels. The same unsteadiness that opens the cone
## rattles the screen: an unstable gun is hard to watch as well as hard to
## place, while a stable one barely moves the picture. Scaled by shake_scale, so
## a heavy round can hit hard without also being sprayed all over the place.
func get_shake() -> float:
	return lerpf(9.5, 0.8, stability * 0.01) * shake_scale * SHAKE_BOOST


## Cone growth per shot. Low stability is what makes a burst wander off on its
## own instead of simply climbing.
func get_bloom_per_shot() -> float:
	return deg_to_rad(lerpf(0.95, 0.04, _steadiness() * 0.01))


## Ceiling on accumulated scatter, so spraying plateaus instead of exploding.
func get_max_bloom() -> float:
	return deg_to_rad(lerpf(4.8, 0.45, _steadiness() * 0.01))


## Bloom decay, radians per second.
func get_bloom_recovery() -> float:
	return deg_to_rad(lerpf(3.0, 30.0, _steadiness() * 0.01))


## Kick recovery rate for exponential settling, 1/seconds. Kept low on purpose:
## a muzzle that snaps back the instant you stop firing costs you nothing, so
## the climb has to hang around long enough to be worth fighting.
func get_kick_recovery() -> float:
	return lerpf(0.9, 4.5, _steadiness() * 0.01)


## Grace period after the last shot before recovery starts, so a burst does not
## reset itself between rounds.
func get_recovery_delay() -> float:
	return lerpf(0.6, 0.2, stability * 0.01)


# --- handling ---------------------------------------------------------------

## How fast the gun swings toward where you point, radians per second.
##
## This is what mouse sensitivity means here: the gun follows the pointer at a
## speed, it does not snap to it, so a heavy weapon lags the mouse. The scale is
## separate from handling because handling also drives swap time, reload speed
## and movement - making a scope heavy to aim should not also make it slow to
## put away.
func get_aim_speed() -> float:
	return lerpf(5.0, 26.0, handling * 0.01) * aim_speed_scale


## Seconds after a weapon swap before the gun can fire.
func get_equip_time() -> float:
	return lerpf(0.9, 0.18, handling * 0.01)


func get_reload_duration() -> float:
	return reload_time * lerpf(1.3, 0.8, handling * 0.01)


## Heavy guns slow you down. A wide range on purpose: this is the stat you are
## meant to feel the moment you swap from the SMG to the LMG.
func get_move_multiplier() -> float:
	return lerpf(0.55, 1.12, handling * 0.01)


## Heavy guns also take longer to get going and to change direction.
func get_accel_multiplier() -> float:
	return lerpf(0.55, 1.15, handling * 0.01)


## Extra cone added while running at full speed.
func get_move_penalty() -> float:
	return deg_to_rad(lerpf(6.0, 1.0, handling * 0.01))
