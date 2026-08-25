class_name ArmorData
extends Resource

## A piece of armour: what it covers, how much it stops, and how long it lasts.
##
## Durability is the whole design. Armour does not make you invulnerable, it
## spends itself protecting you - so a plate that has taken a magazine is worth
## as little as no plate at all, and knowing when yours is finished is the
## decision the system exists to create.

enum Slot { HEAD, BODY }

@export var display_name := "Armour"
@export var short_name := "ARMOUR"
@export var slot := Slot.BODY

## Fraction of an incoming hit absorbed while the piece is intact.
@export_range(0.0, 0.95) var protection := 0.5

## How much damage the piece can soak before it is scrap.
##
## Read it literally: this is a budget of damage the piece will absorb, and each
## hit spends what that hit actually stopped rather than what it arrived with.
## The distinction is the difference between armour that lasts the fight it was
## bought for and armour that is scrap three rounds in - see the note in
## Damage.resolve, which is where the spending happens.
@export var max_durability := 100.0

## Durability below this fraction and the piece is scrap: it stops nothing at
## all, and the cells it costs you are the only thing it is still doing.
##
## It used to mean something narrower - the point where a helmet stopped turning
## headshots aside - which only ever applied to helmets, and only because
## headshots were a yes-or-no rule. Now that both are damage, one failure point
## covers both pieces: a plate that has taken a magazine is not thin armour, it
## is a broken plate, and the last quarter of the bar should not be quietly
## saving you.
@export_range(0.0, 1.0) var failure_point := 0.25

## Footprint in inventory cells.
@export var grid_size := Vector2i(2, 2)

@export var tint := Color(0.55, 0.62, 0.7)


## Damage that gets through this piece at its current durability. Armour thins
## out as it breaks rather than failing all at once, so the last few points are
## still worth something.
func absorbed(amount: float, durability: float) -> float:
	if not is_sound(durability):
		return 0.0
	var condition := clampf(durability / maxf(max_durability, 1.0), 0.0, 1.0)
	return amount * protection * lerpf(0.35, 1.0, condition)


## True while there is enough of this piece left to be worth wearing.
func is_sound(durability: float) -> bool:
	return durability > max_durability * failure_point
