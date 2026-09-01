class_name GadgetData
extends Resource

## A piece of kit that is not a gun: something you throw, or something you charge
## up and spend once a fight.
##
## Throwables are consumable and bought by the pair; ultimates are permanent kit
## that recharge over the course of a raid. Both are bought before you go in,
## which is what makes the shop a decision rather than a shopping list.

enum Kind { FRAG, SMOKE, OVERLOAD, RECON_BOW, PROJECTION, FLASH, DASH, SCREEN, RAIL_BOMB,
	HEADCOUNT }
enum Class { THROWABLE, ULTIMATE }

@export var display_name := "Gadget"
@export var short_name := "GADGET"
@export var kind := Kind.FRAG
@export var gadget_class := Class.THROWABLE
@export var price := 300

@export_group("Throwable")
## Seconds from leaving your hand to going off.
@export var fuse := 1.6
## How far the effect reaches, in pixels. For RAIL_BOMB it is how close to a
## cable you have to be standing to clamp one onto it.
@export var radius := 160.0
## Peak damage at the centre, falling off to nothing at the edge (FRAG). For
## RAIL_BOMB it is damage per jolt, and it jolts every RailBomb.JOLT_INTERVAL -
## not per second, because a player has invulnerability frames after any hit and
## damage spread thinly across frames is damage thrown away. Three jolts is a
## kill on an unarmoured man.
@export var damage := 120.0
## How long the effect lingers (SMOKE), and how long the screen stays white
## after a FLASH goes off in your face.
@export var duration := 8.0

@export_group("Ultimate")
## Seconds of fighting to fill the meter from empty.
@export var charge_time := 45.0
## How long the effect lasts once spent.
@export var active_time := 8.0
## How many rounds the effect can absorb before it comes apart (PROJECTION), and
## how many a RAIL_BOMB takes before it is shot out of the air.
##
## Counted on the host only, like every other kind of damage, and the bomb comes
## down everywhere when the count runs out - see Net.bring_down_rail_bomb. It is
## a small hard thing that moves, so the difficulty is meant to be hitting it
## rather than hurting it.
@export var hit_points := 3
## How many dashes casting it gives you. Spent one at a time and kept until they
## are, rather than running out on a clock: two dashes you are saving is a plan,
## and two dashes evaporating while you wait for the right moment is a tax on
## thinking.
@export var dashes := 2
## How long a screen may be, in player heights. It has to reach something solid
## at one end, so this is the leash on where "something solid" is allowed to be.
@export var reach_in_heights := 5.0

## How fast a RAIL_BOMB climbs its cable, in pixels per second.
##
## Around what a man rides at, and on the quicker ropes rather less - so getting
## off ahead of one is a thing you have to have already started doing, not a
## thing you do when you see it. It was a third of this to begin with, which
## made the climb the whole gadget and the arrival an afterthought; at this
## speed the rope is a short unpleasant moment and the thing that matters is
## where it ends up.
##
## The trade is paid on the way past: the faster it goes, the less time anybody
## on the rope spends inside RailBomb.STRIKE_RANGE, and past about this speed a
## rider takes one jolt on the way by rather than two. That is the intended
## shape now - the cable is the delivery, the sky is the weapon.
@export var travel_speed := 600.0

## Seconds a RAIL_BOMB has left from the moment it stops - whether it stopped
## because it ran out of rope or because it saw somebody worth stopping for.
##
## Set, not subtracted, so the hover is the same length however long the climb
## took. active_time is the budget for everything before that: waiting to be
## pointed, and the climb itself. This is the part that does the work, and a
## bomb that had spent most of its cell getting up a long rope would otherwise
## arrive at the top with nothing left to do there.
@export var hover_time := 10.0

## How far a HEADCOUNT hears, in pixels.
##
## Deliberately wider than the screen, which is the whole gadget: it is not a
## second pair of eyes, it is the answer to "is this building empty". Anything
## you could already see is not worth a charge, so the useful part of this
## number is the part that is off the edge of the frame.
##
## Walls do not stop it. There is no line-of-sight test anywhere in the count,
## because a count you only get on people you can already see is a count of
## nothing - and the price of that is paid at the other end, in what it tells
## you: a bearing and a tally, never a position.
@export var count_range := 1400.0

## How far a RAIL_BOMB can reach once it is holding station at the end of the
## cable, in pixels.
##
## It needs line of sight as well as range, so this is the outer limit of a
## thing it has to be able to see anyway - and the reason the answer to one
## parked over the yard is a wall rather than distance.
@export var sight_range := 520.0

@export_group("Look")
@export var tint := Color(0.8, 0.8, 0.85)
@export var grid_size := Vector2i(1, 1)
