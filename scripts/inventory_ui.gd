extends Control

## The inventory screen, and the looting screen - they are the same screen with
## one or two sides showing.
##
## Everything is drawn from the Inventory objects themselves rather than from a
## copy, so what you see is what the character is carrying, and a transfer takes
## effect the moment you let go of the mouse. Dragging lifts the item clean out
## of its container: while it is on the cursor it is nowhere, which is why a drop
## that fails anywhere has to put it back where it came from.
##
## Left click drags. Right click sends an item straight across to the other side
## (or into your own pack when there is no other side), because looting a body
## one careful drag at a time gets old fast.

const CELL := 30.0
const GAP := 2.0
const PANEL_BG := Color(0.07, 0.086, 0.11, 0.96)
const CELL_BG := Color(0.15, 0.17, 0.21)
const LINE := Color(0.22, 0.25, 0.3)
const TEXT := Color(0.85, 0.89, 0.94)
const DIM := Color(0.45, 0.5, 0.58)
const ACCENT := Color(0.98, 0.78, 0.35)
const GOOD := Color(0.42, 0.78, 0.6, 0.5)
const BAD := Color(0.85, 0.42, 0.42, 0.5)

## Weapon slots are drawn big enough for the longest gun in the game.
const SLOT_CELLS := Vector2i(5, 2)

var player_inventory: Inventory
## The body being searched, or null when this is just your own kit.
var other_inventory: Inventory
var other_name := "BODY"

var _regions: Array[Dictionary] = []
var _drag: Item = null
var _drag_grab := Vector2i.ZERO
var _drag_from: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func open(player_kit: Inventory, other_kit: Inventory = null, title := "BODY") -> void:
	player_inventory = player_kit
	other_inventory = other_kit
	other_name = title
	visible = true


func close() -> void:
	_return_drag()
	# Let go of the body. Its kit is about to be replaced with whatever the host
	# says is left on it, and nothing here may go on pointing at the old object.
	other_inventory = null
	visible = false


func is_open() -> bool:
	return visible


# --- layout -------------------------------------------------------------------


## Works out where every container is drawn, and remembers it so the same
## rectangles can be hit-tested. Rebuilt each frame: it is a handful of Rect2s
## and it can never then disagree with what is on screen.
func _layout() -> void:
	_regions.clear()
	var columns := 2 if other_inventory else 1
	var column_width := SLOT_CELLS.x * 2.0 * (CELL + GAP) + 40.0
	var total := column_width * columns + (30.0 if columns > 1 else 0.0)
	var left := size.x * 0.5 - total * 0.5
	var top := size.y * 0.5 - 250.0

	# You on the left, whoever you are searching on the right: your own kit is
	# the one you read constantly, so it goes where the eye lands first.
	_layout_side(player_inventory, Vector2(left, top), "YOU", false)
	if other_inventory:
		_layout_side(other_inventory, Vector2(left + column_width + 30.0, top),
			other_name, true)


func _layout_side(kit: Inventory, at: Vector2, title: String, is_other: bool) -> void:
	if kit == null:
		return
	var y := at.y + 34.0
	_regions.append({
		"kind": "title", "rect": Rect2(at.x, at.y, 300.0, 24.0),
		"text": title, "inv": kit, "other": is_other,
	})

	for slot in [Inventory.Slot.PRIMARY, Inventory.Slot.SECONDARY]:
		var box := Rect2(Vector2(at.x + (SLOT_CELLS.x * (CELL + GAP) + 16.0) * slot, y),
			Vector2(SLOT_CELLS.x * CELL, SLOT_CELLS.y * CELL))
		_regions.append({
			"kind": "slot", "rect": box, "inv": kit, "slot": slot, "other": is_other,
			"text": "PRIMARY" if slot == Inventory.Slot.PRIMARY else "SECONDARY",
		})
	y += SLOT_CELLS.y * CELL + 34.0

	# Worn armour sits under the guns: it is kit you have on, not kit in a bag.
	for wear in [Inventory.Wear.HELMET, Inventory.Wear.VEST]:
		var box := Rect2(Vector2(at.x + (SLOT_CELLS.x * (CELL + GAP) + 16.0) * wear, y),
			Vector2(2.0 * CELL, CELL))
		_regions.append({
			"kind": "wear", "rect": box, "inv": kit, "wear": wear, "other": is_other,
			"text": "HELMET" if wear == Inventory.Wear.HELMET else "VEST",
		})
	y += CELL + 34.0

	# The bag you are wearing gets its own line rather than a third column: at
	# two columns the panel is already as wide as the half-screen it has to share
	# with the body you are searching, and a third ran straight into it.
	_regions.append({
		"kind": "pack", "inv": kit, "other": is_other, "text": "BACKPACK",
		"rect": Rect2(Vector2(at.x, y), Vector2(3.5 * CELL, CELL)),
	})
	y += CELL + 34.0

	# Five pockets side by side, each its own container. Drawn with a gap between
	# them so it reads as five boxes rather than one row of cells - which matters,
	# because nothing is allowed to lie across two of them.
	for i in kit.pockets.size():
		var pocket: ItemGrid = kit.pockets[i]
		var box := Rect2(Vector2(at.x + i * (CELL + 10.0), y), Vector2(CELL, CELL))
		_regions.append({
			"kind": "grid", "rect": box, "inv": kit, "grid": pocket,
			"other": is_other, "text": "POCKETS" if i == 0 else "",
		})
	y += CELL + 38.0

	var box := Rect2(Vector2(at.x, y), Vector2(kit.backpack.width * (CELL + GAP),
		kit.backpack.height * (CELL + GAP)))
	_regions.append({
		"kind": "grid", "rect": box, "inv": kit, "grid": kit.backpack,
		"other": is_other,
		"text": "BACKPACK" if kit.backpack_item == null else kit.backpack_item.title(),
	})


func _region_at(point: Vector2) -> Dictionary:
	for region in _regions:
		if region.kind != "title" and (region.rect as Rect2).has_point(point):
			return region
	return {}


## Which cell of a grid region the mouse is over.
func _cell_at(region: Dictionary, point: Vector2) -> Vector2i:
	var local := point - (region.rect as Rect2).position
	return Vector2i(int(local.x / (CELL + GAP)), int(local.y / (CELL + GAP)))


# --- drawing ------------------------------------------------------------------


func _draw() -> void:
	if player_inventory == null:
		return
	_layout()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.72))

	for region in _regions:
		match region.kind:
			"title":
				_draw_title(region)
			"slot":
				_draw_slot(region)
			"wear":
				_draw_wear(region)
			"pack":
				_draw_pack(region)
			"grid":
				_draw_grid(region)

	if _drag:
		_draw_dragged()

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(size.x * 0.5 - 250.0, size.y - 96.0),
		"LEFT DRAG  move        RIGHT CLICK  send across        TAB or ESC  close",
		HORIZONTAL_ALIGNMENT_LEFT, 500.0, 13, DIM)


func _draw_title(region: Dictionary) -> void:
	var kit: Inventory = region.inv
	var font := ThemeDB.fallback_font
	var rect: Rect2 = region.rect
	draw_string(font, rect.position + Vector2(0.0, 16.0), region.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ACCENT)
	# Right-aligned across the panel, so a long title and a big number never
	# end up printed on top of each other.
	draw_string(font, rect.position + Vector2(0.0, 16.0),
		"%d rounds" % kit.total_rounds(), HORIZONTAL_ALIGNMENT_RIGHT,
		SLOT_CELLS.x * 2.0 * (CELL + GAP) + 16.0, 12, DIM)


func _draw_slot(region: Dictionary) -> void:
	var rect: Rect2 = region.rect
	var kit: Inventory = region.inv
	var item: Item = kit.get_slot(region.slot)
	var font := ThemeDB.fallback_font

	draw_rect(rect, CELL_BG)
	draw_rect(rect, LINE, false, 1.0)
	draw_string(font, rect.position + Vector2(2.0, -6.0), region.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	if item:
		_draw_item(item, rect.position, rect.size)
	elif _drag:
		# Red on the holster while dragging a rifle: the slot is refusing it, and
		# saying so before the drop is better than swallowing the click.
		draw_rect(rect, GOOD if kit.can_hold(_drag, region.slot) else BAD)


## A worn piece, with its condition bar. Armour that is nearly gone reads red
## here, which is the cue to go looking for a replacement on a body.
func _draw_wear(region: Dictionary) -> void:
	var rect: Rect2 = region.rect
	var kit: Inventory = region.inv
	var item: Item = kit.get_worn(region.wear)
	var font := ThemeDB.fallback_font

	draw_rect(rect, CELL_BG)
	draw_rect(rect, LINE, false, 1.0)
	draw_string(font, rect.position + Vector2(2.0, -5.0), region.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	if item:
		_draw_item(item, rect.position, rect.size)
	elif _drag:
		draw_rect(rect, GOOD if kit.can_wear(_drag, region.wear) else BAD)


## The bag on your back. Empty and there is no grid below it at all, which is
## the honest picture: without a pack, your pockets are everything you have.
func _draw_pack(region: Dictionary) -> void:
	var rect: Rect2 = region.rect
	var kit: Inventory = region.inv
	var item: Item = kit.backpack_item
	var font := ThemeDB.fallback_font

	draw_rect(rect, CELL_BG)
	draw_rect(rect, LINE, false, 1.0)
	draw_string(font, rect.position + Vector2(2.0, -5.0), region.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	if item:
		_draw_item(item, rect.position, rect.size)
	elif _drag:
		draw_rect(rect, GOOD if _drag.is_backpack() else BAD)


func _draw_grid(region: Dictionary) -> void:
	var rect: Rect2 = region.rect
	var grid: ItemGrid = region.grid
	var font := ThemeDB.fallback_font
	if grid.cell_count() <= 0:
		draw_string(font, rect.position + Vector2(0.0, 4.0),
			"no bag - pockets only", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(DIM, 0.7))
		return
	if not String(region.text).is_empty():
		draw_string(font, rect.position + Vector2(0.0, -8.0),
			"%s  %d/%d cells" % [region.text, grid.used_cells(), grid.cell_count()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)

	for y in grid.height:
		for x in grid.width:
			draw_rect(Rect2(rect.position + Vector2(x * (CELL + GAP), y * (CELL + GAP)),
				Vector2(CELL, CELL)), CELL_BG)

	for item in grid.items:
		_draw_item(item, rect.position + Vector2(item.cell) * (CELL + GAP),
			Vector2(item.size) * (CELL + GAP) - Vector2(GAP, GAP))

	# Where the held item would land, and whether it would fit.
	if _drag and (region.rect as Rect2).has_point(get_local_mouse_position()):
		var target := _cell_at(region, get_local_mouse_position()) - _drag_grab
		var ok := grid.fits(_drag, target)
		draw_rect(Rect2(rect.position + Vector2(target) * (CELL + GAP),
			Vector2(_drag.size) * (CELL + GAP) - Vector2(GAP, GAP)), GOOD if ok else BAD)


func _draw_item(item: Item, at: Vector2, box: Vector2, alpha := 1.0) -> void:
	var font := ThemeDB.fallback_font
	var colour := item.tint()
	var rect := Rect2(at, box)
	draw_rect(rect, Color(colour.r * 0.28, colour.g * 0.28, colour.b * 0.32, 0.95 * alpha))
	draw_rect(rect, Color(colour.r, colour.g, colour.b, alpha), false, 1.5)
	# A stripe of the round's own colour, so a stack and the gun that eats it
	# read as the same family without needing to be read at all.
	draw_rect(Rect2(at, Vector2(box.x, 3.0)), Color(colour.r, colour.g, colour.b, alpha))

	if item.is_weapon():
		draw_string(font, at + Vector2(6.0, 20.0), item.weapon.short_name,
			HORIZONTAL_ALIGNMENT_LEFT, box.x - 8.0, 13, Color(TEXT, alpha))
		draw_string(font, at + Vector2(6.0, box.y - 8.0),
			"%d/%d" % [item.count, item.weapon.mag_size],
			HORIZONTAL_ALIGNMENT_LEFT, box.x - 8.0, 11, Color(DIM, alpha))
	elif item.is_armor():
		draw_string(font, at + Vector2(6.0, 20.0), item.armor.short_name,
			HORIZONTAL_ALIGNMENT_LEFT, box.x - 8.0, 13, Color(TEXT, alpha))
		# A condition bar rather than a number: armour is read at a glance, and
		# the question is only ever "is there anything left in it".
		var bar := Rect2(at + Vector2(6.0, box.y - 12.0), Vector2(box.x - 12.0, 5.0))
		draw_rect(bar, Color(0.16, 0.18, 0.22, alpha))
		# Coloured along the bar rather than switched at a threshold. Armour used
		# to be scrap below a quarter and fine above it, so one line could say
		# which; it fades out continuously now, and so does this.
		var left := item.condition()
		var shade := BAD.lerp(GOOD, clampf(left * 1.6, 0.0, 1.0))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, bar.size.y)),
			Color(shade.r, shade.g, shade.b, alpha))
	elif item.is_medkit() or item.is_revive():
		draw_string(font, at + Vector2(6.0, 20.0), item.title(),
			HORIZONTAL_ALIGNMENT_LEFT, box.x - 8.0, 12, Color(TEXT, alpha))
		draw_string(font, at, "x%d" % item.count,
			HORIZONTAL_ALIGNMENT_RIGHT, box.x - 6.0, 12, Color(ACCENT, alpha))
	elif item.is_backpack():
		# How full it is, because that is what decides whether it is worth the
		# cells - a bag is worth taking for what is in it as much as for its size.
		var fill := "%d/%d" % [item.contents.used_cells(), item.contents.cell_count()]
		draw_string(font, at + Vector2(6.0, 20.0), item.backpack.short_name,
			HORIZONTAL_ALIGNMENT_LEFT, box.x - 8.0, 12, Color(TEXT, alpha))
		if box.y < 44.0:
			# One line high: the count goes beside the name, not under it.
			draw_string(font, at + Vector2(0.0, 20.0), fill,
				HORIZONTAL_ALIGNMENT_RIGHT, box.x - 6.0, 11, Color(ACCENT, alpha))
		else:
			draw_string(font, at + Vector2(6.0, 38.0), fill + " cells",
				HORIZONTAL_ALIGNMENT_LEFT, box.x - 8.0, 11, Color(ACCENT, alpha))
	else:
		# One cell is 30px: the calibre goes on the top line and the count on the
		# bottom, right-aligned, so the two can never print over each other.
		draw_string(font, at + Vector2(0.0, 13.0), str(item.ammo_type),
			HORIZONTAL_ALIGNMENT_CENTER, box.x, 10, Color(TEXT, alpha))
		draw_string(font, at + Vector2(0.0, box.y - 5.0), str(item.count),
			HORIZONTAL_ALIGNMENT_CENTER, box.x, 12, Color(ACCENT, alpha))


func _draw_dragged() -> void:
	var box := Vector2(_drag.size) * (CELL + GAP) - Vector2(GAP, GAP)
	var at := get_local_mouse_position() - Vector2(_drag_grab) * (CELL + GAP) \
		- Vector2(CELL, CELL) * 0.5
	_draw_item(_drag, at, box, 0.85)


# --- dragging -----------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var mouse := event as InputEventMouseButton
	if mouse == null:
		return

	if mouse.button_index == MOUSE_BUTTON_LEFT:
		if mouse.pressed:
			_start_drag(mouse.position)
		else:
			_finish_drag(mouse.position)
		accept_event()
	elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
		_quick_transfer(mouse.position)
		accept_event()


func _start_drag(point: Vector2) -> void:
	if _drag:
		return
	var region := _region_at(point)
	if region.is_empty():
		return

	var kit: Inventory = region.inv
	if region.kind == "pack":
		var bag: Item = kit.backpack_item
		if bag == null:
			return
		# Lifted with everything still inside it. That is the point of looting a
		# bag: you take the space and the kit in one movement, not a cell at a
		# time. The grid below it empties out as you lift, because that grid was
		# only ever a window onto this bag.
		kit.set_backpack(null)
		_drag_from = {"inv": kit, "pack": true}
		_drag = bag
		_drag_grab = Vector2i.ZERO
		return

	if region.kind == "slot" or region.kind == "wear":
		var worn: bool = region.kind == "wear"
		var item: Item = kit.get_worn(region.wear) if worn else kit.get_slot(region.slot)
		if item == null:
			return
		if worn:
			kit.set_worn(region.wear, null)
			_drag_from = {"inv": kit, "wear": region.wear}
		else:
			kit.set_slot(region.slot, null)
			_drag_from = {"inv": kit, "slot": region.slot}
		_drag = item
		_drag_grab = Vector2i.ZERO
	else:
		var grid: ItemGrid = region.grid
		var cell := _cell_at(region, point)
		var item := grid.item_at(cell)
		if item == null:
			return
		# Remember which part of the item was grabbed, so a four-cell rifle drops
		# where it looks like it will rather than jumping a cell to the left.
		_drag_grab = cell - item.cell
		_drag_from = {"inv": kit, "grid": grid, "cell": item.cell}
		grid.remove(item)
		_drag = item


func _finish_drag(point: Vector2) -> void:
	if _drag == null:
		return
	var region := _region_at(point)
	if region.is_empty():
		_return_drag()
		return

	var kit: Inventory = region.inv
	if region.kind == "pack":
		# Onto a bare back only. Swapping one worn bag straight for another would
		# have to decide where the old one goes while its contents are still in
		# it, and there is no answer to that which is not a surprise - so take
		# yours off first, which is one drag either way.
		if _drag.is_backpack() and kit.backpack_item == null and kit.set_backpack(_drag):
			_clear_drag()
		else:
			_return_drag()
		return

	if region.kind == "wear":
		if kit.can_wear(_drag, region.wear) and kit.get_worn(region.wear) == null:
			kit.set_worn(region.wear, _drag)
			_clear_drag()
		else:
			_return_drag()
		return

	if region.kind == "slot":
		if kit.can_hold(_drag, region.slot) and kit.get_slot(region.slot) == null:
			kit.set_slot(region.slot, _drag)
			_clear_drag()
		else:
			_return_drag()
		return

	var grid: ItemGrid = region.grid
	var target := _cell_at(region, point) - _drag_grab

	# Dropping ammunition onto a matching stack tops it up instead of demanding
	# an empty cell - the obvious thing to expect, and it frees space.
	var under := grid.item_at(_cell_at(region, point))
	if under and under.is_ammo() and _drag.is_ammo() and under.ammo_type == _drag.ammo_type:
		var moved := mini(under.room_left(), _drag.count)
		under.count += moved
		_drag.count -= moved
		if _drag.count <= 0:
			_clear_drag()
			return

	if grid.place(_drag, target) or grid.add(_drag):
		_clear_drag()
	else:
		_return_drag()


## Right click: straight to the other side, or into your own pack when there is
## no other side. Falls back to leaving it where it was if there is no room.
func _quick_transfer(point: Vector2) -> void:
	if _drag:
		return
	var region := _region_at(point)
	if region.is_empty():
		return

	var kit: Inventory = region.inv
	var item: Item = null
	if region.kind == "pack":
		# Right-clicking his bag takes the whole thing: onto your own back if it
		# is bare, into your pack otherwise. Either way the contents come too.
		item = kit.backpack_item
		if item == null:
			return
		var target: Inventory = player_inventory if region.other else other_inventory
		if target == null:
			target = player_inventory
		if target == kit:
			return
		kit.set_backpack(null)
		if not target.store(item):
			kit.set_backpack(item) # no room over there: he keeps it
		return
	if region.kind == "wear":
		item = kit.get_worn(region.wear)
	elif region.kind == "slot":
		item = kit.get_slot(region.slot)
	else:
		item = (region.grid as ItemGrid).item_at(_cell_at(region, point))
	if item == null:
		return

	var destination: Inventory = player_inventory if region.other else other_inventory
	if destination == null:
		destination = player_inventory
	if destination == kit and region.kind == "slot":
		return # already yours and in hand: nothing to send it to

	# Ammunition merges into existing stacks rather than insisting on a cell.
	if item.is_ammo():
		var moved := destination.add_rounds(item.ammo_type, item.count)
		if moved <= 0:
			return
		item.count -= moved
		if item.count <= 0:
			kit.remove_item(item)
		return

	kit.remove_item(item)
	if not destination.store(item):
		kit.store(item) # no room over there: it stays put


func _clear_drag() -> void:
	_drag = null
	_drag_from = {}


## Puts a dragged item back exactly where it was lifted from.
func _return_drag() -> void:
	if _drag == null:
		return
	var kit: Inventory = _drag_from.get("inv")
	if kit:
		if _drag_from.has("pack"):
			if not kit.set_backpack(_drag):
				kit.store(_drag)
		elif _drag_from.has("wear"):
			kit.set_worn(_drag_from.wear, _drag)
		elif _drag_from.has("slot"):
			kit.set_slot(_drag_from.slot, _drag)
		else:
			var grid: ItemGrid = _drag_from.grid
			if not grid.place(_drag, _drag_from.cell):
				kit.store(_drag)
	_clear_drag()
