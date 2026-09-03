class_name Gunsmith
extends RefCounted

## Where a gun and the parts bolted to it are added up.
##
## The trick this whole feature rests on is that an attached gun is still just a
## WeaponData. build() takes the catalogue resource, duplicates it, folds every
## part's numbers into the copy, and hands back something the rest of the game
## cannot tell from a gun that came off the shelf that way. Nothing downstream
## learns about attachments: the bullet, the recoil curve, the damage graph on
## the shop card, the HUD's ammo count and the AI's idea of how loud you are all
## read the same fields they always did, and all of them are now the modified
## ones.
##
## The alternative - asking "what is on this gun" at every site that reads a stat
## - would have meant touching firing, spread, reload, noise, footprint and every
## piece of UI that draws a number, and leaving a permanent trap where the next
## one gets forgotten. This way there is exactly one place to be wrong.
##
## The original is never modified. Item keeps `base_weapon` pointing at the
## catalogue resource and `weapon` at the built copy, so taking a part off is
## rebuilding from the original rather than trying to subtract.

const SHELF := {
	AttachmentData.Slot.MAGAZINE: [
		"res://resources/attachments/quickdraw_mag.tres",
		"res://resources/attachments/extended_mag.tres",
		"res://resources/attachments/drum_mag.tres",
	],
	AttachmentData.Slot.MUZZLE: [
		"res://resources/attachments/compensator.tres",
		"res://resources/attachments/muzzle_brake.tres",
		"res://resources/attachments/suppressor.tres",
	],
	AttachmentData.Slot.OPTIC: [
		"res://resources/attachments/red_dot.tres",
		"res://resources/attachments/holo_2x.tres",
		"res://resources/attachments/marksman_4x.tres",
		"res://resources/attachments/sniper_scope.tres",
	],
	AttachmentData.Slot.GRIP: [
		"res://resources/attachments/laser_sight.tres",
		"res://resources/attachments/vertical_grip.tres",
		"res://resources/attachments/angled_grip.tres",
	],
	AttachmentData.Slot.STOCK: [
		"res://resources/attachments/light_stock.tres",
		"res://resources/attachments/heavy_stock.tres",
		"res://resources/attachments/folding_stock.tres",
	],
}

## How much of an optic's nominal power the camera actually gives you.
##
## A four power scope does not pull the camera back four times, and it should not.
## Taken literally it did: the aimed view went to 4.3 times the standing one, the
## character came out about five pixels tall, and the difference between a 2x and
## a 4x stopped reading as *double* because both were already past the point where
## you could tell what you were looking at. Magnification in a game seen from the
## side is a widening, and a widening has a useful range that a rifle scope's
## marketing number blows straight past.
##
## So the power is a name and this is the exchange rate. Each point of it widens
## the view by a bit over a third, which keeps the steps between the three optics
## clearly apart while leaving a person legible at the far end of the shot.
const SCOPE_GAIN := 0.35
## And a floor, because the sniper starts wide before any glass goes on it: with
## a 4x it would otherwise land somewhere you cannot pick a body out of the
## background, which is not a scope, it is a map screen.
const SCOPE_FLOOR := 0.26

## The order the five slots are drawn and stored in.
const SLOTS := [
	AttachmentData.Slot.OPTIC,
	AttachmentData.Slot.MUZZLE,
	AttachmentData.Slot.MAGAZINE,
	AttachmentData.Slot.GRIP,
	AttachmentData.Slot.STOCK,
]

## The six tiers of energy cell, cheapest first. Not filed by weapon the way
## SHELF above is - every gun looks at the same six cells and
## EnergyCellData.fits() does the filtering, because what a cell fits is a
## question about its tier next to the gun's own, not about calibre or a
## rail it bolts to.
const ENERGY_SHELF := [
	"res://resources/energy/tier1_cell.tres",
	"res://resources/energy/tier2_cell.tres",
	"res://resources/energy/tier3_cell.tres",
	"res://resources/energy/tier4_cell.tres",
	"res://resources/energy/tier5_cell.tres",
	"res://resources/energy/tier6_cell.tres",
]

## What running a gun `delta` tiers over its own base costs it, index 0..2.
## Zero at index 0 on purpose - a same-tier cell is what the gun already reads
## as on the shelf, exactly the way an unmodified WeaponData is.
##
## Escalating rather than linear, and deliberately so: doubling every delta-1
## number would have made delta 2 nothing but "the same trade, more of it,"
## and the brief was for two genuinely different decisions - one tier over is
## a real, respectable trade, two tiers over is an aggressive commitment. So
## every row below jumps further from index 1 to index 2 than it did from 0
## to 1, which is what makes the second overtier feel like a different choice
## rather than a bigger version of the first one.
## Recoil in particular got a second pass: a gun on an overtiered cell is
## meant to feel like it is fighting you, not politely climbing a bit faster,
## so the climb itself has to be a bigger part of the trade than the other
## four numbers are.
const ENERGY_RECOIL_DELTA := [0.0, 16.0, 40.0]
const ENERGY_STABILITY_DELTA := [0.0, -8.0, -21.0]
## Accuracy is the resting cone - see WeaponData.get_base_spread() - so this
## going down is the spread opening up, the same sense every other accuracy
## number on a card already reads in.
const ENERGY_ACCURACY_DELTA := [0.0, -6.0, -16.0]
const ENERGY_LOUDNESS_DELTA := [0.0, 3.0, 8.0]
const ENERGY_DAMAGE_SCALE := [1.0, 1.08, 1.22]
const ENERGY_SPEED_SCALE := [1.0, 1.12, 1.30]


## Everything on the shelf for one slot that will actually go on this gun.
##
## Filtered here rather than at the till, because a shelf that lists a stock for
## a pistol and refuses to sell it has already wasted the only thing the player
## brought to it, which is attention.
static func shelf_for(which: int, gun: WeaponData) -> Array:
	var out: Array = []
	for path in SHELF.get(which, []):
		var part := load(path) as AttachmentData
		if part and part.fits(gun):
			out.append(part)
	return out


## Every cell on the shelf that will actually run this gun. Filtered here for
## the same reason shelf_for() filters the attachment shelf: offering a cell
## and refusing it at the till wastes the one thing the player brought, which
## is attention.
static func energy_shelf_for(gun: WeaponData) -> Array:
	var out: Array = []
	for path in ENERGY_SHELF:
		var cell := load(path) as EnergyCellData
		if cell and cell.fits(gun):
			out.append(cell)
	return out


## How many tiers over its own base the fitted cell is running this gun, 0 to
## 2. Clamped rather than trusted, so a cell that should never have been
## fittable in the first place - EnergyCellData.fits() is what is meant to
## stop that at the bench - still cannot push a gun's stats past what two
## tiers over is supposed to mean.
static func energy_delta(base: WeaponData, energy: EnergyCellData) -> int:
	if base == null or energy == null:
		return 0
	return clampi(energy.tier - base.base_tier, 0, 2)


## The lines a cell's card prints under it, in the same [text, good] shape
## effect_lines() below returns for a part - good decides the colour, and a
## same-tier cell says so rather than printing six zeroes.
static func energy_effect_lines(base: WeaponData, energy: EnergyCellData) -> Array:
	var out: Array = []
	if base == null or energy == null:
		return out
	var delta := energy_delta(base, energy)
	if delta <= 0:
		out.append(["stock tier - no change, no heat", true])
		return out
	out.append(["damage %+.0f%%" % ((ENERGY_DAMAGE_SCALE[delta] - 1.0) * 100.0), true])
	out.append(["bullet speed %+.0f%%" % ((ENERGY_SPEED_SCALE[delta] - 1.0) * 100.0), true])
	out.append(["recoil %+.0f" % -ENERGY_RECOIL_DELTA[delta], false])
	out.append(["stability %+.0f" % ENERGY_STABILITY_DELTA[delta], false])
	out.append(["accuracy %+.0f" % ENERGY_ACCURACY_DELTA[delta], false])
	out.append(["noise %+.0f dB" % ENERGY_LOUDNESS_DELTA[delta], false])
	out.append(["builds heat while firing" if delta == 1 else
		"builds heat fast while firing", false])
	return out


## The gun as it comes out of the workshop.
##
## Order does not matter: every delta is a sum and every scale is a product, so
## two parts commute and there is no "apply the stock first" rule to get wrong.
## Deltas are clamped only at the end, on the finished numbers, so a part that
## takes stability to -3 and another that puts +20 back is worth exactly what the
## arithmetic says rather than being quietly floored in the middle.
static func build(base: WeaponData, parts: Array, energy: EnergyCellData = null) -> WeaponData:
	if base == null:
		return null
	var delta := energy_delta(base, energy)
	if parts.is_empty() and delta <= 0:
		return base
	var gun: WeaponData = base.duplicate()
	# A duplicate keeps the original's resource_path, which would make it
	# indistinguishable from the catalogue copy to anything that saves or sends
	# one. Cleared, so `to_wire` reaches for base_weapon instead and a modified
	# gun cannot be mistaken for a stock one.
	gun.resource_path = ""

	var mag := float(base.mag_size)
	var mag_extra := 0
	for part in parts:
		var it := part as AttachmentData
		if it == null:
			continue
		gun.accuracy += it.accuracy_delta
		gun.handling += it.handling_delta
		gun.recoil += it.recoil_delta
		gun.stability += it.stability_delta

		mag *= it.mag_scale
		mag_extra += it.mag_delta
		gun.reload_time *= it.reload_scale

		gun.ads_zoom /= view_gain(it.magnify)
		gun.ads_speed_scale *= it.ads_speed_scale
		gun.aim_speed_scale *= it.aim_speed_scale
		gun.scope_glint = gun.scope_glint or it.adds_glint

		gun.suppressed = gun.suppressed or it.suppresses
		gun.loudness_trim += it.loudness_delta
		gun.damage *= it.damage_scale
		gun.falloff_start *= it.falloff_scale
		gun.falloff_end *= it.falloff_scale

		gun.grid_size.x += it.cells_delta

	# The energy cell folds in the same way a part does - deltas added, scales
	# multiplied, clamped once at the end alongside everything the parts did -
	# which is what lets a suppressor and an overtiered cell sit on the same
	# gun and add up rather than fight over who clamps last.
	if delta > 0:
		gun.recoil += ENERGY_RECOIL_DELTA[delta]
		gun.stability += ENERGY_STABILITY_DELTA[delta]
		gun.accuracy += ENERGY_ACCURACY_DELTA[delta]
		gun.loudness_trim += ENERGY_LOUDNESS_DELTA[delta]
		gun.damage *= ENERGY_DAMAGE_SCALE[delta]
		gun.bullet_speed *= ENERGY_SPEED_SCALE[delta]

	gun.accuracy = clampf(gun.accuracy, 0.0, 100.0)
	gun.handling = clampf(gun.handling, 0.0, 100.0)
	gun.recoil = clampf(gun.recoil, 0.0, 100.0)
	gun.stability = clampf(gun.stability, 0.0, 100.0)
	# One round is the floor. A magazine that scales to nothing is not a trade,
	# it is a gun that cannot be fired.
	gun.mag_size = maxi(roundi(mag) + mag_extra, 1)
	gun.reload_time = maxf(gun.reload_time, 0.2)
	gun.ads_zoom = clampf(gun.ads_zoom, SCOPE_FLOOR, 4.0)
	gun.loudness_trim = clampf(gun.loudness_trim, -24.0, 12.0)
	gun.grid_size.x = maxi(gun.grid_size.x, 1)
	return gun


## How much wider a scope of this power makes the aimed view. One is unchanged.
static func view_gain(magnify: float) -> float:
	return maxf(1.0 + (magnify - 1.0) * SCOPE_GAIN, 0.05)


## What the parts on a gun cost, all in. Used to price a gun on a body and to
## refund a whole rig at once.
static func parts_value(parts: Array) -> int:
	var total := 0
	for part in parts:
		if part is AttachmentData:
			total += (part as AttachmentData).price
	return total


## The lines the gunsmith prints under a part: what it does, in plain numbers,
## better first.
##
## Built off the part rather than off the difference between two built guns, so a
## card reads the same wherever it is shown and a part that does nothing to this
## particular gun still says what it is for. Each entry is [text, good], and
## `good` is what decides the colour - which is the only reason this is not just
## a list of strings, because "recoil -12" is an improvement and "reload +18%" is
## not, and no reader should have to remember which dials are backwards.
static func effect_lines(part: AttachmentData) -> Array:
	var out: Array = []
	if part == null:
		return out
	_dial(out, "accuracy", part.accuracy_delta)
	_dial(out, "handling", part.handling_delta)
	# Recoil is the climb, so less of it is better - the sign is flipped for the
	# reader, not for the maths.
	if not is_zero_approx(part.recoil_delta):
		out.append(["recoil %+.0f" % -part.recoil_delta, part.recoil_delta < 0.0])
	_dial(out, "stability", part.stability_delta)

	if not is_equal_approx(part.mag_scale, 1.0):
		out.append(["magazine %+.0f%%" % ((part.mag_scale - 1.0) * 100.0),
			part.mag_scale > 1.0])
	if part.mag_delta != 0:
		out.append(["magazine %+d" % part.mag_delta, part.mag_delta > 0])
	if not is_equal_approx(part.reload_scale, 1.0):
		out.append(["reload %+.0f%%" % ((part.reload_scale - 1.0) * 100.0),
			part.reload_scale < 1.0])
	if not is_equal_approx(part.magnify, 1.0):
		# What the camera will actually do, not what is written on the tube. A
		# card that promises four and delivers two is worse than one that says
		# two, however good the four looks on the shelf.
		out.append(["%.2fx the view" % view_gain(part.magnify), part.magnify > 1.0])
	if not is_equal_approx(part.ads_speed_scale, 1.0):
		out.append(["aim speed %+.0f%%" % ((part.ads_speed_scale - 1.0) * 100.0),
			part.ads_speed_scale > 1.0])
	if not is_equal_approx(part.aim_speed_scale, 1.0):
		out.append(["handling speed %+.0f%%" % ((part.aim_speed_scale - 1.0) * 100.0),
			part.aim_speed_scale > 1.0])
	if not is_equal_approx(part.damage_scale, 1.0):
		out.append(["damage %+.0f%%" % ((part.damage_scale - 1.0) * 100.0),
			part.damage_scale > 1.0])
	if not is_equal_approx(part.falloff_scale, 1.0):
		out.append(["range %+.0f%%" % ((part.falloff_scale - 1.0) * 100.0),
			part.falloff_scale > 1.0])
	if part.suppresses:
		out.append(["suppressed - no report, no marker", true])
	elif not is_zero_approx(part.loudness_delta):
		out.append(["noise %+.0f dB" % part.loudness_delta, part.loudness_delta < 0.0])
	if part.adds_glint:
		out.append(["throws a scope glint", false])
	if part.cells_delta != 0:
		out.append(["%+d cell in the bag" % part.cells_delta, part.cells_delta < 0])
	return out


static func _dial(out: Array, name: String, delta: float) -> void:
	if not is_zero_approx(delta):
		out.append(["%s %+.0f" % [name, delta], delta > 0.0])
