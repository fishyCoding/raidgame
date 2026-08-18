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

## How much damage the piece can soak before it is scrap. Every hit it absorbs
## costs durability whether or not it saved you much.
@export var max_durability := 100.0

## Durability below this fraction and a helmet no longer stops a headshot: the
## shell is cracked, and the next round through it ends you.
@export_range(0.0, 1.0) var failure_point := 0.25

## Footprint in inventory cells.
@export var grid_size := Vector2i(2, 2)

@export var tint := Color(0.55, 0.62, 0.7)


## Damage that gets through this piece at its current durability. Armour thins
## out as it breaks rather than failing all at once, so the last few points are
## still worth something.
func absorbed(amount: float, durability: float) -> float:
	if durability <= 0.0:
		return 0.0
	var condition := clampf(durability / maxf(max_durability, 1.0), 0.0, 1.0)
	return amount * protection * lerpf(0.35, 1.0, condition)


## True while this helmet is still sound enough to stop a round to the head.
func stops_headshots(durability: float) -> bool:
	return durability > max_durability * failure_point
