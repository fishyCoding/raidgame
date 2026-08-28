extends Control

## The screen before the raid: fill the slots on your body, then go in with what
## you bought.
##
## This is where the extraction loop gets its teeth. Everything here costs money
## and everything you take in can be lost, so kitting out is a bet - go in heavy
## and lose more when it goes wrong, or go in light and hope to loot your way up.
##
## Laid out as the body rather than as a shelf. You click the slot you want to
## fill - helmet, vest, primary, a pocket - and it offers you only what actually
## goes there. A shop that lists every item at once makes you do the matching in
## your head; a shop built out of slots has already done it, and what is empty is
## visible without reading anything.
##
## Bought kit goes straight into the inventory the player will carry, so what you
## see here is exactly what you will be holding.

signal deployed()

## Doubled again, to 16000, and this one is scaffolding rather than balance.
##
## Kitting out now costs more than it did: there is a third armour tier to buy
## into and a surgical kit is a thing you want in the bag before you need it,
## and neither of those decisions is worth testing on a budget that only covers
## one of them. Armour is now a consumable that dies inside a single fight and
## comes with repair kits to buy as well, so trying a loadout twice costs what
## trying it once used to. This is a testing number: halve it, twice, once the
## loadouts have settled.
const CREDITS := 16000
## Uses in one bought repair kit. Two, so a kit is a decision about one fight
## rather than a subscription: armour that dies in four rounds and comes back
## twice is still armour you run out of.
const REPAIRS_PER_KIT := 2
## Uses in one bought stack of stims. Buy several stacks if a cell each is worth
## it to you - the pocket and the pack both sell them.
const REVIVES_PER_STACK := 5

## Fully opaque. At 0.97 the HUD underneath ghosted through the panel, which
## read as a rendering fault rather than as depth.
const BG := Color(0.05, 0.06, 0.08)
const PANEL := Color(0.09, 0.1, 0.13, 0.95)
const SLOT_BG := Color(0.12, 0.14, 0.18)
const CELL_BG := Color(0.15, 0.17, 0.21)
const LINE := Color(0.24, 0.27, 0.33)
const TEXT := Color(0.85, 0.89, 0.94)
const DIM := Color(0.48, 0.53, 0.6)
const ACCENT := Color(0.98, 0.78, 0.35)
const GOOD := Color(0.42, 0.78, 0.6)
const BAD := Color(0.85, 0.42, 0.42)
## Which hand a box of rounds is for. Two colours rather than two words, because
## picking the wrong calibre is a mistake you only find out about in a firefight
## and the tag has to be readable without being read.
const PRIMARY_TAG := Color(0.98, 0.78, 0.35)
const SECONDARY_TAG := Color(0.55, 0.78, 0.95)

## Cells in the little footprint previews on each slot box.
const CELL := 9.0
## Cells in the pack grid, which is drawn at readable size because it is the one
## you actually count.
const PACK_CELL := 26.0
const GAP := 2.0

const MARGIN := 44.0
const SLOT_W := 272.0
const SLOT_H := 46.0
const SLOT_GAP := 6.0
const POCKET_BOX := 40.0
## The shelf, and the widest column on the screen. It holds cards rather than
## rows now: choosing a gun is the biggest decision here and it was being made
## off two lines of 10 pt text.
const PICK_W := 520.0
## A gun card carries a damage curve and four stat bars; everything else is a
## name, a line about it and a price.
const CARD_TALL := 132.0
const CARD_SHORT := 62.0
## Ammunition needs a line the others do not: which of your two guns it is for.
const CARD_AMMO := 76.0
const CURVE_SIZE := Vector2(212.0, 40.0)
## Pixels per wheel notch. A little over half a gun card, so one notch always
## brings something new into view without losing what you were reading.
const SCROLL_STEP := 76.0
## How far a thumb may travel and still count as a press rather than a scroll.
## Generous, because a thumb on a phone is never as still as a mouse is.
const TAP_SLOP := 14.0
## World scale for the range readout on a damage curve. The character is 48 px
## tall, so this puts them a bit under two metres.
const PX_PER_M := 28.0

## The slots on your body, top to bottom, and which catalogue each one opens.
## `id` is what the rest of the file matches on.
const SLOTS := [
	{"id": "primary", "label": "PRIMARY", "list": "primary"},
	{"id": "secondary", "label": "SECONDARY", "list": "secondary"},
	{"id": "helmet", "label": "HELMET", "list": "helmet"},
	{"id": "vest", "label": "VEST", "list": "vest"},
	{"id": "backpack", "label": "BACKPACK", "list": "backpack"},
	{"id": "ultimate", "label": "ULTIMATE 1", "list": "ultimate"},
	{"id": "ultimate2", "label": "ULTIMATE 2", "list": "ultimate"},
	{"id": "throw0", "label": "THROW 1", "list": "throw"},
	{"id": "throw1", "label": "THROW 2", "list": "throw"},
]

## What is on the shelf, filed by the slot it goes in. Prices are the balance
## dial for the whole loop: a rifle should hurt, a magazine should not.
const CATALOGUE := {
	"primary": [
		{"kind": "weapon", "path": "res://resources/weapons/smg.tres", "price": 900},
		{"kind": "weapon", "path": "res://resources/weapons/assault_rifle.tres", "price": 1500},
		{"kind": "weapon", "path": "res://resources/weapons/shotgun.tres", "price": 1200},
		{"kind": "weapon", "path": "res://resources/weapons/slug_shotgun.tres", "price": 1700},
		{"kind": "weapon", "path": "res://resources/weapons/lmg.tres", "price": 2200},
		{"kind": "weapon", "path": "res://resources/weapons/sniper.tres", "price": 2600},
	],
	"secondary": [
		{"kind": "weapon", "path": "res://resources/weapons/pistol.tres", "price": 250},
	],
	"helmet": [
		{"kind": "armor", "path": "res://resources/armor/light_helmet.tres", "price": 400},
		{"kind": "armor", "path": "res://resources/armor/medium_helmet.tres", "price": 750},
		{"kind": "armor", "path": "res://resources/armor/heavy_helmet.tres", "price": 1100},
	],
	"vest": [
		{"kind": "armor", "path": "res://resources/armor/light_vest.tres", "price": 500},
		{"kind": "armor", "path": "res://resources/armor/medium_vest.tres", "price": 900},
		{"kind": "armor", "path": "res://resources/armor/heavy_vest.tres", "price": 1400},
	],
	"backpack": [
		{"kind": "backpack", "path": "res://resources/backpacks/sling_bag.tres", "price": 250},
		{"kind": "backpack", "path": "res://resources/backpacks/patrol_pack.tres", "price": 700},
		{"kind": "backpack", "path": "res://resources/backpacks/assault_pack.tres", "price": 1400},
		{"kind": "backpack", "path": "res://resources/backpacks/heavy_rucksack.tres", "price": 2400},
	],
	"ultimate": [
		{"kind": "gadget", "path": "res://resources/gadgets/overload.tres", "price": 1200},
		{"kind": "gadget", "path": "res://resources/gadgets/recon_bow.tres", "price": 1000},
		{"kind": "gadget", "path": "res://resources/gadgets/projection.tres", "price": 1400},
		{"kind": "gadget", "path": "res://resources/gadgets/dash.tres", "price": 1100},
		{"kind": "gadget", "path": "res://resources/gadgets/screen.tres", "price": 1200},
	],
	"throw": [
		{"kind": "gadget", "path": "res://resources/gadgets/frag.tres", "price": 450},
		{"kind": "gadget", "path": "res://resources/gadgets/smoke.tres", "price": 300},
		{"kind": "gadget", "path": "res://resources/gadgets/flash.tres", "price": 380},
	],
	## Pockets take one cell, so only the small stuff is on offer here.
	"pocket": [
		{"kind": "ammo", "ammo": &"9mm", "rounds": 60, "price": 90},
		{"kind": "ammo", "ammo": &"5.56", "rounds": 40, "price": 120},
		{"kind": "ammo", "ammo": &"7.62", "rounds": 40, "price": 150},
		{"kind": "ammo", "ammo": &"12g", "rounds": 24, "price": 110},
		{"kind": "ammo", "ammo": &".338", "rounds": 12, "price": 260},
		# Priced at nothing on purpose, for now. Getting back up is the thing
		# being tested at the moment, and it wants testing dozens of times a
		# session rather than being rationed. This is a number to put back up
		# once picking your fights matters again.
		{"kind": "revive", "price": 10},
		{"kind": "repair", "slot": "helmet", "price": 300},
	],
	## The pack takes anything that fits, including the things too big for a
	## pocket - which is most of the reason to own one.
	"stow": [
		{"kind": "ammo", "ammo": &"9mm", "rounds": 60, "price": 90},
		{"kind": "ammo", "ammo": &"5.56", "rounds": 40, "price": 120},
		{"kind": "ammo", "ammo": &"7.62", "rounds": 40, "price": 150},
		{"kind": "ammo", "ammo": &"12g", "rounds": 24, "price": 110},
		{"kind": "ammo", "ammo": &".338", "rounds": 12, "price": 260},
		{"kind": "medkit", "price": 350},
		{"kind": "surgical", "price": 600},
		{"kind": "revive", "price": 10},
		{"kind": "repair", "slot": "vest", "price": 450},
		{"kind": "repair", "slot": "helmet", "price": 300},
	],
}

var credits := CREDITS
## What the button at the bottom says. In single player it is DEPLOY and pressing
## it starts the raid; in a match the raid starts when the countdown does, so it
## says READY and only means "I have finished spending".
var deploy_label := "DEPLOY"
## A line of match state drawn in the header - who is here, how long is left.
##
## Drawn by the shop rather than over it because the shop is opaque and sits
## later in the HUD than the screen that owns the countdown, so anything that
## screen draws lands underneath. The number belongs on top of the thing you are
## looking at anyway: you are spending against a clock, and the clock should be
## next to the money.
var status := ""
var _inventory: Inventory
## Which slot box is open, as {"id": ..., "list": ..., "label": ...}. Empty when
## nothing is selected and the picker is showing the hint instead.
var _open: Dictionary = {}
## Clickable rectangles, rebuilt every frame so they can never disagree with what
## is drawn. Same trick as the inventory screen.
var _regions: Array[Dictionary] = []
var _deploy_button := Rect2()
var _message := ""
## How far down the shelf we are, in pixels, and how far down it goes. Reset
## whenever a different slot is opened: coming back to a five-gun list halfway
## down it, because that is where you left a seven-item one, reads as items
## missing from the top.
var _scroll := 0.0
var _scroll_max := 0.0
## The band the cards scroll in, in this control's own space. Rebuilt beside the
## regions every frame, so a thumb is tested against what is actually on screen.
var _shelf := Rect2()

## Godot emulates a mouse from the first touch, and that echo is what lets a
## thumb press anything on this screen at all - it is why emulation cannot just
## be switched off (see PlayerInput.MOUSE_ACTIONS). But the echo arrives on
## *press*, before a drag has had the chance to happen, so there was no moment
## at which the shelf could be moved: a thumb going down on a gun card bought
## the gun, and dragging did nothing at all.
##
## On hardware that sends real touches the echo is ignored and this screen is
## driven from the touch events instead, which are the only ones that can tell a
## press from the beginning of a scroll. Same guard as touch_controls.gd, and
## held as a field for the same reason: a headless test can set it and pretend
## to be a phone.
var _mouse_is_an_echo := false
## Belt and braces for hardware that reports no touchscreen and sends touches
## anyway - a Windows laptop with a screen you can prod. Neither test is enough
## alone: the echo can beat the touch it came from, and a phone can be prodded
## before it is ever touched.
var _saw_touch := false
var _touching := false
var _touch_from := Vector2.ZERO
## Furthest the finger has been from where it went down, in pixels.
var _touch_travel := 0.0
var _touch_scrolls := false
## What each bought item cost, so putting something back refunds the right
## amount. Keyed by the Item itself.
var _paid := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mouse_is_an_echo = PlayerInput.has_touchscreen()
	visible = false


func open(kit: Inventory) -> void:
	_inventory = kit
	credits = CREDITS
	_open = {}
	_paid.clear()
	_message = ""
	visible = true


## Comes back to a session already in progress, with the money already spent.
##
## Deliberately not open(): that starts a fresh visit and hands the credits back,
## which during a match would mean re-opening the screen refunded everything you
## had bought and let you buy it again.
func reopen() -> void:
	if _inventory != null:
		visible = true


## Takes the screen away without emitting `deployed`. The countdown running out
## is not you pressing the button, and everything downstream of the button has
## already happened by then.
func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# --- what is in a slot --------------------------------------------------------


func _slot_item(id: String) -> Item:
	match id:
		"primary": return _inventory.primary
		"secondary": return _inventory.secondary
		"helmet": return _inventory.helmet
		"vest": return _inventory.vest
		"backpack": return _inventory.backpack_item
		"ultimate": return _inventory.get_ultimate(0)
		"ultimate2": return _inventory.get_ultimate(1)
		"throw0": return _inventory.get_throwable(0)
		"throw1": return _inventory.get_throwable(1)
	return null


## Puts an item in a slot, or clears it with null. False when the slot refused
## it - only the backpack can refuse, and only when it is too small for what is
## already inside.
func _set_slot_item(id: String, item: Item) -> bool:
	match id:
		"primary":
			_inventory.set_slot(Inventory.Slot.PRIMARY, item)
		"secondary":
			_inventory.set_slot(Inventory.Slot.SECONDARY, item)
		"helmet":
			_inventory.set_worn(Inventory.Wear.HELMET, item)
		"vest":
			_inventory.set_worn(Inventory.Wear.VEST, item)
		"backpack":
			return _inventory.set_backpack(item)
		"ultimate":
			_inventory.set_ultimate(item, 0)
		"ultimate2":
			_inventory.set_ultimate(item, 1)
		"throw0":
			_inventory.set_throwable(0, item)
		"throw1":
			_inventory.set_throwable(1, item)
	return true


# --- buying -------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	# Fingers first. The GUI routes touch and drag to whichever control is under
	# them, the same way it routes a mouse, so this screen keeps stopping input
	# over its whole rect - which is what the buttons the lobby stacks on top of
	# it rely on.
	var touch := event as InputEventScreenTouch
	if touch != null:
		_saw_touch = true
		if touch.index == 0:
			_finger(touch.position, touch.pressed)
		accept_event()
		return

	var drag := event as InputEventScreenDrag
	if drag != null:
		if drag.index == 0:
			_finger_moved(drag.position, drag.relative)
		accept_event()
		return

	var click := event as InputEventMouseButton
	if click == null or not click.pressed or _saw_touch or _mouse_is_an_echo:
		return

	# The wheel moves the shelf, wherever the pointer is. Requiring it to be over
	# the list is the kind of correctness nobody thanks you for: there is only one
	# scrolling thing on this screen.
	if click.button_index == MOUSE_BUTTON_WHEEL_UP or click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var step := -SCROLL_STEP if click.button_index == MOUSE_BUTTON_WHEEL_UP else SCROLL_STEP
		_scroll = clampf(_scroll + step, 0.0, _scroll_max)
		accept_event()
		return

	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_press(click.position)


## A finger going down, or coming back up.
func _finger(at: Vector2, down: bool) -> void:
	if down:
		_touching = true
		_touch_from = at
		_touch_travel = 0.0
		# Only a drag that began on the shelf moves it. A drag across the body
		# on the left scrolling a list on the right is the sort of thing that
		# reads as the screen having a mind of its own.
		_touch_scrolls = _shelf.has_point(at)
		return
	if not _touching:
		return
	_touching = false
	# A thumb that stayed put was pressing something. One that travelled was
	# scrolling, and must not also buy whatever it set off from.
	if _touch_travel <= TAP_SLOP:
		_press(at)


func _finger_moved(at: Vector2, by: Vector2) -> void:
	if not _touching:
		return
	# Measured from where the finger went down rather than summed along the way,
	# so a slow press with a shake in it is still a press - and a scroll that
	# comes back to where it started is still a scroll.
	_touch_travel = maxf(_touch_travel, _touch_from.distance_to(at))
	if _touch_scrolls:
		# The shelf follows the finger.
		_scroll = clampf(_scroll - by.y, 0.0, _scroll_max)


## Whatever is under the pointer, pressed. The one path a click and a tap share.
func _press(at: Vector2) -> void:
	if _deploy_button.has_point(at):
		visible = false
		deployed.emit()
		return

	for region in _regions:
		if not (region.rect as Rect2).has_point(at):
			continue
		match region.kind:
			"slot", "pocket", "pack":
				# Pressing the open slot again closes it, so the picker is never
				# stuck open over something you are trying to read.
				_open = {} if _open.get("id", "") == region.id else region.duplicate()
				_message = ""
				_scroll = 0.0
			"buy":
				_buy(region.entry)
			"clear":
				_sell_back()
		return


## Takes what is in the open slot back off the shelf, refunding what it cost.
## Nothing has been carried anywhere yet, so a full refund is right: this is
## still the shop, and second thoughts are free.
func _sell_back() -> void:
	var id: String = _open.get("id", "")
	if id.is_empty():
		return

	if id.begins_with("pocket"):
		var pocket: ItemGrid = _inventory.pockets[int(id.substr(6))]
		for item in pocket.items.duplicate():
			pocket.remove(item)
			_refund(item)
		_inventory.changed.emit()
		return

	if id == "pack":
		for item in _inventory.backpack.items.duplicate():
			_inventory.backpack.remove(item)
			_refund(item)
		_inventory.changed.emit()
		return

	var held := _slot_item(id)
	if held == null:
		return
	# Emptying the bag first, so taking it off never has to strand its contents.
	if id == "backpack":
		for item in _inventory.backpack.items.duplicate():
			_inventory.backpack.remove(item)
			_refund(item)
	if _set_slot_item(id, null):
		_refund(held)


func _refund(item: Item) -> void:
	credits += _paid.get(item, 0)
	_paid.erase(item)
	_message = "returned %s" % item.title()


func _buy(entry: Dictionary) -> void:
	var id: String = _open.get("id", "")
	if id.is_empty():
		return

	if id == "ammo":
		_buy_ammo(entry)
		return
	var price: int = entry.price
	# What is already there is refunded as part of the swap, so the question is
	# whether you can afford the difference, not the whole price again.
	var replacing := _slot_item(id) if not (id.begins_with("pocket") or id == "pack") else null
	var credit_back: int = _paid.get(replacing, 0) if replacing else 0
	if price > credits + credit_back:
		_message = "not enough credits"
		return

	var item := _make(entry)
	if item == null:
		return

	if id.begins_with("pocket"):
		_buy_into(_inventory.pockets[int(id.substr(6))], item, price)
		return
	if id == "pack":
		_buy_into(_inventory.backpack, item, price)
		return

	# A bigger bag is free to take; a smaller one has to be refused while there is
	# something in the old one that would not survive the move.
	if id == "backpack":
		var stranded := _inventory.backpack_overflow(item)
		if not stranded.is_empty():
			_message = "%s is too small - %d item(s) would not fit" % [
				item.title(), stranded.size()]
			return

	if replacing:
		_refund(replacing)
	if not _set_slot_item(id, item):
		if replacing:
			# Undo the refund: the swap never happened.
			credits -= _paid.get(replacing, 0)
			_set_slot_item(id, replacing)
		_message = "cannot equip that"
		return

	credits -= price
	_paid[item] = price
	_message = "bought %s" % item.title()

	# A gun with no ammunition is a stick, so each one comes with a magazine's
	# worth. Everything past that is bought deliberately, into a pocket or a pack.
	if entry.kind == "weapon":
		var data := load(entry.path) as WeaponData
		if _inventory.add_rounds(data.ammo_type, data.mag_size) <= 0:
			_message = "bought %s - no room for its magazine" % item.title()


## A stack of rounds, put wherever there is room for it.
##
## The whole point of the AMMUNITION button: you are buying rounds for a gun, not
## deciding which pocket they live in. Inventory.add_rounds already fills pockets
## before the pack - see Inventory.grids - which is the order you want anyway,
## since a pocket is reachable and the pack is where the loot goes.
##
## A partial fill still costs the full stack, the same bargain _buy_into makes:
## you asked for rounds and you got rounds. It says how many actually fit, so a
## pack with one cell left does not quietly eat 260 credits of .338.
func _buy_ammo(entry: Dictionary) -> void:
	var price: int = entry.price
	if price > credits:
		_message = "not enough credits"
		return
	var added := _inventory.add_rounds(entry.ammo, entry.rounds)
	if added <= 0:
		_message = "nowhere to put %s - free a pocket or buy a bigger bag" % entry.ammo
		return
	credits -= price
	_message = "bought %s x%d" % [entry.ammo, added]
	if added < entry.rounds:
		_message = "bought %s x%d - only that much would fit" % [entry.ammo, added]


## Buying into a container rather than a slot: ammunition and medkits, which
## stack and stow rather than replacing anything.
func _buy_into(grid: ItemGrid, item: Item, price: int) -> void:
	if item.is_ammo():
		# Top up a part-used stack before demanding a whole cell for a new one.
		var added := grid.add_rounds(item.ammo_type, item.count)
		if added <= 0:
			_message = "no room for that"
			return
		credits -= price
		_message = "bought %s x%d" % [item.ammo_type, added]
		return
	if not grid.add(item):
		_message = "no room for that"
		return
	credits -= price
	_paid[item] = price
	_message = "bought %s" % item.title()
	_inventory.changed.emit()


func _make(entry: Dictionary) -> Item:
	match entry.kind:
		"weapon":
			return Item.from_weapon(load(entry.path) as WeaponData)
		"armor":
			return Item.from_armor(load(entry.path) as ArmorData)
		"gadget":
			return Item.from_gadget(load(entry.path) as GadgetData)
		"backpack":
			return Item.from_backpack(load(entry.path) as BackpackData)
		"ammo":
			return Item.from_ammo(entry.ammo, entry.rounds)
		"medkit":
			return Item.from_medkit(3)
		"surgical":
			return Item.from_surgical(2)
		"revive":
			return Item.from_revive(REVIVES_PER_STACK)
		"repair":
			return Item.from_repair(ArmorData.Slot.BODY if entry.slot == "vest"
				else ArmorData.Slot.HEAD, REPAIRS_PER_KIT)
	return null


func _label(entry: Dictionary) -> String:
	match entry.kind:
		"weapon":
			return (load(entry.path) as WeaponData).display_name
		"armor":
			return (load(entry.path) as ArmorData).display_name
		"gadget":
			return (load(entry.path) as GadgetData).display_name
		"backpack":
			return (load(entry.path) as BackpackData).display_name
		"ammo":
			return "%s   x%d" % [entry.ammo, entry.rounds]
		"revive":
			return "Stim   x%d" % REVIVES_PER_STACK
		"repair":
			return ("Plate Repair Kit   x%d" if entry.slot == "vest"
				else "Helmet Repair Kit   x%d") % REPAIRS_PER_KIT
		# Named rather than left to the fallthrough below, which called it a
		# medkit - the one mistake this pair of items exists to punish.
		"surgical":
			return "Surgical Kit   x2"
	return "Medkit   x3"


func _detail(entry: Dictionary) -> String:
	match entry.kind:
		"weapon":
			var gun := load(entry.path) as WeaponData
			return "%d dmg   %d rpm   %dx%d cells" % [
				roundi(gun.get_burst_damage()), roundi(gun.rounds_per_minute),
				gun.grid_size.x, gun.grid_size.y]
		"armor":
			var piece := load(entry.path) as ArmorData
			return "stops %d%%   %d durability" % [
				roundi(piece.protection * 100.0), roundi(piece.max_durability)]
		"backpack":
			var bag := load(entry.path) as BackpackData
			return "%dx%d grid   %d cells of space" % [
				bag.grid_size.x, bag.grid_size.y, bag.grid_size.x * bag.grid_size.y]
		"gadget":
			var gadget := load(entry.path) as GadgetData
			if gadget.gadget_class == GadgetData.Class.ULTIMATE:
				return "ultimate   charges in %ds" % roundi(gadget.charge_time)
			if gadget.kind == GadgetData.Kind.FLASH:
				return "throwable   pair   blinds for %.0fs   needs line of sight" % gadget.duration
			return "throwable   pair   %dpx radius" % roundi(gadget.radius)
		"ammo":
			return "one stack, one cell"
		"revive":
			return "%d uses   get up at full health   one cell" % REVIVES_PER_STACK
		"repair":
			return ("%d uses   +%d durability each   %s   %s"
				% [REPAIRS_PER_KIT, roundi(Item.from_repair(
					ArmorData.Slot.BODY if entry.slot == "vest"
					else ArmorData.Slot.HEAD).heal),
					"vest only" if entry.slot == "vest" else "helmet only",
					"2x1 cells" if entry.slot == "vest" else "one cell"])
		"surgical":
			return "two uses, closes every wound   %.0fs to use   2x2 cells" % Player.SURGICAL_TIME
	return "three uses, 45 health each   %.0fs to use   2x1 cells" % Player.MEDKIT_TIME


# --- drawing ------------------------------------------------------------------


func _draw() -> void:
	if _inventory == null:
		return
	var font := ThemeDB.fallback_font
	_regions.clear()
	_shelf = Rect2()
	draw_rect(Rect2(Vector2.ZERO, size), BG)

	draw_string(font, Vector2(MARGIN, 54.0), "KIT UP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ACCENT)
	draw_string(font, Vector2(MARGIN, 76.0),
		"click a slot to fill it - what you take in, you can lose",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	draw_string(font, Vector2(0.0, 54.0), "%d credits" % credits,
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - MARGIN, 24, GOOD if credits > 0 else BAD)
	if not status.is_empty():
		draw_string(font, Vector2(0.0, 76.0), status,
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - MARGIN, 14, ACCENT)

	var top := 100.0
	_draw_slots(Vector2(MARGIN, top))
	_draw_carried(Vector2(MARGIN + SLOT_W + 30.0, top))
	_draw_picker(Vector2(size.x - MARGIN - PICK_W, top))

	# Wide enough for what is written on it. The label is not always DEPLOY -
	# queuing for a match says so at length - and a fixed 220 px printed the last
	# third of it onto the background.
	var button_w := maxf(220.0,
		font.get_string_size(deploy_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 48.0)
	_deploy_button = Rect2(Vector2(size.x * 0.5 - button_w * 0.5, size.y - 62.0),
		Vector2(button_w, 40.0))
	draw_rect(_deploy_button, ACCENT)
	draw_string(font, _deploy_button.position + Vector2(0.0, 27.0), deploy_label,
		HORIZONTAL_ALIGNMENT_CENTER, _deploy_button.size.x, 19, Color(0.07, 0.08, 0.1))

	if not _message.is_empty():
		draw_string(font, Vector2(0.0, size.y - 76.0), _message,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, DIM)


## The body: one clickable box per slot, filled or not. A box shows the footprint
## the thing in it takes up, so the shape of your kit is visible while you spend
## rather than only once you are looking at the grid.
func _draw_slots(at: Vector2) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, at, "LOADOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ACCENT)
	var y := at.y + 14.0

	for slot in SLOTS:
		var box := Rect2(Vector2(at.x, y), Vector2(SLOT_W, SLOT_H))
		var item := _slot_item(slot.id)
		var selected: bool = _open.get("id", "") == slot.id
		_regions.append({
			"kind": "slot", "rect": box, "id": slot.id,
			"list": slot.list, "label": slot.label,
		})

		draw_rect(box, PANEL if selected else SLOT_BG)
		draw_rect(box, ACCENT if selected else LINE, false, 2.0 if selected else 1.0)
		draw_string(font, box.position + Vector2(10.0, 17.0), slot.label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ACCENT if selected else DIM)

		if item:
			_draw_footprint(item, Vector2(box.end.x - 14.0, box.position.y + 9.0))
			draw_string(font, box.position + Vector2(10.0, 36.0), item.label(),
				HORIZONTAL_ALIGNMENT_LEFT, SLOT_W - 90.0, 14, TEXT)
		else:
			draw_string(font, box.position + Vector2(10.0, 36.0), "empty",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(DIM, 0.7))
		y += SLOT_H + SLOT_GAP

	_draw_ammo_button(Vector2(at.x, y + 8.0))


## One button for ammunition, instead of buying it a pocket at a time.
##
## Ammunition is the one purchase that is not a choice about what to carry - it
## is a consequence of the guns you already picked - so making you open five
## separate pockets and match calibres by eye was busywork standing in for a
## decision. This asks the loadout what it feeds and offers exactly that.
func _draw_ammo_button(at: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var box := Rect2(at, Vector2(SLOT_W, SLOT_H))
	var selected: bool = _open.get("id", "") == "ammo"
	_regions.append({
		"kind": "slot", "rect": box, "id": "ammo", "list": "ammo", "label": "AMMUNITION",
	})

	var feeds := _calibres_carried()
	draw_rect(box, PANEL if selected else SLOT_BG)
	draw_rect(box, ACCENT if selected else LINE, false, 2.0 if selected else 1.0)
	draw_string(font, box.position + Vector2(10.0, 17.0), "AMMUNITION",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ACCENT if selected else DIM)

	if feeds.is_empty():
		draw_string(font, box.position + Vector2(10.0, 36.0), "no guns to feed",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(DIM, 0.7))
		return

	# The calibres themselves, each in the colour of the hand it feeds, so the
	# mapping is on the button before you have opened anything.
	var x := box.position.x + 10.0
	for calibre in feeds:
		var tint: Color = _fed_by(calibre).tint
		var text := String(calibre)
		draw_string(font, Vector2(x, box.position.y + 36.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0

	draw_string(font, box.position + Vector2(0.0, 36.0),
		"%d rounds" % _inventory.total_rounds(),
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 12.0, 12, DIM)


## Every calibre the guns in your hands actually take, in the order they sit in
## your loadout and without repeats - two 9mm weapons is one line, not two.
func _calibres_carried() -> Array[StringName]:
	var found: Array[StringName] = []
	for item in [_inventory.primary, _inventory.secondary]:
		if item and item.weapon and not found.has(item.weapon.ammo_type):
			found.append(item.weapon.ammo_type)
	return found


## An item's grid footprint, drawn small and right-aligned to `right_edge`.
func _draw_footprint(item: Item, right_edge: Vector2) -> void:
	var colour := item.tint()
	var span := Vector2(item.size) * (CELL + GAP)
	var corner := Vector2(right_edge.x - span.x, right_edge.y)
	for cy in item.size.y:
		for cx in item.size.x:
			draw_rect(Rect2(corner + Vector2(cx, cy) * (CELL + GAP), Vector2(CELL, CELL)),
				Color(colour.r * 0.5, colour.g * 0.5, colour.b * 0.55))
	draw_rect(Rect2(corner, span - Vector2(GAP, GAP)), colour, false, 1.0)


## Pockets and the pack: the space you are carrying it all in. Each pocket is
## its own box because each pocket is its own container - drawing them as one
## strip of five would suggest a medkit could lie across two of them.
func _draw_carried(at: Vector2) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, at, "POCKETS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ACCENT)
	draw_string(font, at + Vector2(66.0, 0.0), "one cell each - small things only",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)

	var y := at.y + 14.0
	for i in _inventory.pockets.size():
		var pocket: ItemGrid = _inventory.pockets[i]
		var box := Rect2(Vector2(at.x + i * (POCKET_BOX + 6.0), y),
			Vector2(POCKET_BOX, POCKET_BOX))
		var id := "pocket%d" % i
		var selected: bool = _open.get("id", "") == id
		_regions.append({
			"kind": "pocket", "rect": box, "id": id,
			"list": "pocket", "label": "POCKET %d" % (i + 1),
		})
		draw_rect(box, CELL_BG)
		draw_rect(box, ACCENT if selected else LINE, false, 2.0 if selected else 1.0)
		var held := pocket.item_at(Vector2i.ZERO)
		if held:
			_draw_stack(held, box)
		else:
			draw_string(font, box.position + Vector2(0.0, 25.0), str(i + 1),
				HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 13, Color(DIM, 0.5))
	y += POCKET_BOX + 26.0

	# The pack, drawn at the size it actually is. An empty back is an empty
	# rectangle with the reason written in it, not a missing panel.
	var bag := _inventory.backpack_item
	var title := "BACKPACK" if bag == null else "BACKPACK  %s" % bag.backpack.display_name
	draw_string(font, Vector2(at.x, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ACCENT)
	draw_string(font, Vector2(at.x, y + 14.0),
		"%d/%d cells" % [_inventory.backpack.used_cells(), _inventory.backpack.cell_count()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	y += 24.0

	if bag == null:
		var empty := Rect2(Vector2(at.x, y), Vector2(240.0, 60.0))
		draw_rect(empty, SLOT_BG)
		draw_rect(empty, LINE, false, 1.0)
		draw_string(font, empty.position + Vector2(0.0, 26.0), "no bag",
			HORIZONTAL_ALIGNMENT_CENTER, empty.size.x, 13, DIM)
		draw_string(font, empty.position + Vector2(0.0, 44.0),
			"buy one in the BACKPACK slot", HORIZONTAL_ALIGNMENT_CENTER,
			empty.size.x, 10, Color(DIM, 0.7))
		return

	var grid := _inventory.backpack
	var box := Rect2(Vector2(at.x, y),
		Vector2(grid.width, grid.height) * (PACK_CELL + GAP))
	var selected: bool = _open.get("id", "") == "pack"
	_regions.append({
		"kind": "pack", "rect": box, "id": "pack", "list": "stow", "label": "BACKPACK",
	})
	for cy in grid.height:
		for cx in grid.width:
			draw_rect(Rect2(box.position + Vector2(cx, cy) * (PACK_CELL + GAP),
				Vector2(PACK_CELL, PACK_CELL)), CELL_BG)
	for item in grid.items:
		_draw_stack(item, Rect2(box.position + Vector2(item.cell) * (PACK_CELL + GAP),
			Vector2(item.size) * (PACK_CELL + GAP) - Vector2(GAP, GAP)))
	if selected:
		draw_rect(box, ACCENT, false, 2.0)


## One item drawn into a box: tinted from what it is, named, counted. The two
## lines are placed off the box's own height rather than at fixed offsets - a
## pack cell is half the height of a pocket, and hard-coded baselines printed the
## count straight through the name.
func _draw_stack(item: Item, box: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var colour := item.tint()
	draw_rect(box, Color(colour.r * 0.3, colour.g * 0.3, colour.b * 0.34))
	draw_rect(box, colour, false, 1.0)

	var counted := item.is_ammo() or item.is_medkit() or item.is_surgical()
	var tight := box.size.y < 34.0
	var text_size := 9 if tight else 10
	draw_string(font, box.position + Vector2(0.0, 11.0 if tight else 15.0), item.title(),
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, text_size, TEXT)
	if counted:
		draw_string(font, box.position + Vector2(0.0, box.size.y - 4.0), "x%d" % item.count,
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, text_size, ACCENT)


## What goes in the slot you clicked, and nothing else. This is the whole point
## of the screen: the matching is done for you, so the list is short and every
## line on it is a real choice.
##
## A scrolling column of cards rather than a list of rows. A gun is the largest
## decision on this screen and the numbers behind it - what it does at range,
## what it does to your aim - are the whole of the decision, so a gun gets a card
## big enough to show them and you scroll through five of those rather than
## squint at five lines.
func _draw_picker(at: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var panel := Rect2(at, Vector2(PICK_W, size.y - at.y - 86.0))
	draw_rect(panel, PANEL)

	if _open.is_empty():
		draw_rect(panel, LINE, false, 1.0)
		draw_string(font, at + Vector2(18.0, 34.0), "NOTHING SELECTED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
		draw_string(font, at + Vector2(18.0, 60.0),
			"Click any slot on the left to see what fits it.",
			HORIZONTAL_ALIGNMENT_LEFT, PICK_W - 36.0, 12, Color(DIM, 0.8))
		draw_string(font, at + Vector2(18.0, 88.0),
			"Pockets hold one cell each, so only magazines go in them.\nAnything bigger needs a backpack, and the backpack is a\nslot like any other - you have to buy one.\n\nAMMUNITION is its own button: it offers the calibres your\nguns actually take and stows them wherever there is room.",
			HORIZONTAL_ALIGNMENT_LEFT, PICK_W - 36.0, 12, Color(DIM, 0.6))
		return

	var entries := _entries_for(_open.list)

	# What is in the slot already, offered back at full price. Pinned above the
	# scrolling column rather than sitting in it: it is about the slot, not about
	# the shelf, and it should not scroll away from the thing it refers to. Drawn
	# after the mask below, or the mask paints over it.
	var head := at.y + 48.0
	var clear_box := Rect2()
	if _can_clear():
		clear_box = Rect2(Vector2(at.x + 14.0, head), Vector2(PICK_W - 28.0, 30.0))
		_regions.append({"kind": "clear", "rect": clear_box, "id": "clear"})
		head += 40.0

	# The band the cards live in. Everything below is drawn into it and masked
	# back to it afterwards - _draw has no scissor, so the panel colour is painted
	# over the overspill instead.
	var view := Rect2(Vector2(at.x, head), Vector2(PICK_W, panel.end.y - head - 26.0))
	_shelf = view
	var y := view.position.y - _scroll
	var content := 0.0

	var feeding: bool = _open.get("list", "") == "ammo"
	for entry in entries:
		var tall := CARD_SHORT
		if entry.kind == "weapon":
			tall = CARD_TALL
		elif feeding:
			tall = CARD_AMMO
		var box := Rect2(Vector2(view.position.x + 14.0, y), Vector2(PICK_W - 40.0, tall - 8.0))
		# Only what is actually on screen is drawn, and only what is drawn can be
		# clicked - a card scrolled out of sight must not still be a hit target
		# hiding under the header.
		if box.end.y > view.position.y and box.position.y < view.end.y:
			_regions.append({"kind": "buy", "rect": box, "entry": entry, "id": "buy"})
			if entry.kind == "weapon":
				_draw_weapon_card(box, entry)
			elif feeding:
				_draw_ammo_card(box, entry)
			else:
				_draw_plain_card(box, entry)
		y += tall
		content += tall

	_scroll_max = maxf(content - view.size.y, 0.0)

	# The mask. A card is up to 132 px tall and is drawn whole the moment any part
	# of it is in view, so it overhangs both ends of the band and past the panel
	# itself - the strips have to run to the edges of the screen, not to the edges
	# of the panel, or the overhang lands on the background where nothing covers it.
	var strip := Vector2(panel.size.x, 0.0)
	draw_rect(Rect2(Vector2(panel.position.x, 0.0),
		Vector2(strip.x, panel.position.y)), BG)
	draw_rect(Rect2(panel.position,
		Vector2(strip.x, view.position.y - panel.position.y)), PANEL)
	draw_rect(Rect2(Vector2(panel.position.x, view.end.y),
		Vector2(strip.x, panel.end.y - view.end.y)), PANEL)
	draw_rect(Rect2(Vector2(panel.position.x, panel.end.y),
		Vector2(strip.x, size.y - panel.end.y)), BG)
	draw_rect(panel, LINE, false, 1.0)

	draw_string(font, at + Vector2(18.0, 30.0), _open.label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ACCENT)
	if clear_box.size.x > 0.0:
		draw_rect(clear_box, SLOT_BG)
		draw_rect(clear_box, BAD, false, 1.0)
		draw_string(font, clear_box.position + Vector2(12.0, 20.0),
			"put it back  -  full refund", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BAD)
	if entries.is_empty():
		draw_string(font, view.position + Vector2(18.0, 28.0),
			"buy a primary or a secondary first - this offers what they take",
			HORIZONTAL_ALIGNMENT_LEFT, PICK_W - 36.0, 12, Color(DIM, 0.8))

	draw_string(font, Vector2(at.x + 18.0, panel.end.y - 12.0),
		"%d rounds carried   -   %d/%d cells used" % [
			_inventory.total_rounds(), _inventory.used_cells(), _inventory.total_cells()],
		HORIZONTAL_ALIGNMENT_LEFT, PICK_W - 36.0, 11, DIM)

	_draw_scrollbar(view)


## Where the shelf comes from. Every list but one is a fixed catalogue; AMMUNITION
## is built from what you are carrying, which is the point of it.
##
## Walked in loadout order rather than catalogue order, so the primary's calibre
## is always the top line. Which gun a box of rounds is for is the only question
## being asked here, and the answer should be the order they are in.
func _entries_for(list: String) -> Array:
	if list != "ammo":
		return CATALOGUE.get(list, [])
	var out: Array = []
	for calibre in _calibres_carried():
		for entry in CATALOGUE["pocket"]:
			if entry.get("kind", "") == "ammo" and entry.ammo == calibre:
				out.append(entry)
				break
	return out


## Which gun a calibre feeds, as the role and the weapon's name. Both roles when
## the two guns share a calibre - which is worth seeing, because it is the whole
## argument for carrying a matched pair.
func _fed_by(calibre: StringName) -> Dictionary:
	var roles: Array[String] = []
	var guns: Array[String] = []
	for pair in [["PRIMARY", _inventory.primary], ["SECONDARY", _inventory.secondary]]:
		var item := pair[1] as Item
		if item and item.weapon and item.weapon.ammo_type == calibre:
			roles.append(pair[0])
			guns.append(item.weapon.display_name)
	var tint := PRIMARY_TAG if roles.size() == 1 and roles[0] == "PRIMARY" else SECONDARY_TAG
	if roles.size() > 1:
		tint = GOOD
	return {"tag": " + ".join(roles), "guns": ", ".join(guns), "tint": tint}


## Whether the open slot has anything in it to hand back. Ammunition never does:
## it is spread across whatever had room for it rather than sitting in one place,
## so there is no "it" to put back.
func _can_clear() -> bool:
	match _open.get("kind", ""):
		"pocket":
			return not (_inventory.pockets[int(String(_open.id).substr(6))] as ItemGrid).items.is_empty()
		"pack":
			return not _inventory.backpack.items.is_empty()
		"slot":
			return _open.get("id", "") != "ammo" and _slot_item(_open.id) != null
	return false


## A gun, at the size a gun deserves: what it does up close, what it still does
## far away, and the four numbers that decide whether you can hold it on target.
##
## These used to be on the in-game HUD, where they were unreadable and useless -
## you cannot change your mind about a rifle mid-raid. Here they are the decision.
func _draw_weapon_card(box: Rect2, entry: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var data := load(entry.path) as WeaponData
	if data == null:
		return
	var affordable: bool = entry.price <= credits
	var held: bool = _is_equipped(data)

	draw_rect(box, PANEL.lightened(0.04) if held else SLOT_BG)
	draw_rect(box, ACCENT if held else LINE, false, 2.0 if held else 1.0)

	draw_string(font, box.position + Vector2(14.0, 24.0), data.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 120.0, 17, TEXT if affordable else DIM)
	draw_string(font, box.position + Vector2(0.0, 24.0), "%d" % entry.price,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 16, ACCENT if affordable else BAD)
	draw_string(font, box.position + Vector2(14.0, 40.0),
		"%s   %d rpm   %dx%d cells%s" % [data.ammo_type, roundi(data.rounds_per_minute),
			data.grid_size.x, data.grid_size.y,
			"   x%d pellets" % data.pellets if data.pellets > 1 else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	if held:
		draw_string(font, box.position + Vector2(0.0, 40.0), "IN YOUR HANDS",
			HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 10, ACCENT)

	# Left: what it hits for, and how far that lasts.
	_draw_damage_curve(Rect2(box.position + Vector2(14.0, 54.0), CURVE_SIZE), data)

	# Right: how much of that you will actually land.
	var stat_x := box.position.x + 14.0 + CURVE_SIZE.x + 22.0
	var stat_w := box.end.x - 14.0 - stat_x
	var y := box.position.y + 62.0
	for pair in [["ACCURACY", data.accuracy, false], ["HANDLING", data.handling, false],
			["RECOIL", data.recoil, true], ["STABILITY", data.stability, false]]:
		_draw_stat_bar(Vector2(stat_x, y), pair[0], pair[1], pair[2], stat_w)
		y += 16.0


## Damage per trigger pull against distance: flat out to falloff_start, sloping
## to falloff_end, flat after. The shape tells you what the gun is for without
## having to memorise any of the numbers.
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


## Recoil is the one stat where a full bar is bad news, so it is drawn in the
## opposite colour to keep the card honest at a glance.
func _draw_stat_bar(at: Vector2, label: String, value: float, inverted: bool,
		width: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(at.x, at.y), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)
	var bar := Rect2(Vector2(at.x + 62.0, at.y - 8.0), Vector2(maxf(width - 92.0, 20.0), 8.0))
	draw_rect(bar, Color(0.16, 0.18, 0.22))
	var fill := clampf(value * 0.01, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)),
		BAD.lerp(GOOD, 1.0 - fill if inverted else fill))
	draw_string(font, Vector2(bar.end.x + 6.0, at.y), str(roundi(value)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)


## A box of rounds, with the gun it belongs to written on it.
##
## Two calibres side by side are two nearly identical lines - "5.56 x40" and
## "9mm x60" - and which one feeds which hand is exactly the thing you cannot
## afford to get wrong, because you find out in a firefight. So the role is a
## coloured chip down the left rather than a word in a sentence: amber for the
## primary, blue for the secondary, green when one calibre feeds both.
func _draw_ammo_card(box: Rect2, entry: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var affordable: bool = entry.price <= credits
	var fed := _fed_by(entry.ammo)
	var tint: Color = fed.tint

	draw_rect(box, SLOT_BG)
	draw_rect(box, LINE, false, 1.0)
	# A stripe in the role's colour down the whole left edge, so the two cards
	# differ at a glance and not only where the label is.
	draw_rect(Rect2(box.position, Vector2(4.0, box.size.y)), tint)

	var chip := Rect2(box.position + Vector2(16.0, 12.0), Vector2(104.0, 18.0))
	draw_rect(chip, Color(tint.r, tint.g, tint.b, 0.16))
	draw_rect(chip, tint, false, 1.0)
	draw_string(font, chip.position + Vector2(0.0, 13.0), fed.tag,
		HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 9, tint)

	draw_string(font, box.position + Vector2(132.0, 27.0), _label(entry),
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 240.0, 16, TEXT if affordable else DIM)
	draw_string(font, box.position + Vector2(0.0, 27.0), "%d" % entry.price,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 15, ACCENT if affordable else BAD)

	# The gun by name under the chip. The chip says which hand; this says which
	# gun, and with two rifles in the same calibre that is the difference.
	draw_string(font, box.position + Vector2(16.0, 48.0), fed.guns,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 150.0, 11, DIM)
	draw_string(font, box.position + Vector2(0.0, 48.0),
		"carrying %d" % _rounds_of(entry.ammo),
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 11, DIM)


## Everything that is not a gun: armour, bags, gadgets, stims. One line of what
## it is and one of what it does, at a size you can hit.
func _draw_plain_card(box: Rect2, entry: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var affordable: bool = entry.price <= credits
	draw_rect(box, SLOT_BG)
	draw_rect(box, LINE, false, 1.0)

	draw_string(font, box.position + Vector2(14.0, 24.0), _label(entry),
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 110.0, 15, TEXT if affordable else DIM)
	draw_string(font, box.position + Vector2(14.0, 42.0), _detail(entry),
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 110.0, 10, DIM)
	draw_string(font, box.position + Vector2(0.0, 26.0), "%d" % entry.price,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 15, ACCENT if affordable else BAD)

	# For ammunition, how much of it you are already carrying. It is the number
	# that decides whether to buy another stack, and counting cells to find out
	# is exactly the work this button exists to remove.
	if entry.get("kind", "") == "ammo":
		draw_string(font, box.position + Vector2(0.0, 42.0),
			"carrying %d" % _rounds_of(entry.ammo),
			HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 10, DIM)


func _rounds_of(calibre: StringName) -> int:
	var total := 0
	for grid in _inventory.grids():
		for item in grid.items:
			if item.is_ammo() and item.ammo_type == calibre:
				total += item.count
	return total


func _is_equipped(data: WeaponData) -> bool:
	for item in [_inventory.primary, _inventory.secondary]:
		if item and item.weapon == data:
			return true
	return false


## Only when there is something to scroll. A track that is always there on a list
## of two implies there is more below it, which is the one thing a scrollbar must
## never lie about.
func _draw_scrollbar(view: Rect2) -> void:
	if _scroll_max <= 0.0:
		return
	var track := Rect2(Vector2(view.end.x - 8.0, view.position.y), Vector2(4.0, view.size.y))
	draw_rect(track, Color(LINE, 0.5))
	var span := view.size.y / (view.size.y + _scroll_max)
	var thumb_h := maxf(view.size.y * span, 24.0)
	var travel := (view.size.y - thumb_h) * (_scroll / _scroll_max)
	draw_rect(Rect2(Vector2(track.position.x, track.position.y + travel),
		Vector2(track.size.x, thumb_h)), Color(ACCENT, 0.75))
