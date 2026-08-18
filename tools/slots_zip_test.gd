extends SceneTree

## Headless check for the cable fixes and the pistol/primary rules:
##   godot --headless --path <project> --script res://tools/slots_zip_test.gd

var _main: Node
var _player: CharacterBody2D
var _input: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_player = _main.get_node("Player")
	_run()


func _run() -> void:
	await physics_frame
	await physics_frame
	var shop = _main.get_node("HUD/Shop")
	shop.visible = false
	shop.deployed.emit()
	await physics_frame
	_input = root.get_node("/root/PlayerInput")

	_slot_rules()
	await _riding()
	quit()


func _slot_rules() -> void:
	print("-- where guns go --")
	var kit: Inventory = _player.inventory
	print("  starting kit: primary=%s secondary=%s (holding %s)" % [
		kit.primary.label() if kit.primary else "-",
		kit.secondary.label() if kit.secondary else "-",
		_player.weapon.data.short_name])

	var rifle := load("res://resources/weapons/assault_rifle.tres") as WeaponData
	kit.store(Item.from_weapon(rifle))
	print("  picked up an AR -> primary=%s, backpack holds %d guns" % [
		kit.primary.label() if kit.primary else "-",
		kit.stowed_weapons().size()])

	var pistol := load("res://resources/weapons/pistol.tres") as WeaponData
	print("  a pistol in the primary slot allowed: %s" % [
		kit.can_hold(Item.from_weapon(pistol), Inventory.Slot.PRIMARY)])
	print("  a rifle in the secondary slot allowed: %s" % [
		kit.can_hold(Item.from_weapon(rifle), Inventory.Slot.SECONDARY)])

	# A second pistol has a full holster, so it has to ride in a bag.
	kit.store(Item.from_weapon(pistol))
	print("  a second pistol -> secondary still %s, bags hold %d" % [
		kit.secondary.weapon.short_name, kit.stowed_weapons().size()])


func _riding() -> void:
	print("\n-- riding, both ways --")
	var cable: Zipline = _main.get_node("Ziplines/ZipEast")
	_player.global_position = cable.world_bottom() + Vector2(10, -30)
	_player.velocity = Vector2.ZERO
	await _wait(8)

	_input.touch_interact_pressed = true
	await _wait(3)
	print("  F -> riding: %s" % (_player.zipline != null))

	# Climbing with the jump key used to detach on the first frame.
	_input.touch_jump_pressed = true
	_input.touch_jump_held = true
	var start := _player.global_position.y
	await _wait(60)
	print("  holding jump for 1s -> climbed %.0f px, still on: %s" % [
		start - _player.global_position.y, _player.zipline != null])
	_input.touch_jump_held = false

	# Down all the way: the bottom should let you off rather than pin you.
	_input.touch_down_held = true
	await _wait(120)
	_input.touch_down_held = false
	print("  held down to the bottom -> off the cable: %s, landed on floor: %s" % [
		_player.zipline == null, _player.is_on_floor()])

	# And F releases mid-cable.
	_player.global_position = cable.world_bottom() + Vector2(10, -200)
	await _wait(4)
	_input.touch_interact_pressed = true
	await _wait(3)
	var riding_again := _player.zipline != null
	_input.touch_interact_pressed = true
	await _wait(3)
	print("  grabbed again: %s, then F -> let go: %s" % [
		riding_again, _player.zipline == null])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
