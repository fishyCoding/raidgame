extends SceneTree

## Headless check for the sound system:
##   godot --headless --path <project> --script res://tools/audio_test.gd
##
## Headless runs a dummy audio driver, so nothing is audible - what is checked
## here is that the waveforms are built, that the right events reach the mixer,
## and that a firefight cannot exhaust the player pool.

var _main: Node
var _player: CharacterBody2D
var _input: Node
var _audio: Node


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
	_audio = root.get_node("/root/Audio")

	print("-- synthesised sounds --")
	var weapon: Weapon = _player.weapon
	for w: WeaponData in _arsenal:
		var stream: AudioStreamWAV = _audio._build_gunshot(w)
		print("  %-8s gunshot %5.0f ms, %d samples, peak %.2f" % [
			w.short_name, _length_ms(stream), stream.data.size() / 2, _peak(stream),
		])
	for entry in [
		["footstep", _audio._footstep], ["footstep (guard)", _audio._footstep_soft],
		["reload start", _audio._reload_start], ["reload end", _audio._reload_end],
		["dry fire", _audio._dry],
	]:
		var stream: AudioStreamWAV = entry[1]
		print("  %-16s %5.0f ms, peak %.2f" % [entry[0], _length_ms(stream), _peak(stream)])

	print("\n-- player footsteps while running --")
	_player.global_position = Vector2(-450, 200)
	await _settle()
	var before := _playing_count()
	_input.touch_move_axis = 1.0
	var steps := 0
	var was_quiet := true
	for i in 90:
		await physics_frame
		var busy := _playing_count() > 0
		if busy and was_quiet:
			steps += 1
		was_quiet = not busy
	_input.touch_move_axis = 0.0
	print("  1.5s of running -> %d footfalls (pool was %d busy before)" % [steps, before])

	print("\n-- gunfire and reload --")
	await _settle()
	_input.touch_aim_direction = Vector2.RIGHT
	_equip(0)
	await _wait(60)
	var mag := weapon.get_mag()
	_input.touch_fire_held = true
	await _wait(30)
	_input.touch_fire_held = false
	print("  half a second on the AR -> %d rounds gone, %d players busy" % [
		mag - weapon.get_mag(), _playing_count(),
	])

	weapon.reload()
	await physics_frame
	print("  reload started -> %d players busy" % _playing_count())
	while weapon.is_reloading():
		await physics_frame
	await physics_frame
	print("  reload finished -> %d players busy" % _playing_count())

	print("\n-- the pool holds up under a full firefight --")
	_equip(3) # LMG, 700rpm
	await _wait(60)
	var overflowed := 0
	_input.touch_fire_held = true
	for i in 180:
		await physics_frame
		if _playing_count() > _audio.POOL_SIZE:
			overflowed += 1
	_input.touch_fire_held = false
	print("  3s of LMG fire + %d guards: %d players busy, pool size %d, overflows %d" % [
		_main.get_node("Enemies").get_child_count(), _playing_count(),
		_audio.POOL_SIZE, overflowed,
	])
	quit()


func _playing_count() -> int:
	var count := 0
	for player in _audio._players:
		if (player as AudioStreamPlayer2D).playing:
			count += 1
	return count


func _length_ms(stream: AudioStreamWAV) -> float:
	return float(stream.data.size() / 2) / stream.mix_rate * 1000.0


## Loudest sample in the waveform. Zero would mean silence got shipped.
func _peak(stream: AudioStreamWAV) -> float:
	var peak := 0.0
	var count := stream.data.size() / 2
	for i in count:
		peak = maxf(peak, absf(stream.data.decode_s16(i * 2) / 32767.0))
	return peak




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
