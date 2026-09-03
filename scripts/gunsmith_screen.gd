extends Control

## The workshop: one gun, five slots, and what each part does to it.
##
## Opened from a weapon slot on the kit screen and closed back onto it, so this
## is a detour off the shop rather than a screen of its own - the money is the
## shop's money, the gun is the one you already bought, and anything bolted on
## here is on the gun you carry in. Nothing is saved anywhere else: an attachment
## lives on the Item, the Item goes into the raid, and a gun on a body you loot
## comes with whatever its owner paid for.
##
## Laid out around the picture, because the picture is the reason to build this
## rather than a list of checkboxes. The gun is drawn big across the top with the
## five slots underneath it; picking a slot opens the shelf down the right, and
## every part on that shelf says what it does to the gun in numbers you can read
## before you spend anything.
##
## The comparison is the other half. Bars for the four dials are drawn twice -
## where the gun is now, and where it would be with the part under your pointer -
## so what a part costs you is visible in the same glance as what it buys, which
## is the whole argument of the feature.

signal closed()

## Opaque. At 0.98 the lobby buttons underneath ghosted through the bottom of the
## screen, which reads as a rendering fault rather than as depth.
const BG := Color(0.05, 0.06, 0.08)
const PANEL := Color(0.09, 0.1, 0.13, 0.95)
const SLOT_BG := Color(0.12, 0.14, 0.18)
const BENCH_BG := Color(0.075, 0.085, 0.11)
const LINE := Color(0.24, 0.27, 0.33)
const TEXT := Color(0.85, 0.89, 0.94)
const DIM := Color(0.48, 0.53, 0.6)
const ACCENT := Color(0.98, 0.78, 0.35)
const GOOD := Color(0.42, 0.78, 0.6)
const BAD := Color(0.85, 0.42, 0.42)

const MARGIN := 44.0
## The shelf on the right, and the slot boxes under the bench.
const SHELF_W := 400.0
const SLOT_W := 132.0
const SLOT_H := 54.0
const SLOT_GAP := 8.0
const CARD_H := 104.0
const SCROLL_STEP := 78.0
const TAP_SLOP := 14.0
## World scale for the range readout on the damage curve. The character is
## 48 px tall, so this puts them a bit under two metres.
const PX_PER_M := 28.0

## The shop this is spending, and the gun it is working on.
var shop: Control
var item: Item

## Which of the five slots is open, or -1 for none, or ENERGY_SLOT for the
## sixth one below them.
var _slot := -1
## Not one of Gunsmith.SLOTS - those are AttachmentData.Slot values (0..4) and
## an energy cell is not an attachment, so it gets a number outside that
## range rather than a sixth entry in an enum about rails and mounts. Drawn
## as a sixth box all the same: "what is loaded into this weapon" is exactly
## what this screen is for, and a cell is one more answer to that question,
## not a different screen's job.
const ENERGY_SLOT := 5
## The part under the pointer, whose numbers the comparison bars are previewing.
var _hover: AttachmentData = null
## Same idea, for the energy shelf - see _draw_comparison.
var _hover_energy: EnergyCellData = null
var _message := ""
var _regions: Array = []
var _shelf := Rect2()
var _back := Rect2()
var _scroll := 0.0
var _scroll_max := 0.0
var _saw_touch := false
var _touching := false
var _touch_from := Vector2.ZERO
var _touch_travel := 0.0
var _touch_scrolls := false


func _ready() -> void:
	# Anchors *and* offsets. set_anchors_preset on its own only moves the anchors
	# and then rewrites the offsets to preserve the rect it already had - which
	# for a Control built in code is nothing at all, so the screen ends up
	# stretched across a box zero pixels tall and everything on it draws off the
	# top. It looks like a layout bug and it is a one-word API difference.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Its own group rather than the shop's. PlayerInput frees the mouse while any
	# of them is up, which this needs - but screens.gd finds *the* shop by asking
	# for the first node in "shop", and a second member of that group is a coin
	# toss over which screen the raid deploys from.
	add_to_group(&"gunsmith")
	set_process(true)


## Opens the workshop over the kit screen. The shop hides itself rather than
## being drawn over, so a stray click cannot reach a slot behind this.
##
## `start_slot` lands the workshop open on a particular slot rather than
## nothing selected - the kit screen's own ENERGY row uses it to jump
## straight to that gun's energy shelf instead of making a player who just
## clicked "load a cell" find the sixth box themselves.
func open(from: Control, gun: Item, start_slot := -1) -> void:
	shop = from
	item = gun
	_slot = start_slot
	_hover = null
	_hover_energy = null
	_message = ""
	_scroll = 0.0
	visible = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if item == null or item.base_weapon == null:
		return
	var font := ThemeDB.fallback_font
	_regions.clear()
	draw_rect(Rect2(Vector2.ZERO, size), BG)

	var gun := item.weapon
	draw_string(font, Vector2(MARGIN, 54.0), "GUNSMITH",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ACCENT)
	draw_string(font, Vector2(MARGIN + 170.0, 54.0),
		"%s  -  %s" % [item.base_weapon.display_name, String(gun.ammo_type)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT)
	draw_string(font, Vector2(MARGIN, 74.0),
		"parts stay on the gun - what you bolt on, you carry in and can lose",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	if shop:
		draw_string(font, Vector2(0.0, 54.0), "%d credits" % shop.credits,
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - MARGIN, 22,
			GOOD if shop.credits > 0 else BAD)
		var spent := Gunsmith.parts_value(item.parts)
		if spent > 0:
			draw_string(font, Vector2(0.0, 74.0), "%d in parts on this gun" % spent,
				HORIZONTAL_ALIGNMENT_RIGHT, size.x - MARGIN, 12, DIM)

	var left := Rect2(Vector2(MARGIN, 96.0),
		Vector2(size.x - MARGIN * 2.0 - SHELF_W - 26.0, size.y - 96.0 - 74.0))
	_draw_bench(left)
	_draw_slots(Vector2(left.position.x, left.position.y + left.size.y * 0.52), left.size.x)
	# Filled down to the bottom of `left` rather than a fixed height: the four
	# dials only need about a hundred pixels, and everything past that is
	# where the damage/range curve lives now that the shop's shelf no longer
	# draws one - see the header comment on _draw_comparison.
	var comparison_y := left.position.y + left.size.y * 0.52 + SLOT_H + 26.0
	_draw_comparison(Rect2(Vector2(left.position.x, comparison_y),
		Vector2(left.size.x, left.end.y - comparison_y)))
	_draw_shelf(Rect2(Vector2(size.x - MARGIN - SHELF_W, 96.0),
		Vector2(SHELF_W, size.y - 96.0 - 74.0)))

	_back = Rect2(Vector2(MARGIN, size.y - 58.0), Vector2(210.0, 38.0))
	draw_rect(_back, ACCENT)
	draw_string(font, _back.position + Vector2(0.0, 25.0), "BACK TO KIT",
		HORIZONTAL_ALIGNMENT_CENTER, _back.size.x, 17, Color(0.07, 0.08, 0.1))
	if not _message.is_empty():
		draw_string(font, Vector2(MARGIN + 232.0, size.y - 33.0), _message,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)


## The gun, drawn as big as the space allows.
##
## Scaled to fit rather than at a fixed zoom, because a suppressed sniper with a
## 4x on it is half again as long as a bare pistol and both have to sit in the
## same box without the small one looking like a mistake.
func _draw_bench(box: Rect2) -> void:
	var bench := Rect2(box.position, Vector2(box.size.x, box.size.y * 0.46))
	draw_rect(bench, BENCH_BG)
	draw_rect(bench, LINE, false, 1.0)

	# A grid behind it, faint. It is a workshop drawing, and the ruling is what
	# says so - without it the gun floats in a dark box.
	for x in range(1, 12):
		var at := bench.position.x + bench.size.x * float(x) / 12.0
		draw_line(Vector2(at, bench.position.y + 4.0), Vector2(at, bench.end.y - 4.0),
			Color(LINE, 0.25), 1.0)
	for y in range(1, 5):
		var at := bench.position.y + bench.size.y * float(y) / 5.0
		draw_line(Vector2(bench.position.x + 4.0, at), Vector2(bench.end.x - 4.0, at),
			Color(LINE, 0.25), 1.0)

	var gun := item.base_weapon
	# Length, depth and how far it reaches behind the receiver, all from the one
	# place that knows how a gun is drawn. See GunArt.span.
	var span := GunArt.span(gun, item.parts)
	var zoom := minf((bench.size.x - 70.0) / maxf(span.x, 1.0),
		(bench.size.y - 44.0) / maxf(span.y, 1.0))
	zoom = clampf(zoom, 0.8, 5.5)
	# Centred on what is actually drawn, including whatever sticks out past the
	# barrel, so bolting a can on does not shove the gun off its own bench. The
	# origin is the back of the receiver and the stock reaches behind it, so the
	# stock's length comes back off the half-span rather than off the front.
	var origin := bench.get_center()
	origin.x -= (span.x * 0.5 - span.z) * zoom
	origin.y -= span.y * 0.12 * zoom
	GunArt.draw_gun(self, origin, zoom, gun, item.parts)

	var font := ThemeDB.fallback_font
	var built := item.weapon
	draw_string(font, bench.position + Vector2(12.0, 20.0), item.label(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT)
	# The three numbers a build changes that a bar cannot show.
	# The sight line is what the *camera* will do against this gun's own iron
	# sights, which is the only version of the number a player can check by
	# looking. What is written on the tube is the part's name, over on the shelf.
	var glass := item.base_weapon.ads_zoom / maxf(built.ads_zoom, 0.01)
	var notes := "%d rnd  -  %.1fs reload  -  %.2fx view  -  %dx%d cells" % [
		built.mag_size, built.reload_time, glass,
		built.grid_size.x, built.grid_size.y]
	if built.suppressed:
		notes += "  -  suppressed"
	draw_string(font, Vector2(bench.position.x + 12.0, bench.end.y - 12.0), notes,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)


## Six boxes: the five parts, and the energy cell after them. Sized to
## whatever width the bench itself has rather than a fixed SLOT_W - the cell
## is a sixth box added to a row that used to hold five, and a fixed width
## that fit five happily can run the row past the edge of its own panel once
## a sixth one joins it.
func _draw_slots(at: Vector2, total_width: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, at, "SLOTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ACCENT)
	var count := Gunsmith.SLOTS.size() + 1
	var box_w := (total_width - SLOT_GAP * float(count - 1)) / float(count)
	var x := at.x
	for which in Gunsmith.SLOTS:
		var box := Rect2(Vector2(x, at.y + 12.0), Vector2(box_w, SLOT_H))
		var part := item.part_in(which)
		var open: bool = _slot == which
		var takes := not Gunsmith.shelf_for(which, item.base_weapon).is_empty()
		_regions.append({"kind": "slot", "rect": box, "slot": which})

		draw_rect(box, PANEL if open else SLOT_BG)
		draw_rect(box, ACCENT if open else LINE, false, 2.0 if open else 1.0)
		draw_string(font, box.position + Vector2(9.0, 16.0),
			AttachmentData.slot_name(which), HORIZONTAL_ALIGNMENT_LEFT, box_w - 12.0, 9,
			ACCENT if open else DIM)
		if part:
			draw_string(font, box.position + Vector2(9.0, 36.0), part.short_name,
				HORIZONTAL_ALIGNMENT_LEFT, box_w - 18.0, 14, TEXT)
			# A chip in the part's own colour, so the box and the thing on the
			# gun above it are visibly the same object.
			draw_rect(Rect2(box.end - Vector2(16.0, 20.0), Vector2(8.0, 8.0)),
				part.tint)
		else:
			draw_string(font, box.position + Vector2(9.0, 36.0),
				"empty" if takes else "n/a", HORIZONTAL_ALIGNMENT_LEFT, box_w - 12.0, 13,
				Color(DIM, 0.7))
		x += box_w + SLOT_GAP

	_draw_energy_slot(Vector2(x, at.y + 12.0), box_w)


## The sixth box: the cell actually feeding this gun, or the absence of one -
## drawn with a red border rather than the ordinary grey, because "empty" here
## does not mean "nothing bolted on", it means the gun will not fire.
func _draw_energy_slot(at: Vector2, box_w: float) -> void:
	var font := ThemeDB.fallback_font
	var box := Rect2(at, Vector2(box_w, SLOT_H))
	var cell := item.energy
	var open: bool = _slot == ENERGY_SLOT
	_regions.append({"kind": "slot", "rect": box, "slot": ENERGY_SLOT})

	draw_rect(box, PANEL if open else SLOT_BG)
	draw_rect(box, ACCENT if open else (BAD if cell == null else LINE), false,
		2.0 if open else 1.0)
	draw_string(font, box.position + Vector2(9.0, 16.0), "ENERGY",
		HORIZONTAL_ALIGNMENT_LEFT, box_w - 12.0, 9, ACCENT if open else DIM)
	if cell:
		draw_string(font, box.position + Vector2(9.0, 36.0), cell.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, box_w - 18.0, 14, TEXT)
		draw_rect(Rect2(box.end - Vector2(16.0, 20.0), Vector2(8.0, 8.0)), cell.tint)
	else:
		draw_string(font, box.position + Vector2(9.0, 36.0), "NO CELL - WON'T FIRE",
			HORIZONTAL_ALIGNMENT_LEFT, box_w - 18.0, 12, BAD)


## The four dials, twice over: where the gun is, and where the part under the
## pointer would put it. The damage/range curve lives underneath them, for
## the same "now against what you are pointing at" reason.
##
## Both used to be on the shop's own shelf, one gun at a time, before you had
## bought anything - which was a number you could look at but not yet act on.
## They are here now instead, on the gun you actually own, where hovering a
## part or a cell shows exactly what it would do to the numbers that matter:
## an attachment's damage_scale or a cell's tier delta moves this curve the
## same way it moves the bars.
##
## Drawn as one bar with a marker rather than two bars, because two bars is a
## chart you have to read and one bar with a notch on it is a before and after.
## Recoil counts backwards - less climb is better - so its bar is inverted and
## says so, which is the only place on this screen a bigger number is worse.
func _draw_comparison(box: Rect2) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, box.position, "THIS GUN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ACCENT)
	if _hover:
		draw_string(font, Vector2(box.position.x + 90.0, box.position.y),
			"with %s" % _hover.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT)
	elif _hover_energy:
		draw_string(font, Vector2(box.position.x + 90.0, box.position.y),
			"with %s" % _hover_energy.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT)

	var now := item.weapon
	# What it would be with the hovered part - or the hovered cell - fitted,
	# the same way fitting it would actually build it, so the preview cannot
	# drift from the result. Only one of the two shelves is ever open at a
	# time, so only one of _hover/_hover_energy is ever set.
	var soon := now
	if _hover:
		var trial: Array = []
		for part in item.parts:
			if part.slot != _hover.slot:
				trial.append(part)
		trial.append(_hover)
		soon = Gunsmith.build(item.base_weapon, trial, item.energy)
	elif _hover_energy:
		soon = Gunsmith.build(item.base_weapon, item.parts, _hover_energy)

	var rows := [
		["ACCURACY", now.accuracy, soon.accuracy, false],
		["HANDLING", now.handling, soon.handling, false],
		["RECOIL", now.recoil, soon.recoil, true],
		["STABILITY", now.stability, soon.stability, false],
	]
	var y := box.position.y + 20.0
	for row in rows:
		_draw_dial(Vector2(box.position.x, y), row[0], row[1], row[2], row[3],
			box.size.x - 30.0)
		y += 24.0

	# Whatever room is left below the dials, if it is worth drawing into -
	# a window short enough to fail this is short enough that the dials
	# above are already the more important thing on screen. Kept tight
	# (a 10 px gap above, an 18 px reserve below for the curve's own axis
	# labels) so the graph still fits on a modest window rather than only
	# on a tall one.
	var graph := Rect2(Vector2(box.position.x, y + 10.0),
		Vector2(minf(box.size.x - 30.0, 280.0), box.end.y - y - 18.0))
	if graph.size.y >= 28.0:
		_draw_damage_curve(graph, soon)


func _draw_dial(at: Vector2, label: String, now: float, soon: float,
		inverted: bool, width: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(at.x, at.y + 9.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	var bar := Rect2(Vector2(at.x + 84.0, at.y), Vector2(maxf(width - 150.0, 40.0), 10.0))
	draw_rect(bar, Color(0.16, 0.18, 0.22))

	var fill := clampf(now * 0.01, 0.0, 1.0)
	var shade := BAD.lerp(GOOD, 1.0 - fill if inverted else fill)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), shade)

	# The difference, drawn on top of the bar in the direction it moves. Green
	# for better whichever way better happens to be on this row.
	if not is_equal_approx(now, soon):
		var to := clampf(soon * 0.01, 0.0, 1.0)
		var better := (soon < now) if inverted else (soon > now)
		var from_x := bar.position.x + bar.size.x * minf(fill, to)
		var to_x := bar.position.x + bar.size.x * maxf(fill, to)
		draw_rect(Rect2(Vector2(from_x, bar.position.y), Vector2(to_x - from_x, bar.size.y)),
			Color(GOOD if better else BAD, 0.75))
		draw_line(Vector2(bar.position.x + bar.size.x * to, bar.position.y - 2.0),
			Vector2(bar.position.x + bar.size.x * to, bar.end.y + 2.0), TEXT, 1.5)

	var says := str(roundi(now))
	if not is_equal_approx(now, soon):
		says = "%d %s %d" % [roundi(now), "->", roundi(soon)]
	draw_string(font, Vector2(bar.end.x + 8.0, at.y + 9.0), says,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		TEXT if not is_equal_approx(now, soon) else DIM)


## Damage per trigger pull against distance: flat out to falloff_start,
## sloping to falloff_end, flat after. The shape tells you what the gun is
## for without having to memorise any of the numbers - moved here from the
## shop's shelf, see the header comment on _draw_comparison.
func _draw_damage_curve(graph: Rect2, data: WeaponData) -> void:
	var font := ThemeDB.fallback_font
	var burst := data.get_burst_damage()

	draw_string(font, Vector2(graph.position.x, graph.position.y - 4.0), "DAMAGE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)
	draw_string(font, Vector2(graph.position.x + 52.0, graph.position.y - 4.0),
		"%d" % roundi(burst), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT)
	draw_string(font, Vector2(graph.position.x, graph.position.y - 4.0),
		"%d far" % roundi(burst * data.min_damage_factor),
		HORIZONTAL_ALIGNMENT_RIGHT, graph.size.x, 10, BAD.lerp(TEXT, 0.35))

	draw_rect(graph, Color(0.13, 0.15, 0.19))
	var max_dist := maxf(data.falloff_end * 1.15, 1.0)
	var curve := PackedVector2Array()
	for dist in [0.0, data.falloff_start, data.falloff_end, max_dist]:
		var px := graph.position.x + graph.size.x * clampf(dist / max_dist, 0.0, 1.0)
		var py := graph.end.y - graph.size.y * data.get_damage_factor(dist)
		curve.append(Vector2(px, py))

	var under := PackedVector2Array(curve)
	under.append(Vector2(graph.end.x, graph.end.y))
	under.append(Vector2(graph.position.x, graph.end.y))
	draw_colored_polygon(under, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18))
	draw_polyline(curve, ACCENT, 2.0, true)

	var start_x := graph.position.x + graph.size.x * (data.falloff_start / max_dist)
	draw_line(Vector2(start_x, graph.position.y), Vector2(start_x, graph.end.y),
		Color(0.55, 0.6, 0.7, 0.35), 1.0)
	var label_y := graph.end.y + 11.0
	draw_string(font, Vector2(graph.position.x, label_y), "0m",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)
	draw_string(font, Vector2(graph.position.x, label_y),
		"%dm+" % roundi(data.falloff_end / PX_PER_M),
		HORIZONTAL_ALIGNMENT_RIGHT, graph.size.x, 9, DIM)


## What can go in the open slot, with prices and what each one does.
func _draw_shelf(box: Rect2) -> void:
	var font := ThemeDB.fallback_font
	_shelf = box
	draw_rect(box, PANEL)
	draw_rect(box, LINE, false, 1.0)

	if _slot < 0:
		draw_string(font, box.position + Vector2(16.0, 34.0), "PARTS",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACCENT)
		draw_string(font, box.position + Vector2(16.0, 60.0),
			"pick a slot to see what goes in it",
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 32.0, 13, DIM)
		_scroll_max = 0.0
		return

	if _slot == ENERGY_SLOT:
		_draw_energy_shelf(box)
		return

	# A slot this gun has no use for says so. An empty panel under a heading is
	# indistinguishable from a shelf that has not loaded, and a player who has
	# just clicked STOCK on a pistol is owed the word "no" rather than a blank.
	if Gunsmith.shelf_for(_slot, item.base_weapon).is_empty():
		draw_string(font, box.position + Vector2(16.0, 34.0),
			AttachmentData.slot_name(_slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACCENT)
		draw_string(font, box.position + Vector2(16.0, 60.0),
			"nothing on the shelf fits a %s here" % item.base_weapon.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 32.0, 13, DIM)
		_scroll_max = 0.0
		return

	draw_string(font, box.position + Vector2(16.0, 34.0),
		AttachmentData.slot_name(_slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACCENT)

	var y := box.position.y + 50.0
	var fitted := item.part_in(_slot)
	if fitted:
		var strip := Rect2(Vector2(box.position.x + 12.0, y), Vector2(box.size.x - 24.0, 28.0))
		_regions.append({"kind": "strip", "rect": strip})
		draw_rect(strip, SLOT_BG)
		draw_rect(strip, LINE, false, 1.0)
		draw_string(font, strip.position + Vector2(12.0, 19.0),
			"take off %s  -  full refund" % fitted.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, strip.size.x - 24.0, 12, ACCENT)
		y += 36.0

	var view := Rect2(Vector2(box.position.x, y),
		Vector2(box.size.x, box.end.y - y - 10.0))
	var shelf := Gunsmith.shelf_for(_slot, item.base_weapon)
	_scroll_max = maxf(float(shelf.size()) * (CARD_H + 8.0) - view.size.y, 0.0)
	_scroll = clampf(_scroll, 0.0, _scroll_max)

	var card_y := view.position.y - _scroll
	for part in shelf:
		var card := Rect2(Vector2(view.position.x + 12.0, card_y),
			Vector2(view.size.x - 24.0, CARD_H))
		if card.end.y > view.position.y and card.position.y < view.end.y:
			_draw_card(card, part, fitted == part)
		card_y += CARD_H + 8.0


## The energy shelf: six tiers, filtered down to whatever will actually run
## this gun - EnergyCellData.fits() throws out anything below the gun's own
## base tier or more than two above it, the same way shelf_for() throws
## attachments off the shelf that would not fit.
func _draw_energy_shelf(box: Rect2) -> void:
	var font := ThemeDB.fallback_font
	_shelf = box
	draw_rect(box, PANEL)
	draw_rect(box, LINE, false, 1.0)
	draw_string(font, box.position + Vector2(16.0, 34.0), "ENERGY CELL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACCENT)

	var y := box.position.y + 50.0
	var fitted := item.energy
	if fitted:
		var strip := Rect2(Vector2(box.position.x + 12.0, y), Vector2(box.size.x - 24.0, 28.0))
		_regions.append({"kind": "strip_energy", "rect": strip})
		draw_rect(strip, SLOT_BG)
		draw_rect(strip, LINE, false, 1.0)
		draw_string(font, strip.position + Vector2(12.0, 19.0),
			"take off %s - refunds what you paid past its stock tier" % fitted.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, strip.size.x - 24.0, 12, ACCENT)
		y += 36.0
	else:
		var warn := Rect2(Vector2(box.position.x + 12.0, y), Vector2(box.size.x - 24.0, 28.0))
		draw_rect(warn, SLOT_BG)
		draw_rect(warn, BAD, false, 1.0)
		draw_string(font, warn.position + Vector2(12.0, 19.0),
			"nothing feeding the chamber - this gun will not fire",
			HORIZONTAL_ALIGNMENT_LEFT, warn.size.x - 24.0, 12, BAD)
		y += 36.0

	var view := Rect2(Vector2(box.position.x, y),
		Vector2(box.size.x, box.end.y - y - 10.0))
	var shelf := Gunsmith.energy_shelf_for(item.base_weapon)
	_scroll_max = maxf(float(shelf.size()) * (CARD_H + 8.0) - view.size.y, 0.0)
	_scroll = clampf(_scroll, 0.0, _scroll_max)

	var card_y := view.position.y - _scroll
	for cell in shelf:
		var card := Rect2(Vector2(view.position.x + 12.0, card_y),
			Vector2(view.size.x - 24.0, CARD_H))
		if card.end.y > view.position.y and card.position.y < view.end.y:
			_draw_energy_card(card, cell, fitted == cell)
		card_y += CARD_H + 8.0


## One cell's card: the stock tier costs nothing and does nothing, and says
## so; anything above it is priced and, in the same two columns effect_lines()
## already draws a part's numbers in, honest about what it costs on top of
## what it buys.
func _draw_energy_card(box: Rect2, cell: EnergyCellData, fitted: bool) -> void:
	var font := ThemeDB.fallback_font
	var stock := cell.tier == item.base_weapon.base_tier
	var price := 0 if stock else cell.price
	var afford: bool = shop == null or shop.credits >= price or fitted
	_regions.append({"kind": "buy_energy", "rect": box, "energy": cell})

	draw_rect(box, SLOT_BG)
	draw_rect(box, ACCENT if fitted else LINE, false, 2.0 if fitted else 1.0)
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), cell.tint)

	draw_string(font, box.position + Vector2(14.0, 22.0), cell.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 110.0, 15, TEXT if afford else DIM)
	draw_string(font, Vector2(0.0, box.position.y + 22.0),
		"ON" if fitted else ("stock" if stock else str(price)),
		HORIZONTAL_ALIGNMENT_RIGHT, box.end.x - 14.0, 15,
		ACCENT if fitted else (TEXT if afford else BAD))
	draw_string(font, box.position + Vector2(14.0, 40.0), cell.blurb,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 28.0, 11, DIM)

	var lines := Gunsmith.energy_effect_lines(item.base_weapon, cell)
	var col_x := box.position.x + 14.0
	var y := box.position.y + 66.0
	for i in lines.size():
		if i == 3:
			col_x = box.position.x + box.size.x * 0.52
			y = box.position.y + 66.0
		if i >= 6:
			break
		draw_string(font, Vector2(col_x, y), str(lines[i][0]),
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x * 0.44, 11,
			GOOD if lines[i][1] else BAD)
		y += 13.0


func _draw_card(box: Rect2, part: AttachmentData, fitted: bool) -> void:
	var font := ThemeDB.fallback_font
	var afford: bool = shop == null or shop.credits >= part.price or fitted
	_regions.append({"kind": "buy", "rect": box, "part": part})

	draw_rect(box, SLOT_BG)
	draw_rect(box, ACCENT if fitted else LINE, false, 2.0 if fitted else 1.0)
	# The part's own colour down the edge, matching the chip on its slot box and
	# the thing drawn on the gun.
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), part.tint)

	draw_string(font, box.position + Vector2(14.0, 22.0), part.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 110.0, 15, TEXT if afford else DIM)
	draw_string(font, Vector2(0.0, box.position.y + 22.0),
		"ON" if fitted else str(part.price),
		HORIZONTAL_ALIGNMENT_RIGHT, box.end.x - 14.0, 15,
		ACCENT if fitted else (TEXT if afford else BAD))
	draw_string(font, box.position + Vector2(14.0, 40.0), part.blurb,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 28.0, 11, DIM)

	# What it does, in two columns of short lines. Green for the half that is
	# why you would buy it, red for the half that is why you might not.
	var lines := Gunsmith.effect_lines(part)
	var col_x := box.position.x + 14.0
	var y := box.position.y + 66.0
	for i in lines.size():
		if i == 3:
			col_x = box.position.x + box.size.x * 0.52
			y = box.position.y + 66.0
		if i >= 6:
			break
		draw_string(font, Vector2(col_x, y), str(lines[i][0]),
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x * 0.44, 11,
			GOOD if lines[i][1] else BAD)
		y += 13.0


# --- input --------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	var touch := event as InputEventScreenTouch
	if touch != null:
		_saw_touch = true
		if touch.index == 0:
			if touch.pressed:
				_touching = true
				_touch_from = touch.position
				_touch_travel = 0.0
				_touch_scrolls = _shelf.has_point(touch.position)
			elif _touching:
				_touching = false
				if _touch_travel <= TAP_SLOP:
					_press(touch.position)
		accept_event()
		return

	var drag := event as InputEventScreenDrag
	if drag != null:
		if drag.index == 0 and _touching:
			_touch_travel = maxf(_touch_travel, _touch_from.distance_to(drag.position))
			if _touch_scrolls:
				_scroll = clampf(_scroll - drag.relative.y, 0.0, _scroll_max)
		accept_event()
		return

	var moved := event as InputEventMouseMotion
	if moved != null and not _saw_touch:
		_hover = _part_at(moved.position)
		_hover_energy = _energy_at(moved.position)
		return

	var click := event as InputEventMouseButton
	if click == null or not click.pressed or _saw_touch:
		return
	if click.button_index == MOUSE_BUTTON_WHEEL_UP or click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var step := -SCROLL_STEP if click.button_index == MOUSE_BUTTON_WHEEL_UP else SCROLL_STEP
		_scroll = clampf(_scroll + step, 0.0, _scroll_max)
		accept_event()
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_press(click.position)


## Which part is under the pointer, for the comparison bars.
func _part_at(at: Vector2) -> AttachmentData:
	for region in _regions:
		if region.kind == "buy" and (region.rect as Rect2).has_point(at):
			return region.part
	return null


## Same idea, for the energy shelf.
func _energy_at(at: Vector2) -> EnergyCellData:
	for region in _regions:
		if region.kind == "buy_energy" and (region.rect as Rect2).has_point(at):
			return region.energy
	return null


func _press(at: Vector2) -> void:
	if _back.has_point(at):
		visible = false
		closed.emit()
		return
	for region in _regions:
		if not (region.rect as Rect2).has_point(at):
			continue
		match region.kind:
			"slot":
				# Pressing the open slot again closes the shelf, so it is never
				# stuck over something you are trying to read.
				_slot = -1 if _slot == region.slot else int(region.slot)
				_scroll = 0.0
				_message = ""
			"strip":
				_take_off()
			"buy":
				_fit(region.part)
			"strip_energy":
				_take_off_energy()
			"buy_energy":
				_fit_energy(region.energy)
		return


## Buys a part and bolts it on, refunding whatever it replaced.
##
## The refund is whole and it is unconditional: nothing has been carried anywhere
## yet, so second thoughts in the workshop cost nothing. That is the same rule
## the shop sells guns under, and the two screens disagreeing about it would be
## the sort of thing a player finds out about only after being punished for it.
func _fit(part: AttachmentData) -> void:
	if item == null or part == null:
		return
	var fitted := item.part_in(part.slot)
	if fitted == part:
		_message = "%s is already on it" % part.display_name
		return
	var owed := part.price - (fitted.price if fitted else 0)
	if shop and not shop.try_spend(owed):
		_message = "%d credits short for a %s" % [
			owed - shop.credits, part.display_name]
		return
	item.fit(part)
	_message = "fitted %s" % part.display_name
	_hover = null


func _take_off() -> void:
	if item == null or _slot < 0:
		return
	var was := item.strip(_slot)
	if was == null:
		return
	if shop:
		shop.give_back(was.price)
	_message = "took off %s - refunded %d" % [was.display_name, was.price]


## A cell's stock tier - its own tier matching the gun's base_tier - is free,
## the same way the gun's starting magazine is: it is what from_weapon()
## fitted before this screen ever opened, and nobody paid credits for it. So
## the price on either side of a swap is zero whenever that side is the stock
## tier, and only the difference between two *paid* tiers is ever charged or
## refunded - which is exactly what a stock cell being "priced at zero" means
## arithmetically, without this needing to remember what was actually paid.
func _energy_cost(cell: EnergyCellData) -> int:
	if cell == null or item == null or item.base_weapon == null:
		return 0
	return 0 if cell.tier == item.base_weapon.base_tier else cell.price


func _fit_energy(cell: EnergyCellData) -> void:
	if item == null or cell == null or not cell.fits(item.base_weapon):
		return
	var fitted := item.energy
	if fitted == cell:
		_message = "%s is already fitted" % cell.display_name
		return
	var owed := _energy_cost(cell) - _energy_cost(fitted)
	if shop and not shop.try_spend(owed):
		_message = "%d credits short for a %s" % [owed - shop.credits, cell.display_name]
		return
	item.fit_energy(cell)
	_message = "fitted %s" % cell.display_name
	_hover_energy = null


func _take_off_energy() -> void:
	if item == null or item.energy == null:
		return
	var refund := _energy_cost(item.energy)
	var was := item.strip_energy()
	if was == null:
		return
	if shop and refund > 0:
		shop.give_back(refund)
	_message = "took off %s - this gun will not fire until you fit another" % was.display_name
