extends SceneTree

## The power rack: what runs your ultimates, and what will fit in it.
##
##   godot --headless --path . --script res://tools/power_test.gd
##
## An ultimate used to be a thing you bought that charged itself. It is now a
## thing that has to live somewhere, and the somewhere is a grid you also bought.
## Most of what is asserted here is the refusals - no source, no ultimate; wrong
## shape, no ultimate - because those are the decisions the whole feature exists
## to create, and a rule that quietly does not apply is a rule nobody plays
## around.

const POWER := "res://resources/power/%s.tres"
const GADGET := "res://resources/gadgets/%s.tres"

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var kit: Object = (load("res://scripts/inventory.gd") as GDScript).new()

	# --- nothing to run it on -------------------------------------------------
	var headcount: Object = maker.from_gadget(load(GADGET % "headcount"))
	_check(not kit.set_ultimate(headcount), "with no power source, a gadget has nowhere to go")
	_check(kit.ultimates.is_empty(), "and nothing is racked")
	_check(kit.get_ultimate(0) == null, "so there is nothing in the first position")
	_check(is_equal_approx(kit.charge_scale(), 1.0),
		"and the charge rate falls back to the gadget's own")

	# --- the cheap rack -------------------------------------------------------
	var rack: Object = maker.from_power(load(POWER % "cell_rack"))
	kit.set_power(rack)
	_say("cell rack: %dx%d, charges at %.2fx" % [kit.power.width, kit.power.height,
		kit.charge_scale()])
	_check(kit.power.width == 3 and kit.power.height == 1, "a 3x1 rack is three cells in a row")
	_check(kit.set_ultimate(headcount), "a 2x1 gadget fits in it")
	_check(kit.ultimates.size() == 1, "and is racked")
	_check(kit.charge_scale() > 1.0, "the cheap rack charges slower than the gadget asks")

	var bomb: Object = maker.from_gadget(load(GADGET % "rail_bomb"))
	_check(bomb.size == Vector2i(2, 2), "the rail bomb is a big gadget - two by two")
	_check(not kit.set_ultimate(bomb), "which will not go in a rack one cell tall")
	_check(kit.ultimates.size() == 1, "and nothing was displaced trying")

	# --- the square one -------------------------------------------------------
	var square: Object = maker.from_power(load(POWER % "power_cell"))
	kit.set_power(square)
	_check(kit.ultimates.is_empty(), "a new source is a new rack - the old one went with it")
	_check(kit.set_ultimate(bomb), "the 2x2 goes in the 2x2")
	_check(not kit.set_ultimate(maker.from_gadget(load(GADGET % "dash"))),
		"and fills it - nothing else fits alongside")

	kit.clear_ultimates()
	var dash: Object = maker.from_gadget(load(GADGET % "dash"))
	var overload: Object = maker.from_gadget(load(GADGET % "overload"))
	_check(kit.set_ultimate(dash) and kit.set_ultimate(overload),
		"or two small ones instead, which is the whole decision")
	_say("racked: %s" % [kit.ultimates.map(func(u): return u.gadget.short_name)])
	_check(kit.ultimates.size() == 2, "both are in it")
	_check(kit.get_ultimate(0) == dash and kit.get_ultimate(1) == overload,
		"and Q and Z point at them in the order they sit in the rack")

	# --- the fast one ---------------------------------------------------------
	var bank: Object = maker.from_power(load(POWER % "rail_bank"))
	_check(bank.power.charge_scale < 1.0, "the dear rack charges faster")
	kit.set_power(bank)
	_check(not kit.set_ultimate(maker.from_gadget(load(GADGET % "projection"))),
		"and being long and thin, it takes no wide gadget at all")
	_check(kit.set_ultimate(maker.from_gadget(load(GADGET % "dash"))),
		"only the small ones - which is what you are paying the speed for")

	# --- it is carried, and it is lootable ------------------------------------
	kit.set_power(maker.from_power(load(POWER % "power_cell")))
	kit.set_ultimate(maker.from_gadget(load(GADGET % "headcount")))
	var carried: Array = kit.all_items()
	var names: Array = []
	for item in carried:
		names.append(item.title())
	_say("on the body: %s" % [names])
	_check(carried.size() == 2, "the source and what is racked in it are both on the body")

	var wire: Dictionary = kit.to_wire()
	var far: Object = (load("res://scripts/inventory.gd") as GDScript).new().from_wire(wire)
	_check(far.power_item != null, "the source travels")
	_check(far.ultimates.size() == 1 and far.get_ultimate(0).gadget.short_name == "HEADCT",
		"with the gadget still racked in it")
	_check(far.power.width == 2 and far.power.height == 2, "and the same rack at the far end")

	# --- and taking it off takes the rack with it -----------------------------
	var source: Object = kit.power_item
	kit.remove_item(source)
	_check(kit.power_item == null, "the source comes off")
	_check(kit.ultimates.is_empty(), "and what was running is off with it")
	_check(source.contents.items.size() == 1,
		"still racked in the thing you would be looting")

	print("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _say(line: String) -> void:
	print("-- %s" % line)


func _check(pass_: bool, says: String) -> void:
	print("   %s  %s" % ["ok  " if pass_ else "FAIL", says])
	if not pass_:
		_ok = false
