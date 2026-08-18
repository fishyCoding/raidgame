extends SceneTree

## Single player: a guard who dies leaves a body with his own kit on it.
##
##   godot --headless --path . --script res://tools/body_test.gd
##
## Corpses go through Net.drop_body now - the same call the host makes in a match,
## minus the socket - so this is the solo half of what server/test_match.ps1
## checks between two clients. It is here because the kit takes a round trip
## through Inventory.to_wire even when there is nobody to send it to, and a
## serialiser that drops the spare magazine is a serialiser that does it quietly.

var _main: Node
var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	# Past the shop and the briefing, or the tree stays paused and the guard
	# never runs a frame. Order matters - see tools/solo_test.gd.
	var shop: Node = _main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	var guard: Node = _main.get_node("Enemies").get_child(0)
	# The inventory itself, not a string taken off it now. Shooting him wears his
	# vest down - Damage.resolve spends armour - so a snapshot from before the
	# first round is not what he was carrying when he fell, and comparing against
	# one fails about half the time depending on whether he was issued a vest.
	# Holding the object works because _drop_weapon only clears the guard's
	# reference to it; the kit itself lives on, and it is what got serialised.
	var kit: Inventory = guard.weapon.inventory
	_say("%s is carrying: %s" % [guard.name, _kit_of(kit)])

	for i in 40:
		if not guard.net_alive:
			break
		# Aimed at the middle of him, so this is a body shot and he has to be
		# worn down rather than dropped by a lucky headshot on the first hit.
		guard.take_damage(20.0, guard.global_position, Vector2.RIGHT)
		await physics_frame
	_check("the guard died", not guard.net_alive)

	await _wait(5)
	var body: Node2D = null
	for node in get_nodes_in_group(&"lootable"):
		var found := node as Node2D
		if found and found.global_position.distance_to(guard.global_position) < 140.0:
			body = found
	_check("he left a body where he fell", body != null)
	if body == null:
		_finish()
		return

	_say("he died carrying:    %s" % _kit_of(kit))
	_say("body %s has: %s" % [body.name, _kit_of(body.inventory)])
	_check("there is something on it", body.has_loot())
	# The whole point: what came back off the wire is what he had when he fell,
	# down to the rounds in the gun and what is left of the vest - not a fresh
	# roll of the same tables.
	_check("with exactly what he had", _kit_of(body.inventory) == _kit_of(kit))
	_check("named after him", str(body.name) == "Body_%s" % guard.name)

	# And it can still be searched, which is what a body is for.
	var taker := Inventory.new()
	taker.set_backpack(Item.from_backpack(
		load("res://resources/backpacks/heavy_rucksack.tres")))
	body.loot_into(taker)
	_say("took: %s" % taker.summary())
	_check("and emptied into a bag", not taker.is_empty())

	_finish()


func _kit_of(kit: Inventory) -> String:
	if kit == null:
		return "-"
	var what: Array[String] = []
	for item in kit.all_items():
		what.append(item.label())
	what.sort()
	return ", ".join(what)


func _check(what: String, passed: bool) -> void:
	_say("%-32s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _say(text: String) -> void:
	print("body | %s" % text)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
