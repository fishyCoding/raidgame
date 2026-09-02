class_name AttachmentData
extends Resource

## One thing you can bolt onto a gun, and what bolting it on costs you.
##
## Every attachment in this game is a trade. There is no part that is simply
## better than no part: a drum holds twenty-five more rounds and takes a second
## longer to change and a cell more to carry, a suppressor buys you silence with
## damage, a 4x scope buys you reach with the speed you get onto a target. That
## is the whole design rule, and a part that breaks it is a part that removes a
## decision instead of adding one.
##
## Everything here is expressed as a *change* to a gun rather than as a value.
## Deltas add to the four dials, scales multiply the concrete numbers, and the
## gunsmith applies them to a copy of the weapon - so an attachment knows nothing
## about which gun it is on, and a gun needs no list of what can be hung off it.
## See Gunsmith.build(), which is the only place the two meet.

## Where it goes. One part per slot, five slots, and the slot is also what the
## gunsmith draws it as - a muzzle device is drawn off the barrel, a stock behind
## the grip, and neither of them needs to say so twice.
enum Slot { MAGAZINE, MUZZLE, OPTIC, GRIP, STOCK }

@export var display_name := "Attachment"
## Six characters or so, for the slot boxes and the weapon label.
@export var short_name := "PART"
@export var slot: Slot = Slot.MUZZLE
@export var price := 300

## One line saying what it is for, in the language a player would use. Shown
## under the name on the shelf, and it is the only prose on the card - the
## numbers underneath it are the argument, this is just the sales pitch.
@export_multiline var blurb := ""

## Which calibres this fits, empty meaning all of them.
##
## Magazines are the only parts that care, and they care absolutely: a 5.56
## magazine does not go in a shotgun. Everything else bolts to a rail or a
## thread, and the guns in this game are all assumed to have both.
@export var fits_calibres: Array[StringName] = []
## Whether it can go on a sidearm. A pistol takes a suppressor and a red dot; it
## does not take a stock or a foregrip, and offering them is offering a choice
## that is not one.
@export var fits_sidearm := true

@export_group("The four dials")
## Added to the gun's own dials, then clamped into 0..100 by the builder. Points
## on the same scale the weapon cards draw, so +14 stability is fourteen percent
## of the whole bar and reads as exactly that much of a change.
@export_range(-40.0, 40.0) var accuracy_delta := 0.0
@export_range(-40.0, 40.0) var handling_delta := 0.0
## Negative is *better* here, as on the weapon itself: recoil is how far the
## muzzle climbs, so a compensator subtracts from it.
@export_range(-40.0, 40.0) var recoil_delta := 0.0
@export_range(-40.0, 40.0) var stability_delta := 0.0

@export_group("Feeding")
## Multiplies the magazine, before mag_delta is added.
##
## A scale rather than a flat number because the guns it has to work across hold
## anywhere from five rounds to a hundred: "plus twelve" is a rounding error on a
## belt-fed and more than a whole magazine on a bolt gun, while "half again" is
## the same decision on both.
@export_range(0.25, 3.0) var mag_scale := 1.0
## Rounds added on top of that. For the odd part that adds a fixed few rather
## than a proportion - a shell holder, a spare in the pipe.
@export_range(-20, 40) var mag_delta := 0
## Multiplies the reload. Above one is slower.
@export_range(0.5, 2.0) var reload_scale := 1.0

@export_group("Sights")
## How much more ground this glass shows you while aimed. 4.0 is a four power
## scope: four times the world across the screen.
##
## A *divisor* on the camera, not an addition to it, and that is the whole point.
## Camera2D.zoom works the other way round from the word "zoom" - lower shows
## more - which is why every gun in the game has an ads_zoom below one and the
## sniper has the lowest of the lot. Adding to that number, which is what this
## field used to do, made a 4x scope show you *less* than iron sights while the
## workshop cheerfully printed "2.4x". In a game seen from the side,
## magnification is how far you can see, so it has to pull the camera back.
@export_range(0.5, 6.0) var magnify := 1.0
## Multiplies how fast the gun comes up and settles. Above one is faster - it is
## a speed, not a duration.
@export_range(0.4, 2.0) var ads_speed_scale := 1.0
## Multiplies the whole aim transition, including the walk-speed penalty. The
## handling knob for parts that change the weight of the thing rather than the
## glass on top of it.
@export_range(0.4, 2.0) var aim_speed_scale := 1.0
## A lens big enough to throw a glint back at whoever you are watching. See
## WeaponData.scope_glint - it is the counterplay to magnification, and any
## optic worth the name pays it.
@export var adds_glint := false

@export_group("Noise and damage")
## Silences the shot: no report at range, no marker on anybody's screen.
@export var suppresses := false
## Added to the gun's loudness trim, in decibels. Negative is quieter.
@export_range(-24.0, 12.0) var loudness_delta := 0.0
## Multiplies damage per round. The suppressor's price, and deliberately a real
## one - a can that cost nothing would be on every gun in the game.
@export_range(0.5, 1.5) var damage_scale := 1.0
## Multiplies both ends of the falloff window, which moves where a gun stops
## being worth firing without touching what it does up close.
@export_range(0.5, 2.0) var falloff_scale := 1.0

@export_group("Carrying")
## Cells added to the gun's footprint, across. A drum magazine is a real object
## and it has to live in the bag with everything else.
@export_range(-2, 2) var cells_delta := 0

@export_group("Look")
## Drawn on the gunsmith's diagram. Length and depth in gun-drawing units, which
## are roughly pixels at the size the diagram is drawn.
@export var art_size := Vector2(18.0, 6.0)
@export var tint := Color(0.62, 0.68, 0.78)


## Whether this part will go on that gun at all.
##
## Two questions and no more: does it feed the right round, and is it being hung
## off a pistol. Anything finer belongs on the part - a rule that lives in code
## is a rule nobody browsing the shelf can see.
func fits(gun: WeaponData) -> bool:
	if gun == null:
		return false
	if gun.sidearm and not fits_sidearm:
		return false
	if fits_calibres.is_empty():
		return true
	return fits_calibres.has(gun.ammo_type)


## The slot's name, for the boxes down the middle of the gunsmith.
static func slot_name(which: int) -> String:
	match which:
		Slot.MAGAZINE: return "MAGAZINE"
		Slot.MUZZLE: return "MUZZLE"
		Slot.OPTIC: return "OPTIC"
		Slot.GRIP: return "GRIP"
		Slot.STOCK: return "STOCK"
	return "PART"
