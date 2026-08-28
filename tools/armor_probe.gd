extends SceneTree

## What each gun actually does through each plate, at range.
##
##   godot --headless --path . --script res://tools/armor_probe.gd
##
## A readout, not a test - nothing here passes or fails. It exists because
## "the shotgun does nothing against armour" is a claim about four numbers
## multiplied together (pellet damage, pellet count, falloff, protection) and
## arguing about it from any one of them gets you the wrong answer.

const GUNS := [
	"res://resources/weapons/shotgun.tres",
	"res://resources/weapons/slug_shotgun.tres",
	"res://resources/weapons/assault_rifle.tres",
	"res://resources/weapons/pistol.tres",
	"res://resources/weapons/sniper.tres",
]
const VESTS := [
	"",
	"res://resources/armor/light_vest.tres",
	"res://resources/armor/medium_vest.tres",
	"res://resources/armor/heavy_vest.tres",
]
const RANGES := [30.0, 100.0, 200.0, 400.0]


func _initialize() -> void:
	for path in GUNS:
		var gun := load(path) as WeaponData
		if gun == null:
			continue
		print("\n== %s -- %d pellet(s) x %.0f, %.0f rpm, pierce %.2f" % [
			gun.display_name, gun.pellets, gun.damage, gun.rounds_per_minute,
			gun.armor_pierce])
		print("   %-14s %s" % ["", _header()])
		for vest_path in VESTS:
			var vest: ArmorData = null
			if vest_path != "":
				vest = load(vest_path) as ArmorData
			var row := ""
			for distance in RANGES:
				row += "%14s" % _one_pull(gun, vest, distance)
			print("   %-14s%s" % [vest.short_name if vest else "no plate", row])
	quit()


func _header() -> String:
	var out := ""
	for distance in RANGES:
		out += "%14s" % ("%.0f px" % distance)
	return out


## One trigger pull against one plate at one distance: damage through, and how
## many pulls that is to take a hundred points of health off.
##
## The plate is fresh for every pull rather than worn down across them, because
## what is being compared is the guns and not the order somebody shot in.
func _one_pull(gun: WeaponData, vest: ArmorData, distance: float) -> String:
	var each := gun.get_damage_at(distance)
	var through := 0.0
	for i in gun.pellets:
		if vest == null:
			through += each
			continue
		through += each - vest.absorbed(each, vest.max_durability,
			gun.armor_pierce)
	if through <= 0.01:
		return "-"
	return "%.0f (x%.1f)" % [through, 100.0 / through]
