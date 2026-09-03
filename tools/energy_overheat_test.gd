extends SceneTree

## Checks the energy cell / overheat feature against the numbers it was built
## with: tier compatibility, the stat fold in Gunsmith.build(), the free
## stock cell, and the two overheat shapes (automatic lock, semi-auto
## cooldown stretch).
##
## Weapon.gd reaches Net, so it is never named as a type in this file - only
## loaded and instantiated after the one-frame wait below. See
## headless-test-must-unpause in project memory for why.

var _failures: Array[String] = []


func _init() -> void:
	await process_frame

	_check_compatibility()
	_check_stat_fold()
	_check_stock_cell()
	_check_wire_round_trip()
	await _check_overheat_automatic()
	await _check_overheat_semiauto()
	await _check_hot_bullet_visual()
	_check_muzzle_flash_easing()

	print("")
	if _failures.is_empty():
		print("OK - energy/overheat model matches spec")
	else:
		for line in _failures:
			print("FAIL - %s" % line)
		print("FAILED %d check(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


# --- tier compatibility --------------------------------------------------------


func _check_compatibility() -> void:
	print("-- compatibility --")
	var smg: WeaponData = load("res://resources/weapons/smg.tres")
	var ar: WeaponData = load("res://resources/weapons/assault_rifle.tres")
	var lmg: WeaponData = load("res://resources/weapons/lmg.tres")
	var sniper: WeaponData = load("res://resources/weapons/sniper.tres")

	_eq_int("pistol base tier", (load("res://resources/weapons/pistol.tres") as WeaponData).base_tier, 1)
	_eq_int("SMG base tier", smg.base_tier, 2)
	_eq_int("shotgun base tier", (load("res://resources/weapons/shotgun.tres") as WeaponData).base_tier, 2)
	_eq_int("AR base tier", ar.base_tier, 3)
	_eq_int("slug base tier", (load("res://resources/weapons/slug_shotgun.tres") as WeaponData).base_tier, 3)
	_eq_int("LMG base tier", lmg.base_tier, 4)
	_eq_int("sniper base tier", sniper.base_tier, 4)

	_bool("SMG(T2) takes T2", _cell(2).fits(smg), true)
	_bool("SMG(T2) takes T3", _cell(3).fits(smg), true)
	_bool("SMG(T2) takes T4", _cell(4).fits(smg), true)
	_bool("SMG(T2) refuses T1 (below base)", _cell(1).fits(smg), false)
	_bool("SMG(T2) refuses T5 (three over)", _cell(5).fits(smg), false)

	_bool("AR(T3) takes T5 (two over)", _cell(5).fits(ar), true)
	_bool("AR(T3) refuses T2 (below base)", _cell(2).fits(ar), false)
	_bool("AR(T3) refuses T6 (three over)", _cell(6).fits(ar), false)

	_bool("LMG(T4) takes T6 (two over)", _cell(6).fits(lmg), true)
	_bool("LMG(T4) refuses T3 (below base)", _cell(3).fits(lmg), false)

	_bool("sniper(T4) takes T6", _cell(6).fits(sniper), true)
	_bool("sniper(T4) refuses T3 (below base, even though LMG shares its tier)",
		_cell(3).fits(sniper), false)

	_eq_int("Gunsmith.energy_delta same tier", Gunsmith.energy_delta(smg, _cell(2)), 0)
	_eq_int("Gunsmith.energy_delta one over", Gunsmith.energy_delta(smg, _cell(3)), 1)
	_eq_int("Gunsmith.energy_delta two over", Gunsmith.energy_delta(smg, _cell(4)), 2)
	_eq_int("Gunsmith.energy_delta clamps a cell that should never fit",
		Gunsmith.energy_delta(smg, _cell(6)), 2)


# --- the stat fold --------------------------------------------------------------


func _check_stat_fold() -> void:
	print("\n-- Gunsmith.build() stat fold --")
	var ar: WeaponData = load("res://resources/weapons/assault_rifle.tres")

	var stock := Gunsmith.build(ar, [], _cell(3))
	_eq("delta 0: recoil unchanged", stock.recoil, ar.recoil)
	_eq("delta 0: stability unchanged", stock.stability, ar.stability)
	_eq("delta 0: damage unchanged", stock.damage, ar.damage)
	_eq("delta 0: bullet_speed unchanged", stock.bullet_speed, ar.bullet_speed)
	_bool("delta 0 returns the same reference (no wasted duplicate)",
		stock == ar, true)

	var hot1 := Gunsmith.build(ar, [], _cell(4))
	var hot2 := Gunsmith.build(ar, [], _cell(5))
	_bool("delta 1: recoil goes up", hot1.recoil > ar.recoil, true)
	_bool("delta 1: stability goes down", hot1.stability < ar.stability, true)
	_bool("delta 1: accuracy goes down (spread opens up)", hot1.accuracy < ar.accuracy, true)
	_bool("delta 1: damage goes up", hot1.damage > ar.damage, true)
	_bool("delta 1: bullet_speed goes up", hot1.bullet_speed > ar.bullet_speed, true)
	_bool("delta 1: noise goes up", hot1.loudness_trim > ar.loudness_trim, true)

	# The escalation the brief asked for: delta 2 is not delta 1 doubled, it is a
	# noticeably bigger jump than the one from delta 0 to delta 1.
	var step1 := hot1.recoil - ar.recoil
	var step2 := hot2.recoil - hot1.recoil
	_bool("delta 1->2 jumps further than delta 0->1 (recoil)", step2 > step1, true)
	var dstep1 := hot1.damage - ar.damage
	var dstep2 := hot2.damage - hot1.damage
	_bool("delta 1->2 jumps further than delta 0->1 (damage)", dstep2 > dstep1, true)


# --- the free stock cell ---------------------------------------------------------


func _check_stock_cell() -> void:
	print("\n-- the stock cell every gun ships with --")
	var smg_item := Item.from_weapon(load("res://resources/weapons/smg.tres"))
	_bool("a fresh SMG has a cell fitted", smg_item.energy != null, true)
	_eq_int("that cell is exactly the SMG's own base tier", smg_item.energy.tier, 2)
	_eq_int("so it fires at delta 0", smg_item.energy_delta(), 0)
	_bool("its weapon reference is the unmodified catalogue resource (delta 0, no fold)",
		smg_item.weapon == smg_item.base_weapon, true)

	# Guards build their kit the same way the shop does - Item.from_weapon() -
	# and never visit the gunsmith, so this is what stops every guard in the
	# level from spawning with an unfireable rifle.
	var guard_item := Item.from_weapon(load("res://resources/weapons/enemy_rifle.tres"))
	_bool("a guard's rifle also comes with a cell", guard_item.energy != null, true)

	# Fitting an incompatible cell is refused outright and touches nothing.
	var refused := smg_item.fit_energy(_cell(6))
	_bool("fitting a T6 cell to an SMG is refused", refused == null, true)
	_eq_int("the SMG's cell is unchanged after the refusal", smg_item.energy.tier, 2)

	# Fitting a real overtier folds it into .weapon and .weapon becomes a copy.
	smg_item.fit_energy(_cell(4))
	_eq_int("after fitting a T4 cell, delta reads 2", smg_item.energy_delta(), 2)
	_bool("the built copy now differs from the catalogue resource",
		smg_item.weapon != smg_item.base_weapon, true)
	_bool("stripping the cell leaves the gun unable to fire (energy null)",
		smg_item.strip_energy() != null and smg_item.energy == null, true)
	_bool("and rebuilds back to the unmodified catalogue resource",
		smg_item.weapon == smg_item.base_weapon, true)


# --- wire round-trip --------------------------------------------------------------


func _check_wire_round_trip() -> void:
	print("\n-- Item.to_wire()/from_wire() --")
	var item := Item.from_weapon(load("res://resources/weapons/assault_rifle.tres"))
	item.fit_energy(_cell(5)) # AR base tier 3, T5 = delta 2
	var wire := item.to_wire()
	var back := Item.from_wire(wire)
	_bool("a fitted overtier survives the wire", back.energy != null, true)
	_eq_int("at the right tier", back.energy.tier, 5)
	_eq_int("and the delta comes back the same", back.energy_delta(), 2)
	_eq("and the folded stats come back the same", back.weapon.damage, item.weapon.damage)

	item.strip_energy()
	var stripped_wire := item.to_wire()
	var stripped_back := Item.from_wire(stripped_wire)
	_bool("a stripped (null) cell survives the wire as null, not the free default",
		stripped_back.energy == null, true)


# --- automatics: hard lock --------------------------------------------------------


func _check_overheat_automatic() -> void:
	print("\n-- automatic overheat: hard lock --")
	var weapon: Node = (load("res://scripts/weapon.gd") as GDScript).new()
	var kit := Inventory.new()
	var smg_item := Item.from_weapon(load("res://resources/weapons/smg.tres"))
	# Two tiers over: heats fastest, and the case the brief cares most about.
	smg_item.fit_energy(_cell(4))
	kit.primary = smg_item
	weapon.inventory = kit
	root.add_child(weapon)
	await process_frame

	var data: WeaponData = smg_item.weapon
	var interval := data.get_shot_interval()

	# Same-tier fire never builds heat, full stop - checked first against the
	# stock cell before it is ever swapped for the hot one.
	var cold_item := Item.from_weapon(load("res://resources/weapons/smg.tres"))
	kit.primary = cold_item
	weapon.refresh()
	for i in 40:
		weapon.try_fire(Vector2.ZERO, 0.0, i == 0, true)
		weapon.tick(interval)
	_eq("same-tier fire never builds heat", weapon.get_heat(), 0.0)

	# Back to the overtiered cell, and hold the trigger until it locks.
	kit.primary = smg_item
	weapon.refresh()
	var shots := 0
	var locked := false
	while shots < 200:
		var fired: bool = weapon.try_fire(Vector2.ZERO, 0.0, shots == 0, true)
		if fired:
			shots += 1
		weapon.tick(interval)
		if weapon.is_heat_locked():
			locked = true
			break
	_bool("an SMG two tiers over locks out under sustained fire", locked, true)
	_bool("heat sits at the ceiling the instant it locks", weapon.get_heat() >= 0.999, true)
	# The calibration point the whole curve is built from: a full eight
	# rounds out of an SMG on a T4 cell before it locks - see the header
	# comment on WeaponData.get_heat_per_shot().
	_eq_int("locks after exactly 8 rounds, not fewer and not more", shots, 8)
	_eq("the unlock mark reads a flat 25%, whatever delta bought the lock",
		weapon.get_heat_unlock_threshold(), 0.25, 0.001)
	_bool("heat bleeds off slower while actually locked than it does otherwise",
		data.get_heat_recovery(true) < data.get_heat_recovery(false), true)

	# Held down, a locked automatic refuses every further shot - no dribbling
	# a few more out past the lock.
	var mag_before := smg_item.count
	weapon.try_fire(Vector2.ZERO, 0.0, false, true)
	_eq_int("locked automatic will not fire while held", smg_item.count, mag_before)

	# Let it vent. Heat has to actually fall below the gun's unlock threshold,
	# not just stop climbing, before the trigger works again.
	var vented := false
	for i in 300:
		weapon.tick(0.05)
		if not weapon.is_heat_locked():
			vented = true
			break
	_bool("it unlocks again once it has cooled enough", vented, true)
	_bool("but not all the way to zero - it unlocks with heat still on the bar",
		weapon.get_heat() > 0.0, true)

	var refired: bool = weapon.try_fire(Vector2.ZERO, 0.0, true, true)
	_bool("and can fire again once unlocked", refired, true)

	weapon.queue_free()

	# The second calibration point the whole curve is built from: an AR one
	# tier over its own base - a T4 cell, delta 1 - locks at exactly twenty
	# rounds. See the header comment on WeaponData.get_heat_per_shot().
	var mild: Node = (load("res://scripts/weapon.gd") as GDScript).new()
	var mild_kit := Inventory.new()
	var mild_item := Item.from_weapon(load("res://resources/weapons/assault_rifle.tres"))
	mild_item.fit_energy(_cell(4)) # AR base tier 3, T4 = delta 1
	mild_kit.primary = mild_item
	mild.inventory = mild_kit
	root.add_child(mild)
	await process_frame
	var mild_interval := mild_item.weapon.get_shot_interval()
	var mild_shots := 0
	var mild_locked := false
	while mild_shots < 200:
		var fired: bool = mild.try_fire(Vector2.ZERO, 0.0, mild_shots == 0, true)
		if fired:
			mild_shots += 1
		mild.tick(mild_interval)
		if mild.is_heat_locked():
			mild_locked = true
			break
	_bool("an AR one tier over locks out too, eventually", mild_locked, true)
	_eq_int("locks after exactly 20 rounds, not fewer and not more", mild_shots, 20)
	mild.queue_free()

	# A same-tier-over-base sanity check on a different gun, so the AR/SMG
	# pair above is not the only thing exercising the curve: the escalation
	# from delta 1 to delta 2 has to hold for the SMG too, not just produce
	# the one exact number it was calibrated against.
	var smg1: Node = (load("res://scripts/weapon.gd") as GDScript).new()
	var smg1_kit := Inventory.new()
	var smg1_item := Item.from_weapon(load("res://resources/weapons/smg.tres"))
	smg1_item.fit_energy(_cell(3)) # SMG base tier 2, T3 = delta 1
	smg1_kit.primary = smg1_item
	smg1.inventory = smg1_kit
	root.add_child(smg1)
	await process_frame
	var smg1_interval := smg1_item.weapon.get_shot_interval()
	var smg1_shots := 0
	while smg1_shots < 200:
		var fired: bool = smg1.try_fire(Vector2.ZERO, 0.0, smg1_shots == 0, true)
		if fired:
			smg1_shots += 1
		smg1.tick(smg1_interval)
		if smg1.is_heat_locked():
			break
	_bool("delta 1 still locks later than delta 2 does on the same gun",
		smg1_shots > 8, true)
	print("  (SMG locks after %d rounds at delta 1, against 8 at delta 2)" % smg1_shots)
	smg1.queue_free()


# --- semi-autos: stretched cooldown -----------------------------------------------


func _check_overheat_semiauto() -> void:
	print("\n-- semi-auto overheat: stretched cooldown --")
	var weapon: Node = (load("res://scripts/weapon.gd") as GDScript).new()
	var kit := Inventory.new()
	var sniper_item := Item.from_weapon(load("res://resources/weapons/sniper.tres"))
	sniper_item.fit_energy(_cell(6)) # sniper base tier 4, T6 = delta 2
	kit.primary = sniper_item
	weapon.inventory = kit
	root.add_child(weapon)
	await process_frame

	var data: WeaponData = sniper_item.weapon
	var base_interval := data.get_shot_interval()

	# A shot fired cold - heat at zero - sets an ordinary cooldown. This is
	# the "fires at its own natural rhythm" case and it must not be stretched,
	# and nowhere near the ceiling this shot must not lock it either.
	weapon.try_fire(Vector2.ZERO, 0.0, true, false)
	_bool("a cold shot does not lock a semi-auto out", weapon.is_heat_locked(), false)

	# Semi-autos read the same flat unlock mark automatics do now - see the
	# header comment on Weapon.heat_locked for why that used to be
	# automatic-only and stopped being.
	_eq("a semi-auto reads the same 25% unlock mark an automatic does",
		weapon.get_heat_unlock_threshold(), 0.25, 0.001)

	# Let the ordinary per-shot cooldown from the first shot lapse so
	# try_fire's own _cooldown > 0.0 gate is not what is blocking the next
	# shot - done *before* heat is forced, since tick() is also what decays
	# heat and a big jump here would undo the next line.
	weapon.tick(base_interval + 0.01)

	# Forced short of the ceiling on purpose, not to it - a shot that fills
	# the bar now locks the gun (see the maxed weapon below), and this part
	# of the test is only about the stretch a shot short of that pays. Set
	# and fired in the same instant, so no further tick() has a chance to
	# bleed it off before try_fire reads it.
	weapon.heat = 0.4
	var stretch_cap: float = data.get_heat_stretch_cap(sniper_item.energy_delta())
	var expected := base_interval * (1.0 + 0.4 * stretch_cap)
	# Trigger released and pressed again - semi-auto needs a fresh edge.
	weapon.try_fire(Vector2.ZERO, 0.0, false, false)
	weapon.try_fire(Vector2.ZERO, 0.0, true, false)
	_eq("a hot-but-not-maxed shot stretches the chamber cooldown proportionally",
		weapon._cooldown, expected, 0.05)
	_bool("that stretch is a real tax: noticeably longer than the base interval",
		weapon._cooldown > base_interval * 1.3, true)
	_bool("not yet hot enough to actually lock", weapon.is_heat_locked(), false)

	# The invariant that still holds below the ceiling: the instant a
	# not-yet-maxed shot's stretched cooldown ends, the gun can fire -
	# nothing else gates it.
	weapon.tick(weapon._cooldown + 0.001)
	var fired_after_stretch: bool = weapon.try_fire(Vector2.ZERO, 0.0, true, false)
	_bool("fires the instant a sub-ceiling stretch finishes, no further gate",
		fired_after_stretch, true)

	weapon.queue_free()

	# The calibration point for the semi-auto side: a sniper two tiers over,
	# fired at its own bare cooldown with no real pause, is fully overheated
	# by the second shot - not gradually, the way an automatic's magazine
	# lets it climb. A fresh weapon, so the forced heat above cannot bleed
	# into this.
	var quickscope: Node = (load("res://scripts/weapon.gd") as GDScript).new()
	var qs_kit := Inventory.new()
	var qs_item := Item.from_weapon(load("res://resources/weapons/sniper.tres"))
	qs_item.fit_energy(_cell(6))
	qs_kit.primary = qs_item
	quickscope.inventory = qs_kit
	root.add_child(quickscope)
	await process_frame
	_tick_in_steps(quickscope, 1.0)
	quickscope.try_fire(Vector2.ZERO, 0.0, true, false)
	_tick_in_steps(quickscope, quickscope._cooldown + 0.001)
	quickscope.try_fire(Vector2.ZERO, 0.0, false, false)
	quickscope.try_fire(Vector2.ZERO, 0.0, true, false)
	_eq("two consecutive shots overheats a sniper two tiers over completely",
		quickscope.get_heat(), 1.0, 0.001)
	# The invariant that changed: a shot that actually fills the bar locks a
	# semi-auto out exactly the way it locks an automatic out - "always
	# fireable the instant cooldown ends" now holds everywhere except the
	# very top of the bar, which is the one place it was supposed to stop
	# holding.
	_bool("and that second shot locks it out, the same as an automatic",
		quickscope.is_heat_locked(), true)
	var mag_before: int = qs_item.count
	_tick_in_steps(quickscope, quickscope._cooldown + 0.001)
	quickscope.try_fire(Vector2.ZERO, 0.0, false, false)
	quickscope.try_fire(Vector2.ZERO, 0.0, true, false)
	_eq_int("and stays refused past its own cooldown while still locked",
		qs_item.count, mag_before)
	quickscope.queue_free()

	# The split the brief actually asked for: rapid-fire at the gun's own bare
	# cooldown - the "quickscoping" case - has to build heat, and a genuine
	# pause between shots has to bleed it back off. Two fresh weapons, so
	# neither history contaminates the other.
	var rapid: Node = (load("res://scripts/weapon.gd") as GDScript).new()
	var rapid_kit := Inventory.new()
	var rapid_item := Item.from_weapon(load("res://resources/weapons/sniper.tres"))
	rapid_item.fit_energy(_cell(6))
	rapid_kit.primary = rapid_item
	rapid.inventory = rapid_kit
	root.add_child(rapid)
	await process_frame
	# A fresh Weapon starts mid-draw - _equip_left is nonzero the instant it
	# is refreshed - and try_fire() refuses everything until that clears.
	# The earlier tests in this file never noticed because they either loop
	# tick()+try_fire() together until real progress happens (the automatic
	# lock test) or their first real shot lands after a tick() big enough to
	# clear it as a side effect - this one does neither, so it needs the wait
	# stated outright.
	_tick_in_steps(rapid, 1.0)
	for i in 6:
		rapid.try_fire(Vector2.ZERO, 0.0, false, false)
		rapid.try_fire(Vector2.ZERO, 0.0, true, false)
		# Sub-stepped at a physics-frame grain (1/60s) rather than jumped in
		# one lump sum to the end of the cooldown. tick()'s decay check reads
		# _since_shot only at the end of whatever delta it was handed, so one
		# giant tick() overshoots the recovery-delay threshold by the entire
		# remainder of that jump instead of by a fraction of a frame - real
		# gameplay never does that, and a test that does reports decay that
		# could never actually happen.
		_tick_in_steps(rapid, rapid._cooldown + 0.001)
	_bool("firing back-to-back at the gun's own bare cooldown builds real heat",
		rapid.get_heat() > 0.05, true)
	rapid.queue_free()

	var spaced: Node = (load("res://scripts/weapon.gd") as GDScript).new()
	var spaced_kit := Inventory.new()
	var spaced_item := Item.from_weapon(load("res://resources/weapons/sniper.tres"))
	spaced_item.fit_energy(_cell(6))
	spaced_kit.primary = spaced_item
	spaced.inventory = spaced_kit
	root.add_child(spaced)
	await process_frame
	_tick_in_steps(spaced, 1.0)
	for i in 6:
		spaced.try_fire(Vector2.ZERO, 0.0, false, false)
		spaced.try_fire(Vector2.ZERO, 0.0, true, false)
		_tick_in_steps(spaced, spaced._cooldown + 0.001)
		# A real pause past the gun's own rhythm - taking the time to
		# reacquire a target rather than clicking again the instant it is
		# legal to.
		_tick_in_steps(spaced, 4.0)
	_eq("spaced, deliberate shots at the gun's own rhythm barely touch the bar",
		spaced.get_heat(), 0.0, 0.02)
	spaced.queue_free()


# --- the bullet itself looks different when it is hot -------------------------


## Bullet.gd reaches Net too (through Net.deals_damage() in spawn()), so it is
## named the same careful way Weapon is - loaded and instantiated, never typed.
func _check_hot_bullet_visual() -> void:
	print("\n-- a hot round looks like a different gun firing it --")
	var ar: WeaponData = load("res://resources/weapons/assault_rifle.tres")
	var bullet_script := load("res://scripts/bullet.gd") as GDScript

	var cold: Node = bullet_script.spawn(self, Vector2.ZERO, 0.0, ar,
		Layers.PLAYER_SHOT, 1.0, 0, 1.0, 0.0)
	var hot: Node = bullet_script.spawn(self, Vector2.ZERO, 0.0, ar,
		Layers.PLAYER_SHOT, 1.0, 0, 1.0, 0.95)
	await process_frame

	var cold_visual: Node2D = cold.get_node("Visual")
	var hot_visual: Node2D = hot.get_node("Visual")
	var cold_color: Color = cold_visual.color
	var hot_color: Color = hot_visual.color

	_bool("a cold round keeps the gun's own bullet_color", cold_color.is_equal_approx(ar.bullet_color), true)
	_bool("a nearly-maxed-out round has moved well off it",
		_color_dist(cold_color, hot_color) > 0.5, true)
	_bool("and moved toward OVERHEAT_COLOR specifically, not just anywhere",
		_color_dist(hot_color, bullet_script.OVERHEAT_COLOR) <
			_color_dist(cold_color, bullet_script.OVERHEAT_COLOR), true)

	var cold_width: float = (cold_visual.polygon[2] as Vector2).y - (cold_visual.polygon[1] as Vector2).y
	var hot_width: float = (hot_visual.polygon[2] as Vector2).y - (hot_visual.polygon[1] as Vector2).y
	_bool("a hot tracer is visibly thicker than a cold one", hot_width > cold_width * 1.5, true)

	cold.queue_free()
	hot.queue_free()


## MuzzleFlash reaches Bullet (for OVERHEAT_COLOR) which reaches Net, so it
## gets the same loaded-not-typed treatment.
func _check_muzzle_flash_easing() -> void:
	print("\n-- the muzzle flash grows a lot near the top, not evenly --")
	var ar: WeaponData = load("res://resources/weapons/assault_rifle.tres")
	var flash_script := load("res://scripts/muzzle_flash.gd") as GDScript

	var cold: Node = flash_script.new()
	cold.setup(ar, 0.0)
	var half: Node = flash_script.new()
	half.setup(ar, 0.5)
	var full: Node = flash_script.new()
	full.setup(ar, 1.0)

	var r0: float = cold._radius
	var r_half: float = half._radius
	var r_full: float = full._radius
	var half_growth := r_half - r0
	var full_growth := r_full - r0

	_bool("half heat is only a modest step up from cold", half_growth < full_growth * 0.4, true)
	_bool("the last stretch to full heat grows more than the first half did",
		(r_full - r_half) > half_growth, true)

	cold.free()
	half.free()
	full.free()


# --- helpers ------------------------------------------------------------------


## Advances a weapon node's clock in ~1/60s slices instead of one lump call,
## so a threshold tick() checks against - like the heat recovery delay - is
## crossed the way a real physics frame crosses it, by a fraction of a
## frame, not by however much time this test happens to be jumping.
func _tick_in_steps(weapon: Node, total: float) -> void:
	var step := 1.0 / 60.0
	var left := total
	while left > 0.0:
		var this_step := minf(step, left)
		weapon.tick(this_step)
		left -= this_step


## Color has no distance_to() in this Godot version.
func _color_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _cell(tier: int) -> EnergyCellData:
	return load("res://resources/energy/tier%d_cell.tres" % tier) as EnergyCellData


func _eq(what: String, got: float, want: float, tolerance := 0.001) -> void:
	if absf(got - want) <= tolerance:
		print("  ok   %-58s %.3f" % [what, got])
	else:
		_failures.append("%s: got %.4f, wanted %.4f" % [what, got, want])
		print("  FAIL %-58s %.3f (wanted %.3f)" % [what, got, want])


func _eq_int(what: String, got: int, want: int) -> void:
	if got == want:
		print("  ok   %-58s %d" % [what, got])
	else:
		_failures.append("%s: got %d, wanted %d" % [what, got, want])
		print("  FAIL %-58s %d (wanted %d)" % [what, got, want])


func _bool(what: String, got: bool, want: bool) -> void:
	if got == want:
		print("  ok   %-58s %s" % [what, got])
	else:
		_failures.append("%s: got %s, wanted %s" % [what, got, want])
		print("  FAIL %-58s %s (wanted %s)" % [what, got, want])
