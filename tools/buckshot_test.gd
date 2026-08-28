extends SceneTree

## Buckshot: a cone inside a cone.
##
##   godot --headless --path . --script res://tools/buckshot_test.gd
##
## The outer cone is the gun - accuracy, bloom, whatever you were doing with your
## feet - and it decides where the shell goes. The inner cone is the shell, and
## it decides how the nine pellets sit around that line. Both matter, and which
## one is which is the whole behaviour: rolled per pellet across one wide cone,
## a shotgun's pattern is nailed to the crosshair however badly you were moving,
## because the middle pellet always goes exactly where you pointed.
##
## Measured off the bullets themselves rather than off the numbers, because the
## numbers being right and the loop being wrong is exactly the bug this is for.

const SHOTGUN := "res://resources/weapons/shotgun.tres"
const RIFLE := "res://resources/weapons/assault_rifle.tres"

var _ok := true


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("  FAIL  %s" % what)
	else:
		print("  ok    %s" % what)


func _run() -> void:
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame
	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("no character - cannot run")
		quit(1)
		return
	# Armed through the inventory, the way every other harness does it: the gun
	# reads its own data off whatever Item is in the slot, so a WeaponData poked
	# straight onto the node is overwritten the next time the slot is looked at.
	var kit := Inventory.new()
	kit.set_backpack(Item.from_backpack(
		load("res://resources/backpacks/heavy_rucksack.tres")))
	for path in [SHOTGUN, RIFLE]:
		var gun := load(path) as WeaponData
		kit.store(Item.from_weapon(gun))
		kit.add_rounds(gun.ammo_type, 600)
	player.weapon.set_inventory(kit)
	player.inventory = kit

	var weapon: Node = player.weapon
	var data := load(SHOTGUN) as WeaponData
	weapon.equip_data(data)
	await physics_frame

	print("-- the gun --")
	print("  %d pellets, aim cone +-%.2f deg, pattern +-%.2f deg, %.0f rpm" % [
		data.pellets, rad_to_deg(data.get_base_spread()),
		rad_to_deg(data.get_pellet_spread()), data.rounds_per_minute])
	_check(data.pellets > 1, "a shotgun has to throw more than one pellet")
	_check(data.get_pellet_spread() > 0.0, "and the shell has a pattern of its own")

	# --- one shell, one line --------------------------------------------------
	#
	# Every pellet of a single shot has to sit inside the pattern, measured from
	# the middle of that shot rather than from the crosshair. That is the whole
	# claim: the pellets are grouped around wherever the shell went, not sprayed
	# across everywhere the shell might have gone.
	print("\n-- one shell --")
	var pattern := rad_to_deg(data.get_pellet_spread())
	var widest := 0.0
	var wander := 0.0
	var shells := 0
	for shot in 24:
		var angles := await _fire(main, weapon, player)
		if angles.size() != data.pellets:
			continue
		shells += 1
		# Measured end to end rather than from the middle of the shot. Where the
		# shell went is not something this can see - the average of the pellets
		# is near it but not it - and every pellet being inside the pattern means
		# the two outermost are at most a pattern either side of each other.
		var low: float = angles[0]
		var high: float = angles[0]
		var middle := 0.0
		for a in angles:
			low = minf(low, a)
			high = maxf(high, a)
			middle += a
		middle /= float(angles.size())
		widest = maxf(widest, rad_to_deg(high - low))
		wander = maxf(wander, absf(rad_to_deg(middle)))
	print("  %d shells: widest was %.2f deg across (the pattern is %.2f)" % [
		shells, widest, pattern * 2.0])
	_check(shells > 10, "the gun has to have actually fired for this")
	_check(widest <= pattern * 2.0 + 0.01,
		"no pellet leaves the pattern of the shell it came out of")

	# And the shell itself moves. If it never did, the outer cone is being
	# ignored and the pattern is welded to the crosshair.
	print("  the shell's own line wandered up to %.2f deg off the crosshair" % wander)
	_check(wander > 0.05, "the shell goes where the gun was pointed, not the reticle")

	# --- the pattern is much tighter than the cone it sits in -----------------
	#
	# The number that was asked for. Before this the pellets were laid across the
	# whole aim cone, so the pattern *was* the cone.
	var aim := rad_to_deg(data.get_base_spread())
	print("\n-- pattern %.2f deg vs aim cone %.2f deg --" % [pattern, aim])
	_check(pattern < aim,
		"the shell patterns tighter than the gun points, or it is one cone again")

	# --- a single round is untouched ------------------------------------------
	#
	# Every other gun in the game goes through the same loop, and a rifle must
	# still put its one round anywhere in its cone.
	print("\n-- and a rifle is still a rifle --")
	var rifle := load(RIFLE) as WeaponData
	weapon.equip_data(rifle)
	await physics_frame
	_check(rifle.get_pellet_spread() == 0.0,
		"a gun that fires one round has no pattern to have")
	var rifle_spread := rad_to_deg(rifle.get_base_spread())
	var off := 0.0
	var rounds := 0
	for shot in 30:
		var angles := await _fire(main, weapon, player)
		for a in angles:
			rounds += 1
			off = maxf(off, absf(rad_to_deg(a)))
	print("  %d rounds, furthest %.2f deg off (cone is %.2f)" % [
		rounds, off, rifle_spread])
	_check(rounds > 10, "the rifle has to have fired for this")
	_check(off <= rifle_spread + 0.01, "a single round stays inside its own cone")
	_check(off > rifle_spread * 0.2, "and still scatters across it")

	print("\n%s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


## One trigger pull, and the angles of everything it put in the air.
##
## Read off the bullets in the level rather than returned by the gun: what is
## under test is the loop that spawns them.
func _fire(main: Node, weapon: Node, player: Node2D) -> Array:
	var bullets: Node = main.get_node("Bullets")
	for old in bullets.get_children():
		old.free()
	# Rested first, so bloom from the last shot is not measured as spread; with
	# the trigger let go, so a semi-automatic will take the next press; and out
	# of the draw, because equip_data starts one and a gun coming up does not
	# fire. That last one is why an earlier version of this measured three rounds
	# out of thirty and called it a scatter.
	weapon.bloom = 0.0
	weapon.kick = 0.0
	weapon.focus = 0.0
	weapon._cooldown = 0.0
	weapon._equip_left = 0.0
	weapon.stowed = false
	weapon._trigger_held = false
	var item: Item = weapon._item()
	if item:
		item.count = weapon.data.mag_size
	weapon.try_fire(player.global_position, 0.0, true, true, 0.0, 0.0)
	# Read on the spot rather than a frame later. Rounds travel three thousand
	# pixels a second and free themselves on the first thing they touch, so a
	# frame of flight is a frame in which most of a pattern can go missing.
	var angles: Array = []
	for shot in bullets.get_children():
		angles.append((shot as Node2D).rotation)
	return angles
