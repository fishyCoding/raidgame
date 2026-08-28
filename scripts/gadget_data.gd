class_name GadgetData
extends Resource

## A piece of kit that is not a gun: something you throw, or something you charge
## up and spend once a fight.
##
## Throwables are consumable and bought by the pair; ultimates are permanent kit
## that recharge over the course of a raid. Both are bought before you go in,
## which is what makes the shop a decision rather than a shopping list.

enum Kind { FRAG, SMOKE, OVERLOAD, RECON_BOW, PROJECTION, FLASH, DASH }
enum Class { THROWABLE, ULTIMATE }

@export var display_name := "Gadget"
@export var short_name := "GADGET"
@export var kind := Kind.FRAG
@export var gadget_class := Class.THROWABLE
@export var price := 300

@export_group("Throwable")
## Seconds from leaving your hand to going off.
@export var fuse := 1.6
## How far the effect reaches, in pixels.
@export var radius := 160.0
## Peak damage at the centre, falling off to nothing at the edge (FRAG).
@export var damage := 120.0
## How long the effect lingers (SMOKE), and how long the screen stays white
## after a FLASH goes off in your face.
@export var duration := 8.0

@export_group("Ultimate")
## Seconds of fighting to fill the meter from empty.
@export var charge_time := 45.0
## How long the effect lasts once spent.
@export var active_time := 8.0
## How many rounds the effect can absorb before it comes apart (PROJECTION).
@export var hit_points := 3
## How many dashes casting it gives you. Spent one at a time and kept until they
## are, rather than running out on a clock: two dashes you are saving is a plan,
## and two dashes evaporating while you wait for the right moment is a tax on
## thinking.
@export var dashes := 2

@export_group("Look")
@export var tint := Color(0.8, 0.8, 0.85)
@export var grid_size := Vector2i(1, 1)
