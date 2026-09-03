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

@export_group("Energy")
## The tier of energy cell this gun ships on. See EnergyCellData for what a
## tier is; the short version is that a cell at this number or up to two above
## it will run the gun, and nothing below it will. Fixed per weapon rather
## than picked freely, the same way ammo_type is - a pistol was never going to
## take the same cell as an LMG, and the four values this actually holds
## (pistol 1, SMG/shotgun 2, AR/slug 3, LMG/sniper 4) are the whole reason the
## tier system has six rungs and not four: the top two only exist as
## somewhere for every gun to overclock into.
@export_range(1, 4) var base_tier := 1
## Thermal mass, 0 to 100 - not "how good", the way every other dial on this
## resource reads, but "how heavy the gun's own heat system is", and both
## halves of what that means point the same way. A high number is an LMG: it
## takes a long, sustained overtiered burst to bring one up to a lock at all,
## and once it is hot it stays hot, because that much metal does not shed
## heat quickly either - running one two tiers over is a commitment to a
## style of play, not a button you tap. A low number is an SMG: light enough
## to spike and drop in the same couple of seconds, so it punishes and
## forgives fast rather than slow. See get_heat_per_shot, get_heat_recovery
## and get_heat_recovery_delay - all three read this dial in the same
## direction - and Gunsmith's ENERGY_* constants for the tier deltas the
## result is scaling.
@export_range(0.0, 100.0) var heat_capacity := 55.0

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


# --- overheat -----------------------------------------------------------------
#
# Only ever asked about while `delta` (how many tiers over base the fitted cell
# is) is 1 or 2 - a same-tier cell never calls into any of this, because there
# is nothing for it to build. See Weapon.gd's `heat` field for where these
# numbers actually get used, and Gunsmith.energy_delta for where `delta` comes
# from.
#
# heat_capacity is the one hand-tuned dial, in the same shape every other stat
# on this resource is: a 0-100 knob a designer sets per gun, turned into a
# gameplay number by a curve rather than typed in directly. The alternative -
# deriving heat entirely from rounds_per_minute and mag_size - was the other
# option and it was the wrong one for this codebase specifically: every other
# number on this file is authored, not computed, because a designer needs to
# be able to say "the LMG should feel deliberately harder to overheat than its
# fire rate alone would suggest" without fighting a formula to get there. A
# derived number can't be handed an opinion; this one can.

## Delta 2 does not build heat twice as fast as delta 1 - it builds it two and
## a half times as fast. See Gunsmith's own ENERGY_* comment for why the stat
## curve escalates rather than doubles between the two overtiers, and this is
## the same shape applied to heat: one tier over should read as a real trade,
## two tiers over should read as a different, more reckless decision, and a
## flat multiplier would have made the second tier just a bigger first one.
const HEAT_DELTA2_MULT := 2.5

## Delta 1's own reading of the base curve - not "softened" against it any
## more, that undershot: an AR (heat_capacity 45) one tier over is
## calibrated to lock at exactly 20 rounds, and solving that backwards
## against the base curve below is what actually sets this, whichever side
## of 1.0 it lands on. It is still the gentler of the two overtiers - 2.5
## against 1.15 is still a real escalation to delta 2 - it just is not
## gentle enough to read as "barely notice it for most of a magazine".
const HEAT_DELTA1_MULT := 1.15

## How far an automatic has to cool from a hard lock before it can fire again,
## as a fraction of max heat. Not all the way to zero - see try_fire() in
## weapon.gd - because "vent completely" and "vent enough to trust it again"
## are different asks, and demanding the first turns every lockout into the
## same fixed pause regardless of how the gun got there. One flat threshold
## for both overtiers now rather than two different ones - the thing that
## makes delta 2 the harsher lock is not a deeper vent, it is getting there
## faster and cooling slower once it has, both of which already live
## elsewhere (get_heat_per_shot, get_heat_recovery) - so a second knob here
## saying the same thing again was just a number to keep in sync with those.
const HEAT_UNLOCK_FRACTION := 0.25

## How much longer a semi-auto's own chamber cooldown runs at full heat, as a
## multiple of its ordinary get_shot_interval(). 1.6x at delta 1, 2.5x at
## delta 2 - a real tax on spamming an overtiered bolt gun, never a wall: see
## try_fire(), which always lets the shot go the instant the (now longer)
## cooldown ends.
const HEAT_STRETCH_CAP := [0.0, 0.6, 1.5]


## A semi-auto has no lock to punish it the slow way an automatic's hundred-
## round mag does - see try_fire() in weapon.gd, which never sets
## heat_locked for one. A handful of shots is the whole magazine on most of
## these guns, so the bar has to move fast enough to matter within two or
## three pulls of the trigger, not dozens the way an automatic's does.
## Calibrated the same way HEAT_DELTA2_MULT was: a sniper (heat_capacity 35)
## on a cell two tiers over its own reaches the ceiling in exactly two
## consecutive shots, which is what solving this backwards against the base
## curve below sets it to.
const SEMI_HEAT_MULT := 4.2

## Heat added per shot fired on an overtiered cell, 0 to 1 against a max of 1.
## `delta` must be 1 or 2; callers on a same-tier cell should never reach here.
##
## Calibrated off two concrete cases rather than picked in the abstract: an
## SMG (heat_capacity 30) two tiers over its own tier - a T4 cell, delta 2 -
## gets a full eight rounds out before it locks, and an AR (heat_capacity 45)
## one tier over - a T4 cell, delta 1 - locks at exactly twenty. Solving
## those backwards against each other is what sets both the 0.063/0.02 range
## below and HEAT_DELTA1_MULT; everything else on the shelf is read off the
## same curve rather than tuned to its own target, so a heavier gun like the
## LMG earns proportionally more rounds at either delta and a lighter one
## earns fewer, without needing a second number per gun to keep them in
## line with each other. Semi-autos read the same curve again on top,
## through SEMI_HEAT_MULT - a different shot count needs a different
## multiplier, not a different curve.
func get_heat_per_shot(delta: int) -> float:
	if delta <= 0:
		return 0.0
	var base := lerpf(0.063, 0.02, heat_capacity * 0.01)
	var per_shot := base * (HEAT_DELTA1_MULT if delta == 1 else HEAT_DELTA2_MULT)
	return per_shot * (1.0 if automatic else SEMI_HEAT_MULT)


## How much slower heat bleeds off while an automatic is actually locked,
## against the ordinary rate below - real enough to feel, not a second wall
## on top of the first one. A jammed-feeling gun that vents at the same
## speed it was quietly cooling at all along undersells the moment; this is
## what makes reaching the lock cost more than *almost* reaching it does.
## Cut again on top of the first pass at this (0.55 - too quick to actually
## feel like a real pause) down to little over a third of the ordinary rate.
const LOCKED_HEAT_RECOVERY_SCALE := 0.35

## Heat lost per second once the recovery delay below has passed. Not scaled
## by delta - venting is a property of the gun, not of how it got hot - so the
## whole difference between a bad and a brutal overtier is on the way in,
## through get_heat_per_shot, and on how far it has to fall before an
## automatic trusts it again, through get_heat_unlock_threshold. Scaled by
## `locked` instead, through LOCKED_HEAT_RECOVERY_SCALE - see its own comment.
##
## Reads heat_capacity the same direction get_heat_per_shot does, not the
## opposite one: a high-mass gun that took a long time to heat up also takes
## a long time to cool, the same way a real barrel does, so this goes down
## as capacity goes up rather than up.
func get_heat_recovery(locked := false) -> float:
	var rate := lerpf(0.42, 0.10, heat_capacity * 0.01)
	return rate * LOCKED_HEAT_RECOVERY_SCALE if locked else rate


## Grace period after the last shot before heat starts falling, mirroring
## get_recovery_delay() above - a burst does not get to vent between rounds
## just because the trigger let up for a single frame. Longer for a
## high-mass gun for the same reason get_heat_recovery() is slower for one:
## heat that took a while to build does not start leaving the instant the
## trigger does.
##
## Floored at 1.15x this gun's own get_shot_interval() *at its most stretched*
## - HEAT_STRETCH_CAP's own ceiling of 2.5 - rather than at the bare
## interval, which is the half of this formula that actually makes the
## semi-auto side of the feature work. Without it, a slow single-shot gun -
## the sniper is the case that exposed this, twice - has a natural interval
## longer than the capacity-based delay above, so firing it back-to-back as
## fast as it legally allows would always leave enough of a gap for full
## recovery between shots, and heat could never accumulate under ordinary
## rapid fire at all: the mechanic would be a bar that is never seen. Using
## the bare interval fixed that for a *cold* gun, but a gun that is already
## hot sets its own trap back up - a stretched cooldown is itself a longer
## gap, so as heat climbed the very cooldown it bought started to hand heat
## back before the next shot. Flooring against the worst case a stretch can
## reach closes that: firing at every legal opportunity, at any heat, never
## gives a semi-auto enough of a gap to vent, so heat only ever drains when a
## player deliberately holds off past their own trigger's natural rhythm -
## the "spaced, deliberate shots barely trigger this, quickscoping does"
## split the feature asks for, now true at the top of the bar as well as the
## bottom of it. An automatic's own interval is always far below its
## capacity-based delay - the trigger is held, not tapped - so the floor
## never engages for one and this changes nothing about how those behave.
func get_heat_recovery_delay() -> float:
	return maxf(lerpf(0.5, 1.1, heat_capacity * 0.01),
		get_shot_interval() * (1.0 + HEAT_STRETCH_CAP[2]) * 1.15)


## Where a locked gun's trigger un-refuses, whichever class it is. Heat
## still has to fall this far even though the trigger is no longer adding to
## it. Takes `delta` for the
## callers that already have one to hand - see try_fire() in weapon.gd - but
## reads the same flat threshold whichever tier bought the lock; see the
## header comment on HEAT_UNLOCK_FRACTION for why that stopped needing to
## vary by delta.
func get_heat_unlock_threshold(_delta: int) -> float:
	return HEAT_UNLOCK_FRACTION


## The most a semi-auto's chamber cooldown will stretch at full heat, `delta`
## tiers over base - see try_fire() in weapon.gd for where this actually
## multiplies get_shot_interval().
func get_heat_stretch_cap(delta: int) -> float:
	return HEAT_STRETCH_CAP[clampi(delta, 0, 2)]
