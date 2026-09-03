class_name EnergyCellData
extends Resource

## What actually lets a gun fire, and the second half of the loadout decision
## a weapon used to be alone.
##
## Not PowerData - that resource charges ultimates and this one has nothing
## to do with it, which is the whole reason it is not called PowerCellData or
## anything else with "power" in it. This is the thing every primary and
## secondary weapon needs plugged into it before it will put a round
## downrange, the same way it needs a magazine, and one comes free with every
## gun you buy: from_weapon() fits a cell at the gun's own base_tier for
## nothing, the same way it fills the magazine for nothing, so buying a rifle
## has never left it unable to fire. The decision this resource exists to
## create is not "do I own one" - it is whether to pay for a hotter one.
##
## Six tiers, cheap to dear, and a weapon can run its own tier or up to two
## above it - never below, because a cell that cannot feed a gun's own
## chamber is not a smaller version of the right one, it is the wrong one.
## See EnergyCellData.fits() for exactly where that line sits, and
## Gunsmith.energy_delta() for how far over it a fitted cell actually is.
##
## Running hot is the trade, and it is a real one in both directions - the
## same "no part is simply better than no part" rule AttachmentData's header
## comment sets out. A cell two tiers over does not just cost more money: it
## costs recoil, stability and accuracy on the gun holding it, in exchange for
## more damage and a faster round, and on top of that it costs heat - see
## Weapon.gd's `heat` field for what firing on a cell like that does to a gun
## while the trigger is down. Nobody drifts into this by accident; every
## number is a decision made at the gunsmith's bench, in credits, before the
## raid ever starts.

@export var display_name := "Energy Cell"
## Short enough for the gunsmith's slot box: "T1" through "T6" rather than a
## name, because the number is the only thing about a cell that changes what
## it does - two cells at the same tier are interchangeable, so naming them
## individually would be inventing a difference that is not there.
@export var short_name := "T1"
@export_range(1, 6) var tier := 1
@export var price := 400
@export_multiline var blurb := ""
@export var tint := Color(0.55, 0.85, 0.95)


## Whether this cell will run that gun at all: its own tier or up to two over,
## never under. The only rule a cell has - unlike an AttachmentData, which
## cares about calibre and whether it is being hung off a sidearm, a cell
## cares about exactly one number.
func fits(weapon: WeaponData) -> bool:
	if weapon == null:
		return false
	var delta := tier - weapon.base_tier
	return delta >= 0 and delta <= 2
