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
## Set to zero on everything in the shop now, and kept as a dial rather than
## deleted. The cliff existed because the old absorption curve never got near
## zero on its own, so something had to declare the piece finished; the curve
## reaches nothing by itself now, and a plate that fades out is better than one
## that switches off - you feel the rounds landing harder as it goes.
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


## Damage this piece stops at its current durability. Armour thins out as it
## breaks rather than failing all at once, and by the end it is worth almost
## nothing at all.
##
## The condition curve used to bottom out at 0.35, so a plate at death's door
## still took a third off every round - which meant the bottom half of the bar
## was quietly doing most of the work of the top half and there was never a
## moment where you knew you were unprotected. It bottoms out at 0.06 now: a
## nearly-dead plate stops about three percent of a rifle round, which is a
## rounding error and reads as one. Low armour is no armour, said in the
## model's own terms rather than by a cliff at a threshold.
##
## `pierce` is what the round does about the plate rather than what the plate
## does about the round: 0 is an ordinary bullet and the piece works as
## advertised, 1 goes through as though it were not being worn. It scales the
## protection rather than the damage, which is the distinction that matters -
## protection here is a *fraction*, so a bigger round is cut by exactly the same
## proportion as a small one and no amount of raw damage will ever get you
## through a plate any faster. Beating armour has to be a property of the round.
func absorbed(amount: float, durability: float, pierce := 0.0) -> float:
	if not is_sound(durability):
		return 0.0
	var condition := clampf(durability / maxf(max_durability, 1.0), 0.0, 1.0)
	var stops := protection * (1.0 - clampf(pierce, 0.0, 1.0))
	return amount * stops * lerpf(0.06, 1.0, condition)


## True while there is enough of this piece left to be worth wearing.
func is_sound(durability: float) -> bool:
	return durability > max_durability * failure_point
