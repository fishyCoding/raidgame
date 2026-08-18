extends SceneTree

## Headless check for the sighting changes:
##   godot --headless --path <project> --script res://tools/sights_test.gd
##
## Covers the aim line, the one-way platforms you can see through but not shoot
## through, the overlay layer the reticle sits on, and per-weapon scope zoom.

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
	_input = root.get_node("/root/PlayerInput")
	_arm_player()
	# Guards patrol through the ranges used below, and this test is not about
	# them. What they do under fire is checked in a real session, by match_test.
	for guard in _main.get_node("Enemies").get_children():
		guard.collision_layer = 0
		guard.process_mode = Node.PROCESS_MODE_DISABLED
		guard.visible = false
		guard.remove_from_group(&"hideable")

	await _overlay_layers()
	await _aim_line()
	await _one_way()
	await _scopes()
	quit()


## The reticle and aim line must not live in the world canvas, or the ambient
## tint and the vision light's shadows fall across them.
func _overlay_layers() -> void:
	print("-- overlay layers --")
	var overlay: CanvasLayer = _player.get_node("Overlay")
	print("  player overlay: layer=%d follow_viewport=%s children=%s" % [
		overlay.layer, overlay.follow_viewport_enabled,
		overlay.get_children().map(func(n: Node) -> String: return n.name),
	])
	var world_overlay: CanvasLayer = _main.get_node("WorldOverlay")
	print("  damage numbers:  layer=%d follow_viewport=%s" % [
		world_overlay.layer, world_overlay.follow_viewport_enabled,
	])
	print("  hud layer=%d, ambient tint applies to the world canvas only" % [
		(_main.get_node("HUD") as CanvasLayer).layer,
	])

	var target: Node2D = _main.get_node("Targets/Target1")
	_player.global_position = Vector2(-400, 200)
	await _settle()
	target.take_damage(10.0, target.global_position, Vector2.RIGHT)
	await physics_frame
	print("  damage number parented to: %s" % world_overlay.get_child(0).name
		if world_overlay.get_child_count() > 0 else "  no damage number spawned")


func _aim_line() -> void:
	print("\n-- aim line --")
	var line: AimLine = _player.get_node("Overlay/AimLine")
	for aim in [Vector2.RIGHT, Vector2(1, -1).normalized(), Vector2.LEFT]:
		_input.touch_aim_direction = aim
		await _wait(30)
		var muzzle: Vector2 = _player.get_muzzle_position()
		print("  aim %-14s from=%s (muzzle %s) to=%s | length %.0f px, focus %.2f" % [
			aim, line.from.round(), muzzle.round(), line.to.round(),
			line.from.distance_to(line.to), line.focus,
		])
	_input.touch_aim_direction = Vector2.RIGHT

	_input.touch_aim_held = true
	await _wait(30)
	print("  aimed: focus %.2f, length %.0f px (line straightens as focus rises)" % [
		line.focus, line.from.distance_to(line.to),
	])
	_input.touch_aim_held = false
	await _wait(30)


## OneWay1 spans x 180..380 at y 170..190. Standing under it, the dummy moved
## just above it should be visible, and rounds fired up at it should not reach.
func _one_way() -> void:
	print("\n-- one-way platforms: see through, not shoot through --")
	var vision: VisionSystem = _main.get_node("VisionSystem")
	print("  sight mask = %d (world only: %s, one_way excluded: %s)" % [
		VisionSystem.SIGHT_MASK,
		VisionSystem.SIGHT_MASK & Layers.WORLD != 0,
		VisionSystem.SIGHT_MASK & Layers.ONE_WAY == 0,
	])

	var target: Node2D = _main.get_node("Targets/Target2")
	target.global_position = Vector2(280, 124) # resting on top of OneWay1
	target._reset()
	_player.global_position = Vector2(280, 256) # directly underneath
	_player.velocity = Vector2.ZERO
	await _settle()
	await _wait(5)
	print("  dummy above the catwalk, player below: visible=%s" % target.visible)

	# And the same line of sight, with a round sent up it.
	_input.touch_aim_direction = Vector2.UP
	var weapon: Weapon = _player.weapon
	_equip(4) # sniper: one shot, no spread worth speaking of
	await _wait(90)
	var before: float = target._health
	_input.touch_fire_held = true
	await _wait(2)
	_input.touch_fire_held = false
	await _wait(40)
	print("  sniper round straight up -> dummy %.0f -> %.0f hp (%s)" % [
		before, target._health,
		"stopped by the catwalk" if is_equal_approx(before, target._health) else "PASSED THROUGH",
	])

	# Sanity: the same shot with nothing in the way does land. The wait is the
	# sniper's 1.25s cooldown - without it the control shot never leaves the
	# barrel and the check passes for the wrong reason.
	target.global_position = Vector2(560, 124)
	_player.global_position = Vector2(560, 256)
	target._reset()
	await _settle()
	await _wait(90)
	before = target._health
	_input.touch_fire_held = true
	await _wait(2)
	_input.touch_fire_held = false
	await _wait(40)
	print("  same shot in the clear    -> dummy %.0f -> %.0f hp" % [before, target._health])
	_input.touch_aim_direction = Vector2.RIGHT


func _scopes() -> void:
	print("\n-- sights, per weapon --")
	var weapon: Weapon = _player.weapon
	var camera: Camera2D = _player.get_node("Camera2D")
	_player.global_position = Vector2(-450, 200)
	await _settle()

	for slot in _arsenal.size():
		_equip(slot)
		await _wait(60)
		var data: WeaponData = weapon.data
		var hip := rad_to_deg(weapon.get_spread())
		_input.touch_aim_held = true
		await _wait(60)
		# How much ground is on screen ahead of the player: what you can see to
		# shoot at. Magnification cuts it, the camera lean buys it back.
		var half_screen: float = _player.get_viewport_rect().size.x * 0.5 / camera.zoom.x
		var forward := half_screen + absf(camera.position.x)
		print("  %-8s zoom %.2fx | cone %.2f -> %.2f deg | ramp %.2fs | reticle %.0f px | lean %.0f px -> %.0f px of ground ahead" % [
			data.short_name, camera.zoom.x, hip, rad_to_deg(weapon.get_spread()),
			_player.ads_time * data.ads_speed_scale, _player._reticle.radius,
			absf(camera.position.x), forward,
		])
		_input.touch_aim_held = false
		await _wait(40)

	print("\n-- recoil climbs, stability scatters --")
	for w: WeaponData in _arsenal:
		print("  %-8s recoil %3d -> climb %.2f deg/shot (max %.1f) | stability %3d -> scatter %.2f deg/shot (max %.1f)" % [
			w.short_name,
			roundi(w.recoil), rad_to_deg(w.get_kick_per_shot()), rad_to_deg(w.get_max_kick()),
			roundi(w.stability), rad_to_deg(w.get_bloom_per_shot()), rad_to_deg(w.get_max_bloom()),
		])

	print("\n-- one second on the trigger: where does the aim end up --")
	_input.touch_aim_direction = Vector2.RIGHT
	for slot in [0, 1, 3]: # the three automatics
		_equip(slot)
		await _wait(60)
		var start_angle: float = _player.aim_angle
		_input.touch_fire_held = true
		await _wait(60)
		_input.touch_fire_held = false
		# Positive = the muzzle finished higher than it started (y is down).
		print("  %-8s climbed %.2f deg, cone widened to %.2f deg" % [
			weapon.data.short_name,
			rad_to_deg(start_angle - _player.aim_angle),
			rad_to_deg(weapon.get_spread()),
		])
		await _wait(150)




## The player starts with a sidearm and loots the rest; these checks measure the
## guns, so build a kit holding all five with ammunition to spare. Indexed in
## the order the checks assume: AR, SMG, shotgun, LMG, sniper.
const ARSENAL_PATHS := [
	"res://resources/weapons/assault_rifle.tres",
	"res://resources/weapons/smg.tres",
	"res://resources/weapons/shotgun.tres",
	"res://resources/weapons/lmg.tres",
	"res://resources/weapons/sniper.tres",
]

var _arsenal: Array[WeaponData] = []


func _arm_player() -> void:
	# Grids big enough that space is never the thing under test here.
	var kit := Inventory.new()
	# A big bag, so space never limits what these harnesses are measuring.
	kit.set_backpack(Item.from_backpack(load("res://resources/backpacks/heavy_rucksack.tres")))
	for path in ARSENAL_PATHS:
		var data := load(path) as WeaponData
		_arsenal.append(data)
		kit.store(Item.from_weapon(data))
		kit.add_rounds(data.ammo_type, 400)
	_player.weapon.set_inventory(kit)
	_player.inventory = kit


## Brings arsenal weapon `index` to hand, wherever the inventory is keeping it.
func _equip(index: int) -> void:
	_player.weapon.equip_data(_arsenal[index])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _settle() -> void:
	_input.touch_move_axis = 0.0
	for i in 300:
		await physics_frame
		if _player.is_on_floor() and absf(_player.velocity.x) < 1.0:
			return
	push_error("player never settled")
