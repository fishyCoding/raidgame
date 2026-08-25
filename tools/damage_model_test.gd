extends SceneTree

## Checks the damage model against the numbers it was specified with.
##
## Runs the real Damage.resolve against real armour resources rather than
## repeating the arithmetic, so a change to the falloff curve, the absorption
## curve or a weapon resource shows up here as a failed count instead of as a
## fight that quietly feels wrong.
##
## The benchmark, and the numbers every line below is defending:
##
##   AR, 620 rpm, medium vest -> 26 a round, 4 rounds, 290 ms
##   AR, medium helmet, head  -> 51 a round, 2 rounds
##   AR, nothing on, body     -> 51 a round, 2 rounds
##   AR, half damage at       -> 480 px, ten player heights
##
## Loaded rather than named: `Damage` reaches Net, and naming it from a --script
## tool compiles it before the autoloads exist and breaks the class for the whole
## process. See the note in tools/, and headless-test-must-unpause.

const HP := 100.0
const BODY_HEIGHT := 48.0

var _failures: Array[String] = []


func _init() -> void:
	# One frame first, and the whole test depends on it. Autoloads are not
	# registered as script globals when a --script tool starts, so damage.gd -
	# which names Net - fails to compile with "Identifier not found: Net" and
	# load() hands back a script you cannot call. After a single frame Net,
	# PlayerInput and Audio are on the root and it compiles clean.
	await process_frame

	# An instance, because a static call straight on the GDScript ref is not
	# a thing GDScript will do - statics are reachable through an instance.
	var damage: RefCounted = (load("res://scripts/damage.gd") as GDScript).new()
	var ar: WeaponData = load("res://resources/weapons/assault_rifle.tres")

	# --- the benchmark ------------------------------------------------------
	_eq("AR rpm", ar.rounds_per_minute, 620.0)
	_eq("AR raw damage", ar.damage, 51.0)
	_eq("AR half-damage range", ar.get_half_damage_range(), 480.0)
	_eq("AR range in player heights", ar.get_half_damage_range() / BODY_HEIGHT, 10.0)

	var first_body := _first_hit(damage, ar.damage, _kit("medium_vest", 1), false)
	_eq("AR first round through a medium vest", first_body, 26.0, 0.1)
	var first_head := _first_hit(damage, ar.damage, _kit("medium_helmet", 0), true)
	_eq("AR headshot through a medium helmet", first_head, 51.0, 0.1)

	var armored := _rounds_to_kill(damage, ar, "medium_vest", false)
	_eq("AR rounds to kill, medium vest", float(armored), 4.0)
	_eq("AR time to kill, medium vest (ms)",
		float(armored - 1) * ar.get_shot_interval() * 1000.0, 290.0, 1.0)

	var bare := _rounds_to_kill(damage, ar, "", false)
	_eq("AR rounds to kill, no vest", float(bare), 2.0)

	var heads := _rounds_to_kill(damage, ar, "medium_helmet", true)
	_eq("AR headshots to kill, medium helmet", float(heads), 2.0)

	# --- the armour ladder --------------------------------------------------
	#
	# The medium vest above is the benchmark, but it is not what anyone is
	# actually wearing when they land: the deploy loadout is the light one. Four
	# rounds has to be true of the vest you are issued, not only of the vest you
	# might buy, or the number is a spec nobody plays against.
	#
	# The rest of the ladder is pinned for the same reason it exists. Every tier
	# has to buy something you can count - a round, or a head hit - or the shop
	# is selling a number that does not change the fight.
	_eq("AR rounds to kill, light vest (the deploy loadout)",
		float(_rounds_to_kill(damage, ar, "light_vest", false)), 4.0)
	_eq("AR rounds to kill, heavy vest",
		float(_rounds_to_kill(damage, ar, "heavy_vest", false)), 5.0)
	_eq("AR headshots to kill, light helmet",
		float(_rounds_to_kill(damage, ar, "light_helmet", true)), 2.0)
	_eq("AR headshots to kill, heavy helmet",
		float(_rounds_to_kill(damage, ar, "heavy_helmet", true)), 3.0)

	# Armour has to survive the fight it is priced for. It used to be charged
	# the whole incoming round rather than the part it stopped, which left a
	# medium vest scrap after three rifle rounds - so the four-round kill above
	# was only ever true of the first magazine, and nothing on screen said so.
	var vest: Inventory = _kit("medium_vest", 1)
	var worn: Item = vest.get_worn(Inventory.Wear.VEST)
	for i in 4:
		damage.resolve(ar.damage, Vector2.ZERO, Vector2.ZERO, BODY_HEIGHT, vest)
	if not worn.armor.is_sound(worn.durability):
		_failures.append("a medium vest is scrap after the four rounds it is "
			+ "meant to survive (%.0f of %.0f left)"
			% [worn.durability, worn.armor.max_durability])
	else:
		print("  ok   %-42s %.0f/%.0f" % ["medium vest left after four rounds",
			worn.durability, worn.armor.max_durability])

	# --- the benchmark has to actually be the benchmark ---------------------
	#
	# Worth pinning because the obvious tuning gets this backwards. Armour wears
	# out as it absorbs, so a gun that lands fewer, bigger rounds strips a vest
	# faster and its later rounds land nearly whole - which flattered the LMG and
	# the SMG enough that both killed a plated man quicker than the AR did. The
	# benchmark being outrun by the guns it is meant to anchor is how a model
	# stops meaning anything.
	var ar_ttk := float(armored - 1) * ar.get_shot_interval()
	for other_name in ["smg", "lmg"]:
		var other: WeaponData = load("res://resources/weapons/%s.tres" % other_name)
		var other_rounds := _rounds_to_kill(damage, other, "medium_vest", false)
		var other_ttk := float(other_rounds - 1) * other.get_shot_interval()
		if other_ttk <= ar_ttk:
			_failures.append("%s kills a plated man in %.0f ms, at or under the AR's %.0f"
				% [other_name, other_ttk * 1000.0, ar_ttk * 1000.0])

	# --- every other gun measured the same way ------------------------------
	print("")
	print("%-14s %5s %6s %8s | %-18s | %s" % [
		"gun", "rpm", "dmg", "range", "medium vest", "nothing on"])
	for name in ["assault_rifle", "smg", "pistol", "shotgun", "lmg", "sniper",
			"enemy_rifle"]:
		var gun: WeaponData = load("res://resources/weapons/%s.tres" % name)
		var vested := _rounds_to_kill(damage, gun, "medium_vest", false)
		var naked := _rounds_to_kill(damage, gun, "", false)
		print("%-14s %5d %6.0f %7.0fpx | %2d rounds %8.0f ms | %2d rounds %8.0f ms" % [
			name, gun.rounds_per_minute, gun.damage, gun.get_half_damage_range(),
			vested, float(vested - 1) * gun.get_shot_interval() * 1000.0,
			naked, float(naked - 1) * gun.get_shot_interval() * 1000.0])
		# The floor the whole model stands on.
		if not gun.automatic and gun.pellets == 1 and name == "sniper":
			continue
		if naked < 2 and name != "shotgun":
			_failures.append("%s kills in one body shot with no vest on" % name)

	print("")
	if _failures.is_empty():
		print("OK - damage model matches spec")
	else:
		for line in _failures:
			print("FAIL - %s" % line)
		print("FAILED %d check(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


## One vest or helmet, worn, at full durability.
func _kit(armor_name: String, slot: int) -> Inventory:
	var kit := Inventory.new()
	if armor_name.is_empty():
		return kit
	var data: ArmorData = load("res://resources/armor/%s.tres" % armor_name)
	kit.set_worn(slot as Inventory.Wear, Item.from_armor(data))
	return kit


func _hit_point(centre: Vector2, head: bool) -> Vector2:
	# Anywhere in the top 26% counts as head; the centre of the box never does.
	return Vector2(centre.x, centre.y - BODY_HEIGHT * 0.5 + 2.0) if head else centre


func _first_hit(damage: RefCounted, amount: float, kit: Inventory, head: bool) -> float:
	var centre := Vector2.ZERO
	var result = damage.resolve(amount, _hit_point(centre, head), centre, BODY_HEIGHT, kit)
	return result.amount


## Fires into a fresh body until it drops, spending armour as it goes - so this
## counts what actually happens rather than what the first round suggests.
func _rounds_to_kill(damage: RefCounted, gun: WeaponData, armor_name: String,
		head: bool) -> int:
	var kit := _kit(armor_name, 0 if head else 1)
	var centre := Vector2.ZERO
	var at := _hit_point(centre, head)
	var health := HP
	var rounds := 0
	while health > 0.0 and rounds < 200:
		rounds += 1
		for pellet in gun.pellets:
			var result = damage.resolve(gun.damage, at, centre, BODY_HEIGHT, kit)
			health -= result.amount
	return rounds


func _eq(what: String, got: float, want: float, tolerance := 0.001) -> void:
	if absf(got - want) <= tolerance:
		print("  ok   %-42s %.2f" % [what, got])
	else:
		_failures.append("%s: got %.3f, wanted %.3f" % [what, got, want])
		print("  FAIL %-42s %.2f (wanted %.2f)" % [what, got, want])
