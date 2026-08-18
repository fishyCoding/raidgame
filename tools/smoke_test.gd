extends SceneTree

## Throwaway harness for headless checks:
##   godot --headless --path <project> --script res://tools/smoke_test.gd
##
## Drives the character through the PlayerInput autoload, which is the same
## seam the touch HUD will use â€” so this doubles as a check that the seam works.

var _main: Node
var _player: CharacterBody2D
## Looked up at runtime: autoload globals are not visible to a --script main loop.
var _input: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	# --script never sets this, and gameplay code parents bullets relative to it.
	current_scene = _main
	_player = _main.get_node("Player")
	_run()


func _run() -> void:
	await physics_frame # let _ready() propagate
	_input = root.get_node("/root/PlayerInput")
	_park_guards()
	_arm_player()

	print("-- level blocks --")
	for p in _main.get_node("World").get_children():
		var col: CollisionShape2D = p.get_node("CollisionShape2D")
		var occ: OccluderPolygon2D = p.get_node("LightOccluder2D").occluder
		var bounds := Rect2(occ.polygon[0], Vector2.ZERO)
		for point in occ.polygon:
			bounds = bounds.expand(point)
		print("%-9s size=%-14s collision=%-14s occluder=%-14s one_way=%s" % [
			p.name, p.size, (col.shape as RectangleShape2D).size, bounds.size,
			col.one_way_collision,
		])

	await _settle()
	var ground_y := _player.global_position.y
	print("\n-- landing --")
	print("resting y=%.1f on_floor=%s" % [ground_y, _player.is_on_floor()])

	print("\n-- full jump --")
	var peak := await _jump(0.5)
	print("held 0.5s -> peak height %.1f px (jump_height export = %.1f)" % [
		ground_y - peak, _player.jump_height,
	])

	print("\n-- short hop --")
	await _settle()
	peak = await _jump(0.08)
	print("held 0.08s -> peak height %.1f px" % [ground_y - peak])

	print("\n-- run --")
	_player.global_position = Vector2(-450, 200) # clear stretch of ground
	await _settle()
	var start_x := _player.global_position.x
	_input.touch_move_axis = 1.0
	for i in 60:
		await physics_frame
	_input.touch_move_axis = 0.0
	print("1s of run -> %.1f px, speed %.1f (max_speed = %.1f)" % [
		_player.global_position.x - start_x, _player.velocity.x, _player.max_speed,
	])

	print("\n-- drop through one-way --")
	_player.global_position = Vector2(280, 130) # above OneWay1 (top y=170)
	_player.velocity = Vector2.ZERO
	await _settle()
	var on_platform_y := _player.global_position.y
	print("landed on one-way at y=%.1f" % on_platform_y)
	_input.touch_down_held = true
	_input.touch_jump_pressed = true
	for i in 60:
		await physics_frame
	_input.touch_down_held = false
	print("after down+jump y=%.1f (fell %.1f px)" % [
		_player.global_position.y, _player.global_position.y - on_platform_y,
	])

	print("\n-- aim --")
	_input.touch_aim_direction = Vector2.LEFT
	await physics_frame
	await physics_frame
	print("aiming left -> facing=%d" % _player.facing)
	_input.touch_aim_direction = Vector2.RIGHT
	for i in 20:
		await physics_frame
	print("aiming right -> facing=%d muzzle=%s" % [
		_player.facing, _player.get_muzzle_position() - _player.global_position,
	])

	await _weapons()
	await _line_of_sight()
	quit()




## This harness measures movement, weapons and line of sight, and every one of
## its shooting ranges runs straight through a guard's patrol beat. Switch them
## off so a wandering body never eats a round meant for a dummy. Guard behaviour
## under fire is checked in a real session instead, by match_test.
func _park_guards() -> void:
	for guard in _main.get_node("Enemies").get_children():
		guard.collision_layer = 0
		guard.process_mode = Node.PROCESS_MODE_DISABLED
		guard.visible = false
		guard.remove_from_group(&"hideable")


func _line_of_sight() -> void:
	print("\n-- line of sight --")
	var target: Node2D = _main.get_node("Targets/Target1") # x=-150, on the ground
	var vision: Node = _main.get_node("VisionSystem")
	target._reset()

	# The crate at x=115..205 sits squarely between this vantage point and the
	# target; from the left there is nothing in the way.
	for vantage in [Vector2(500, 200), Vector2(-400, 200)]:
		_player.global_position = vantage
		_player.velocity = Vector2.ZERO
		await _settle()
		await _wait(3)
		var eye: Vector2 = _player.get_node("Vision").global_position
		print("eye at %-16s -> target visible=%-5s modulate_alpha=%.2f (dist %.0fpx)" % [
			eye, target.visible, target.modulate.a, eye.distance_to(target.global_position),
		])

	print("beyond vision range (%.0fpx):" % vision.vision_range)
	_player.global_position = Vector2(-1000, 200)
	await _settle()
	await _wait(3)
	var far_target: Node2D = _main.get_node("Targets/Target6") # x=1010
	print("  eye->target %.0fpx -> visible=%s" % [
		_player.get_node("Vision").global_position.distance_to(far_target.global_position),
		far_target.visible,
	])

	print("destroyed targets stay hidden even in the open:")
	_player.global_position = Vector2(-400, 200)
	await _settle()
	target._health = 1.0
	target.take_damage(50.0, target.global_position, Vector2.RIGHT)
	await _wait(5)
	print("  after break -> visible=%s in_hideable_group=%s" % [
		target.visible, target.is_in_group(&"hideable"),
	])


func _weapons() -> void:
	var weapon: Weapon = _player.weapon
	_player.global_position = Vector2(-500, 200)
	_input.touch_aim_direction = Vector2.RIGHT
	await _settle()

	print("\n-- one second on the trigger, per weapon --")
	for slot in _arsenal.size():
		_equip(slot)
		await _wait(45) # let the equip animation clear
		var data: WeaponData = weapon.data
		var start_mag := weapon.get_mag()

		var shots := [0]
		var counter := func(_shake: float, _knock: float) -> void: shots[0] += 1
		weapon.shot_fired.connect(counter)

		_input.touch_fire_held = true
		await _wait(60)
		_input.touch_fire_held = false
		weapon.shot_fired.disconnect(counter)

		print("%-8s %s %4drpm | %2d shots | mag %3d->%3d | cone %.2f->%.2f deg | kick %.1f deg" % [
			data.short_name,
			"auto" if data.automatic else "semi",
			int(data.rounds_per_minute),
			shots[0], start_mag, weapon.get_mag(),
			rad_to_deg(data.get_base_spread()),
			rad_to_deg(weapon.get_spread()),
			rad_to_deg(weapon.kick),
		])
		await _wait(120) # let recoil wash out before the next gun

	print("\n-- recovery (stability) --")
	_equip(0)
	await _wait(45)
	_input.touch_fire_held = true
	await _wait(30)
	_input.touch_fire_held = false
	var hot_bloom := weapon.bloom
	var hot_kick := weapon.kick
	await _wait(90)
	print("AR after burst: cone +%.2f deg, kick %.2f deg" % [
		rad_to_deg(hot_bloom), rad_to_deg(hot_kick),
	])
	print("AR 1.5s later:  cone +%.2f deg, kick %.2f deg" % [
		rad_to_deg(weapon.bloom), rad_to_deg(weapon.kick),
	])

	print("\n-- pellets --")
	_equip(2) # shotgun
	await _wait(60)
	var bullets := _main.get_node("Bullets")
	_input.touch_fire_held = true
	await physics_frame
	_input.touch_fire_held = false
	await physics_frame
	print("one shotgun shell -> %d projectiles in flight" % bullets.get_child_count())

	print("\n-- mag, dry fire, reload --")
	_equip(1) # smg
	await _wait(60)
	var reserve_before := weapon.get_reserve()
	# Hold the trigger only until the mag runs dry, so the dry-fire handoff into
	# a reload can be observed instead of the whole cycle blurring together.
	_input.touch_fire_held = true
	var fired := 0
	var start_mag := weapon.get_mag()
	while weapon.get_mag() > 0 and fired < 600:
		await physics_frame
		fired += 1
	await _wait(4) # keep holding: the dry pull is what kicks off the reload
	_input.touch_fire_held = false
	print("emptied %d rounds in %.2fs -> mag=%d, auto-reload started=%s" % [
		start_mag, fired / 60.0, weapon.get_mag(), weapon.is_reloading(),
	])
	var reload_frames := 0
	while weapon.is_reloading() and reload_frames < 600:
		await physics_frame
		reload_frames += 1
	print("reload took %.2fs (expected %.2fs) -> mag=%d reserve=%d->%d" % [
		reload_frames / 60.0, weapon.data.get_reload_duration(),
		weapon.get_mag(), reserve_before, weapon.get_reserve(),
	])

	print("\n-- damage on target --")
	var target: Node = _main.get_node("Targets/Target1") # sits at x=-150 on the ground
	_player.global_position = Vector2(-420, 200)
	await _settle()
	for slot in [0, 2, 4]: # AR, shotgun, sniper
		_equip(slot)
		await _wait(50)
		var before: float = target._health
		_input.touch_fire_held = true
		await physics_frame
		_input.touch_fire_held = false
		await _wait(30) # time of flight
		print("%-8s single trigger pull -> target %.0f -> %.0f (%.0f damage)" % [
			weapon.data.short_name, before, target._health, before - target._health,
		])
		target._reset()
		await _wait(30)

	print("\n-- damage falloff curves --")
	for w: WeaponData in _arsenal:
		var row := "%-8s burst %3d |" % [w.short_name, roundi(w.get_burst_damage())]
		for dist in [0.0, 300.0, 600.0, 1000.0, 2000.0]:
			row += " %4dpx:%3d" % [dist, roundi(w.get_burst_damage() * w.get_damage_factor(dist))]
		print("%s | full to %dpx, floor %dpx" % [row, w.falloff_start, w.falloff_end])

	# The corridor right of the crate is clear from x=205 to the far wall, so
	# these two shots differ only in distance.
	print("\n-- falloff, actually shot --")
	var near_target: Node = _main.get_node("Targets/Target4") # x=700
	var far_target: Node = _main.get_node("Targets/Target6")  # x=1010
	for slot in [0, 1, 2, 4]:
		_equip(slot)
		await _wait(60)
		var near_hit := await _shoot_at(near_target)
		var far_hit := await _shoot_at(far_target)
		print("%-8s %3dpx -> %3d dmg | %3dpx -> %3d dmg%s" % [
			weapon.data.short_name,
			roundi(near_hit.y), roundi(near_hit.x),
			roundi(far_hit.y), roundi(far_hit.x),
			"  (past max range)" if far_hit.x <= 0.0 else "",
		])

	print("\n-- handling: move speed while carrying --")
	for slot in [1, 3]: # smg (light) vs lmg (heavy)
		_equip(slot)
		await _wait(60)
		_player.global_position = Vector2(-450, 200)
		await _settle()
		_input.touch_move_axis = 1.0
		await _wait(60)
		_input.touch_move_axis = 0.0
		print("%-8s top speed %.0f px/s (base %.0f x %.2f)" % [
			weapon.data.short_name, absf(_player.velocity.x), _player.max_speed,
			weapon.data.get_move_multiplier(),
		])


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


## Stands in the open corridor, fires single shots at a target until one lands,
## and returns (damage dealt, distance travelled). Retries because spread means
## any one round can miss.
func _shoot_at(target: Node) -> Vector2:
	_player.global_position = Vector2(250, 200)
	_player.velocity = Vector2.ZERO
	await _settle()

	# Take every other dummy out of the physics world first: they stand in the
	# same corridor, and a nearer one eats the rounds meant for a farther one.
	var others: Array[Node] = []
	for t in _main.get_node("Targets").get_children():
		if t != target:
			t.collision_layer = 0
			others.append(t)
	target._reset()

	var muzzle: Vector2 = _player.get_muzzle_position()
	var distance: float = absf(target.global_position.x - target.size.x * 0.5 - muzzle.x)
	var result := await _fire_until_hit(target, distance)

	for t in others:
		t.collision_layer = Layers.TARGET
	return result


func _fire_until_hit(target: Node, distance: float) -> Vector2:

	for attempt in 8:
		var before: float = target._health
		_input.touch_fire_held = true
		await _wait(2)
		_input.touch_fire_held = false
		await _wait(40) # time of flight at the slowest muzzle velocity
		if target._health < before:
			return Vector2(before - target._health, distance)
	return Vector2(0.0, distance)


## Waits until the player is standing still on the floor.
func _settle() -> void:
	_input.touch_move_axis = 0.0
	for i in 300:
		await physics_frame
		if _player.is_on_floor() and absf(_player.velocity.x) < 1.0:
			return
	push_error("player never settled")


## Jumps, holding the button for `hold` seconds, and returns the peak y.
func _jump(hold: float) -> float:
	var peak_y := _player.global_position.y
	_input.touch_jump_pressed = true
	_input.touch_jump_held = true
	var frames_held := int(hold * 60.0)
	for i in 120:
		if i == frames_held:
			_input.touch_jump_held = false
		await physics_frame
		peak_y = minf(peak_y, _player.global_position.y)
		if i > frames_held and _player.is_on_floor():
			break
	_input.touch_jump_held = false
	return peak_y

