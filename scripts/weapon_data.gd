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
@export var damage := 26.0
@export var bullet_speed := 2800.0
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


## What one trigger pull does at point blank, buckshot included.
func get_burst_damage() -> float:
	return damage * pellets


# --- accuracy ---------------------------------------------------------------

## Half-angle of the resting cone, in radians.
func get_base_spread() -> float:
	return deg_to_rad(lerpf(9.0, 0.12, accuracy * 0.01))


# --- recoil (the climb) -------------------------------------------------------

## Upward aim kick per shot, in radians. The whole of the recoil stat: point the
## gun higher, every shot, by an amount you can predict and correct for.
func get_kick_per_shot() -> float:
	return deg_to_rad(lerpf(0.25, 6.0, recoil * 0.01)) * kick_scale


## Ceiling on accumulated climb, so a long burst tops out instead of pointing at
## the sky. Set high enough that a full magazine walks the reticle well clear of
## where it started - the climb is meant to be fought, not shrugged off.
func get_max_kick() -> float:
	return deg_to_rad(lerpf(4.0, 42.0, recoil * 0.01)) * kick_scale


## Shove applied to the shooter, px/s of horizontal velocity.
func get_knockback() -> float:
	return lerpf(0.0, 42.0, recoil * 0.01) * kick_scale




# --- stability (the scatter) --------------------------------------------------

## Camera shake per shot, in pixels. The same unsteadiness that opens the cone
## rattles the screen: an unstable gun is hard to watch as well as hard to
## place, while a stable one barely moves the picture. Scaled by shake_scale, so
## a heavy round can hit hard without also being sprayed all over the place.
func get_shake() -> float:
	return lerpf(9.5, 0.8, stability * 0.01) * shake_scale


## Cone growth per shot. Low stability is what makes a burst wander off on its
## own instead of simply climbing.
func get_bloom_per_shot() -> float:
	return deg_to_rad(lerpf(0.95, 0.04, stability * 0.01))


## Ceiling on accumulated scatter, so spraying plateaus instead of exploding.
func get_max_bloom() -> float:
	return deg_to_rad(lerpf(4.8, 0.45, stability * 0.01))


## Bloom decay, radians per second.
func get_bloom_recovery() -> float:
	return deg_to_rad(lerpf(3.0, 30.0, stability * 0.01))


## Kick recovery rate for exponential settling, 1/seconds. Kept low on purpose:
## a muzzle that snaps back the instant you stop firing costs you nothing, so
## the climb has to hang around long enough to be worth fighting.
func get_kick_recovery() -> float:
	return lerpf(0.9, 4.5, stability * 0.01)


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
