class_name Inventory
extends RefCounted

## What a person is carrying: two guns in hand, and two grids of space.
##
## Everyone uses this - the player and every guard - which is what makes looting
## work. A body is just an inventory that has stopped moving, and taking from it
## is a transfer between two of these.
##
##   primary / secondary  what you can shoot right now
##   pockets              five single cells, each its own container
##   backpack             the big grid - only as big as the bag you bought
##
## Pockets are five separate one-cell containers rather than one grid, which is
## the point of them: a pocket holds a magazine, and nothing you own spans two of
## them. Anything larger than a single cell has to go in the pack, and if you did
## not buy a pack it does not come with you.
##
## Ammunition is stacks of rounds sitting in those grids, not a number attached
## to a gun. Two weapons in the same calibre feed from the same stacks, and a
## stack takes up a cell whether you like it or not - so what you can carry out
## of a fight is a decision about space, not a list of items.

signal changed()

enum Slot { PRIMARY, SECONDARY }
enum Wear { HELMET, VEST }
## Two ultimates, two throwables. The whole of your kit beyond guns and armour.
const THROWABLE_SLOTS := 2
## Five, and each one a single cell. A 1x1 grid refuses anything bigger on its
## own, so "only small things in pockets" needs no rule of its own.
const POCKET_COUNT := 5

var primary: Item
var secondary: Item
## Worn armour. Not in a grid: it is on you, not in a bag.
var helmet: Item
var vest: Item
## The charged gadgets, and the two things you can throw. Two ultimate slots,
## kept as a list for the same reason the throwables are: they are the same kind
## of thing in the same kind of holder, and code that wants "the one that is a
## bow" should be able to look rather than remember which hand it went in.
var ultimates: Array[Item] = [null, null]
var throwables: Array[Item] = [null, null]
## Five one-cell containers, each independent of the others.
var pockets: Array[ItemGrid] = []
## The bag being worn. Its contents live on the bag itself (Item.contents), so
## the grid below is a view of whatever is currently on your back - and taking a
## bag off takes the kit inside it along with the space.
var backpack_item: Item
## No bag means a grid of nothing, which refuses everything without needing to be
## checked for separately.
var backpack: ItemGrid:
	get:
		return backpack_item.contents if backpack_item != null else _no_bag

## The grid stood in for an empty back. One per inventory, never written to.
var _no_bag := ItemGrid.new(0, 0)


func _init() -> void:
	pockets = []
	for i in POCKET_COUNT:
		pockets.append(ItemGrid.new(1, 1))


## Every container, nearest to hand first. Anything looking for ammunition or for
## space searches in this order, so pockets are used before the pack.
func grids() -> Array[ItemGrid]:
	var list: Array[ItemGrid] = []
	list.append_array(pockets)
	list.append(backpack)
	return list


## Cells across every pocket and the pack - what "how much can I carry" means.
func total_cells() -> int:
	var total := 0
	for grid in grids():
		total += grid.cell_count()
	return total


func used_cells() -> int:
	var used := 0
	for grid in grids():
		used += grid.used_cells()
	return used


# --- the bag ------------------------------------------------------------------


## Puts a bag on, moving what the old one held into the new one. Refused if it
## will not all fit, rather than quietly binning the overflow: losing kit should
## always be something you did, not something that happened to you.
## Puts a bag on. Whatever was in your old bag moves across into the new one,
## alongside anything the new one already contains - so wearing a looted pack
## keeps its kit and yours. Refused if it will not all fit, rather than quietly
## binning the overflow: losing kit should always be something you did, not
## something that happened to you.
##
## Passing null takes the bag off. The contents go with it, still inside it.
func set_backpack(item: Item) -> bool:
	if item != null and not item.is_backpack():
		return false
	if item == backpack_item:
		return true

	var moving := backpack.items.duplicate()
	if item == null:
		# Nowhere to put your old contents except the bag they are already in,
		# which is leaving with you. That is the point.
		backpack_item = null
		changed.emit()
		return true

	var was := _saved_cells(moving)
	for held in moving:
		if not item.contents.add(held):
			# Put back everything already moved, then the cells, and refuse.
			for undo in moving:
				if item.contents.items.has(undo):
					item.contents.remove(undo)
			_restore_cells(was)
			return false

	if backpack_item:
		for held in moving:
			backpack_item.contents.remove(held)
	backpack_item = item
	changed.emit()
	return true


## What your current pack would have to leave behind to be swapped for this one.
## Empty when the swap is clean - which is what the shop asks before offering it.
func backpack_overflow(item: Item) -> Array[Item]:
	if item == null:
		return [] as Array[Item]
	var trial := ItemGrid.new(item.backpack.grid_size.x, item.backpack.grid_size.y)
	# Whatever is already in the incoming bag keeps its place; yours has to fit
	# around it.
	for held in item.contents.items:
		trial.place(held, held.cell)

	var moving := backpack.items
	var was := _saved_cells(moving)
	var overflow: Array[Item] = []
	for held in moving:
		if not trial.add(held):
			overflow.append(held)
	_restore_cells(was)
	return overflow


## Whether this inventory is currently holding an item anywhere on it.
func holds(item: Item) -> bool:
	if item == null:
		return false
	if item in [primary, secondary, helmet, vest, backpack_item] or ultimates.has(item):
		return true
	if throwables.has(item):
		return true
	return grid_holding(item) != null


## Laying items out writes their cells, so a caller that might not commit has to
## be able to put the old ones back.
func _saved_cells(items: Array[Item]) -> Array:
	var saved := []
	for held in items:
		saved.append([held, held.cell])
	return saved


func _restore_cells(saved: Array) -> void:
	for pair in saved:
		(pair[0] as Item).cell = pair[1]


# --- weapons ------------------------------------------------------------------


## Whether this weapon is allowed in that slot.
##
## The two slots are different jobs, not two of the same: the secondary is a
## holster and only a sidearm fits it, and the primary is where a long gun is
## carried - a pistol slung across your back is not a primary weapon. Between
## them that means one of each, which is the loadout decision.
func can_hold(item: Item, slot: Slot) -> bool:
	if item == null or not item.is_weapon():
		return false
	if slot == Slot.SECONDARY:
		return item.weapon.sidearm
	return not item.weapon.sidearm


func get_worn(where: Wear) -> Item:
	return helmet if where == Wear.HELMET else vest


func set_worn(where: Wear, item: Item) -> void:
	if where == Wear.HELMET:
		helmet = item
	else:
		vest = item
	changed.emit()


func get_throwable(index: int) -> Item:
	return throwables[index] if index >= 0 and index < throwables.size() else null


func set_throwable(index: int, item: Item) -> void:
	if index < 0 or index >= throwables.size():
		return
	throwables[index] = item
	changed.emit()


func set_ultimate(item: Item, index := 0) -> void:
	ultimates[clampi(index, 0, ultimates.size() - 1)] = item
	changed.emit()


## The ultimate in a slot, or null. Bounds-checked, because the callers are
## screens and input handlers that count from whatever the player pressed.
func get_ultimate(index: int) -> Item:
	if index < 0 or index >= ultimates.size():
		return null
	return ultimates[index]


## The first slot holding a gadget of this kind, or -1.
##
## What the gameplay actually wants to ask. A bow behaves like a bow whichever
## slot it went into, and making every caller remember which one it was is how
## the second slot would quietly only work for one of them.
func slot_of_kind(kind: int) -> int:
	for i in ultimates.size():
		var item: Item = ultimates[i]
		if item and item.gadget and item.gadget.kind == kind:
			return i
	return -1


## The first empty ultimate slot, or -1 when both are full.
func free_ultimate_slot() -> int:
	for i in ultimates.size():
		if ultimates[i] == null:
			return i
	return -1


## Whether a piece of armour belongs in that worn slot.
func can_wear(item: Item, where: Wear) -> bool:
	if item == null or not item.is_armor():
		return false
	var wanted := ArmorData.Slot.HEAD if where == Wear.HELMET else ArmorData.Slot.BODY
	return item.armor.slot == wanted


func get_slot(slot: Slot) -> Item:
	return primary if slot == Slot.PRIMARY else secondary


func set_slot(slot: Slot, item: Item) -> void:
	if slot == Slot.PRIMARY:
		primary = item
	else:
		secondary = item
	changed.emit()


## Guns in hand, then guns riding in the grids. What a body offers up, and what
## the 1-5 keys reach.
func all_weapons() -> Array[Item]:
	var list: Array[Item] = []
	if primary:
		list.append(primary)
	if secondary:
		list.append(secondary)
	list.append_array(stowed_weapons())
	return list


## Everything on the body, worn or stowed - what looting walks through.
func all_items() -> Array[Item]:
	var list: Array[Item] = []
	for item in ([primary, secondary, helmet, vest, backpack_item] + ultimates):
		if item:
			list.append(item)
	for item in throwables:
		if item:
			list.append(item)
	for grid in grids():
		list.append_array(grid.items)
	return list


func stowed_weapons() -> Array[Item]:
	var list: Array[Item] = []
	for grid in grids():
		for item in grid.items:
			if item.is_weapon():
				list.append(item)
	return list


## Puts an item somewhere sensible: a gun into a free hand first, then either
## grid. Returns false when there is nowhere for it - which leaves it on the
## body it came from rather than deleting it.
func store(item: Item) -> bool:
	if item == null:
		return false
	if item.is_armor():
		var where := Wear.HELMET if item.armor.slot == ArmorData.Slot.HEAD else Wear.VEST
		if get_worn(where) == null:
			set_worn(where, item)
			return true
	if item.is_ultimate() and free_ultimate_slot() >= 0:
		set_ultimate(item, free_ultimate_slot())
		return true
	# A bag goes on your back if your back is empty, and into the bag you are
	# already wearing otherwise - a spare pack is loot like anything else.
	if item.is_backpack() and backpack_item == null:
		if set_backpack(item):
			return true
	if item.is_throwable():
		for i in throwables.size():
			# Stack onto a matching slot before taking up a second one.
			var held := throwables[i]
			if held and held.gadget == item.gadget:
				held.count += item.count
				changed.emit()
				return true
		for i in throwables.size():
			if throwables[i] == null:
				set_throwable(i, item)
				return true
	if item.is_weapon():
		# Straight to the hand it belongs in, if that hand is empty. Picking up a
		# rifle should arm you with it, not bury it in the pack.
		var home := Slot.SECONDARY if item.weapon.sidearm else Slot.PRIMARY
		if get_slot(home) == null:
			set_slot(home, item)
			return true
	for grid in grids():
		if grid.add(item):
			changed.emit()
			return true
	return false


## Brings a stowed gun to hand, putting whatever was in that hand where the new
## one came from. A straight swap: nothing is ever dropped by accident.
func equip_stowed(index: int, slot: Slot = Slot.PRIMARY) -> bool:
	var stowed := stowed_weapons()
	if index < 0 or index >= stowed.size():
		return false

	var incoming := stowed[index]
	if not can_hold(incoming, slot):
		return false
	var home := grid_holding(incoming)
	var at := incoming.cell
	var outgoing := get_slot(slot)

	home.remove(incoming)
	if outgoing:
		# Try to put the old gun exactly where the new one was; if it is a
		# bigger gun and will not fit there, anywhere in the same grid will do.
		if not home.place(outgoing, at):
			if not home.add(outgoing) and not store(outgoing):
				home.place(incoming, at) # nowhere for it: undo the whole swap
				return false
	set_slot(slot, incoming)
	return true


func grid_holding(item: Item) -> ItemGrid:
	for grid in grids():
		if grid.items.has(item):
			return grid
	return null


## Takes an item out of wherever it is being carried, without placing it.
func remove_item(item: Item) -> void:
	if primary == item:
		primary = null
	elif secondary == item:
		secondary = null
	elif helmet == item:
		helmet = null
	elif vest == item:
		vest = null
	elif ultimates.has(item):
		ultimates[ultimates.find(item)] = null
	elif backpack_item == item:
		# The bag leaves with everything still inside it.
		backpack_item = null
	elif throwables.has(item):
		throwables[throwables.find(item)] = null
	else:
		var home := grid_holding(item)
		if home:
			home.remove(item)
	changed.emit()


# --- ammunition ---------------------------------------------------------------


func rounds_of(calibre: StringName) -> int:
	var total := 0
	for grid in grids():
		total += grid.rounds_of(calibre)
	return total


## Pulls rounds for a reload, emptying pockets before the pack.
func take_rounds(calibre: StringName, wanted: int) -> int:
	var taken := 0
	for grid in grids():
		if taken >= wanted:
			break
		taken += grid.take_rounds(calibre, wanted - taken)
	if taken > 0:
		changed.emit()
	return taken


## Stuffs rounds in wherever they fit. Returns how many actually went in, so a
## caller looting a body knows what to leave behind.
func add_rounds(calibre: StringName, rounds: int) -> int:
	var added := 0
	for grid in grids():
		if added >= rounds:
			break
		added += grid.add_rounds(calibre, rounds - added)
	if added > 0:
		changed.emit()
	return added


func total_rounds() -> int:
	var total := 0
	for grid in grids():
		for item in grid.items:
			if item.is_ammo():
				total += item.count
	return total


# --- looting ------------------------------------------------------------------


## Takes everything from `other` that there is room for, leaving the rest.
## Guns first, since a rifle you cannot fit is a worse miss than loose rounds.
func take_everything_from(other: Inventory) -> Dictionary:
	var guns: Array[String] = []
	var ammo := {}

	# His bag first: taking it takes the space and everything in it at once, which
	# is usually the best thing on the body and often the only way the rest of it
	# would have fitted anyway.
	var order := other.all_items()
	if other.backpack_item:
		order.erase(other.backpack_item)
		order.push_front(other.backpack_item)

	for item in order:
		if item.is_ammo():
			continue
		# Anything that was inside a bag we already took has moved with it, and is
		# no longer his to hand over. Taking it again would duplicate it.
		if not other.holds(item):
			continue
		other.remove_item(item)
		if store(item):
			guns.append(item.weapon.display_name if item.is_weapon() else item.title())
		else:
			other.store(item) # no room: put it back where it was
			break

	for grid in other.grids():
		for item in grid.items.duplicate():
			if not item.is_ammo():
				continue
			var moved := add_rounds(item.ammo_type, item.count)
			if moved <= 0:
				continue
			item.count -= moved
			if item.count <= 0:
				grid.remove(item)
			ammo[item.ammo_type] = ammo.get(item.ammo_type, 0) + moved

	changed.emit()
	other.changed.emit()
	return {"weapons": guns, "ammo": ammo}


func is_empty() -> bool:
	return all_items().is_empty()


# --- over the wire ------------------------------------------------------------
#
# A whole kit as plain data, so a body can be put on the floor of every machine
# in the session with exactly what was on it.
#
# Sent rather than regenerated from a shared seed. Every machine could roll the
# same guard the same rifle, but that guard has been *using* it since the raid
# started - a magazine half emptied at whoever he was shooting, a vest he has
# taken two rounds in - and only the host knows any of that. A body whose
# contents depend on who is looking at it is worse than no body at all.


func to_wire() -> Dictionary:
	var out := {}
	for named in [["primary", primary], ["secondary", secondary],
			["helmet", helmet], ["vest", vest], ["ultimate", ultimates[0]],
			["ultimate_2", ultimates[1]], ["backpack", backpack_item]]:
		var item := named[1] as Item
		if item:
			out[named[0]] = item.to_wire()

	var thrown: Array = []
	for item in throwables:
		thrown.append(item.to_wire() if item else null)
	out["throwables"] = thrown

	var pocketed: Array = []
	for grid in pockets:
		pocketed.append(grid.items[0].to_wire() if not grid.items.is_empty() else null)
	out["pockets"] = pocketed
	return out


static func from_wire(wire: Dictionary) -> Inventory:
	var kit := Inventory.new()
	kit.primary = _wired(wire, "primary")
	kit.secondary = _wired(wire, "secondary")
	kit.helmet = _wired(wire, "helmet")
	kit.vest = _wired(wire, "vest")
	kit.ultimates[0] = _wired(wire, "ultimate")
	kit.ultimates[1] = _wired(wire, "ultimate_2")
	# Assigned rather than put on with set_backpack(). The bag arrives with its
	# contents already laid out in known cells, and set_backpack repacks whatever
	# it is handed - which would quietly rearrange a body's pack into a different
	# shape on every machine that received it.
	kit.backpack_item = _wired(wire, "backpack")

	var thrown: Array = wire.get("throwables", [])
	for i in mini(thrown.size(), THROWABLE_SLOTS):
		if thrown[i] != null:
			kit.throwables[i] = Item.from_wire(thrown[i])

	var pocketed: Array = wire.get("pockets", [])
	for i in mini(pocketed.size(), kit.pockets.size()):
		if pocketed[i] == null:
			continue
		var held := Item.from_wire(pocketed[i])
		if held:
			kit.pockets[i].place(held, Vector2i.ZERO)
	return kit


static func _wired(wire: Dictionary, key: String) -> Item:
	return Item.from_wire(wire[key]) if wire.has(key) else null


## One line for the loot prompt: "AR, PISTOL, 146 rounds".
func summary() -> String:
	var parts: Array[String] = []
	for item in all_items():
		if not item.is_ammo():
			parts.append(item.title())
	var loose := total_rounds()
	if loose > 0:
		parts.append("%d rounds" % loose)
	return ", ".join(parts) if not parts.is_empty() else "nothing"
