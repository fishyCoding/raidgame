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
##   mag_w     how wide the magazine is, and with it the well it goes into
##
## mag_w is per gun because a 9mm stick and a belt-fed's box are not the same
## object at different lengths. Drawn at one width for everything, the SMG came
## out carrying a rifle magazine.
##
## The shapes are deliberately blunt. A silhouette this size reads as a class of
## weapon - long and thin is a rifle, short and deep is a shotgun - and detail
## below that is noise at the scale it will be looked at.
const PROFILES := {
	"PISTOL": {"receiver": Vector2(38.0, 10.5), "barrel": Vector2(6.0, 5.5),
		"guard": 0.0, "grip_at": 8.0, "mag_at": 10.0, "stock": 0.0, "vents": 0,
		"mark": "", "well": 0.0, "mag_w": 6.5},
	"SMG": {"receiver": Vector2(48.0, 11.5), "barrel": Vector2(20.0, 5.0),
		"guard": 16.0, "grip_at": 16.0, "mag_at": 36.0, "stock": 18.0, "vents": 2,
		"mark": "shroud", "well": 4.0, "mag_w": 4.6},
	"AR": {"receiver": Vector2(58.0, 11.5), "barrel": Vector2(40.0, 4.2),
		"guard": 28.0, "grip_at": 15.0, "mag_at": 39.0, "stock": 24.0, "vents": 4,
		"mark": "carry", "well": 5.0, "mag_w": 8.0},
	"SHOTGUN": {"receiver": Vector2(52.0, 13.0), "barrel": Vector2(46.0, 6.5),
		"guard": 32.0, "grip_at": 14.0, "mag_at": 0.0, "stock": 26.0, "vents": 0,
		"mark": "tube", "well": 0.0, "mag_w": 7.0},
	"SLUG": {"receiver": Vector2(52.0, 13.0), "barrel": Vector2(50.0, 6.0),
		"guard": 32.0, "grip_at": 14.0, "mag_at": 0.0, "stock": 26.0, "vents": 0,
		"mark": "tube", "well": 0.0, "mag_w": 7.0},
	"LMG": {"receiver": Vector2(70.0, 14.5), "barrel": Vector2(48.0, 5.0),
		"guard": 22.0, "grip_at": 18.0, "mag_at": 47.0, "stock": 26.0, "vents": 5,
		"mark": "bipod", "well": 6.0, "mag_w": 9.5},
	"SNIPER": {"receiver": Vector2(64.0, 11.0), "barrel": Vector2(64.0, 4.0),
		"guard": 20.0, "grip_at": 18.0, "mag_at": 43.0, "stock": 32.0, "vents": 2,
		"mark": "bolt", "well": 4.5, "mag_w": 7.0},
	"GRD": {"receiver": Vector2(54.0, 11.0), "barrel": Vector2(32.0, 4.2),
		"guard": 24.0, "grip_at": 15.0, "mag_at": 36.0, "stock": 20.0, "vents": 3,
		"mark": "", "well": 4.0, "mag_w": 7.0},
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
		# The lip of the magwell, not the bottom of the receiver: a magazine is
		# fed up into the housing, so what it seats against is the bottom of the
		# housing. Guns without a well - the pump shotguns - fall back to the
		# receiver line and never use it, having no box magazine to hang.
		AttachmentData.Slot.MAGAZINE: Vector2(
			p["mag_at"] if p["mag_at"] > 0.0 else body.x * 0.5,
			body.y * 0.42 + p["well"]),
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
	var has_stock := _has(parts, AttachmentData.Slot.STOCK)
	var has_mag := _has(parts, AttachmentData.Slot.MAGAZINE)

	# Back to front, the way it would be assembled.
	if p["stock"] > 0.0 and not has_stock:
		var stock_len: float = p["stock"]
		# A thin comb rising to the receiver and a slim tube under it, rather
		# than one solid wedge. Two long shapes read as a stock; one fat one
		# reads as a doorstop.
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(0.0, -body.y * 0.40), Vector2(0.0, -body.y * 0.05),
			Vector2(-stock_len * 0.94, body.y * 0.02),
			Vector2(-stock_len, -body.y * 0.06),
			Vector2(-stock_len, -body.y * 0.44),
			Vector2(-stock_len * 0.55, -body.y * 0.46)]))
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(0.0, body.y * 0.06), Vector2(0.0, body.y * 0.40),
			Vector2(-stock_len * 0.52, body.y * 0.30),
			Vector2(-stock_len * 0.62, body.y * 0.02)]), METAL.darkened(0.1), EDGE)
		# The butt plate, upright and thin.
		_shape(canvas, at, zoom, _box(-stock_len - 2.0, -body.y * 0.44,
			2.4, body.y * 0.5), METAL.darkened(0.22), EDGE)

	# The barrel: one taper rather than two boxes, so the line down it is
	# continuous. A gun this size is read along its length, and a step halfway
	# breaks the read.
	_shape(canvas, at, zoom, PackedVector2Array([
		Vector2(body.x, -barrel.y * 0.5), Vector2(body.x + barrel.x, -barrel.y * 0.34),
		Vector2(body.x + barrel.x, barrel.y * 0.34), Vector2(body.x, barrel.y * 0.5)]))
	# A gas block, which is what stops a long barrel reading as wire.
	_shape(canvas, at, zoom, _box(body.x + barrel.x * 0.58, -barrel.y * 0.5 - 1.6,
		4.5, barrel.y + 3.2), METAL.lightened(0.06), EDGE)
	# The front sight post: square, and no taller than the barrel is thick.
	var post := maxf(barrel.y * 0.7, 2.0)
	_shape(canvas, at, zoom,
		_box(body.x + barrel.x - 5.0, -barrel.y * 0.34 - post, 2.2, post))

	# The handguard: slimmer than the receiver and slotted, so the two read as
	# different parts of one object rather than as one long box.
	if p["guard"] > 0.0:
		var guard: float = p["guard"]
		var guard_x: float = body.x - 2.0
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(guard_x, -barrel.y * 0.5 - 2.6),
			Vector2(guard_x + guard, -barrel.y * 0.5 - 2.0),
			Vector2(guard_x + guard, barrel.y * 0.5 + GUARD_DEPTH - 1.0),
			Vector2(guard_x, barrel.y * 0.5 + GUARD_DEPTH)]))
		var vents: int = p["vents"]
		for i in vents:
			var slot_x := guard_x + guard * (0.18 + 0.62 * (float(i) / maxf(float(vents), 1.0)))
			_shape(canvas, at, zoom,
				_box(slot_x, -barrel.y * 0.4, 1.8, barrel.y + 2.2),
				METAL.darkened(0.38), Color(EDGE, 0.0))

	# The receiver, tapered toward the muzzle end and with a cut-back heel, so
	# the silhouette has a direction to it.
	_shape(canvas, at, zoom, PackedVector2Array([
		Vector2(2.0, -body.y * 0.5), Vector2(body.x, -body.y * 0.42),
		Vector2(body.x, body.y * 0.42), Vector2(2.0, body.y * 0.5),
		Vector2(0.0, body.y * 0.28), Vector2(0.0, -body.y * 0.28)]))
	# A lit edge along the top and an ejection port, which between them give it a
	# near side.
	_shape(canvas, at, zoom, _box(3.0, -body.y * 0.5 + 0.8, body.x - 5.0, 1.3),
		METAL.lightened(0.18), Color(EDGE, 0.0))
	_shape(canvas, at, zoom, _box(body.x * 0.54, -body.y * 0.24,
		body.x * 0.20, body.y * 0.26), METAL.darkened(0.32), Color(EDGE, 0.3))

	# The one feature that tells this weapon apart from the others at a glance.
	_draw_mark(canvas, at, zoom, p)

	# The magazine before the grip, so the hand is drawn in front of the box the
	# way it sits on the real thing.
	for part in parts:
		var it := part as AttachmentData
		if it and it.slot == AttachmentData.Slot.MAGAZINE:
			draw_part(canvas, at, zoom, gun, it)
	if not has_mag and p["mag_at"] > 0.0:
		var well: Vector2 = mounts(gun)[AttachmentData.Slot.MAGAZINE]
		var mag_w: float = p["mag_w"] * 0.5
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(well.x - mag_w, well.y - 1.0), Vector2(well.x + mag_w, well.y - 1.0),
			Vector2(well.x + mag_w * 0.8, well.y + 13.0),
			Vector2(well.x - mag_w * 1.4, well.y + 13.0)]))

	# The magwell last, over the magazine rather than under it.
	#
	# It is the housing the magazine goes *up into*, so it has to be in front of
	# it: drawn first, the magazine's own outline ran across the well and the two
	# read as a box hung under the gun beside another box. Drawn after, the
	# magazine disappears into the well the way it does on the real thing, and
	# the join stops being a line at all.
	#
	# Without the well at all a magazine looks stuck to the underside, and it is
	# the single detail that makes the underside read as designed.
	var well_deep: float = p["well"]
	var well_at: float = p["mag_at"]
	if well_deep > 0.0 and well_at > 0.0:
		var well_wide: float = p["mag_w"] + 2.5
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(well_at - well_wide * 0.5 - 1.0, body.y * 0.30),
			Vector2(well_at + well_wide * 0.5 + 1.0, body.y * 0.30),
			Vector2(well_at + well_wide * 0.5, body.y * 0.42 + well_deep),
			Vector2(well_at - well_wide * 0.5 - 2.0, body.y * 0.42 + well_deep)]),
			METAL.lightened(0.05), EDGE)

	# Trigger guard and grip.
	#
	# The grip is a hand, not a second magazine: about seven units across where
	# the web of your thumb sits, tapering to five, and it stops above the bottom
	# of the magazine rather than hanging past it. Drawn as deep as the magazine
	# and nearly as wide, which is what it was, the underside of every gun came
	# out as two identical slabs and the eye could not tell which one it was
	# meant to be holding.
	var grip_x: float = p["grip_at"]
	var guard_y: float = body.y * 0.42
	var grip_wide := 7.0
	var grip_deep := 13.0
	if p["well"] > 0.0:
		# A unit clear of the magazine's own bottom edge, so the two never line
		# up and never cross.
		grip_deep = minf(grip_deep, p["well"] + 13.0 - 1.5)
	canvas.draw_polyline(PackedVector2Array([
		at + Vector2(grip_x + 10.0, guard_y) * zoom,
		at + Vector2(grip_x + 11.0, guard_y + 5.5) * zoom,
		at + Vector2(grip_x + 5.0, guard_y + 6.5) * zoom,
		at + Vector2(grip_x + 1.5, guard_y + 3.0) * zoom]),
		EDGE, maxf(1.0, zoom * 0.4), true)
	_shape(canvas, at, zoom, PackedVector2Array([
		Vector2(grip_x, guard_y - 0.5),
		Vector2(grip_x + grip_wide, guard_y - 0.5),
		Vector2(grip_x + grip_wide - 1.6, guard_y + grip_deep),
		Vector2(grip_x - 2.2, guard_y + grip_deep)]))

	# The rail along the top, and the iron sight standing on it.
	for i in 5:
		_shape(canvas, at, zoom,
			_box(body.x * (0.26 + 0.09 * float(i)), -body.y * 0.5 - RAIL_H, 2.6, RAIL_H),
			METAL.lightened(0.14), Color(EDGE, 0.0))
	var rail: Vector2 = mounts(gun)[AttachmentData.Slot.OPTIC]
	if not _has(parts, AttachmentData.Slot.OPTIC):
		_shape(canvas, at, zoom, _box(rail.x - 1.6, rail.y - 3.2, 3.2, 3.2))

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


## How far a drum leans toward the muzzle, in radians.
##
## They are not hung straight down. The body sits forward of the feed lips so the
## rounds feed up and back into the well, and every drum on a rifle has that lean
## - about twelve degrees is enough to read as deliberate rather than as a
## drawing that slipped.
const DRUM_TILT := 0.21


## A drum magazine, side on.
##
## The disc faces down the barrel - the way you are aiming - so from the
## shooter's side you are looking at its *edge*: the drum's thickness across and
## its diameter down. On a D-60's numbers, 4.1 inches thick and 7.4 from the feed
## lips to the bottom, at about three units to the inch on these profiles, that
## is a body roughly twelve across and twenty deep. A capsule: flat sides, round
## top and bottom, and half again wider than a box magazine.
##
## Two earlier attempts got this wrong in opposite directions. The first drew it
## seven units across, which is a bottle rather than a drum. The second drew the
## round face, which is a different magazine mounted a different way. The
## thickness is the number that makes it read - too narrow and no amount of
## detail rescues it - and the shading is what makes it a cylinder rather than a
## rounded box.
static func _draw_drum(canvas: CanvasItem, at: Vector2, zoom: float,
		where: Vector2, span: Vector2, fill: Color, line: Color) -> void:
	var tower := span.x * 0.40
	var shoulder := where.y + span.y * 0.16
	# Everything below the well hangs off it and leans forward, so the pivot is
	# where the two meet rather than the body's own centre - rotating about the
	# middle pulls the top of the magazine out of the well it is feeding.
	var pivot := Vector2(where.x, shoulder)
	var half := span.x * 0.36
	var nose := half * 0.3
	# The body runs most of the drop below the tower: a drum seen on edge is its
	# diameter tall against its thickness wide, which is about half again taller
	# than it is broad. Drawn square it reads as a box with rounded corners.
	var top := shoulder + half * 0.30
	var bottom := where.y + span.y - half * 0.30

	# One outline round the whole magazine.
	#
	# The tower and the drum are one object, and drawing them as two shapes - even
	# in the right order, even with the tower on top - leaves the join visible as
	# a change in the line rather than as a continuous edge. So they are merged
	# into a single polygon first and that is what gets filled and stroked.
	# Geometry2D does the union; the two pieces overlap by a few units at the
	# shoulder so there is always something to merge.
	var body := _lean(_casing(Vector2(where.x + nose, top),
		Vector2(where.x + nose, bottom), half), pivot)
	var neck := PackedVector2Array([
		Vector2(where.x - tower * 0.5, where.y - 1.5),
		Vector2(where.x + tower * 0.5, where.y - 1.5),
		Vector2(where.x + tower * 0.5, shoulder + half * 0.9),
		Vector2(where.x - tower * 0.5, shoulder + half * 0.9)])
	for piece in Geometry2D.merge_polygons(neck, body):
		_shape(canvas, at, zoom, piece, fill, line)

	# The recessed face, drawn inside that outline and never touching it. This is
	# the whole of the shading: a lit strip down one side and a dark strip down
	# the other read, once rotated, as two bars laid across the drum rather than
	# as a curved surface.
	var inset := _casing(Vector2(where.x + nose, top + half * 0.42),
		Vector2(where.x + nose, bottom - half * 0.42), half * 0.64)
	_shape(canvas, at, zoom, _lean(inset, pivot), fill.darkened(0.16),
		Color(line, 0.0))

	# The winder cap at the middle of it, and a pair of ribs across the face.
	var middle := Vector2(where.x + nose, (top + bottom) * 0.5)
	var hub := _lean(PackedVector2Array([middle]), pivot)[0]
	canvas.draw_circle(at + hub * zoom, half * 0.26 * zoom, fill.lightened(0.16))
	for i in 2:
		var band := top + (bottom - top) * (0.24 + 0.52 * float(i))
		var rib := _lean(PackedVector2Array([
			Vector2(where.x + nose - half * 0.42, band),
			Vector2(where.x + nose + half * 0.42, band)]), pivot)
		canvas.draw_line(at + rib[0] * zoom, at + rib[1] * zoom,
			Color(line, 0.22), maxf(1.0, zoom * 0.18))


## Leans a set of points forward about a pivot. Negative because screen y is
## down: a positive rotation would swing the bottom of the drum toward the stock.
static func _lean(points: PackedVector2Array, pivot: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(pivot + (point - pivot).rotated(-DRUM_TILT))
	return out


## A drum casing seen edge on: a rectangle with the corners taken off, from the
## middle of its top edge to the middle of its bottom edge.
##
## Not a capsule. Full half-circle ends made it read as a pill, and a drum from
## this angle is a cylinder with a rim - much closer to a rectangle than to a
## lozenge. The first attempt at the corners mirrored one of the four arcs by
## negating it, which is not the same as reflecting it, and the result was a
## boot.
##
## Walked clockwise in screen space, one corner at a time, so the outline never
## doubles back on itself.
static func _casing(from: Vector2, to: Vector2, wide: float) -> PackedVector2Array:
	var round_by := minf(wide * 0.45, (to.y - from.y) * 0.45)
	var out := PackedVector2Array()
	var corners := [
		[Vector2(from.x + wide - round_by, from.y + round_by), -PI * 0.5, 0.0],
		[Vector2(to.x + wide - round_by, to.y - round_by), 0.0, PI * 0.5],
		[Vector2(to.x - wide + round_by, to.y - round_by), PI * 0.5, PI],
		[Vector2(from.x - wide + round_by, from.y + round_by), PI, PI * 1.5],
	]
	for corner in corners:
		var middle: Vector2 = corner[0]
		var from_turn: float = corner[1]
		var to_turn: float = corner[2]
		for i in range(0, 5):
			var turn: float = lerpf(from_turn, to_turn, float(i) / 4.0)
			out.append(middle + Vector2(cos(turn), sin(turn)) * round_by)
	return out


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
