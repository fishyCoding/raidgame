class_name ItemGrid
extends RefCounted

## A rectangle of cells that things sit in, and the rules about what fits where.
##
## The whole point of a grid rather than a list of slots is that space is the
## constraint: a rifle is eight cells and a magazine is one, so what you can
## carry out of a fight is a real decision rather than a number of items. This
## class knows nothing about guns - it only places rectangles.

var width: int
var height: int
var items: Array[Item] = []


func _init(cells_across := 8, cells_down := 5) -> void:
	width = cells_across
	height = cells_down


func cell_count() -> int:
	return width * height


func used_cells() -> int:
	var used := 0
	for item in items:
		used += item.cells()
	return used


## True if `item` would fit with its top-left corner at `at`, ignoring itself so
## an item can be nudged around without colliding with where it already is.
func fits(item: Item, at: Vector2i) -> bool:
	if at.x < 0 or at.y < 0:
		return false
	if at.x + item.size.x > width or at.y + item.size.y > height:
		return false
	var wanted := Rect2i(at, item.size)
	for other in items:
		if other == item:
			continue
		if wanted.intersects(Rect2i(other.cell, other.size)):
			return false
	return true


func place(item: Item, at: Vector2i) -> bool:
	if not fits(item, at):
		return false
	item.cell = at
	if not items.has(item):
		items.append(item)
	return true


## Drops the item into the first space it fits, scanning left to right and top
## to bottom. What automatic looting and "give me this back" both use.
func add(item: Item) -> bool:
	for y in height:
		for x in width:
			if fits(item, Vector2i(x, y)):
				return place(item, Vector2i(x, y))
	return false


## Whether a footprint of this size would land anywhere, without needing an item
## to try it with. What a shop asks before it sells you something that has to go
## in here, and what a rack asks before it says it is full.
func has_room(size: Vector2i) -> bool:
	for y in height:
		for x in width:
			if _clear(Rect2i(Vector2i(x, y), size)):
				return true
	return false


## Nothing in the way, and inside the grid.
func _clear(want: Rect2i) -> bool:
	if want.position.x < 0 or want.position.y < 0:
		return false
	if want.end.x > width or want.end.y > height:
		return false
	for other in items:
		if want.intersects(Rect2i(other.cell, other.size)):
			return false
	return true


func remove(item: Item) -> void:
	items.erase(item)


func item_at(at: Vector2i) -> Item:
	for item in items:
		if Rect2i(item.cell, item.size).has_point(at):
			return item
	return null


## Ammunition of this calibre held here, across every stack.
func rounds_of(calibre: StringName) -> int:
	var total := 0
	for item in items:
		if item.is_ammo() and item.ammo_type == calibre:
			total += item.count
	return total


## Takes rounds out of the stacks, emptying the smallest first so the grid tends
## to free up whole cells rather than leaving a scatter of part-used stacks.
func take_rounds(calibre: StringName, wanted: int) -> int:
	var stacks: Array[Item] = []
	for item in items:
		if item.is_ammo() and item.ammo_type == calibre:
			stacks.append(item)
	stacks.sort_custom(func(a: Item, b: Item) -> bool: return a.count < b.count)

	var taken := 0
	for stack in stacks:
		if taken >= wanted:
			break
		var moved := mini(stack.count, wanted - taken)
		stack.count -= moved
		taken += moved
		if stack.count <= 0:
			remove(stack)
	return taken


## Adds rounds, topping up part-used stacks before starting new ones. Returns
## how many actually fitted - the rest has nowhere to go.
func add_rounds(calibre: StringName, rounds: int) -> int:
	var added := 0
	for item in items:
		if added >= rounds:
			break
		if item.is_ammo() and item.ammo_type == calibre:
			var moved := mini(item.room_left(), rounds - added)
			item.count += moved
			added += moved

	while added < rounds:
		var stack := Item.from_ammo(calibre, mini(Item.stack_size(calibre), rounds - added))
		if not add(stack):
			break
		added += stack.count
	return added
