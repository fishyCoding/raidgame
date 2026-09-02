class_name PowerData
extends Resource

## What charges your ultimates, and the rack they sit in.
##
## Before this, an ultimate was a thing you bought and it charged itself, which
## made "which ultimate" the only question. A power source turns it into three:
## what you want to run, whether you can afford the thing that runs it, and
## whether the shape you bought has room for it.
##
## The rack is the whole of it. Ultimates are not put in numbered slots any more
## - they are laid into this grid the way kit is laid into a bag, so a big
## gadget takes the space a big gadget should and two small ones are a decision
## against one large one. No source means no rack, which means no ultimate: the
## gadget has nowhere to be rather than being separately forbidden.
##
## And it charges. `charge_scale` multiplies every gadget's own charge_time, so
## the cheap rack is slower than the expensive one at running the same gadget,
## and buying up is worth something even when the shape you had already fit.

@export var display_name := "Power Source"
@export var short_name := "POWER"

## The rack this gives you. Cells, on the same grid as everything else.
##
## Shape matters as much as area: four cells as 2x2 takes one big gadget or two
## small ones, and the same four as 4x1 takes two small ones and no big one at
## all. That is the decision this whole resource exists to create, so the sizes
## shipped are deliberately not all the same rectangle.
@export var grid_size := Vector2i(2, 2)

## Footprint the source itself takes when it is being carried rather than worn -
## looted off a body, it has to go somewhere.
@export var carried_size := Vector2i(2, 2)

## Multiplies how long every gadget in the rack takes to charge. Below one is
## faster. The reason to buy the dear one when the cheap one already fits.
@export_range(0.5, 2.0) var charge_scale := 1.0

@export var price := 1000

## One line for the shelf, in the language a player would use.
@export_multiline var blurb := ""

@export var tint := Color(0.55, 0.78, 0.95)


## "2x2, charges at 100%" - the line under the name on the shelf and in the slot.
func summary() -> String:
	return "%dx%d  -  charges at %d%%" % [grid_size.x, grid_size.y,
		roundi(100.0 / maxf(charge_scale, 0.01))]
