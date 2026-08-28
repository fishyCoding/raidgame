extends SceneTree

## Checks the repair kits: that they put durability back, that they are spent
## doing it, and above all that a plate kit will not fix a helmet.
##
## The slot match is the part worth defending. Both kits are the same Item.Kind
## with a field saying which piece they answer for, so a wrong comparison does
## not fail loudly - it just quietly makes one kit repair everything, which is
## the entire distinction between the two items on the shelf.
##
## Loaded rather than named, for the reason spelled out in tools/glint_test.gd.

var _failures: Array[String] = []
var _player: Node = null


func _init() -> void:
	await process_frame
	_player = (load("res://scripts/player.gd") as GDScript).new()

	var vest := Item.from_armor(load("res://resources/armor/medium_vest.tres"))
	var helmet := Item.from_armor(load("res://resources/armor/medium_helmet.tres"))
	var kit := Inventory.new()
	kit.set_worn(Inventory.Wear.VEST, vest)
	kit.set_worn(Inventory.Wear.HELMET, helmet)
	_player.inventory = kit

	# Both pieces shot up, the vest worse than the helmet.
	vest.durability = vest.armor.max_durability * 0.2
	helmet.durability = helmet.armor.max_durability * 0.5

	# Carrying a helmet kit only: the vest is in a worse state and is not what
	# gets fixed, because it is not what you brought a kit for.
	# A bag, because pockets are one cell each and a plate kit is two - the
	# first version of this test quietly failed to put one anywhere and then
	# reported that the wrong piece got repaired.
	kit.set_backpack(Item.from_backpack(
		load("res://resources/backpacks/patrol_pack.tres")))
	var bag: ItemGrid = kit.backpack

	var helmet_kit := Item.from_repair(ArmorData.Slot.HEAD)
	_want("the helmet kit goes in the bag", bag.place(helmet_kit, Vector2i.ZERO))
	var chosen = _player._worst_repairable()
	_want("a helmet kit picks the helmet, not the worse vest", chosen == helmet)
	_want("and will not answer for a vest", _player._repair_kit_for(vest) == null)
	_want("but does answer for a helmet", _player._repair_kit_for(helmet) == helmet_kit)

	# Now a plate kit as well. The vest is in the worse state, so it wins.
	var plate_kit := Item.from_repair(ArmorData.Slot.BODY)
	_want("the plate kit goes in the bag", bag.place(plate_kit, Vector2i(1, 0)))
	_want("with both kits, the worse piece is chosen", _player._worst_repairable() == vest)

	# The repair itself: a fixed amount back, and a use gone.
	var before := vest.durability
	var uses := plate_kit.count
	_player._finish_repair()
	_want("durability goes back up by the kit's worth",
		absf(vest.durability - (before + plate_kit.heal)) < 0.01)
	_want("and a use is spent", plate_kit.count == uses - 1)

	# It refills rather than overfills. The helmet goes to full first, or it is
	# the worse piece and the repair lands there instead - which is the code
	# behaving correctly and the test asking the wrong question.
	helmet.durability = helmet.armor.max_durability
	vest.durability = vest.armor.max_durability - 5.0
	_player._finish_repair()
	_want("and never past full", vest.durability == vest.armor.max_durability)

	# Nothing to do, once everything is whole.
	_want("a whole kit list with nothing to fix picks nothing",
		_player._worst_repairable() == null)

	_player.free()
	if _failures.is_empty():
		print("OK - the kits fix what they are for")
	else:
		for line in _failures:
			print("FAIL - %s" % line)
		print("FAILED %d check(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _want(what: String, got: Variant) -> void:
	if typeof(got) != TYPE_BOOL:
		_failures.append("%s: did not answer (got %s)" % [what, got])
		print("  FAIL %-52s no answer" % what)
		return
	if got:
		print("  ok   %s" % what)
	else:
		_failures.append(what)
		print("  FAIL %s" % what)
