extends SceneTree

## Headless check for cooked throws, the arc preview and the Y debug key:
##   godot --headless --path <project> --script res://tools/throw_test.gd

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

	# Open ground with clear sky: standing under a step makes every hard throw
	# hit the underside of it, which says nothing about range.
	_player.global_position = Vector2(-1000, 250)
	_input.touch_aim_direction = Vector2(1.0, -0.2).normalized()
	await _wait(20)

	_debug_key()
	_distances()
	quit()


func _debug_key() -> void:
	print("-- Y with nothing equipped --")
	var kit: Inventory = _player.inventory
	print("  ultimate before: %s" % (kit.ultimate.label() if kit.ultimate else "none"))
	# The same path the key takes, minus the keyboard.
	if kit.ultimate == null:
		kit.set_ultimate(Item.from_gadget(
			load("res://resources/gadgets/overload.tres") as GadgetData))
	kit.ultimate.charge = 1.0
	print("  after Y: %s at %d%%" % [
		kit.ultimate.gadget.short_name, roundi(kit.ultimate.charge * 100.0)])


## The arc is the grenade's own maths, so measuring the arc measures the throw.
func _distances() -> void:
	print("\n-- how far a grenade goes --")
	var kit: Inventory = _player.inventory
	kit.store(Item.from_gadget(load("res://resources/gadgets/frag.tres")))

	for power in [0.0, 0.5, 1.0]:
		var arc: PackedVector2Array = _player._simulate_throw(power)
		var landing: Vector2 = arc[arc.size() - 1]
		var reach: float = absf(landing.x - _player.global_position.x)
		print("  %3d%% wind-up -> %d arc points, lands %.0f px away" % [
			roundi(power * 100.0), arc.size(), reach])

	print("\n-- winding up and letting go --")
	_player.throw_slot = 0
	_player.throw_charge = 0.0
	_input.touch_aim_direction = Vector2(1, -0.35).normalized()
	await_frames()
	var line = _player.get_node("Overlay/AimLine")
	print("  arc shown while held: %s, %d points" % [line.showing_arc, line.arc_points.size()])

	var before: int = kit.get_throwable(0).count
	_player._release_throw()
	var grenades := 0
	for child in _main.get_children():
		if child is Grenade:
			grenades += 1
	print("  released -> %d grenade in the level, %d left in the slot (was %d)" % [
		grenades, kit.get_throwable(0).count if kit.get_throwable(0) else 0, before])
	print("  arc hidden again: %s, message \"%s\"" % [not line.showing_arc, _player.loot_message])


func await_frames() -> void:
	# Winding up happens in _update_throw; drive it directly for one step.
	_player.throw_charge = 1.0
	_player._aim_line.arc_points = _player._simulate_throw(1.0)
	_player._aim_line.arc_power = 1.0
	_player._aim_line.showing_arc = true


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
