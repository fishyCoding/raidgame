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
	"PISTOL": {"receiver": Vector2(38.0, 13.0), "barrel": Vector2(6.0, 8.0),
		"guard": 0.0, "grip_at": 10.0, "mag_at": 10.0, "stock": 0.0},
	"SMG": {"receiver": Vector2(52.0, 15.0), "barrel": Vector2(16.0, 7.0),
		"guard": 14.0, "grip_at": 20.0, "mag_at": 26.0, "stock": 16.0},
	"AR": {"receiver": Vector2(64.0, 15.0), "barrel": Vector2(34.0, 6.0),
		"guard": 26.0, "grip_at": 22.0, "mag_at": 34.0, "stock": 24.0},
	"SHOTGUN": {"receiver": Vector2(58.0, 17.0), "barrel": Vector2(40.0, 9.0),
		"guard": 30.0, "grip_at": 18.0, "mag_at": 0.0, "stock": 26.0},
	"SLUG": {"receiver": Vector2(58.0, 17.0), "barrel": Vector2(44.0, 8.0),
		"guard": 30.0, "grip_at": 18.0, "mag_at": 0.0, "stock": 26.0},
	"LMG": {"receiver": Vector2(74.0, 19.0), "barrel": Vector2(44.0, 7.0),
		"guard": 20.0, "grip_at": 24.0, "mag_at": 40.0, "stock": 26.0},
	"SNIPER": {"receiver": Vector2(70.0, 15.0), "barrel": Vector2(56.0, 6.0),
		"guard": 22.0, "grip_at": 24.0, "mag_at": 38.0, "stock": 30.0},
}
## Anything not in the table is drawn as a rifle rather than as nothing.
const FALLBACK := "AR"

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
## Public because the gunsmith draws a leader line from a slot box to the place
## on the gun it belongs to, and a line that lands somewhere other than the part
## it names is worse than no line.
static func mounts(gun: WeaponData) -> Dictionary:
	var p := profile(gun)
	var body: Vector2 = p["receiver"]
	var barrel: Vector2 = p["barrel"]
	return {
		AttachmentData.Slot.MUZZLE: Vector2(body.x + barrel.x, 0.0),
		AttachmentData.Slot.OPTIC: Vector2(body.x * 0.42, -body.y * 0.5),
		AttachmentData.Slot.MAGAZINE: Vector2(
			p["mag_at"] if p["mag_at"] > 0.0 else body.x * 0.5, body.y * 0.5),
		AttachmentData.Slot.GRIP: Vector2(body.x + barrel.x * 0.35, barrel.y * 0.5 + 1.0),
		AttachmentData.Slot.STOCK: Vector2(0.0, 0.0),
	}


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

	# Stock first so the receiver overlaps it, then the barrel, then the bits
	# that stand proud. Back to front, the way it would be assembled.
	if p["stock"] > 0.0:
		var stock_len: float = p["stock"]
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(0.0, -body.y * 0.42), Vector2(0.0, body.y * 0.30),
			Vector2(-stock_len, body.y * 0.52), Vector2(-stock_len, -body.y * 0.34)]))
	# The handguard, under and around the barrel.
	if p["guard"] > 0.0:
		var guard: float = p["guard"]
		_shape(canvas, at, zoom, _box(body.x - 2.0, -barrel.y * 0.5 - 3.0,
			guard, barrel.y + 7.0))
	_shape(canvas, at, zoom, _box(body.x, -barrel.y * 0.5, barrel.x, barrel.y))
	_shape(canvas, at, zoom, _box(0.0, -body.y * 0.5, body.x, body.y))

	# The magazine before the grip, so the hand is drawn in front of the box the
	# way it sits on the real thing - and so a drum, which is wider than the gap
	# between the two, does not swallow the grip whole.
	var has_mag := false
	for part in parts:
		var it := part as AttachmentData
		if it and it.slot == AttachmentData.Slot.MAGAZINE:
			draw_part(canvas, at, zoom, gun, it)
			has_mag = true
	if not has_mag and p["mag_at"] > 0.0:
		var well: Vector2 = mounts(gun)[AttachmentData.Slot.MAGAZINE]
		_shape(canvas, at, zoom, PackedVector2Array([
			Vector2(well.x - 4.5, well.y), Vector2(well.x + 4.5, well.y),
			Vector2(well.x + 3.0, well.y + 15.0),
			Vector2(well.x - 6.0, well.y + 15.0)]))

	# The pistol grip, raked back the way one is.
	var grip_x: float = p["grip_at"]
	_shape(canvas, at, zoom, PackedVector2Array([
		Vector2(grip_x, body.y * 0.4), Vector2(grip_x + 11.0, body.y * 0.4),
		Vector2(grip_x + 6.0, body.y * 0.5 + 20.0),
		Vector2(grip_x - 5.0, body.y * 0.5 + 20.0)]))

	# The iron sight, so a gun with no optic on it still has something to aim
	# with and the empty rail does not read as a missing piece.
	var rail: Vector2 = mounts(gun)[AttachmentData.Slot.OPTIC]
	_shape(canvas, at, zoom, _box(rail.x - 2.0, rail.y - 4.0, 4.0, 4.0))

	# Everything else on top of the gun it is bolted to.
	for part in parts:
		var it := part as AttachmentData
		if it and it.slot != AttachmentData.Slot.MAGAZINE:
			draw_part(canvas, at, zoom, gun, it)


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
			_shape(canvas, at, zoom,
				_box(where.x, -span.y * 0.5, span.x, span.y), fill, line)
			# Three cuts along it, which is what says "can" rather than "pipe".
			for i in 3:
				var cut := where.x + span.x * (0.25 + 0.22 * float(i))
				_shape(canvas, at, zoom, _box(cut, -span.y * 0.5, 1.6, span.y),
					Color(line, 0.5), Color(line, 0.0))
		AttachmentData.Slot.OPTIC:
			# Two mounts and a tube, and a lens on the front of it.
			_shape(canvas, at, zoom, _box(where.x - span.x * 0.35, where.y - 3.0,
				3.0, 3.5), fill, line)
			_shape(canvas, at, zoom, _box(where.x + span.x * 0.25, where.y - 3.0,
				3.0, 3.5), fill, line)
			_shape(canvas, at, zoom, _box(where.x - span.x * 0.5,
				where.y - 3.0 - span.y, span.x, span.y), fill, line)
			canvas.draw_circle(at + Vector2(where.x + span.x * 0.5,
				where.y - 3.0 - span.y * 0.5) * zoom, span.y * 0.34 * zoom,
				Color(line, 0.85))
		AttachmentData.Slot.MAGAZINE:
			if part.short_name == "DRUM":
				var hub := at + Vector2(where.x + 1.0, where.y + span.y * 0.8) * zoom
				canvas.draw_circle(hub, span.y * 0.72 * zoom, fill)
				canvas.draw_arc(hub, span.y * 0.72 * zoom, 0.0, TAU, 28, line,
					maxf(1.0, zoom * 0.45), true)
			else:
				_shape(canvas, at, zoom, PackedVector2Array([
					Vector2(where.x - span.x * 0.5, where.y),
					Vector2(where.x + span.x * 0.5, where.y),
					Vector2(where.x + span.x * 0.5 - 2.0, where.y + span.y),
					Vector2(where.x - span.x * 0.5 - 3.0, where.y + span.y)]), fill, line)
		AttachmentData.Slot.GRIP:
			if part.short_name == "LASER":
				_shape(canvas, at, zoom, _box(where.x, where.y, span.x, span.y),
					fill, line)
				# The beam, because a laser you cannot see is a stat with no
				# picture attached to it.
				canvas.draw_line(at + Vector2(where.x + span.x, where.y + span.y * 0.5) * zoom,
					at + Vector2(where.x + span.x + 46.0, where.y + span.y * 0.5) * zoom,
					Color(0.95, 0.32, 0.34, 0.55), maxf(1.0, zoom * 0.6))
			elif part.short_name == "A-GRIP":
				_shape(canvas, at, zoom, PackedVector2Array([
					Vector2(where.x, where.y), Vector2(where.x + span.x * 0.5, where.y),
					Vector2(where.x - span.x * 0.4, where.y + span.y),
					Vector2(where.x - span.x * 0.9, where.y + span.y)]), fill, line)
			else:
				_shape(canvas, at, zoom,
					_box(where.x - span.x * 0.5, where.y, span.x, span.y), fill, line)
		AttachmentData.Slot.STOCK:
			_shape(canvas, at, zoom, PackedVector2Array([
				Vector2(where.x, where.y - span.y * 0.5),
				Vector2(where.x, where.y + span.y * 0.35),
				Vector2(where.x - span.x, where.y + span.y * 0.75),
				Vector2(where.x - span.x, where.y - span.y * 0.75)]), fill, line)


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
