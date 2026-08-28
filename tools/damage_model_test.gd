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
##   AR, 620 rpm, medium vest -> 30 a round, 3 rounds, 194 ms
##   AR, medium helmet, head  -> 58 a round, 2 rounds
##   AR, nothing on, body     -> 58 a round, 2 rounds
##   AR, at the falloff floor -> 38 a round, from 1320 px out
##   AR, four rounds          -> a Kevlar vest at nothing
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
	_eq("AR raw damage", ar.damage, 58.0)
	# The range half of the benchmark, restated. It used to be "half damage at
	# 480 px, ten player heights", which described a rifle that had given up
	# most of what it did by twenty of them - so every fight worth having was
	# fought inside the first third of the curve and the rest of the map was
	# decoration. The window is out at 520-1320 now and the floor is 0.65, which
	# is the same statement made about a gun that still works at the far end of
	# a room it can see across.
	_eq("AR damage at the falloff floor", ar.get_damage_at(9999.0), 37.70, 0.01)
	_eq("AR floor reached at", ar.falloff_end, 1320.0)
	_eq("AR floor in player heights", ar.falloff_end / BODY_HEIGHT, 27.5)
	# Nothing is allowed to keep more of itself at range than the gun built for
	# range, which is the one ordering in the falloff table that is not a taste
	# call: a scope you can be seen through has to buy something a rifle cannot.
	for closer in ["assault_rifle", "smg", "lmg", "pistol", "shotgun"]:
		var other: WeaponData = load("res://resources/weapons/%s.tres" % closer)
		var sniper_floor: float = (load("res://resources/weapons/sniper.tres")
			as WeaponData).min_damage_factor
		if other.min_damage_factor >= sniper_floor:
			_failures.append("%s keeps as much of itself at range as the sniper does"
				% closer)

	var first_body := _first_hit(damage, ar.damage, _kit("medium_vest", 1), false)
	_eq("AR first round through a medium vest", first_body, 29.58, 0.1)
	var first_head := _first_hit(damage, ar.damage, _kit("medium_helmet", 0), true)
	_eq("AR headshot through a medium helmet", first_head, 58.0, 0.1)

	var armored := _rounds_to_kill(damage, ar, "medium_vest", false)
	_eq("AR rounds to kill, medium vest", float(armored), 3.0)
	_eq("AR time to kill, medium vest (ms)",
		float(armored - 1) * ar.get_shot_interval() * 1000.0, 194.0, 1.0)

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
		float(_rounds_to_kill(damage, ar, "light_vest", false)), 3.0)
	_eq("AR rounds to kill, heavy vest",
		float(_rounds_to_kill(damage, ar, "heavy_vest", false)), 4.0)
	_eq("AR headshots to kill, light helmet",
		float(_rounds_to_kill(damage, ar, "light_helmet", true)), 2.0)
	_eq("AR headshots to kill, heavy helmet",
		float(_rounds_to_kill(damage, ar, "heavy_helmet", true)), 2.0)

	# --- piercing, which is the only thing that beats a plate -----------------
	#
	# Protection is a fraction, so a plate takes the same *proportion* off a big
	# round as off a small one and no amount of damage on the sheet ever gets you
	# through it faster. That is the whole reason the shotgun felt useless
	# against armour and the reason raising its damage would not have fixed it.
	# Piercing thins the plate instead, and it is the round that carries it.
	var slug := load("res://resources/weapons/slug_shotgun.tres") as WeaponData
	var plate := load("res://resources/armor/heavy_vest.tres") as ArmorData
	var full := plate.max_durability
	print("\n-- a slug against a plate carrier --")
	_eq("plain round of the slug's size, through a plate",
		slug.damage - plate.absorbed(slug.damage, full), 33.44, 0.1)
	_eq("the same round as a slug",
		slug.damage - plate.absorbed(slug.damage, full, slug.armor_pierce),
		67.27, 0.1)
	_eq("and untouched with no plate in the way", slug.damage, 88.0)
	# Two body shots whatever they are wearing is the gun's whole identity, and
	# it is the number worth pinning: the plate changes what it costs you to get
	# there, not whether you get there.
	_eq("slug body shots to kill through a plate",
		float(_rounds_to_kill(damage, slug, "heavy_vest", false)), 2.0)
	_eq("slug body shots to kill with no plate",
		float(_rounds_to_kill(damage, slug, "", false)), 2.0)
	# And nothing that was here before it existed moved. Piercing defaults to
	# zero, so an ordinary round meets the plate it always met.
	_eq("the rifle is untouched by any of this",
		ar.armor_pierce, 0.0)

	# --- the sniper: two to the body, one to the head -------------------------
	#
	# A body shot used to be 205 against a hundred health, so the gun answered
	# every question by itself and the vest slot had nothing to say about the
	# one round it most needed to. It is 95 now, which is under a hundred on
	# purpose: nothing this gun does to a torso ends a fight on its own, whether
	# you are plated or standing there in a shirt.
	#
	# That alone would have made the head a joke, because a doubled 95 does not
	# get through a Combat Helmet - 190 with 65% taken off is 66, and the most
	# expensive helmet in the shop would have made you immune to the sniper
	# entirely. So the round pierces. 0.4 thins every plate it meets by that
	# much, which is what a .338 is *for* and is the same mechanism the slug
	# already uses; it is what buys the headshot back without putting a single
	# point back on the body shot. Both facts below fall out of the pair, and
	# neither survives changing one without the other.
	var sniper := load("res://resources/weapons/sniper.tres") as WeaponData
	print("
-- the sniper against the armour ladder --")
	_eq("sniper body shots with nothing on",
		float(_rounds_to_kill(damage, sniper, "", false)), 2.0)
	for vest_name in ["light_vest", "medium_vest", "heavy_vest"]:
		_eq("sniper body shots through a %s" % vest_name,
			float(_rounds_to_kill(damage, sniper, vest_name, false)), 2.0)
	for helmet_name in ["light_helmet", "medium_helmet", "heavy_helmet"]:
		_eq("sniper headshots through a %s" % helmet_name,
			float(_rounds_to_kill(damage, sniper, helmet_name, true)), 1.0)
	# The two walls, stated as the numbers rather than as the counts, so a
	# failure says which way it went. A torso has to survive the round and a
	# helmeted head has not to.
	_eq("sniper into a bare torso", _first_hit(damage, sniper.damage, _kit("", 1), false),
		95.0, 0.1)
	_eq("sniper headshot through a fresh Combat Helmet",
		_first_hit_pierced(damage, sniper, _kit("heavy_helmet", 0), true), 115.9, 0.1)

	# The far end of the curve. The floor came up from 0.45 to 0.6 as the damage
	# came down, and it is carrying one thing: an unhelmeted head is a one-shot
	# at any range the bullet will travel. At 0.45 it stopped being one somewhere
	# in the middle distance, which is the shot the gun exists to take.
	_eq("sniper damage at the falloff floor", sniper.get_damage_at(9999.0), 71.25, 0.01)
	var bare_head_far := sniper.get_damage_at(9999.0) * 2.0
	if bare_head_far < HP:
		_failures.append("a bare head survives a sniper round at the far end of "
			+ "the curve (%.0f against %.0f)" % [bare_head_far, HP])
	else:
		print("  ok   %-42s %.0f" % ["bare head at the far end of the curve",
			bare_head_far])

	# What it costs, said out loud because it is a real loss and not an
	# oversight: a guard has 90 health, so a body shot that no longer drops a
	# hundred-health player no longer drops him either past the flat part of the
	# curve. Inside 900 px it still does.
	if sniper.get_damage_at(sniper.falloff_start) < 90.0:
		_failures.append("a sniper body shot no longer kills a guard even at "
			+ "point blank (%.0f against 90)" % sniper.get_damage_at(sniper.falloff_start))
	else:
		print("  ok   %-42s %.0f" % ["guard drops to one body shot inside %.0fpx"
			% sniper.falloff_start, sniper.get_damage_at(sniper.falloff_start)])

	# --- armour is a consumable, and this is the number that says so ---------
	#
	# The reverse of what used to be pinned here, and deliberately. A vest was
	# charged only for the damage it actually stopped, which made it last about
	# five fights: you finished nearly every gunfight with most of the bar left
	# and no reason to think about it again. It is charged for the round as it
	# arrives now, so four rifle rounds take a Kevlar vest from full to nothing -
	# inside a single exchange, which is the point. What you are wearing is
	# something you spend, and repair kits exist because of this line.
	var vest: Inventory = _kit("medium_vest", 1)
	var worn: Item = vest.get_worn(Inventory.Wear.VEST)
	for i in 4:
		damage.resolve(ar.damage, Vector2.ZERO, Vector2.ZERO, BODY_HEIGHT, vest)
	_eq("a Kevlar vest after four rifle rounds", worn.durability, 0.0, 0.01)

	# And on the way down it stops being worth anything well before it is gone.
	# Half a bar is not half a plate: the condition curve bottoms out near zero,
	# so a vest at a fifth is stopping about a tenth of what a fresh one does.
	var thin: Inventory = _kit("medium_vest", 1)
	var thin_worn: Item = thin.get_worn(Inventory.Wear.VEST)
	thin_worn.durability = thin_worn.armor.max_durability * 0.2
	var through: float = _first_hit(damage, ar.damage, thin, false)
	_eq("a fifth of a vest is nearly no vest", through, 51.0, 0.5)

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
		# INF is a real answer and not a broken one - a gun still doing 60% of
		# its damage at the edge of the map has no half-damage range - but
		# "infpx" in a column of numbers reads as a bug, so it says so in words.
		var reach := gun.get_half_damage_range()
		var reach_text := "no drop" if is_inf(reach) else "%.0fpx" % reach
		print("%-14s %5d %6.0f %8s | %2d rounds %8.0f ms | %2d rounds %8.0f ms" % [
			name, gun.rounds_per_minute, gun.damage, reach_text,
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


## Like _first_hit, but for a round that does something about the plate.
func _first_hit_pierced(damage: RefCounted, gun: WeaponData, kit: Inventory,
		head: bool) -> float:
	var centre := Vector2.ZERO
	var result = damage.resolve(gun.damage, _hit_point(centre, head), centre,
		BODY_HEIGHT, kit, gun.armor_pierce)
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
			var result = damage.resolve(gun.damage, at, centre, BODY_HEIGHT, kit,
				gun.armor_pierce)
			health -= result.amount
	return rounds


func _eq(what: String, got: float, want: float, tolerance := 0.001) -> void:
	if absf(got - want) <= tolerance:
		print("  ok   %-42s %.2f" % [what, got])
	else:
		_failures.append("%s: got %.3f, wanted %.3f" % [what, got, want])
		print("  FAIL %-42s %.2f (wanted %.2f)" % [what, got, want])
