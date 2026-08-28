class_name Item
extends RefCounted

## Anything that takes up space: a gun, or a stack of ammunition.
##
## Both are the same kind of thing once they are in a bag - a shape that
## occupies cells and can be moved from one container to another - so they share
## a class rather than being special-cased everywhere a container is drawn or
## searched.
##
## Size is in grid cells. A rifle is four cells across and two down; a stack of
## rounds is one cell whatever the calibre, because what limits ammunition is
## the stack size, not the footprint.

enum Kind { WEAPON, AMMO, ARMOR, MEDKIT, THROWABLE, ULTIMATE, BACKPACK, REVIVE,
	SURGICAL, REPAIR }

## Rounds per stack, by calibre. Fat rifle rounds stack smaller than pistol
## ammunition, which is what makes carrying a sniper rifle expensive in space
## as well as in weight.
const STACK_SIZES := {
	&"9mm": 60,
	&"5.56": 40,
	&"7.62": 40,
	&"12g": 24,
	&".338": 12,
}
const DEFAULT_STACK := 30

var kind := Kind.WEAPON
## Set for weapons, null otherwise.
var weapon: WeaponData
## Set for armour, null otherwise.
var armor: ArmorData
## Durability left (ARMOR) - armour is spent, not permanent.
var durability := 0.0
## Health restored per use (MEDKIT, SURGICAL), or durability put back into a
## piece of armour (REPAIR). One field because it is one idea - how much this
## use is worth - and the kind already says what it is worth it to.
var heal := 0.0
## Which piece a repair kit answers for (REPAIR). A plate kit will not fix a
## helmet: they are different items on the shelf and the whole point of them is
## that you decided in the menu which of the two you expected to lose.
var repair_slot := ArmorData.Slot.BODY
## Set for throwables and ultimates, null otherwise.
var gadget: GadgetData
## Set for backpacks, null otherwise.
var backpack: BackpackData
## What is inside this bag. The contents live on the bag rather than on whoever
## is wearing it, which is the whole reason a bag can be taken off a body with
## everything still in it - the space and the kit are one object, and moving it
## moves both.
var contents: ItemGrid
## Charge on an ultimate, 0 to 1. Spent on use, refilled by fighting.
var charge := 0.0
## Rounds loaded in the gun (WEAPON) or held in the stack (AMMO).
var count := 0
var ammo_type := &"9mm"
var size := Vector2i.ONE
## Where the top-left corner sits in the grid holding it. Meaningless while the
## item is in a weapon slot or in transit on the cursor.
var cell := Vector2i.ZERO


static func from_weapon(data: WeaponData, rounds := -1) -> Item:
	var item := Item.new()
	item.kind = Kind.WEAPON
	item.weapon = data
	item.ammo_type = data.ammo_type
	item.size = data.grid_size
	item.count = data.mag_size if rounds < 0 else clampi(rounds, 0, data.mag_size)
	return item


static func from_ammo(calibre: StringName, rounds: int) -> Item:
	var item := Item.new()
	item.kind = Kind.AMMO
	item.ammo_type = calibre
	item.size = Vector2i.ONE
	item.count = rounds
	return item


static func from_armor(data: ArmorData, condition := -1.0) -> Item:
	var item := Item.new()
	item.kind = Kind.ARMOR
	item.armor = data
	item.size = data.grid_size
	item.durability = data.max_durability if condition < 0.0 else condition
	return item


## A medkit holds a number of uses; each one puts health back.
static func from_medkit(uses := 3, heal_each := 45.0) -> Item:
	var item := Item.new()
	item.kind = Kind.MEDKIT
	item.size = Vector2i(2, 1)
	item.count = uses
	item.heal = heal_each
	return item


## A surgical kit: the only thing that closes wounds.
##
## A medkit and this one are not interchangeable, and the split is the point. A
## medkit puts the bar back up and does nothing about why it keeps falling - use
## one while you are carrying wounds and you will watch the health you just paid
## for drain straight back out. This is the one that fixes the cause, and it
## costs more space and more time to say so.
##
## Clears every wound at once rather than one per use. Wounds are not a stack
## you whittle down - being patched up is a state, and half-treating yourself is
## not a decision anybody would make on purpose.
static func from_surgical(uses := 2) -> Item:
	var item := Item.new()
	item.kind = Kind.SURGICAL
	item.size = Vector2i(2, 2)
	item.count = uses
	item.heal = 25.0
	return item


## A repair kit for one kind of armour.
##
## Armour is a consumable now - four rifle rounds take a Kevlar vest to nothing -
## and a consumable you cannot top up is just a shorter fight. This is the
## answer to that, and it is deliberately not a better vest: it costs cells in
## the bag, it costs seconds you spend standing still, and it puts back a fixed
## amount rather than filling the bar, so a plate you have been living behind
## all raid is never quite new again.
static func from_repair(slot: int, uses := 2, per_use := 90.0) -> Item:
	var item := Item.new()
	item.kind = Kind.REPAIR
	item.repair_slot = slot
	item.size = Vector2i(2, 1) if slot == ArmorData.Slot.BODY else Vector2i(1, 1)
	item.count = uses
	item.heal = per_use
	return item


## A stim you can stick in yourself on the floor. One use puts you back on your
## feet at full health.
##
## A medkit is no use while down - patching up is not the problem, being unable
## to stand is - so this is the item that answers that, and it is the only thing
## you can still do once you are on the floor. It stacks, because the interesting
## question is how many you brought, not whether you brought one.
static func from_revive(uses := 5) -> Item:
	var item := Item.new()
	item.kind = Kind.REVIVE
	item.size = Vector2i.ONE
	item.count = uses
	return item


## Throwables come in a pair by default: two of a kind is a loadout choice,
## one is an accident.
static func from_gadget(data: GadgetData, uses := -1) -> Item:
	var item := Item.new()
	item.gadget = data
	item.size = data.grid_size
	if data.gadget_class == GadgetData.Class.ULTIMATE:
		item.kind = Kind.ULTIMATE
		item.count = 1
		item.charge = 0.0
	else:
		item.kind = Kind.THROWABLE
		item.count = 2 if uses < 0 else uses
	return item


## A bag. Its size here is what it costs to carry, not what it holds - the grid
## it gives you lives on the BackpackData.
static func from_backpack(data: BackpackData) -> Item:
	var item := Item.new()
	item.kind = Kind.BACKPACK
	item.backpack = data
	item.size = data.carried_size
	item.count = 1
	item.contents = ItemGrid.new(data.grid_size.x, data.grid_size.y)
	return item


static func stack_size(calibre: StringName) -> int:
	return STACK_SIZES.get(calibre, DEFAULT_STACK)


# --- over the wire ------------------------------------------------------------
#
# What gets sent is only what cannot be worked out again: which resource this is,
# and how used up it is. Size, footprint, colour and stack limits all come back
# off the resource, and a wire format that repeats what both ends already hold is
# a wire format that can contradict itself.


func to_wire() -> Dictionary:
	var out := {"kind": int(kind), "count": count, "cell": [cell.x, cell.y]}
	var data: Resource = weapon
	if data == null:
		data = armor
	if data == null:
		data = gadget
	if data == null:
		data = backpack
	if data:
		out["path"] = data.resource_path
	if is_armor():
		out["durability"] = durability
	elif is_ultimate():
		out["charge"] = charge
	elif is_medkit() or is_surgical():
		out["heal"] = heal
	elif is_repair():
		out["heal"] = heal
		out["repair_slot"] = int(repair_slot)
	elif is_ammo():
		out["ammo"] = String(ammo_type)
	elif is_backpack() and contents:
		# A bag travels with what is in it, cells and all. That is not an
		# optimisation - a bag is one object that carries both the space and the
		# kit, which is what makes taking a whole rig off a body work.
		var inside: Array = []
		for held in contents.items:
			inside.append(held.to_wire())
		out["inside"] = inside
	return out


## Rebuilds an item from `to_wire`. Null when the resource it names cannot be
## loaded, which is a build mismatch rather than something to paper over.
static func from_wire(wire: Dictionary) -> Item:
	var path: String = wire.get("path", "")
	var count_in: int = wire.get("count", 0)
	var item: Item = null

	match int(wire.get("kind", Kind.WEAPON)):
		Kind.WEAPON:
			var gun := load(path) as WeaponData
			if gun:
				item = Item.from_weapon(gun, count_in)
		Kind.ARMOR:
			var plate := load(path) as ArmorData
			if plate:
				item = Item.from_armor(plate, wire.get("durability", 0.0))
		Kind.BACKPACK:
			var bag := load(path) as BackpackData
			if bag:
				item = Item.from_backpack(bag)
				for held in wire.get("inside", []):
					var inner := Item.from_wire(held)
					if inner:
						item.contents.place(inner, inner.cell)
		Kind.THROWABLE, Kind.ULTIMATE:
			var thing := load(path) as GadgetData
			if thing:
				item = Item.from_gadget(thing, count_in)
				item.charge = wire.get("charge", 0.0)
		Kind.AMMO:
			item = Item.from_ammo(StringName(wire.get("ammo", "9mm")), count_in)
		Kind.MEDKIT:
			item = Item.from_medkit(count_in, wire.get("heal", 45.0))
		Kind.REVIVE:
			item = Item.from_revive(count_in)
		Kind.SURGICAL:
			item = Item.from_surgical(count_in)
			item.heal = wire.get("heal", 25.0)
		Kind.REPAIR:
			item = Item.from_repair(int(wire.get("repair_slot", ArmorData.Slot.BODY)),
				count_in, wire.get("heal", 90.0))

	if item == null:
		return null
	var at: Array = wire.get("cell", [0, 0])
	item.cell = Vector2i(at[0], at[1])
	return item


func is_weapon() -> bool:
	return kind == Kind.WEAPON


func is_ammo() -> bool:
	return kind == Kind.AMMO


func is_armor() -> bool:
	return kind == Kind.ARMOR


func is_medkit() -> bool:
	return kind == Kind.MEDKIT


func is_revive() -> bool:
	return kind == Kind.REVIVE


func is_surgical() -> bool:
	return kind == Kind.SURGICAL


func is_repair() -> bool:
	return kind == Kind.REPAIR


func is_throwable() -> bool:
	return kind == Kind.THROWABLE


func is_ultimate() -> bool:
	return kind == Kind.ULTIMATE


func is_backpack() -> bool:
	return kind == Kind.BACKPACK


func capacity() -> int:
	if is_weapon():
		return weapon.mag_size
	if is_ammo():
		return Item.stack_size(ammo_type)
	return count


func room_left() -> int:
	return maxi(capacity() - count, 0)


func cells() -> int:
	return size.x * size.y


func title() -> String:
	if is_weapon():
		return weapon.short_name
	if is_armor():
		return armor.short_name
	if is_medkit():
		return "MEDKIT"
	if is_surgical():
		return "SURGICAL"
	if is_repair():
		return "PLATE KIT" if repair_slot == ArmorData.Slot.BODY else "HELMET KIT"
	if is_revive():
		return "STIM"
	if is_backpack():
		return backpack.short_name
	if gadget:
		return gadget.short_name
	return str(ammo_type)


## "AR 24/30", "5.56 x40", "VEST 88%" or "MEDKIT x3".
func label() -> String:
	if is_weapon():
		return "%s %d/%d" % [weapon.short_name, count, weapon.mag_size]
	if is_armor():
		return "%s %d%%" % [armor.short_name, roundi(condition() * 100.0)]
	if is_medkit():
		return "MEDKIT x%d" % count
	if is_surgical():
		return "SURGICAL x%d" % count
	if is_repair():
		return "%s x%d" % [title(), count]
	if is_revive():
		return "STIM x%d" % count
	if is_backpack():
		return "%s %dx%d" % [backpack.short_name, backpack.grid_size.x, backpack.grid_size.y]
	if is_throwable():
		return "%s x%d" % [gadget.short_name, count]
	if is_ultimate():
		return "%s %d%%" % [gadget.short_name, roundi(charge * 100.0)]
	return "%s x%d" % [ammo_type, count]


## How much of this armour piece is left, 0 to 1.
func condition() -> float:
	if not is_armor():
		return 1.0
	return clampf(durability / maxf(armor.max_durability, 1.0), 0.0, 1.0)


## Colour for the tile, taken from the round the gun fires so a weapon and its
## ammunition read as belonging together at a glance.
func tint() -> Color:
	if is_weapon():
		return weapon.bullet_color
	if is_armor():
		return armor.tint
	if is_medkit():
		return Color(0.55, 0.85, 0.62)
	# Colder and bluer than a medkit, because reaching for the wrong one of the
	# two in a hurry is exactly the mistake this system can produce.
	if is_surgical():
		return Color(0.48, 0.78, 0.88)
	# The colour armour is drawn in, because that is the only thing it is for
	# and a bag is read by colour before it is read by name.
	if is_repair():
		return Color(0.62, 0.68, 0.76)
	if is_backpack():
		return backpack.tint
	if gadget:
		return gadget.tint
	match ammo_type:
		&"9mm": return Color(1.0, 0.88, 0.66)
		&"5.56": return Color(1.0, 0.86, 0.48)
		&"7.62": return Color(1.0, 0.79, 0.36)
		&"12g": return Color(1.0, 0.65, 0.31)
		&".338": return Color(0.74, 0.92, 1.0)
	return Color(0.8, 0.8, 0.8)
