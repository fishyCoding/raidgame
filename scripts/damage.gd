class_name Damage
extends RefCounted

## Where a round landed and what the armour did about it.
##
## Shared by the player and the guards so a headshot means the same thing to
## both: a hit above the shoulders is lethal unless there is a sound helmet in
## the way, and armour is spent stopping what it stops.

## Fraction of a body's height counted as head, measured from the top.
const HEAD_FRACTION := 0.26

class Result extends RefCounted:
	var amount := 0.0
	var headshot := false
	## True when the hit puts the target down regardless of health left.
	var knockout := false
	var armor_hit: Item = null


## Tells the player their hit landed, so the HUD can mark it and the ears can
## confirm it.
##
## Called by whoever took the damage rather than by whoever dealt it, for one
## reason: only the target knows whether it died. That also means every source
## reports for free - a bullet, a grenade, anything that ends up in take_damage -
## instead of each one having to remember to.
##
## The machine noticing a hit is usually not the machine that fired it, and now
## that players can shoot each other it is often neither the shooter's nor the
## host's: a player works out what a round did to their own body, so the mark for
## the best shot in the game is reported by the person it was fired at. Net knows
## which round is being resolved (Net.attributing_to) and routes the mark to
## whoever pulled the trigger, wherever they happen to be sitting.
static func report_hit(_tree: SceneTree, headshot: bool, killed: bool) -> void:
	Net.credit_hit(headshot, killed)


## Works out what a hit does. `at` is where the round landed in world space,
## `centre` and `height` describe the body it landed on.
static func resolve(amount: float, at: Vector2, centre: Vector2, height: float,
		kit: Inventory) -> Result:
	var result := Result.new()
	result.amount = amount
	result.headshot = at.y <= centre.y - height * 0.5 + height * HEAD_FRACTION

	var worn: Item = null
	if kit:
		worn = kit.get_worn(Inventory.Wear.HELMET if result.headshot else Inventory.Wear.VEST)

	if result.headshot:
		# A helmet with anything left in it turns a killing shot into a bad one.
		# Without one - or with a cracked one - there is no saving it.
		if worn == null or not worn.armor.stops_headshots(worn.durability):
			result.knockout = true
			result.armor_hit = worn
			return result
		result.armor_hit = worn
		result.amount = amount - worn.armor.absorbed(amount, worn.durability)
		# Head hits chew through a helmet far faster than body hits do a plate.
		worn.durability = maxf(worn.durability - amount * 1.6, 0.0)
		return result

	if worn:
		result.armor_hit = worn
		result.amount = amount - worn.armor.absorbed(amount, worn.durability)
		worn.durability = maxf(worn.durability - amount, 0.0)
	return result
