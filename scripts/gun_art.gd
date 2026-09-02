class_name GunArt
extends RefCounted

## Draws a gun side-on, with whatever is bolted to it.
##
## The point of the gunsmith is that you can see what you built. A list of parts
## with plus and minus numbers next to them is a spreadsheet; a gun that visibly
## grows a can on the front and a drum underneath is a thing you made, and the
## difference between those two is most of why anybody enjoys this screen.
##
## Everything is drawn from numbers rather than from art files. Each gun is six
## measurements - how long the receiver is, how far the barrel sticks out, where
## the magazine hangs - and the silhouette is assembled from those, which means a
## new weapon needs a row in PROFILES and no artist. It also means the mounting
## points are known rather than guessed: a suppressor goes on the end of the
## barrel because the profile says where the end of the barrel is.
##
## Gun space has the muzzle toward +x and up toward -y, with the origin at the
## back of the receiver on the bore line. The caller scales it.

## Six numbers per gun, and a name to find them by.
##
##   receiver  the body, from the origin forward
##   barrel    how far past the receiver the barrel runs, and how thick
##   guard     the handguard's length, measured back from the barrel
##   grip_at   where the pistol grip hangs, along the receiver
##   mag_at    where the magazine hangs, along the receiver
##   stock     how far back the stock reaches, zero for none
##
## The shapes are deliberately blunt. A silhouette this size reads as a class of
## weapon - long and thin is a rifle, short and deep is a shotgun - and detail
## below that is noise at the scale it will be looked at.
const PROFILES := {
	"PISTOL": {"receiver": Vector2(40.0, 12.0), "barrel": Vector2(5.0, 7.0),
		"guard": 0.0, "grip_at": 9.0, "mag_at": 11.0, "stock": 0.0, "vents": 0,
		"mark": ""},
	"SMG": {"receiver": Vector2(50.0, 14.0), "barrel": Vector2(18.0, 6.0),
		"guard": 15.0, "grip_at": 17.0, "mag_at": 31.0, "stock": 18.0, "vents": 2,
		"mark": "shroud"},
	"AR": {"receiver": Vector2(60.0, 14.0), "barrel": Vector2(38.0, 5.0),
		"guard": 26.0, "grip_at": 18.0, "mag_at": 36.0, "stock": 24.0, "vents": 4,
		"mark": "carry"},
	"SHOTGUN": {"receiver": Vector2(54.0, 16.0), "barrel": Vector2(44.0, 8.0),
		"guard": 30.0, "grip_at": 16.0, "mag_at": 0.0, "stock": 26.0, "vents": 0,
		"mark": "tube"},
	"SLUG": {"receiver": Vector2(54.0, 16.0), "barrel": Vector2(48.0, 7.0),
		"guard": 30.0, "grip_at": 16.0, "mag_at": 0.0, "stock": 26.0, "vents": 0,
		"mark": "tube"},
	"LMG": {"receiver": Vector2(72.0, 18.0), "barrel": Vector2(46.0, 6.0),
		"guard": 20.0, "grip_at": 20.0, "mag_at": 42.0, "stock": 26.0, "vents": 5,
		"mark": "bipod"},
	"SNIPER": {"receiver": Vector2(66.0, 13.0), "barrel": Vector2(62.0, 4.5),
		"guard": 20.0, "grip_at": 20.0, "mag_at": 40.0, "stock": 32.0, "vents": 2,
		"mark": "bolt"},
	"GRD": {"receiver": Vector2(56.0, 13.0), "barrel": Vector2(30.0, 5.0),
		"guard": 22.0, "grip_at": 18.0, "mag_at": 33.0, "stock": 20.0, "vents": 3,
		"mark": ""},
}
## Anything not in the table is drawn as a rifle rather than as nothing.
const FALLBACK := "AR"

## How far the rail stands proud of the receiver, and how far the handguard hangs
## below the bore. Both are used twice - once to draw the gun and once to work out
## where a part bolts to it - so they are named rather than typed out in each
## place and left to drift apart.
const RAIL_H := 1.6
const GUARD_DEPTH := 4.5
## How high an optic's mounts stand it off the rail. Enough to clear the iron
## sight it replaces, and no more - a scope floating a centimetre above the gun
## is the first thing anybody notices.
const OPTIC_LIFT := 2.5

## Steel, and the line drawn round it. Two greys and no more: the parts are the
## colourful things on this screen and the gun they hang off should not compete.
const METAL := Color(0.29, 0.32, 0.38)
const EDGE := Color(0.52, 0.57, 0.65)


static func profile(gun: WeaponData) -> Dictionary:
	if gun == null:
		return PROFILES[FALLBACK]
	return PROFILES.get(gun.short_name, PROFILES[FALLBACK])


## Where each kind of part bolts on, in gun space.
##
## Every one of these is a point on the *surface* the part sits against, not a
## centreline near it. That is the whole difference between a part that is bolted
## on and a part that is floating next to the gun: a scope wants the top of the
## rail, a foregrip wants the underside of the handguard, a magazine wants the
## bottom of the magwell, and a muzzle device wants the flat end of the barrel.
## Getting these from the same numbers the gun is drawn from is what makes them
## line up at every zoom instead of at the one somebody eyeballed.
##
## Public because the parts are drawn against them and because a test can then
## ask "does this land on the gun" without looking at a canvas.
static func mounts(gun: WeaponData) -> Dictionary:
	var p := profile(gun)
	var body: Vector2 = p["receiver"]
	var barrel: Vector2 = p["barrel"]
	# The rail's top face, which is the notch strip standing 1.6 off the receiver.
	var rail_top := -body.y * 0.5 - RAIL_H
	# The handguard's underside, where a foregrip clamps. A gun with no handguard
	# - a pistol - has only the barrel to hang one under.
	var under: float = barrel.y * 0.5 + (GUARD_DEPTH if p["guard"] > 0.0 else 1.0)
	return {
		AttachmentData.Slot.MUZZLE: Vector2(body.x + barrel.x, 0.0),
		AttachmentData.Slot.OPTIC: Vector2(body.x * 0.44, rail_top),
		AttachmentData.Slot.MAGAZINE: Vector2(
			p["mag_at"] if p["mag_at"] > 0.0 else body.x * 0.5, body.y * 0.5),
		AttachmentData.Slot.GRIP: Vector2(body.x + barrel.x * 0.30, under),
		AttachmentData.Slot.STOCK: Vector2(0.0, 0.0),
	}


## How much room this gun needs, drawn: length, depth, and how far it reaches
## behind the origin.
##
## One function rather than three because everywhere that draws a gun has to
## scale it to a box first, and three separate answers to "how big is it" is
## three places for a suppressed sniper to hang off the end of its panel. Packed
## into a Vector3 so callers get all of it in one call: x is the whole length
## including anything screwed to the muzzle, y the depth including whatever hangs
## under it, and z how much of x is behind the receiver.
static func span(gun: WeaponData, parts: Array) -> Vector3:
	var p := profile(gun)
	var body: Vector2 = p["receiver"]
	var barrel: Vector2 = p["barrel"]
	var behind: float = p["stock"]
	var ahead := 0.0
	var below := 22.0
	for part in parts:
		var it := part as AttachmentData
		if it == null:
			continue
		match it.slot:
			AttachmentData.Slot.STOCK:
				behind = maxf(behind, it.art_size.x)
			AttachmentData.Slot.MUZZLE:
				ahead += it.art_size.x
			AttachmentData.Slot.MAGAZINE:
				below = maxf(below, it.art_size.y * 1.8)
	return Vector3(body.x + barrel.x + ahead + behind, body.y + 20.0 + below, behind)


## The gun and everything on it, drawn into `canvas` with the bore line running
## through `at`.
##
## `parts` is whatever is bolted on; passing an empty array draws the bare gun,
## which is how the shelf previews what you have not bought yet.
static func draw_gun(canvas: CanvasItem, at: Vector2, zoom: float,
		gun: WeaponData, parts: Array) -> void:
	if gun == null:
		return
	var p := profile(gun)
	var body: Vector2 = p["receiver"]
	var barrel: Vector2 = p["barrel"]

	# What is bolted on decides what of the gun itself gets drawn: a stock
	# attachment *replaces* the stock rather than being screwed to the back of
	# it, and a magazine replaces the magazine. Drawing both is how you end up
	# with two stocks overlapping, which reads as a rendering fault rather than
	# as a gun.
	var has_stock := false
	var has_mag := false
	for part in parts:
		var it := part as AttachmentData
		if it == null:
			continue
		has_stock = has_stock or it.slot == AttachmentData.Slot.STOCK
		has_mag = has_mag or it.slot == AttachmentData.Slot.MAGAZINE

	# Back to front, the way it would be assembled: stock, barrel, handguard,
	# receiver, then the things that hang off it.
	if p["stock"] > 0.0 and not has_stock:
		var stock_len: float = p["stock"]
		# A comb along the top and a butt plate at the back, rather than one
		# wedge. Two extra polygons, and it stops reading as a doorstop.
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(0.0, -body.y * 0.40), Vector2(0.0, body.y * 0.34),
			Vector2(-stock_len * 0.72, body.y * 0.50),
			Vector2(-stock_len, body.y * 0.46),
			Vector2(-stock_len, -body.y * 0.30),
			Vector2(-stock_len * 0.60, -body.y * 0.40)]))
		_shape(canvas, at, zoom, _box(-stock_len - 1.5, -body.y * 0.30,
			3.0, body.y * 0.76), METAL.darkened(0.18), EDGE)

	# The barrel, with a step down to a thinner muzzle end - a straight tube all
	# the way reads as a pipe.
	_shape(canvas, at, zoom, _box(body.x, -barrel.y * 0.5, barrel.x * 0.58, barrel.y))
	_shape(canvas, at, zoom, _box(body.x + barrel.x * 0.55, -barrel.y * 0.42,
		barrel.x * 0.45, barrel.y * 0.84))
	# The front sight post. Square, and no taller than the barrel is thick: the
	# slanted version of this read as a little flag on the end of the gun, which
	# is the sort of thing the eye trips over and cannot name.
	var post := maxf(barrel.y * 0.55, 2.2)
	_shape(canvas, at, zoom,
		_box(body.x + barrel.x - 5.0, -barrel.y * 0.36 - post, 2.4, post))
	# A gas block under it, which is also what stops a long barrel reading as a
	# length of wire with a gun on the end.
	_shape(canvas, at, zoom, _box(body.x + barrel.x * 0.62, -barrel.y * 0.5 - 1.2,
		5.0, barrel.y + 2.4))

	# The handguard, with vents cut in it. The vents are most of what separates
	# an LMG from a shotgun at this size.
	if p["guard"] > 0.0:
		var guard: float = p["guard"]
		var guard_x: float = body.x - 3.0
		_shape(canvas, at, zoom, _box(guard_x, -barrel.y * 0.5 - 3.5,
			guard, barrel.y * 0.5 + 3.5 + GUARD_DEPTH))
		var vents: int = p["vents"]
		for i in vents:
			var slot_x := guard_x + guard * (0.16 + 0.66 * (float(i) / maxf(float(vents), 1.0)))
			_shape(canvas, at, zoom,
				_box(slot_x, -barrel.y * 0.5 - 1.0, 2.0, barrel.y + 3.0),
				METAL.darkened(0.35), Color(EDGE, 0.0))

	# The receiver, with an ejection port cut into it so it has a near side, and
	# a lit edge along the top so it has a shape rather than an outline.
	_shape(canvas, at, zoom, _box(0.0, -body.y * 0.5, body.x, body.y))
	_shape(canvas, at, zoom, _box(1.0, -body.y * 0.5 + 1.0, body.x - 2.0, 1.6),
		METAL.lightened(0.16), Color(EDGE, 0.0))
	_shape(canvas, at, zoom, _box(body.x * 0.52, -body.y * 0.30,
		body.x * 0.22, body.y * 0.30), METAL.darkened(0.3), Color(EDGE, 0.35))

	# The one feature that tells this weapon apart from the others at a glance.
	# Every gun here is a receiver, a barrel and a stock, and at the size these
	# are drawn that made a shotgun and a rifle the same picture at different
	# lengths - which is no use on a screen whose whole job is telling you what
	# you are holding.
	_draw_mark(canvas, at, zoom, p)

	# The magazine before the grip, so the hand is drawn in front of the box the
	# way it sits on the real thing - and so a drum, which is wider than the gap
	# between the two, does not swallow the grip whole.
	for part in parts:
		var it := part as AttachmentData
		if it and it.slot == AttachmentData.Slot.MAGAZINE:
			draw_part(canvas, at, zoom, gun, it)
	if not has_mag and p["mag_at"] > 0.0:
		var well: Vector2 = mounts(gun)[AttachmentData.Slot.MAGAZINE]
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(well.x - 4.5, well.y), Vector2(well.x + 4.5, well.y),
			Vector2(well.x + 3.5, well.y + 15.0),
			Vector2(well.x - 6.5, well.y + 15.0)]))

	# Trigger guard and grip. The loop is a thin polygon rather than a filled
	# one, which is the cheapest way to make a gun look like a gun.
	var grip_x: float = p["grip_at"]
	var guard_y: float = body.y * 0.5
	canvas.draw_polyline(PackedVector2Array([
		at + Vector2(grip_x + 12.0, guard_y) * zoom,
		at + Vector2(grip_x + 14.0, guard_y + 7.0) * zoom,
		at + Vector2(grip_x + 6.0, guard_y + 8.5) * zoom,
		at + Vector2(grip_x + 2.0, guard_y + 4.0) * zoom]),
		EDGE, maxf(1.0, zoom * 0.5), true)
	_shape(canvas, at, zoom, PackedVector2Array([
		Vector2(grip_x, guard_y - 1.0), Vector2(grip_x + 11.0, guard_y - 1.0),
		Vector2(grip_x + 7.0, guard_y + 19.0),
		Vector2(grip_x - 4.0, guard_y + 19.0)]))

	# The rail along the top, drawn as notches, and the iron sight standing on it
	# so a gun with no optic still has something to aim with. Both hung off
	# RAIL_H, which is also what an optic mounts against - see mounts().
	for i in 5:
		_shape(canvas, at, zoom,
			_box(body.x * (0.24 + 0.10 * float(i)), -body.y * 0.5 - RAIL_H, 3.0, RAIL_H),
			METAL.lightened(0.12), Color(EDGE, 0.0))
	var rail: Vector2 = mounts(gun)[AttachmentData.Slot.OPTIC]
	if not _has(parts, AttachmentData.Slot.OPTIC):
		_shape(canvas, at, zoom, _box(rail.x - 2.0, rail.y - 3.5, 4.0, 3.5))

	# Everything else on top of the gun it is bolted to.
	for part in parts:
		var it := part as AttachmentData
		if it and it.slot != AttachmentData.Slot.MAGAZINE:
			draw_part(canvas, at, zoom, gun, it)


## What makes a shotgun look like a shotgun.
##
## One shape each, chosen for being readable rather than for being complete: a
## magazine tube under the barrel, a bipod folded down at the muzzle, a bolt
## handle standing off the receiver, a heat shroud, a carry handle.
static func _draw_mark(canvas: CanvasItem, at: Vector2, zoom: float,
		p: Dictionary) -> void:
	var body: Vector2 = p["receiver"]
	var barrel: Vector2 = p["barrel"]
	match p.get("mark", ""):
		"tube":
			# The magazine tube: a pump gun carries its shells under the barrel,
			# which is the whole reason it has no box hanging out of the middle.
			_shape(canvas, at, zoom, _box(body.x - 4.0, barrel.y * 0.5 + 1.0,
				barrel.x * 0.78, 4.5))
			# And the slide handle around it, forward of the receiver.
			_shape(canvas, at, zoom, _box(body.x + barrel.x * 0.30,
				barrel.y * 0.5 - 0.5, barrel.x * 0.26, 7.0),
				METAL.darkened(0.12), EDGE)
		"bipod":
			var foot := body.x + barrel.x * 0.82
			for lean in [-6.0, 6.0]:
				canvas.draw_line(at + Vector2(foot, barrel.y * 0.5) * zoom,
					at + Vector2(foot + lean, barrel.y * 0.5 + 16.0) * zoom,
					EDGE, maxf(1.0, zoom * 0.6))
			canvas.draw_line(at + Vector2(foot - 7.0, barrel.y * 0.5 + 16.0) * zoom,
				at + Vector2(foot + 7.0, barrel.y * 0.5 + 16.0) * zoom,
				Color(EDGE, 0.7), maxf(1.0, zoom * 0.45))
		"bolt":
			# The bolt handle, standing out of the right-hand side of the action.
			_shape(canvas, at, zoom, _box(body.x * 0.66, -body.y * 0.16, 9.0, 2.4),
				METAL.lightened(0.1), EDGE)
			_shape(canvas, at, zoom, PackedVector2Array([
				Vector2(body.x * 0.66 + 9.0, -body.y * 0.16 - 1.0),
				Vector2(body.x * 0.66 + 12.5, -body.y * 0.16 - 2.5),
				Vector2(body.x * 0.66 + 12.5, -body.y * 0.16 + 3.0),
				Vector2(body.x * 0.66 + 9.0, -body.y * 0.16 + 2.4)]),
				METAL.lightened(0.1), EDGE)
		"shroud":
			# A perforated shroud over the barrel, which is what says "cheap and
			# fast" without needing a word next to it.
			_shape(canvas, at, zoom, _box(body.x + 1.0, -barrel.y * 0.5 - 2.0,
				barrel.x * 0.62, barrel.y + 4.0), METAL.lightened(0.06), EDGE)
			for i in 4:
				canvas.draw_circle(at + Vector2(body.x + 5.0 + barrel.x * 0.13 * float(i),
					0.0) * zoom, 1.3 * zoom, METAL.darkened(0.35))
		"carry":
			# A carry handle over the rail, cut away so the sight line survives.
			_shape(canvas, at, zoom, _box(body.x * 0.22, -body.y * 0.5 - RAIL_H - 4.5,
				body.x * 0.30, 2.2), METAL.lightened(0.08), EDGE)
			for side in [body.x * 0.23, body.x * 0.47]:
				_shape(canvas, at, zoom,
					_box(side, -body.y * 0.5 - RAIL_H - 4.5, 2.0, 4.5),
					METAL.lightened(0.08), EDGE)


## One bolted-on part, drawn where it goes.
##
## Each slot has its own silhouette because each one is a different shape of
## object, and the part's own art_size is what makes a 4x scope longer than a red
## dot without either of them needing its own drawing code.
static func draw_part(canvas: CanvasItem, at: Vector2, zoom: float,
		gun: WeaponData, part: AttachmentData) -> void:
	var where: Vector2 = mounts(gun)[part.slot]
	var span := part.art_size
	var fill := Color(part.tint, 1.0)
	var line := Color(part.tint.lightened(0.35), 1.0)

	match part.slot:
		AttachmentData.Slot.MUZZLE:
			# Butted against the flat end of the barrel and centred on the bore,
			# so it reads as screwed on rather than as floating in front.
			_shape(canvas, at, zoom,
				_box(where.x - 1.0, -span.y * 0.5, span.x + 1.0, span.y), fill, line)
			# Cuts along it, which is what says "can" rather than "pipe", and a
			# collar at the back where it meets the barrel.
			_shape(canvas, at, zoom, _box(where.x - 1.5, -span.y * 0.5 - 1.0,
				3.0, span.y + 2.0), fill.darkened(0.15), line)
			for i in 3:
				var cut := where.x + span.x * (0.28 + 0.20 * float(i))
				_shape(canvas, at, zoom, _box(cut, -span.y * 0.5, 1.6, span.y),
					Color(line, 0.45), Color(line, 0.0))
		AttachmentData.Slot.OPTIC:
			# Two mounts standing on the rail, the tube sitting on top of them,
			# and a lens at the front. The mounts start exactly at the rail's top
			# face, so nothing hovers over it.
			var tube_y := where.y - OPTIC_LIFT - span.y
			for side in [-span.x * 0.34, span.x * 0.22]:
				_shape(canvas, at, zoom,
					_box(where.x + side, where.y - OPTIC_LIFT, 3.0, OPTIC_LIFT + 0.5),
					fill.darkened(0.2), line)
			_shape(canvas, at, zoom,
				_box(where.x - span.x * 0.5, tube_y, span.x, span.y), fill, line)
			# The eyepiece flares at the back and the objective at the front, so
			# it reads as glass rather than as a brick.
			_shape(canvas, at, zoom, _box(where.x - span.x * 0.5 - 1.5,
				tube_y - 1.0, 3.0, span.y + 2.0), fill.darkened(0.12), line)
			canvas.draw_circle(at + Vector2(where.x + span.x * 0.45,
				tube_y + span.y * 0.5) * zoom, span.y * 0.3 * zoom,
				Color(line, 0.9))
		AttachmentData.Slot.MAGAZINE:
			if part.short_name == "DRUM":
				_draw_drum(canvas, at, zoom, where, span, fill, line)
			else:
				# Seated in the magwell: the top edge is the magwell's own line,
				# and it tapers forward the way a box magazine does.
				_shape(canvas, at, zoom, PackedVector2Array([
					Vector2(where.x - span.x * 0.5, where.y - 1.0),
					Vector2(where.x + span.x * 0.5, where.y - 1.0),
					Vector2(where.x + span.x * 0.5 - 2.0, where.y + span.y),
					Vector2(where.x - span.x * 0.5 - 3.0, where.y + span.y)]), fill, line)
		AttachmentData.Slot.GRIP:
			if part.short_name == "LASER":
				# Clamped to the underside of the handguard, not hanging off it.
				_shape(canvas, at, zoom,
					_box(where.x, where.y - 0.5, span.x, span.y), fill, line)
				# The beam, because a laser you cannot see is a stat with no
				# picture attached to it.
				var eye := Vector2(where.x + span.x, where.y + span.y * 0.4)
				canvas.draw_line(at + eye * zoom,
					at + (eye + Vector2(52.0, 0.0)) * zoom,
					Color(0.95, 0.32, 0.34, 0.5), maxf(1.0, zoom * 0.5))
				canvas.draw_circle(at + eye * zoom, maxf(1.0, zoom * 0.7),
					Color(0.98, 0.45, 0.45, 0.9))
			elif part.short_name == "A-GRIP":
				_shape(canvas, at, zoom, PackedVector2Array([
					Vector2(where.x + span.x * 0.5, where.y - 0.5),
					Vector2(where.x + span.x * 0.5 - 1.0, where.y + span.y * 0.35),
					Vector2(where.x - span.x * 0.5, where.y + span.y),
					Vector2(where.x - span.x * 0.75, where.y + span.y * 0.55),
					Vector2(where.x - span.x * 0.5, where.y - 0.5)]), fill, line)
			else:
				# A vertical grip: a collar on the rail and a post under it.
				_shape(canvas, at, zoom, _box(where.x - span.x * 0.5 - 1.0,
					where.y - 0.5, span.x + 2.0, 2.5), fill.darkened(0.15), line)
				_shape(canvas, at, zoom, PackedVector2Array([
					Vector2(where.x - span.x * 0.5, where.y + 1.5),
					Vector2(where.x + span.x * 0.5, where.y + 1.5),
					Vector2(where.x + span.x * 0.5 - 0.6, where.y + span.y),
					Vector2(where.x - span.x * 0.5 + 0.6, where.y + span.y)]), fill, line)
		AttachmentData.Slot.STOCK:
			# Butted against the back of the receiver, with a comb along the top
			# and a plate on the end - the same shape the built-in stock has, so
			# swapping one for another changes the size and not the species.
			_shape(canvas, at, zoom, PackedVector2Array([
				Vector2(where.x, where.y - span.y * 0.5),
				Vector2(where.x, where.y + span.y * 0.42),
				Vector2(where.x - span.x * 0.7, where.y + span.y * 0.62),
				Vector2(where.x - span.x, where.y + span.y * 0.58),
				Vector2(where.x - span.x, where.y - span.y * 0.42),
				Vector2(where.x - span.x * 0.58, where.y - span.y * 0.5)]), fill, line)
			_shape(canvas, at, zoom, _box(where.x - span.x - 1.5,
				where.y - span.y * 0.42, 3.0, span.y), fill.darkened(0.2), line)


## A drum magazine, side on.
##
## Not a circle, and not parked under the pistol grip. A drum seen from the side
## of a gun is a feed tower standing in the magwell with a deep, flat-topped body
## slung under and forward of it - the top is flat because that is where it bolts
## to the tower, and the bottom is round because that is where the spring lives.
## Drawn as a plain circle it read as a ball stuck to the receiver, and centred on
## the magwell it sat straight through the grip.
static func _draw_drum(canvas: CanvasItem, at: Vector2, zoom: float,
		where: Vector2, span: Vector2, fill: Color, line: Color) -> void:
	var tower := span.x * 0.44
	var shoulder := where.y + span.y * 0.30
	# The tower: the part that is actually in the magwell, drawn first so the
	# body overlaps its lower end.
	_shape(canvas, at, zoom, PackedVector2Array([
		Vector2(where.x - tower * 0.5, where.y - 1.0),
		Vector2(where.x + tower * 0.5, where.y - 1.0),
		Vector2(where.x + tower * 0.5, shoulder + 2.0),
		Vector2(where.x - tower * 0.5, shoulder + 2.0)]), fill, line)

	# The body, hung forward of the magwell so it clears the grip behind it. Flat
	# across the top and rounded below - a D on its back rather than a wheel.
	# Forward of the magwell by a third of its own width. A drum hangs off the
	# front of the well on a real gun and it has to here too, or it is drawn
	# straight through the pistol grip behind it - which read as a satchel
	# strapped to the trigger hand.
	var hub := Vector2(where.x + span.x * 0.34, shoulder + span.y * 0.42)
	var wide := span.x * 0.62
	var deep := span.y * 0.46
	var shell := PackedVector2Array([Vector2(hub.x - wide, shoulder),
		Vector2(hub.x + wide, shoulder)])
	for i in range(1, 15):
		var turn := PI * float(i) / 14.0
		shell.append(hub + Vector2(cos(turn) * wide, sin(turn) * deep))
	_shape(canvas, at, zoom, shell, fill, line)

	# The hub and its spokes: the reason anybody reads it as a drum rather than
	# as a pouch.
	canvas.draw_circle(at + hub * zoom, deep * 0.34 * zoom, fill.darkened(0.28))
	canvas.draw_arc(at + hub * zoom, deep * 0.34 * zoom, 0.0, TAU, 16, line,
		maxf(1.0, zoom * 0.3), true)
	for i in 3:
		var turn := PI * (0.18 + 0.32 * float(i))
		canvas.draw_line(
			at + (hub + Vector2(cos(turn), sin(turn)) * deep * 0.4) * zoom,
			at + (hub + Vector2(cos(turn) * wide, sin(turn) * deep) * 0.78) * zoom,
			Color(line, 0.45), maxf(1.0, zoom * 0.25))


## Whether anything in that slot is bolted on.
static func _has(parts: Array, slot: int) -> bool:
	for part in parts:
		if part is AttachmentData and (part as AttachmentData).slot == slot:
			return true
	return false


static func _box(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y),
		Vector2(x + w, y + h), Vector2(x, y + h)])


## A filled polygon with a line round it, scaled and moved into place. The outline
## is what keeps two overlapping grey shapes from reading as one blob.
static func _shape(canvas: CanvasItem, at: Vector2, zoom: float,
		points: PackedVector2Array, fill := METAL, line := EDGE) -> void:
	var moved := PackedVector2Array()
	for point in points:
		moved.append(at + point * zoom)
	canvas.draw_colored_polygon(moved, fill)
	if line.a > 0.0:
		moved.append(moved[0])
		canvas.draw_polyline(moved, line, maxf(1.0, zoom * 0.45), true)
