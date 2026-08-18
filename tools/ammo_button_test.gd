extends SceneTree

## The AMMUNITION button: it offers what your guns take, and stows what you buy
## wherever there is room.
##
##   godot --headless --path . --script res://tools/ammo_button_test.gd
##
## No level and no session - this is the shop's own logic, and loading a raid to
## test it would only add ways for it to fail.

var _ok := true
var _shop: Control
var _kit: Inventory


func _initialize() -> void:
	_run()


func _run() -> void:
	# Loaded, not named: naming Weapon compiles weapon.gd before the autoloads
	# exist and breaks the class for the process. See headless-test-must-unpause.
	var weapon_script: GDScript = load("res://scripts/weapon.gd")
	_kit = weapon_script.starting_inventory()

	_shop = Control.new()
	_shop.set_script(load("res://scripts/shop.gd"))
	root.add_child(_shop)
	_shop.open(_kit)
	await physics_frame

	# --- it offers what you carry, and only that ----------------------------
	#
	# The starting kit is a pistol, so one calibre. Every other line in the
	# catalogue is ammunition for a gun you do not own.
	var offered := _calibres()
	_say("with just the sidearm: %s" % str(offered))
	# has(), not ==: these are StringNames and an Array of them never equals an
	# Array of Strings, however identical they read in the log.
	_check("only the pistol's calibre is offered",
		offered.size() == 1 and offered.has(&"9mm"))

	_select("primary")
	_shop._buy(_shop.CATALOGUE["primary"][1])   # the assault rifle, 5.56
	await physics_frame
	offered = _calibres()
	_say("after buying the rifle: %s" % str(offered))
	_check("now it offers the rifle's calibre too", offered.has(&"5.56"))
	_check("and still the pistol's", offered.has(&"9mm"))
	_check("and nothing else", offered.size() == 2)
	# Loadout order, not catalogue order: the primary's rounds are the top line.
	_check("the primary's calibre comes first", offered[0] == &"5.56")

	# --- and it says which gun each one is for -------------------------------
	var rifle: Dictionary = _shop._fed_by(&"5.56")
	var sidearm: Dictionary = _shop._fed_by(&"9mm")
	_say("5.56 -> %s (%s) | 9mm -> %s (%s)" % [
		rifle.tag, rifle.guns, sidearm.tag, sidearm.guns])
	_check("5.56 is tagged for the primary", rifle.tag == "PRIMARY")
	_check("and names the gun", rifle.guns == "Assault Rifle")
	_check("9mm is tagged for the secondary", sidearm.tag == "SECONDARY")
	_check("and the two tags are different colours", rifle.tint != sidearm.tint)

	# --- one calibre feeding both hands is one line, tagged for both ---------
	#
	# The SMG is 9mm and so is the pistol. That pairing is a real choice - one
	# kind of ammunition for the whole loadout - so it has to read as one supply
	# rather than as the secondary's rounds that the primary happens to accept.
	_select("primary")
	_shop._buy(_shop.CATALOGUE["primary"][0])   # the SMG, 9mm
	await physics_frame
	offered = _calibres()
	_say("with an SMG and a pistol: %s" % str(offered))
	_check("a shared calibre is one line", offered.size() == 1)
	var shared: Dictionary = _shop._fed_by(&"9mm")
	_say("9mm -> %s (%s)" % [shared.tag, shared.guns])
	_check("tagged for both hands", shared.tag == "PRIMARY + SECONDARY")
	_check("and coloured as neither", shared.tint != rifle.tint and shared.tint != sidearm.tint)

	# Back to the rifle for the rest of this.
	_select("primary")
	_shop._buy(_shop.CATALOGUE["primary"][1])
	await physics_frame

	# --- buying puts it somewhere sensible -----------------------------------
	_select("ammo")
	var before_rounds: int = _rounds(&"5.56")
	var before_credits: int = _shop.credits
	var entry := _entry_for(&"5.56")
	_check("there is a 5.56 line to buy", not entry.is_empty())
	if entry.is_empty():
		_finish()
		return

	_shop._buy(entry)
	await physics_frame
	_say("5.56: %d -> %d rounds, credits %d -> %d" % [
		before_rounds, _rounds(&"5.56"), before_credits, _shop.credits])
	_check("the rounds arrived", _rounds(&"5.56") > before_rounds)
	_check("and were paid for", _shop.credits == before_credits - int(entry.price))
	# Pockets first, because a pocket is reachable and the pack is where loot
	# goes - see Inventory.grids.
	_check("into a pocket, not the pack", _in_pockets(&"5.56") > 0)

	# --- and into the pack once the pockets are full -------------------------
	#
	# Five one-cell pockets fill quickly. What matters is that the button keeps
	# working rather than refusing the moment the easy space is gone.
	# The BACKPACK slot, not the pack grid: buying a bag into the grid it grants
	# is a different operation and quietly does nothing.
	_select("backpack")
	_shop._buy(_shop.CATALOGUE["backpack"][2])   # assault pack, a big grid
	await physics_frame
	_check("wearing a bag now", _kit.backpack_item != null)
	_select("ammo")
	for i in 12:
		_shop._buy(entry)
		await physics_frame
	_say("after filling up: %d in pockets, %d in the pack" % [
		_in_pockets(&"5.56"), _in_pack(&"5.56")])
	_check("the overflow went into the backpack", _in_pack(&"5.56") > 0)

	# --- a full man is told, not charged -------------------------------------
	# Money is not what is being tested here, and filling a rucksack with .338
	# runs out of credits long before it runs out of cells - so the wallet is
	# topped up and the only reason left to refuse is space.
	_shop.credits = 99999
	var fired := 0
	for i in 60:
		var was: int = _shop.credits
		_shop._buy(entry)
		await physics_frame
		if _shop.credits == was:
			fired += 1
			break
	_say("full kit holds %d rounds of 5.56; refusal says %s" % [
		_rounds(&"5.56"), _shop._message])
	# The loop breaks on the first purchase that did not move the credits, so
	# reaching here at all is both halves of it: refused, and not charged for.
	_check("a purchase with nowhere to go is refused, and free", fired > 0)
	_check("and says why", _shop._message.contains("nowhere"))

	_finish()


func _calibres() -> Array:
	var out: Array = []
	for entry in _shop._entries_for("ammo"):
		out.append(entry.ammo)
	return out


func _entry_for(calibre: StringName) -> Dictionary:
	for entry in _shop._entries_for("ammo"):
		if entry.ammo == calibre:
			return entry
	return {}


func _select(id: String) -> void:
	var list := "ammo"
	var kind := "slot"
	if id == "pack":
		list = "stow"
		kind = "pack"
	elif id != "ammo":
		for slot in _shop.SLOTS:
			if slot.id == id:
				list = slot.list
	_shop._open = {"id": id, "list": list, "label": id.to_upper(), "kind": kind}


func _rounds(calibre: StringName) -> int:
	return _in_pockets(calibre) + _in_pack(calibre)


func _in_pockets(calibre: StringName) -> int:
	var total := 0
	for pocket in _kit.pockets:
		for item in pocket.items:
			if item.is_ammo() and item.ammo_type == calibre:
				total += item.count
	return total


func _in_pack(calibre: StringName) -> int:
	var total := 0
	for item in _kit.backpack.items:
		if item.is_ammo() and item.ammo_type == calibre:
			total += item.count
	return total


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("ammo | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
