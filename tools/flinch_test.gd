extends SceneTree

## Checks that being shot widens your own cone, and that aiming does not erase it.
##
## The second half is the one worth a test. Every other term in get_spread is
## multiplied by the weapon's ads_spread_scale, which is 0.05 on the sniper - so
## the obvious implementation, adding flinch to `bloom`, would have meant a
## scoped rifle flinched by a twentieth of what everyone else did and the man
## with the most reach in the game was the one hardest to disturb. Flinch is
## added after the sights instead, and this pins that.
##
## Loaded rather than named, for the reason spelled out in tools/glint_test.gd.

var _failures: Array[String] = []


func _init() -> void:
	await process_frame
	var script: GDScript = load("res://scripts/weapon.gd")
	var gun: Node = script.new()
	gun.data = load("res://resources/weapons/assault_rifle.tres")
	var sniper_gun: Node = script.new()
	sniper_gun.data = load("res://resources/weapons/sniper.tres")

	var rifle_round := 51.0
	var expected: float = gun.FLINCH_DEGREES_PER_100 * rifle_round * 0.01

	var before: float = gun.get_spread()
	gun.take_flinch(rifle_round)
	var after: float = gun.get_spread()
	_eq("a rifle round widens the cone, degrees",
		rad_to_deg(after - before), expected, 0.001)

	# Aimed, it is still most of the way there. 0.65 of it, not the 0.12 an
	# assault rifle's sights do to everything else in the cone.
	gun.focus = 1.0
	var aimed_before: float = gun.get_spread()
	gun.flinch = 0.0
	var aimed_clean: float = gun.get_spread()
	_eq("and survives aiming, degrees",
		rad_to_deg(aimed_before - aimed_clean), expected * gun.FLINCH_AIM_SCALE, 0.001)

	# The gun with the best glass in the game flinches exactly as hard as the
	# rifle does, which is the whole reason the term is where it is.
	sniper_gun.focus = 1.0
	var scoped_clean: float = sniper_gun.get_spread()
	sniper_gun.take_flinch(rifle_round)
	_eq("a scoped sniper flinches the same, degrees",
		rad_to_deg(sniper_gun.get_spread() - scoped_clean),
		expected * gun.FLINCH_AIM_SCALE, 0.001)

	# Directly after, and not for long: a rifle round's worth is gone inside a
	# fifth of a second.
	gun.focus = 0.0
	gun.take_flinch(rifle_round)
	gun.tick(expected / gun.FLINCH_RECOVERY_DEGREES)
	_eq("and washes out on its own clock", rad_to_deg(gun.flinch), 0.0, 0.001)

	# A burst that catches you cannot stack past the ceiling.
	gun.take_flinch(10000.0)
	_eq("capped, degrees", rad_to_deg(gun.flinch), gun.FLINCH_MAX_DEGREES, 0.001)

	gun.free()
	sniper_gun.free()

	if _failures.is_empty():
		print("OK - being shot costs you the shot")
	else:
		for line in _failures:
			print("FAIL - %s" % line)
		print("FAILED %d check(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _eq(what: String, got: float, want: float, tolerance := 0.001) -> void:
	if absf(got - want) <= tolerance:
		print("  ok   %-44s %.3f" % [what, got])
	else:
		_failures.append("%s: got %.4f, wanted %.4f" % [what, got, want])
		print("  FAIL %-44s %.3f (wanted %.3f)" % [what, got, want])
