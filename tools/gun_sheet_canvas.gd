extends Control

## The canvas tools/gun_sheet_shot.gd photographs: every weapon, bare on the left
## and with every slot filled on the right, drawn against a ruled ground so a
## part that has come off its mount is visible against a straight line rather
## than against a dark rectangle.

const GUN := "res://resources/weapons/%s.tres"
const ATT := "res://resources/attachments/%s.tres"

const BG := Color(0.06, 0.07, 0.09)
const ROW_BG := Color(0.085, 0.095, 0.12)
const LINE := Color(0.22, 0.25, 0.31)
const TEXT := Color(0.85, 0.89, 0.94)
const DIM := Color(0.5, 0.55, 0.62)
const ACCENT := Color(0.98, 0.78, 0.35)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_string(font, Vector2(28.0, 38.0), "EVERY GUN, BARE AND LOADED",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ACCENT)
	draw_string(font, Vector2(28.0, 58.0),
		"left: as bought.   right: an optic, a can, a drum, a foregrip and a stock on every mount.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)

	var names := ["pistol", "smg", "assault_rifle", "shotgun", "slug_shotgun",
		"lmg", "sniper"]
	var top := 74.0
	var tall := (size.y - top - 16.0) / float(names.size())
	var half := (size.x - 56.0) * 0.5

	for i in names.size():
		var gun := load(GUN % names[i]) as WeaponData
		if gun == null:
			continue
		var row := Rect2(Vector2(28.0, top + tall * float(i)),
			Vector2(size.x - 56.0, tall - 6.0))
		draw_rect(row, ROW_BG)
		draw_line(Vector2(row.get_center().x, row.position.y + 4.0),
			Vector2(row.get_center().x, row.end.y - 4.0), Color(LINE, 0.7), 1.0)
		draw_string(font, row.position + Vector2(10.0, 16.0), gun.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		draw_string(font, row.position + Vector2(10.0, 30.0),
			"%s   %d rnd   %dx%d cells" % [gun.short_name, gun.mag_size,
				gun.grid_size.x, gun.grid_size.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)

		_draw_one(Rect2(row.position, Vector2(half, row.size.y)), gun, [])
		_draw_one(Rect2(Vector2(row.get_center().x, row.position.y),
			Vector2(half, row.size.y)), gun, _parts_for(gun))


## What will actually go on this weapon. A sidearm takes no stock and no
## foregrip, so asking for them would draw a gun the shop refuses to build.
func _parts_for(gun: WeaponData) -> Array:
	var wanted := ["marksman_4x", "suppressor", "drum_mag", "vertical_grip",
		"heavy_stock", "red_dot", "extended_mag", "laser_sight"]
	var out: Array = []
	var filled := {}
	for name in wanted:
		var part := load(ATT % name) as AttachmentData
		if part == null or not part.fits(gun) or filled.has(part.slot):
			continue
		filled[part.slot] = true
		out.append(part)
	return out


## One gun, scaled into its half of the row, with a bore line drawn through it.
##
## The rule is drawn *first* and the gun over it: a part sitting a pixel off its
## mount shows as a kink against a straight line, which is the whole reason this
## sheet exists.
func _draw_one(box: Rect2, gun: WeaponData, parts: Array) -> void:
	var span := GunArt.span(gun, parts)
	var zoom := minf((box.size.x - 60.0) / maxf(span.x, 1.0),
		(box.size.y - 30.0) / maxf(span.y, 1.0))
	zoom = clampf(zoom, 0.5, 4.0)
	var bore := Vector2(box.get_center().x - (span.x * 0.5 - span.z) * zoom,
		box.get_center().y + 4.0)
	draw_line(Vector2(box.position.x + 14.0, bore.y),
		Vector2(box.end.x - 14.0, bore.y), Color(LINE, 0.55), 1.0)
	GunArt.draw_gun(self, bore, zoom, gun, parts)
