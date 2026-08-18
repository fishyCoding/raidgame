class_name BackpackData
extends Resource

## A bag: the space you have beyond your pockets, and a thing you choose rather
## than something you are given.
##
## Pockets are fixed at five single cells and hold only the small stuff, so the
## pack is the whole of your carrying capacity for anything bigger than a
## magazine. That makes it the loadout decision it should be: a big bag costs
## money you could have spent on the rifle, and it is worth nothing if you die
## with it - but it is the difference between extracting with the loot and
## extracting with a story about the loot.

@export var display_name := "Backpack"
@export var short_name := "PACK"

## The grid this bag gives you. Cells, not litres.
@export var grid_size := Vector2i(6, 3)

## Footprint the bag itself takes up when it is being carried rather than worn -
## looted off a body, it has to go somewhere.
@export var carried_size := Vector2i(2, 2)

@export var tint := Color(0.5, 0.55, 0.6)
