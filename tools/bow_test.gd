extends SceneTree

## Headless check for the recon arrow, the bag-is-not-a-hotkey rule, and the
## weapon display refreshing after the loot screen closes.
##   godot --headless --path <project> --script res://tools/bow_test.gd

var _main: Node
var _player: CharacterBody2D
var _input: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()


func _run() -> void:
	await physics_frame
	await physics_frame
	var shop = _main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await physics_frame
	_input = root.get_node("/root/PlayerInput")
	# Taken from Net after the deploy, not from a node called "Player" in the
	# scene. There has not been one of those since characters started being
	# spawned per peer, so this fetched null and every check below it died on
	# the first line that touched it - silently, because the tool reported no
	# verdict at all rather than a failure.
	_player = root.get_node("Net").local_player
	if _player == null:
		print("no character - cannot run")
		quit(1)
		return

	await _bow()
	_bags()
	await _refresh()
	quit()


func _bow() -> void:
	print("-- the recon bow --")
	var kit: Inventory = _player.inventory
	kit.fit_default_power()
	kit.set_ultimate(Item.from_gadget(load("res://resources/gadgets/recon_bow.tres")))
	kit.ultimates[0].charge = 1.0

	var guard: Node2D = _main.get_node("Enemies/Enemy2")
	# Open ground with a clear lane east: standing against the crate makes the
	# arrow stick on the first frame and proves nothing about its flight.
	_player.global_position = Vector2(-500, 200)
	_input.touch_aim_direction = Vector2.RIGHT
	await _wait(20)

	_player._use_ultimate()
	await physics_frame
	var bolt := _find_bolt()
	print("  fired -> an arrow exists in the level: %s" % (bolt != null))
	if bolt == null:
		return
	var start: Vector2 = bolt.global_position
	await _wait(6)
	print("  it travels: %.0f px in 6 frames, and drops as it goes (vy %.0f)" % [
		start.distance_to(bolt.global_position), bolt.velocity.y])

	var vision: VisionSystem = _main.get_node("VisionSystem")
	print("  guard revealed before it lands: %s" % vision.is_revealed(guard))
	for i in 120:
		await physics_frame
		if not is_instance_valid(bolt) or bolt._stuck:
			break
	print("  arrow stuck: %s, revealed %d nearby" % [
		bolt._stuck if is_instance_valid(bolt) else false,
		bolt.get_meta(&"revealed_count", 0) if is_instance_valid(bolt) else 0])
	print("  guard revealed after it lands: %s" % vision.is_revealed(guard))


func _find_bolt() -> ReconBolt:
	for child in _main.get_children():
		var bolt := child as ReconBolt
		if bolt:
			return bolt
	return null


func _bags() -> void:
	print("\n-- a gun in the bag is cargo --")
	var kit: Inventory = _player.inventory
	var rifle := load("res://resources/weapons/assault_rifle.tres") as WeaponData
	kit.store(Item.from_weapon(rifle))
	print("  carrying: primary=%s, stowed=%s" % [
		_player.weapon.data.short_name,
		kit.stowed_weapons().map(func(i: Item) -> String: return i.weapon.short_name)])

	_input.touch_weapon_slot = 2 # the "3" key
	_player._update_inventory_keys()
	print("  pressed 3 -> holding %s, message \"%s\"" % [
		_player.weapon.data.short_name, _player.loot_message])
	_input.touch_weapon_slot = -1


func _refresh() -> void:
	print("\n-- the display follows what is actually in hand --")
	var kit: Inventory = _player.inventory
	var weapon = _player.weapon
	print("  holding %s" % weapon.data.short_name)

	# Swap the primary the way a drag on the loot screen would, with no call to
	# the weapon at all.
	var stowed := kit.stowed_weapons()
	var incoming: Item = stowed[0]
	kit.remove_item(incoming)
	var outgoing := kit.primary
	kit.primary = incoming
	kit.store(outgoing)
	await physics_frame
	print("  swapped underneath it -> weapon now reports %s" % weapon.data.short_name)

	_player.inventory_open = true
	_player._close_screen()
	await physics_frame
	print("  after closing the screen -> %s, %d in the mag" % [
		weapon.data.short_name, weapon.get_mag()])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
