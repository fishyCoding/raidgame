@tool
class_name Decor
extends Node2D

## Scenery. Draws a picture in the world and does nothing else.
##
## There is no body, no collision shape and no occluder here on purpose. A
## Decor stops nothing, hides nothing and is never raycast: rounds fly through
## it, sight passes through it, the minimap does not know it exists. It is
## purely something to put behind the level so the gaps between the walkways
## are a place rather than a hole.
##
## Keep them out of the World node. Everything under World is read as level
## geometry by map_screen.gd, which goes by whether a child has a `size`, and a
## backdrop drawn onto the minimap as a solid wall is a lie you would act on.
## main.tscn parks them under Backdrop, behind World and in front of Air.

## Left null, the rectangle is filled with [member tint] alone - a plain block
## of colour is often all a background needs.
@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()

## The rectangle to fill, centred on this node.
@export var size := Vector2(512, 256):
	set(value):
		size = value
		queue_redraw()

## Repeat the picture across the rectangle at [member tile_size] instead of
## stretching one copy to fit. Stretching is right for a painted backdrop; tiling
## is right for material - brick, panelling, corrugated sheet.
@export var tiled := false:
	set(value):
		tiled = value
		queue_redraw()

## How big one repeat is, in world pixels, when [member tiled] is on.
@export_range(8.0, 512.0, 1.0, "or_greater") var tile_size := 128.0:
	set(value):
		tile_size = value
		queue_redraw()

## Multiplied into the picture. Backdrops want to sit behind the level rather
## than compete with it, so the default is dimmed and slightly cooled.
@export var tint := Color(0.62, 0.68, 0.78, 1.0):
	set(value):
		tint = value
		queue_redraw()

## Turned off, the backdrop ignores the vision light and draws at full strength
## - which is what you want for a sky or a far horizon that should not go dark
## just because nobody is standing near it.
@export var lit := true:
	set(value):
		lit = value
		_apply_light()
		queue_redraw()


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_apply_light()
	queue_redraw()


func _apply_light() -> void:
	# "Unshaded" is the light mask being empty: no Light2D can reach it, so the
	# ambient tint is the only thing that touches it.
	light_mask = 1 if lit else 0


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := Rect2(-size * 0.5, size)
	if texture == null:
		draw_rect(rect, tint)
		return
	if not tiled:
		draw_texture_rect(texture, rect, false, tint)
		return

	# draw_texture_rect() repeats at the texture's own size, so scale the draw
	# space until a texture-sized step measures one tile of world pixels, and
	# give the rectangle in those units.
	var tex := texture.get_size()
	var step := maxf(tile_size, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(step / tex.x, step / tex.y))
	var tiles := size / step
	draw_texture_rect(texture,
			Rect2(-tiles * 0.5 * tex, tiles * tex), true, tint)
