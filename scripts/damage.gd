class_name Damage
extends RefCounted

## Where a round landed and what the armour did about it.
##
## Shared by the player and the guards so a headshot means the same thing to
## both: a hit above the shoulders counts double, armour subtracts from whatever
## reaches it, and armour is spent stopping what it stops.

## Fraction of a body's height counted as head, measured from the top.
const HEAD_FRACTION := 0.26

## What a hit above the shoulders is worth, before any helmet gets a say.
##
## This used to be a flag rather than a number: an unhelmeted head ended the
## fight whatever the health bar said, and a sound helmet made it survivable.
## That is a rule you cannot tune - it has no answer to "how much better is a
## heavy helmet than a light one" beyond yes and no.
##
## Doubling instead says the same thing in the model's own terms and keeps
## saying it as the guns change. A rifle doing 51 to the body does 102 to an
## unprotected head, which is still over a full health bar and still ends the
## fight in one round - the old rule, arrived at rather than asserted. Put a
## medium helmet in the way and the same round does 51, so it takes two. What a
## helmet buys is no longer a binary; it is how many head hits you can eat.
const HEADSHOT_MULTIPLIER := 2.0

## Head hits chew through a helmet faster than body hits do a plate.
const HELMET_WEAR := 1.6

class Result extends RefCounted:
	var amount := 0.0
	var headshot := false
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
	result.headshot = at.y <= centre.y - height * 0.5 + height * HEAD_FRACTION

	# The multiplier lands before the armour does, so a helmet is subtracting
	# from the doubled number rather than the raw one. That ordering is the
	# whole reason a headshot still hurts through a good helmet: halve 102 and
	# you have 51, which is twice what the same helmet leaves of a body shot.
	if result.headshot:
		amount *= HEADSHOT_MULTIPLIER
	result.amount = amount

	var worn: Item = null
	if kit:
		worn = kit.get_worn(Inventory.Wear.HELMET if result.headshot else Inventory.Wear.VEST)
	if worn == null:
		return result

	# Spent on what it stopped, not on what arrived.
	#
	# It used to be charged the whole incoming round, which read as fair and was
	# not: a plate lost 51 durability for the 25 it actually caught, so a medium
	# vest was scrap inside three rifle rounds and every round after that landed
	# whole. The advertised four-round kill was really "four if the first one
	# finds you fresh" - armour that stopped mattering halfway through the fight
	# it was bought for, and a time-to-kill that slid from four rounds to two
	# without anything on screen saying so.
	#
	# Charging the absorbed figure instead makes the bar mean what it looks like
	# it means: durability is a budget of damage the piece will eat, and it eats
	# it at the rate it is actually working. The four rounds hold up across a
	# magazine, and a plate still wears out - just over a fight rather than over
	# a burst.
	var stopped := worn.armor.absorbed(amount, worn.durability)
	result.armor_hit = worn
	result.amount = amount - stopped
	var wear := stopped * (HELMET_WEAR if result.headshot else 1.0)
	worn.durability = maxf(worn.durability - wear, 0.0)
	return result
