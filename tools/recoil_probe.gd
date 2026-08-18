extends SceneTree

## Does recoil always push the muzzle UP, whatever direction the gun points and
## however far the aim angle has been wound around the circle?
##   godot --headless --path <project> --script res://tools/recoil_probe.gd
##
## "Up" is checked as the vertical part of the aim direction getting smaller
## (y grows downward), comparing the aim with recoil against the aim without it.

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
	for guard in _main.get_node("Enemies").get_children():
		guard.process_mode = Node.PROCESS_MODE_DISABLED

	_player.global_position = Vector2(-450, 200)
	await _wait(60)

	await _vertical_stability()
	await _long_burst()
	await _settling()

	print("\n-- climb, by aim direction --")
	await _sweep()

	# Wind the aim several times around the circle first: rotate_toward walks the
	# angle rather than wrapping it, and an unwrapped angle used to flip the
	# facing test and send the recoil the wrong way.
	print("\n-- after spinning the aim 3 laps --")
	for lap in 3:
		for step in 12:
			_input.touch_aim_direction = Vector2.RIGHT.rotated(TAU * step / 12.0)
			await _wait(3)
	print("  _aim_base = %.2f rad (wrapped into -PI..PI: %s)" % [
		_player._aim_base, absf(_player._aim_base) <= PI + 0.001,
	])
	await _sweep()
	quit()


## Firing straight up, with the mouse wobbling a hair either side of vertical -
## the case where a signed kick flips back and forth and throws the aim across
## the sky. Reports the widest jump between one frame and the next; anything
## beyond a degree or two means the aim is snapping rather than settling.
func _vertical_stability() -> void:
	print("-- firing straight up, mouse wobbling across vertical --")
	var weapon: Weapon = _player.weapon
	for slot in [3, 4]: # LMG (worst climb) and sniper (worst single kick)
		_equip(slot)
		await _wait(70)
		_top_up()
		_input.touch_aim_direction = Vector2.UP
		await _wait(60)

		var worst_jump := 0.0
		var lowest := 999.0
		var highest := -999.0
		var previous: float = _player.aim_angle
		_input.touch_fire_held = true
		for i in 180:
			# A hair either side of straight up, alternating - a hand on a mouse.
			_input.touch_aim_direction = Vector2(0.03 if i % 2 == 0 else -0.03, -1.0).normalized()
			await physics_frame
			var current: float = _player.aim_angle
			worst_jump = maxf(worst_jump, absf(rad_to_deg(angle_difference(previous, current))))
			var from_vertical := rad_to_deg(angle_difference(-PI * 0.5, current))
			lowest = minf(lowest, from_vertical)
			highest = maxf(highest, from_vertical)
			previous = current
		_input.touch_fire_held = false

		print("  %-8s aim stayed within %.1f..%.1f deg of vertical | worst frame-to-frame jump %.2f deg | kick %.1f deg" % [
			weapon.data.short_name, lowest, highest, worst_jump, rad_to_deg(weapon.kick),
		])
		await _wait(240)
	_input.touch_aim_direction = Vector2.RIGHT


## Holds the trigger down on the automatics for four seconds, sampling the climb
## twice a second. What matters here is the shape: it should keep creeping as it
## nears the ceiling, never jump to a number and sit there dead.
func _long_burst() -> void:
	print("-- four seconds on the trigger, climb every 0.5s --")
	var weapon: Weapon = _player.weapon
	_input.touch_aim_direction = Vector2.RIGHT
	for slot in [0, 1, 3]:
		_equip(slot)
		await _wait(70)
		_top_up() # never run dry mid-burst

		var samples: Array[String] = []
		_input.touch_fire_held = true
		for i in 8:
			await _wait(30)
			samples.append("%5.1f" % rad_to_deg(weapon.kick))
		_input.touch_fire_held = false
		print("  %-8s %s | ceiling %.1f deg" % [
			weapon.data.short_name, " ".join(samples),
			rad_to_deg(weapon.data.get_max_kick()),
		])
		await _wait(240)


## How long the climb hangs around after the trigger is released, per weapon.
func _settling() -> void:
	print("\n-- climb, and how slowly it comes back down --")
	var weapon: Weapon = _player.weapon
	_input.touch_aim_direction = Vector2.RIGHT
	for slot in _arsenal.size():
		_equip(slot)
		await _wait(70)
		_top_up()

		# One trigger pull for the semis, a second on the trigger for the autos.
		_input.touch_fire_held = true
		await _wait(60 if weapon.data.automatic else 2)
		_input.touch_fire_held = false
		await physics_frame
		var peak: float = weapon.kick

		var samples: Array[String] = []
		for i in 4:
			await _wait(30)
			samples.append("%.1fs %5.2f" % [(i + 1) * 0.5, rad_to_deg(weapon.kick)])
		print("  %-8s peak %5.2f deg | after release: %s | shake %.1f px/shot" % [
			weapon.data.short_name, rad_to_deg(peak), " | ".join(samples),
			weapon.data.get_shake(),
		])
		await _wait(180)


func _sweep() -> void:
	var weapon: Weapon = _player.weapon
	var bad := 0
	for step in 12:
		var angle := TAU * step / 12.0 - PI
		_input.touch_aim_direction = Vector2.RIGHT.rotated(angle)
		_equip(0)
		await _wait(70) # swing onto the new heading, and let the last kick wash out

		# Top the gun up: a heading that happens to land mid-reload fires nothing,
		# and "did not move" would otherwise read as "kicked the wrong way".
		_top_up()

		var before := Vector2.RIGHT.rotated(_player._aim_base)
		_input.touch_fire_held = true
		await _wait(18)
		_input.touch_fire_held = false
		await physics_frame
		var after: Vector2 = _player.aim_direction
		# Straight up and straight down have no "up" to climb into; the muzzle
		# swings sideways there and the vertical test does not apply.
		var vertical := absf(before.x) < 0.001
		var climbed := after.y < before.y - 0.0001
		var verdict := "n/a (pointing straight up/down)" if vertical \
			else ("UP" if climbed else "*** DOWN ***")
		if is_zero_approx(weapon.kick):
			verdict = "no shot fired - inconclusive"
		elif not vertical and not climbed:
			bad += 1
		print("  aim %4d deg | facing %2d | kick %5.2f deg | aim y %.3f -> %.3f | %s" % [
			roundi(rad_to_deg(angle)), _player.facing, rad_to_deg(weapon.kick),
			before.y, after.y, verdict,
		])
		await _wait(120)
	print("  headings kicking the wrong way: %d" % bad)




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


## Fills the magazine of whatever is in hand. A gun that runs dry mid-burst
## fires nothing, and "the aim did not move" would then be read as a failure.
func _top_up() -> void:
	var weapon: Weapon = _player.weapon
	var item: Item = _player.inventory.get_slot(weapon.slot)
	if item:
		item.count = item.weapon.mag_size
	weapon._reload_left = 0.0


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
