extends SceneTree

## The gunsmith: what a part does to a gun, what it costs, and that it survives
## the trip into the raid.
##
##   godot --headless --path . --script res://tools/gunsmith_test.gd
##
## No screen involved. What is asserted here is the arithmetic and the plumbing -
## the drawing is checked by looking at it, in tools/gunsmith_shot.gd.

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var smith: Object = (load("res://scripts/gunsmith.gd") as GDScript).new()
	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var ar: Resource = load("res://resources/weapons/assault_rifle.tres")
	var pistol: Resource = load("res://resources/weapons/pistol.tres")

	# --- what fits ------------------------------------------------------------
	var stock: Resource = load("res://resources/attachments/heavy_stock.tres")
	var can: Resource = load("res://resources/attachments/suppressor.tres")
	var drum: Resource = load("res://resources/attachments/drum_mag.tres")
	_say("stock on a pistol: %s   can on a pistol: %s" % [
		stock.fits(pistol), can.fits(pistol)])
	_check(not stock.fits(pistol), "a pistol does not take a stock")
	_check(can.fits(pistol), "but it does take a suppressor")
	_check(not drum.fits(load("res://resources/weapons/shotgun.tres")),
		"and a 5.56 drum does not go in a shotgun")

	# --- the arithmetic -------------------------------------------------------
	var gun: Object = maker.from_weapon(ar)
	var base_mag: int = ar.mag_size
	var base_recoil: float = ar.recoil
	gun.fit(load("res://resources/attachments/extended_mag.tres"))
	gun.fit(load("res://resources/attachments/compensator.tres"))
	_say("AR with an extended mag and a comp: %d rnd (was %d), recoil %.0f (was %.0f)" % [
		gun.weapon.mag_size, base_mag, gun.weapon.recoil, base_recoil])
	_check(gun.weapon.mag_size == roundi(base_mag * 1.4), "the mag is half again as big")
	_check(is_equal_approx(gun.weapon.recoil, base_recoil - 12.0), "the comp takes 12 off the climb")
	_check(gun.weapon.handling < ar.handling, "and both of them cost handling")
	_check(is_equal_approx(ar.mag_size, base_mag) and is_equal_approx(ar.recoil, base_recoil),
		"the gun on the shelf is untouched - the workshop works on a copy")
	_check(gun.count <= gun.weapon.mag_size, "and the rounds in it still fit")

	# --- taking one off is not subtracting ------------------------------------
	var was: Object = gun.strip(1)
	_say("comp off: recoil %.0f, still %d rnd" % [gun.weapon.recoil, gun.weapon.mag_size])
	_check(was != null and is_equal_approx(gun.weapon.recoil, base_recoil),
		"taking the comp off puts the climb back exactly")
	_check(gun.weapon.mag_size == roundi(base_mag * 1.4),
		"and leaves the magazine that is still on it alone")

	# --- the trades are real --------------------------------------------------
	var quiet: Object = maker.from_weapon(ar)
	quiet.fit(can)
	_say("suppressed: damage %.1f (was %.1f), suppressed=%s, handling %.0f" % [
		quiet.weapon.damage, ar.damage, quiet.weapon.suppressed, quiet.weapon.handling])
	_check(quiet.weapon.suppressed, "a can silences the gun")
	_check(quiet.weapon.damage < ar.damage, "and costs damage doing it")
	_check(quiet.weapon.falloff_end < ar.falloff_end, "and some of the reach")

	var scoped: Object = maker.from_weapon(ar)
	scoped.fit(load("res://resources/attachments/marksman_4x.tres"))
	_check(scoped.weapon.ads_zoom > ar.ads_zoom, "a 4x magnifies")
	_check(scoped.weapon.scope_glint, "and throws a glint back, which is its price")
	_check(scoped.weapon.ads_speed_scale < ar.ads_speed_scale, "and is slower onto a target")

	var fat: Object = maker.from_weapon(ar)
	fat.fit(drum)
	_say("drum: %d rnd, %dx%d cells (was %dx%d)" % [fat.weapon.mag_size,
		fat.size.x, fat.size.y, ar.grid_size.x, ar.grid_size.y])
	_check(fat.weapon.mag_size == base_mag * 2, "a drum doubles the magazine")
	_check(fat.size.x == ar.grid_size.x + 1, "and takes another cell in the bag")

	# --- one part per slot ----------------------------------------------------
	var swapped: Object = maker.from_weapon(ar)
	swapped.fit(load("res://resources/attachments/compensator.tres"))
	var kicked: Object = swapped.fit(load("res://resources/attachments/muzzle_brake.tres"))
	_check(swapped.parts.size() == 1, "a second muzzle device replaces the first")
	_check(kicked != null and kicked.short_name == "COMP", "and the old one comes back to be refunded")

	# --- and it survives the wire ---------------------------------------------
	var built: Object = maker.from_weapon(ar)
	built.fit(can)
	built.fit(drum)
	built.count = 12
	var wire: Dictionary = built.to_wire()
	var there: Object = maker.from_wire(wire)
	_say("over the wire: %s -> %s" % [built.label(), there.label()])
	_check(there != null and there.parts.size() == 2, "both parts travel with the gun")
	_check(there.weapon.suppressed and there.weapon.mag_size == built.weapon.mag_size,
		"and the far end builds the same gun")
	_check(there.count == 12, "with the same rounds in it")
	_check(there.is_gun(ar), "and it is still recognisably an assault rifle")

	# --- what it costs --------------------------------------------------------
	_say("parts on that gun: %d credits" % smith.parts_value(built.parts))
	_check(smith.parts_value(built.parts) == can.price + drum.price,
		"a built gun is worth the sum of what went into it")
	_check(not smith.effect_lines(can).is_empty(), "and every part can say what it does")

	print("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _say(line: String) -> void:
	print("-- %s" % line)


func _check(pass_: bool, says: String) -> void:
	print("   %s  %s" % ["ok  " if pass_ else "FAIL", says])
	if not pass_:
		_ok = false
