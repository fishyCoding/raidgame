extends SceneTree

## SAVE LOADOUT: whatever is sitting in the shop lands on disk, and round-trips
## back through Inventory.from_wire intact.
##
##   godot --headless --path . --script res://tools/save_loadout_test.gd
##
## Pressed through the same handler the button is wired to (lobby._on_save_loadout),
## same shape as tools/test_drive_test.gd does for its own button.

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _wait(10)

	var kit: Inventory = lobby._kit
	_check("the lobby built a starting kit", kit != null)
	if kit == null:
		_finish()
		return

	# Bought as the shop would: a rifle in the primary slot and some rounds for
	# it, so there is something in the saved file that was not there by default.
	kit.set_slot(Inventory.Slot.PRIMARY,
		Item.from_weapon(load("res://resources/weapons/assault_rifle.tres")))
	kit.add_rounds(&"5.56", 90)

	lobby._on_save_loadout()

	var file := ConfigFile.new()
	var err := file.load(lobby.LOADOUT_FILE)
	_check("the file is on disk", err == OK)
	if err != OK:
		_finish()
		return

	var wire: Dictionary = file.get_value("loadout", "kit", {})
	_check("it has a kit entry", not wire.is_empty())
	var back := Inventory.from_wire(wire)
	_check("the rifle round-tripped", back.primary != null
		and back.primary.weapon.short_name == "AR")
	_check("and the rounds with it", back.rounds_of(&"5.56") >= 90)

	_finish()


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("save_loadout | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
