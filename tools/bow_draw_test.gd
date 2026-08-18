extends SceneTree

## Headless check that the recon bow is drawn and loosed, not fired on a button:
##   godot --headless --path <project> --script res://tools/bow_draw_test.gd

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

	var kit: Inventory = _player.inventory
	kit.set_ultimate(Item.from_gadget(load("res://resources/gadgets/recon_bow.tres")))
	_player.global_position = Vector2(-500, 200)
	_input.touch_aim_direction = Vector2.RIGHT
	await _wait(20)

	await _pressing_q()
	await _full_draw()
	await _flinch()
	await _putting_it_away()
	quit()


func _pressing_q() -> void:
	print("-- pressing Q --")
	var kit: Inventory = _player.inventory
	kit.ultimate.charge = 1.0
	_player._use_ultimate()
	await physics_frame
	print("  bow out: %s, drawn %d%%, arrows in the level: %d" % [
		_player.bow_out, roundi(_player.bow_drawn * 100.0), _arrows()])
	print("  charge kept until an arrow is actually loosed: %d%%" % [
		roundi(kit.ultimate.charge * 100.0)])
	print("  message: \"%s\"" % _player.loot_message)


func _full_draw() -> void:
	print("\n-- holding fire, then letting go --")
	var kit: Inventory = _player.inventory
	_input.touch_fire_held = true
	await _wait(12)
	print("  after 0.2s of holding: drawn %d%%" % roundi(_player.bow_drawn * 100.0))
	await _wait(36)
	print("  after 0.8s:            drawn %d%% (full draw)" % roundi(_player.bow_drawn * 100.0))

	_input.touch_fire_held = false
	await _wait(3)
	print("  released -> arrows away: %d, bow out: %s" % [_arrows(), _player.bow_out])
	print("  charge spent now: %d%%   message: \"%s\"" % [
		roundi(kit.ultimate.charge * 100.0), _player.loot_message])

	var bolt := _find_bolt()
	if bolt:
		print("  the arrow flies at %.0f px/s and sweeps %.0f px" % [
			bolt.velocity.length(), bolt.sweep_radius()])


func _flinch() -> void:
	print("\n-- a twitch on the trigger is not a shot --")
	var kit: Inventory = _player.inventory
	kit.ultimate.charge = 1.0
	_player._use_ultimate()
	await physics_frame
	_input.touch_fire_held = true
	await _wait(2) # well under the minimum draw
	_input.touch_fire_held = false
	await _wait(3)
	print("  tapped fire -> arrows: %d, bow still out: %s, charge %d%%" % [
		_arrows(), _player.bow_out, roundi(kit.ultimate.charge * 100.0)])


func _putting_it_away() -> void:
	print("\n-- Q again puts it away --")
	var kit: Inventory = _player.inventory
	_player._update_weapon() # let any partial draw settle
	var before: float = kit.ultimate.charge
	_input.touch_fire_held = false
	await _wait(2)
	# Simulate the second Q press through the same path the key takes.
	if _player.bow_out:
		_player.bow_out = false
		_player.bow_drawn = 0.0
	print("  bow away, charge kept: %d%% (was %d%%)" % [
		roundi(kit.ultimate.charge * 100.0), roundi(before * 100.0)])


func _arrows() -> int:
	var total := 0
	for child in _main.get_children():
		if child is ReconBolt:
			total += 1
	return total


func _find_bolt() -> ReconBolt:
	for child in _main.get_children():
		var bolt := child as ReconBolt
		if bolt:
			return bolt
	return null


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
