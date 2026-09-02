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


## The gun as it comes out of the workshop.
##
## Order does not matter: every delta is a sum and every scale is a product, so
## two parts commute and there is no "apply the stock first" rule to get wrong.
## Deltas are clamped only at the end, on the finished numbers, so a part that
## takes stability to -3 and another that puts +20 back is worth exactly what the
## arithmetic says rather than being quietly floored in the middle.
static func build(base: WeaponData, parts: Array) -> WeaponData:
	if base == null:
		return null
	if parts.is_empty():
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
