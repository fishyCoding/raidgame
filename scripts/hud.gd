extends Control

## Weapon readout: current gun, ammo, reload progress, the four stat bars, and
## the slot list. Drawn entirely in _draw() with the fallback font so there is no
## theme or layout scaffolding to keep in sync while the game is still a
## prototype.

const PANEL_BG := Color(0.07, 0.086, 0.11, 0.82)
const TEXT := Color(0.82, 0.87, 0.93)
const DIM := Color(0.45, 0.5, 0.58)
const ACCENT := Color(0.98, 0.78, 0.35)
const LOW_AMMO := Color(1.0, 0.44, 0.4)
const GOOD := Color(0.42, 0.78, 0.6)
const BAD := Color(0.85, 0.42, 0.42)
const OVERLOAD := Color(1.0, 0.68, 0.28)
const RECON := Color(0.55, 0.85, 0.95, 0.95)
const PROJECTION := Color(0.62, 0.78, 1.0)

## How far the weapon panel steps back while fully aimed. Not all the way to
## invisible: ammo still matters mid-fight.
const PANEL_FADE_AIMED := 0.25
## Just the gun and what is in it. The damage curve and the four stat bars used
## to live here, which made this the largest thing on the screen and the least
## useful: they are properties of a gun you already own and cannot change, so
## they belong where you are choosing between guns. They are on the weapon cards
## in the kit screen now - see shop.gd.
const PANEL_SIZE := Vector2(300, 92)
const MARGIN := 20.0

var _player: Player
var _weapon: Weapon
var _font: Font
## Alpha applied to the weapon panel. Aiming leans the camera hard enough that
## the player can end up standing behind the panel, so it gets out of the way.
var _panel_fade := 1.0
## Remembered so the countdown bar has something to be a fraction of. One span
## for whichever ultimate is running, because only one ever is.
var _overload_span := 8.0
## Seconds left of the "you have been scanned" banner. Counted here rather than
## on the player because it is nothing but a thing on a screen - the body it
## happened to is unchanged, and dying should not leave it frozen mid-fade.
var _scanned_left := 0.0

## How long the banner stays up. Shorter than the reveal it warns about: it is
## telling you to move, and it should be out of the way while you do.
const SCANNED_TIME := 2.4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_player = Net.local_player
	Net.player_spawned.connect(_on_player_spawned)
	# The character can be here before this node is - solo spawns one as the level
	# loads - so binding happens in both places rather than only on the signal.
	if _player:
		_weapon = _player.weapon
		_player.scanned.connect(_on_scanned)


## Characters arrive after the level does now - spawned per peer rather than
## placed in the scene - so the HUD waits to be told which one is ours.
func _on_player_spawned(body: Node) -> void:
	if body != Net.local_player:
		return
	_player = body
	_weapon = _player.weapon
	if not _player.scanned.is_connected(_on_scanned):
		_player.scanned.connect(_on_scanned)


func _on_scanned() -> void:
	_scanned_left = SCANNED_TIME


func _process(delta: float) -> void:
	# The bar needs the full duration, and only the player knows it - catch it on
	# the frame it starts rather than hard-coding eight seconds here.
	if _player and _ult_left() > _overload_span:
		_overload_span = _ult_left()
	_scanned_left = maxf(_scanned_left - delta, 0.0)
	queue_redraw()


## Panel colours run through this, so the whole readout can step back while you
## are aiming without touching the health bar or the reticle.
func _fade(color: Color) -> Color:
	return Color(color.r, color.g, color.b, color.a * _panel_fade)


func _draw() -> void:
	# Before every early return below it. Being painted is worth knowing whether
	# you are holding a gun, holding nothing, or lying on the floor bleeding -
	# and on the floor it is the most useful thing on the screen, because it
	# means somebody is on their way.
	if _scanned_left > 0.0:
		_draw_scanned()
	if _weapon == null:
		_draw_flash()
		return
	_draw_health()
	# On the floor the weapon card comes down with you. Leaving a gun and its
	# ammunition on screen while the bar underneath says "no weapon" is the HUD
	# arguing with itself.
	if _weapon.data == null or _player.is_downed:
		return
	_panel_fade = lerpf(1.0, PANEL_FADE_AIMED, _player.focus)

	var data := _weapon.data
	# Bottom-left is the move stick's corner when there is one, so the gun card
	# goes to the top-left instead of underneath a thumb.
	var origin := Vector2(MARGIN, 68.0) if PlayerInput.is_touch() \
		else Vector2(MARGIN, size.y - PANEL_SIZE.y - MARGIN)

	draw_rect(Rect2(origin, PANEL_SIZE), _fade(PANEL_BG))
	draw_rect(Rect2(origin, Vector2(3.0, PANEL_SIZE.y)), _fade(ACCENT))

	var x := origin.x + 16.0
	var y := origin.y + 28.0

	# Name + slot
	draw_string(_font, Vector2(x, y), data.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, _fade(TEXT))
	y += 30.0

	# Ammo
	var mag := _weapon.get_mag()
	var ammo_color := LOW_AMMO if mag <= maxi(1, data.mag_size / 5) else TEXT
	draw_string(_font, Vector2(x, y), str(mag),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, _fade(ammo_color))
	var mag_width := _font.get_string_size(str(mag), HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(_font, Vector2(x + mag_width + 8.0, y), "/ %d" % _weapon.get_reserve(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _fade(DIM))

	if _weapon.is_reloading():
		var bar := Rect2(Vector2(x + mag_width + 74.0, y - 14.0), Vector2(86.0, 10.0))
		draw_rect(bar, _fade(Color(0.16, 0.18, 0.22)))
		draw_rect(Rect2(bar.position,
			Vector2(bar.size.x * _weapon.get_reload_progress(), bar.size.y)), _fade(ACCENT))
		draw_string(_font, Vector2(bar.position.x, bar.position.y - 4.0), "RELOADING",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _fade(ACCENT))
	elif mag <= 0:
		draw_string(_font, Vector2(x + mag_width + 74.0, y), "R TO RELOAD",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _fade(LOW_AMMO))
	# Under the card when it is at the top of the screen, over it when it is at
	# the bottom - either way the pair reads as one block rather than one of them
	# hanging off the edge.
	_draw_slots(Vector2(origin.x,
		origin.y + PANEL_SIZE.y + 22.0 if PlayerInput.is_touch() else origin.y - 30.0))


## How far past the edge of the screen a full-strength flash blooms. Over 1 on
## purpose: at full strength there must be no corner left to read anything out
## of, and a core that stopped exactly at the diagonal would leave the four
## corners faintly legible.
const FLASH_CORE_REACH := 1.2

## How far the soft halo runs past the solid core, as a fraction of the screen's
## half-diagonal. A hard-edged white circle reads as a decal stuck on the lens;
## the gradient is what makes it light.
const FLASH_HALO := 0.55

## Rings the halo is built from. Enough that the gradient is smooth, few enough
## that it is twenty draw calls and not two hundred.
const FLASH_RINGS := 22


## The size of the part of the screen a flash has taken away completely.
##
## Public and separate from the drawing because it is the thing worth asserting:
## "did anything actually become unreadable" is the whole question, and it is not
## one a headless run can answer by looking at a canvas.
func flash_core_radius() -> float:
	if _player == null:
		return 0.0
	var bloom: float = _player.flash_amount()
	if bloom <= 0.003:
		return 0.0
	return size.length() * 0.5 * bloom * FLASH_CORE_REACH


## The white-out from a flash grenade, over everything.
##
## Drawn last from every branch of _draw rather than first, and that is the whole
## behaviour: a flash has to take the readouts away too. Painted underneath, you
## would be blinded but could still read your ammo, your health and the ultimate
## meter off a screen that is otherwise useless - which turns the gadget into a
## brief cosmetic annoyance instead of a thing that costs you the fight.
##
## A **solid** core, not a wash. The first version of this was one translucent
## rectangle at the flash's strength, which meant you were never actually blind:
## a full-strength hit was a 94% white screen you could still read the map
## through, and anything past point-blank was a haze. Being partly blinded is not
## a weaker version of being blinded, it is a different and much worse gadget.
## So the strength decides *how much of the screen* goes, and what goes is gone -
## opaque, with a gradient around it and a wash over whatever is left.
##
## Centred on the flash rather than on the screen, so it takes the part of your
## view the light came from and leaves you the rest. That is what makes turning
## away from one worth doing.
##
## Not quite pure white. A screen that is exactly #FFFFFF reads as the game
## having crashed; a hair of warmth in it reads as light.
func _draw_flash() -> void:
	if _player == null:
		return
	var bloom: float = _player.flash_amount()
	if bloom <= 0.003:
		return

	# Everything not inside the bloom is still washed out - you are not reading
	# fine detail off any of this screen - but it is the core that blinds.
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.98, 0.93, bloom * 0.45))

	var centre := _flash_centre()
	var core := flash_core_radius()
	var halo := core + size.length() * 0.5 * FLASH_HALO * bloom

	# Outside in, so the middle accumulates towards solid rather than the edge
	# being painted over the part that is supposed to be opaque.
	for i in FLASH_RINGS:
		var t := 1.0 - float(i) / float(FLASH_RINGS)
		var edge := pow(1.0 - t, 1.8)
		draw_circle(centre, lerpf(core, halo, t),
			Color(1.0, 0.98, 0.93, edge * 0.5))
	if core > 1.0:
		draw_circle(centre, core, Color(1.0, 0.99, 0.95, 1.0))

	# The last of it goes warm rather than simply thinning out, so recovering
	# from a flash looks like an eye adjusting instead of an overlay fading.
	if bloom < 0.5:
		draw_rect(Rect2(Vector2.ZERO, size),
			Color(1.0, 0.86, 0.62, bloom * 0.35))


## Where on the screen the light came from.
##
## Clamped inside the frame rather than allowed to run off it: a flash that went
## off behind you is still one you saw, and the bloom belongs on the edge it came
## from instead of somewhere you cannot see it. Falls back to the middle when
## there is no camera or no recorded origin, which is what a flash with no
## direction to it should look like anyway.
func _flash_centre() -> Vector2:
	var from: Vector2 = _player.flash_from
	if not from.is_finite():
		return size * 0.5
	var camera := get_viewport().get_camera_2d()
	if camera == null or camera.zoom.x <= 0.0 or camera.zoom.y <= 0.0:
		return size * 0.5
	var at := (from - camera.get_screen_center_position()) * camera.zoom + size * 0.5
	var margin := size * 0.15
	return Vector2(
		clampf(at.x, margin.x, size.x - margin.x),
		clampf(at.y, margin.y, size.y - margin.y))


## Player health, bottom centre, plus the aim state so it is obvious at a glance
## whether the tighter cone is currently in effect.
func _draw_health() -> void:
	var bar := Rect2(Vector2(size.x * 0.5 - 130.0, size.y - MARGIN - 22.0), Vector2(260.0, 14.0))
	draw_rect(Rect2(bar.position - Vector2(3, 3), bar.size + Vector2(6, 6)), PANEL_BG)
	draw_rect(bar, Color(0.16, 0.18, 0.22))

	# What you have to spend, and what is being spent on you, in both states.
	#
	# These four used to live inside _draw_downed, so the ultimate, the throwables,
	# the overload timer and the loot prompt were only ever on screen while you
	# were lying on the floor - which is the one state in which none of them can
	# be used. Standing up you had no idea whether your ultimate was charged.
	if _player.overload_left > 0.0:
		_draw_overload()
	if _player.projection_left > 0.0:
		_draw_projection()
	_draw_gadgets()
	if _player.bow_out:
		_draw_bow_meter(bar.position + Vector2(0.0, -52.0), bar.size.x)
	_draw_loot_prompt(bar.position.y - 34.0)

	if _player.is_downed:
		_draw_downed(bar)
		_draw_recon_pings()
		if _player.extracting:
			_draw_extraction(_player.extracting)
		_draw_flash()
		return

	var fraction := clampf(_player.health / maxf(_player.max_health, 1.0), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)),
		BAD.lerp(GOOD, fraction))
	draw_string(_font, Vector2(bar.position.x, bar.position.y - 6.0),
		"%d HP" % roundi(_player.health), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)

	_draw_injuries(bar)

	if not _player.is_alive:
		draw_string(_font, Vector2(bar.position.x, bar.position.y - 6.0), "DOWN",
			HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x, 12, LOW_AMMO)
	elif _player.crouch > 0.5:
		draw_string(_font, Vector2(bar.position.x, bar.position.y - 6.0), "CROUCHED",
			HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x, 12, DIM.lerp(GOOD, _player.crouch))
	elif _player.focus > 0.05:
		draw_string(_font, Vector2(bar.position.x, bar.position.y - 6.0), "AIMED",
			HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x, 12,
			DIM.lerp(ACCENT, _player.focus))

	_draw_grapple(bar)
	_draw_recon_pings()
	if _player.extracting:
		_draw_extraction(_player.extracting)
	_draw_flash()


## Wounds, as notches under the left end of the health bar.
##
## Drawn against the bar rather than off in a corner because the two are the
## same story: the notches are why the bar is sliding, and a wound count you
## have to go looking for is a wound count nobody reads. The floor the bleed
## stops at is marked on the bar itself for the same reason - it turns "the bar
## keeps dropping" into "the bar stops there", which is the difference between
## a bug and a mechanic.
func _draw_injuries(bar: Rect2) -> void:
	if _player.injuries <= 0:
		return

	# Where the bleeding gives up, so it is obvious this is not a slow death.
	var floor_x: float = (bar.position.x + bar.size.x
		* clampf(_player.injury_floor_health / maxf(_player.max_health, 1.0), 0.0, 1.0))
	draw_line(Vector2(floor_x, bar.position.y),
		Vector2(floor_x, bar.position.y + bar.size.y), LOW_AMMO, 1.0)

	var notch := 9.0
	var gap := 4.0
	var at := Vector2(bar.position.x, bar.position.y + bar.size.y + 5.0)
	for i in _player.injuries:
		draw_rect(Rect2(at + Vector2(float(i) * (notch + gap), 0.0),
			Vector2(notch, 3.0)), LOW_AMMO)

	var label := "WOUNDED x%d" % _player.injuries
	draw_string(_font, Vector2(at.x + float(_player.injuries) * (notch + gap) + 4.0,
		at.y + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LOW_AMMO)


## Hooks in hand, as pips rather than a number - how many you have is a glance,
## not a reading, and it is checked constantly once the grapple is how you get
## around. The one coming back fills as it recharges.
func _draw_grapple(bar: Rect2) -> void:
	var pip := 11.0
	var gap := 5.0
	var total := _player.grapple_charges
	var have := _player.grapple_left
	var origin := Vector2(bar.position.x - 18.0 - total * (pip + gap), bar.position.y + 1.0)

	draw_string(_font, Vector2(origin.x, origin.y - 5.0), "HOOKS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)
	for i in total:
		var spot := Rect2(origin + Vector2(i * (pip + gap), 0.0), Vector2(pip, pip))
		draw_rect(spot, Color(0.16, 0.18, 0.22))
		if i < have:
			draw_rect(spot, ACCENT)
		elif i == have:
			# The next one back, filling from the bottom.
			var left: float = _player.grapple_recharge_left()
			var done := 1.0 - clampf(left / maxf(_player.grapple_recharge, 0.01), 0.0, 1.0)
			draw_rect(Rect2(spot.position + Vector2(0.0, spot.size.y * (1.0 - done)),
				Vector2(spot.size.x, spot.size.y * done)), Color(ACCENT, 0.45))
		draw_rect(spot, Color(DIM, 0.6), false, 1.0)

	if _player.is_grappling():
		draw_string(_font, Vector2(origin.x, origin.y + pip + 12.0), "E  let go",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ACCENT)


## The bar while you are on the floor. Deliberately not the health bar with a
## different number in it: what it measures has changed, so it should not look
## like the same meter running low. Red, pulsing, and labelled with the only
## thing you can still do about it.
func _draw_downed(bar: Rect2) -> void:
	var left := clampf(_player.down_health_left / maxf(_player.down_health, 1.0), 0.0, 1.0)
	var pulse := 0.62 + 0.38 * sin(Time.get_ticks_msec() * 0.009)

	# Hatched rather than solid, so it reads as damage you are absorbing rather
	# than health you are spending.
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, bar.size.y)),
		Color(0.86, 0.18, 0.2, pulse))
	draw_rect(bar, Color(1.0, 0.35, 0.35, 0.7), false, 1.0)

	draw_string(_font, Vector2(bar.position.x, bar.position.y - 6.0), "DOWNED",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.4, 0.4, pulse))
	# Seconds, not a fraction. The bar is draining whether or not anyone shoots
	# you, so the useful number is how long you have - and it is the thing every
	# decision from here depends on.
	var left_seconds := _player.seconds_down_left()
	var label := "BLEEDING OUT" if is_inf(left_seconds) else "%.1fs" % left_seconds
	draw_string(_font, Vector2(bar.position.x, bar.position.y - 6.0), label,
		HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x, 13, Color(1.0, 0.45, 0.45, pulse))
	# The instruction matters more than the number here: the first time this
	# happens you need to know the run is not over. Given the full screen width
	# to centre in rather than the bar's - the line is wider than the bar, and
	# centring it in 260 px simply cut the end off.
	# Carrying a stim changes what this moment is - from counting down to
	# deciding - so the line says so, and says how many are left. Without the
	# count you cannot tell your last one from your fifth.
	var stims: int = _player.revives_left()
	if stims > 0:
		draw_string(_font, Vector2(0.0, bar.end.y + 15.0),
			"H  get up  (%d stim%s)        A / D  crawl" % [stims, "" if stims == 1 else "s"],
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.6, 0.95, 0.7, 0.95))
	else:
		draw_string(_font, Vector2(0.0, bar.end.y + 15.0),
			"A / D  crawl        no weapon        you are bleeding out",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.85, 0.55, 0.55, 0.85))


## Everyone the recon arrow painted, marked wherever they are - through walls,
## through the dark, and pinned to the edge of the screen when they are off it.
## A reveal you cannot see is not a reveal.
func _draw_recon_pings() -> void:
	var vision := get_tree().get_first_node_in_group(&"vision_system")
	if vision == null:
		return
	var canvas := get_viewport().get_canvas_transform()
	var margin := 28.0

	for node in get_tree().get_nodes_in_group(&"hideable"):
		var target := node as Node2D
		if target == null or not vision.is_revealed(target):
			continue

		var at := canvas * target.global_position
		var off_screen := at.x < margin or at.x > size.x - margin \
			or at.y < margin or at.y > size.y - margin
		at.x = clampf(at.x, margin, size.x - margin)
		at.y = clampf(at.y, margin, size.y - margin)

		var tint := RECON if not off_screen else Color(RECON.r, RECON.g, RECON.b, 0.7)
		# A diamond, so it reads as a marker rather than as part of the world.
		var points := PackedVector2Array([
			at + Vector2(0.0, -11.0), at + Vector2(9.0, 0.0),
			at + Vector2(0.0, 11.0), at + Vector2(-9.0, 0.0)])
		draw_polyline(points + PackedVector2Array([at + Vector2(0.0, -11.0)]),
			tint, 1.5, true)
		if off_screen:
			draw_circle(at, 3.0, tint)


## You have been painted, and somebody is watching you through a wall right now.
##
## Deliberately the loudest thing the HUD ever draws. Everything else here is a
## readout you consult; this is the one message that is worth interrupting you
## for, because it is only actionable for the few seconds it is up - the whole
## value of knowing is that you can be somewhere else by the time they arrive.
##
## Above the middle rather than on it: the reticle and whatever you are aiming at
## are the things you should be looking at while you read this.
func _draw_scanned() -> void:
	var t := _scanned_left / SCANNED_TIME
	# Snaps to full and falls away, so it arrives as an alarm rather than fading
	# up politely from nothing.
	var alpha := clampf(t * 1.6, 0.0, 1.0)
	# A slow pulse underneath, so it reads as live rather than as a still frame.
	var pulse := 0.82 + 0.18 * sin(_scanned_left * 12.0)
	var centre := size.x * 0.5
	var y := size.y * 0.3

	var text := "SCANNED"
	var big := 62
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var box := Rect2(Vector2(centre - width * 0.5 - 30.0, y - 54.0),
		Vector2(width + 60.0, 96.0))
	draw_rect(box, Color(0.05, 0.09, 0.12, 0.72 * alpha))
	draw_rect(box, Color(RECON.r, RECON.g, RECON.b, alpha * pulse), false, 2.0)

	draw_string(_font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x,
		big, Color(RECON.r, RECON.g, RECON.b, alpha * pulse))
	draw_string(_font, Vector2(0.0, y + 26.0), "they can see you - move",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(TEXT.r, TEXT.g, TEXT.b, alpha * 0.9))


## Standing in an exit: a bar that fills while you hold the ground. It empties
## twice as fast as it fills if you step out, so leaving early costs you.
func _draw_extraction(point) -> void:
	var box := Rect2(Vector2(size.x * 0.5 - 150.0, 190.0), Vector2(300.0, 44.0))
	draw_rect(box, PANEL_BG)
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), GOOD)
	draw_string(_font, box.position + Vector2(14.0, 20.0), "EXTRACTING - hold this ground",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOOD)
	var bar := Rect2(box.position + Vector2(14.0, 28.0), Vector2(box.size.x - 28.0, 8.0))
	draw_rect(bar, Color(0.16, 0.18, 0.22))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * point.progress(), bar.size.y)), GOOD)


## Overload running: a banner, a countdown and a rim of colour around the whole
## screen. It lasts eight seconds and changes how the gun behaves, so it should
## be impossible to forget that it is on.
## Seconds left of whichever ultimate is currently burning, or 0.
##
## One number rather than one per gadget. Only one ultimate can be equipped, so
## only one can ever be running, and the tile at the bottom of the screen asks
## the same question of all of them: is this thing doing something right now.
func _ult_left() -> float:
	if _player == null:
		return 0.0
	return maxf(_player.overload_left, _player.projection_left)


## What colour to say it in. Overload is a fire; a projection is a picture.
func _ult_colour() -> Color:
	return PROJECTION if _player and _player.projection_left > 0.0 else OVERLOAD


func _draw_overload() -> void:
	var left: float = _player.overload_left
	var span := maxf(_overload_span, 0.01)
	var fraction := clampf(left / span, 0.0, 1.0)

	# A border rather than a wash, so the middle of the screen stays readable.
	var rim := Color(1.0, 0.62, 0.2, 0.16 + 0.12 * sin(Time.get_ticks_msec() * 0.008))
	var thickness := 10.0
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, thickness)), rim)
	draw_rect(Rect2(Vector2(0.0, size.y - thickness), Vector2(size.x, thickness)), rim)
	draw_rect(Rect2(Vector2.ZERO, Vector2(thickness, size.y)), rim)
	draw_rect(Rect2(Vector2(size.x - thickness, 0.0), Vector2(thickness, size.y)), rim)

	var box := Rect2(Vector2(size.x * 0.5 - 130.0, 132.0), Vector2(260.0, 52.0))
	draw_rect(box, PANEL_BG)
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), OVERLOAD)
	draw_string(_font, box.position + Vector2(14.0, 20.0), "OVERLOAD",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, OVERLOAD)
	draw_string(_font, box.position + Vector2(14.0, 36.0), "faster, and further off the ground",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	draw_string(_font, box.position + Vector2(0.0, 20.0), "%.1fs" % left,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 15, TEXT)

	var bar := Rect2(box.position + Vector2(14.0, 42.0), Vector2(box.size.x - 28.0, 6.0))
	draw_rect(bar, Color(0.16, 0.18, 0.22))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), OVERLOAD)


## The ghost, while it is out.
##
## Deliberately quieter than Overload's banner: no border round the screen, no
## pulse. Overload is something happening to you and wants to be felt; a
## projection is something happening somewhere else, and the whole point of it is
## that you have gone the other way. What you need off it is the two numbers -
## how long it has left, and how many rounds it has taken - because between them
## they tell you whether anybody has found it yet, which is the only thing that
## decides whether your own next move is safe.
func _draw_projection() -> void:
	var left: float = _player.projection_left
	var span := maxf(_overload_span, 0.01)

	var box := Rect2(Vector2(size.x * 0.5 - 130.0, 132.0), Vector2(260.0, 52.0))
	draw_rect(box, PANEL_BG)
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), PROJECTION)
	draw_string(_font, box.position + Vector2(14.0, 20.0), "PROJECTION",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, PROJECTION)
	draw_string(_font, box.position + Vector2(0.0, 20.0), "%.1fs" % left,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 15, TEXT)

	# Asked of the ghost itself rather than tracked here. It is the caster's own
	# machine that owns the body, so the count is sitting in the level already
	# and does not need a second copy kept in step with it.
	var ghost := Net.projection_for(Net.peer_id())
	var note := "walking, unshot"
	var tint := DIM
	if ghost == null:
		note = "gone"
		tint = LOW_AMMO
	elif ghost.hits > 0:
		var spare: int = maxi(ghost.max_hits - ghost.hits, 0)
		note = "found - %d round%s left in it" % [spare, "" if spare == 1 else "s"]
		tint = LOW_AMMO
	draw_string(_font, box.position + Vector2(14.0, 36.0), note,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)

	var bar := Rect2(box.position + Vector2(14.0, 42.0), Vector2(box.size.x - 28.0, 6.0))
	draw_rect(bar, Color(0.16, 0.18, 0.22))
	draw_rect(Rect2(bar.position,
		Vector2(bar.size.x * clampf(left / span, 0.0, 1.0), bar.size.y)), PROJECTION)


## What you have to spend, along the bottom beside the health bar: the ultimate
## and both throwables, always, whatever state you are in.
##
## Laid out as three tiles in a row rather than a stacked panel in the corner.
## They are three answers to one question - can I do something about this right
## now - so they should be read in one sweep, and the bottom edge next to your
## own health is where the eye already is.
##
## While an ultimate is running this shows the seconds it has left rather than
## its charge. A charge bar is a question about the future and a duration is a
## question about right now, and once overload is burning, right now is the only
## thing worth a number.
func _draw_gadgets() -> void:
	var kit: Inventory = _player.inventory
	if kit == null:
		return

	# Wide enough for the longest pairing it has to hold: a six-letter short name
	# on the left and READY on the right, which at 126 printed one through the
	# other.
	var tile := Vector2(142.0, 44.0)
	var gap := 8.0
	# Anchored to the right of the health bar, which is centred - so the two read
	# as one strip across the bottom rather than as furniture in a corner.
	#
	# With thumbs, the right of the bar is the aim stick's corner, so the row
	# moves to sit centred *above* the bar instead. Same strip, stacked.
	var row := tile.x * Inventory.THROWABLE_SLOTS + (tile.x + gap * 2.0)
	var origin := Vector2(size.x * 0.5 - row * 0.5, size.y - MARGIN - tile.y - 56.0) \
		if PlayerInput.is_touch() \
		else Vector2(size.x * 0.5 + 150.0, size.y - MARGIN - tile.y)

	var ult: Item = kit.ultimate
	var burning := _ult_left()
	var running := burning > 0.0
	var lit := _ult_colour()
	var ready := ult != null and ult.charge >= 1.0
	var box := Rect2(origin, tile)
	draw_rect(box, PANEL_BG)
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)),
		lit if running else (ACCENT if ready else Color(DIM, 0.5)))

	if ult == null:
		draw_string(_font, box.position + Vector2(12.0, 18.0), "Q",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		draw_string(_font, box.position + Vector2(30.0, 18.0), "no ultimate",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(DIM, 0.8))
	else:
		draw_string(_font, box.position + Vector2(12.0, 18.0), "Q",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		draw_string(_font, box.position + Vector2(30.0, 18.0), ult.gadget.short_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			lit if running else (ACCENT if ready else TEXT))
		var idle := "READY" if ready else "%d%%" % roundi(ult.charge * 100.0)
		var right := "%.1fs" % burning if running else idle
		draw_string(_font, box.position + Vector2(0.0, 18.0), right,
			HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 12.0, 12,
			lit if running else (ACCENT if ready else DIM))

		# Draining while it runs, filling while it charges. Same bar either way,
		# because it is the same question asked from the two ends.
		var spent := clampf(burning / maxf(_overload_span, 0.01), 0.0, 1.0)
		var fraction := spent if running else clampf(ult.charge, 0.0, 1.0)
		var bar := Rect2(box.position + Vector2(12.0, 28.0), Vector2(box.size.x - 24.0, 6.0))
		draw_rect(bar, Color(0.16, 0.18, 0.22))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)),
			lit if running else (ACCENT if ready else Color(0.45, 0.62, 0.75)))

	for i in Inventory.THROWABLE_SLOTS:
		var item: Item = kit.get_throwable(i)
		var slot := Rect2(origin + Vector2((tile.x + gap) * (i + 1), 0.0), tile)
		draw_rect(slot, PANEL_BG)
		draw_rect(Rect2(slot.position, Vector2(3.0, slot.size.y)),
			ACCENT if item else Color(DIM, 0.5))
		draw_string(_font, slot.position + Vector2(12.0, 18.0), "G" if i == 0 else "T",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		draw_string(_font, slot.position + Vector2(30.0, 18.0),
			item.gadget.short_name if item else "empty",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT if item else Color(DIM, 0.8))
		if item:
			# The count is the whole reason to look: a throwable you have run out
			# of is worse than one you never bought, because you plan around it.
			draw_string(_font, slot.position + Vector2(0.0, 33.0), "x%d" % item.count,
				HORIZONTAL_ALIGNMENT_RIGHT, slot.size.x - 12.0, 14, ACCENT)


## How far the bow is drawn. Worth its own bar: a bow you cannot see the draw on
## is a bow you will always loose too early.
func _draw_bow_meter(at: Vector2, width: float) -> void:
	var bar := Rect2(at, Vector2(width, 10.0))
	draw_rect(Rect2(bar.position - Vector2(3, 3), bar.size + Vector2(6, 6)), PANEL_BG)
	draw_rect(bar, Color(0.16, 0.18, 0.22))
	var full := _player.bow_drawn >= 1.0
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * _player.bow_drawn, bar.size.y)),
		ACCENT if full else Color(0.55, 0.85, 0.95))
	draw_string(_font, Vector2(bar.position.x, bar.position.y - 5.0),
		"RECON BOW - hold to draw" if not full else "RECON BOW - full draw",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ACCENT if full else DIM)


## "F  search body: AR, 48 rounds" while standing over one, and for a moment
## afterwards, what you actually took. Sits above the health bar rather than at
## the body, so it is always in the same place and never behind the player.
func _draw_loot_prompt(y: float) -> void:
	var body = _player.loot_target
	var text := ""
	if body != null and is_instance_valid(body):
		# The key is not the control on a phone - the LOOT button that appears
		# over the thumb is - so the caption names whichever one is true.
		text = ("LOOT    %s" if PlayerInput.is_touch() else "F    search %s") 			% body.get_prompt()
	elif _player.loot_message_left > 0.0:
		text = _player.loot_message
	if text.is_empty():
		return

	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var box := Rect2(Vector2(size.x * 0.5 - width * 0.5 - 12.0, y - 20.0),
		Vector2(width + 24.0, 28.0))
	draw_rect(box, PANEL_BG)
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), ACCENT)
	draw_string(_font, Vector2(box.position.x + 12.0, y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT)


## The two hands, then whatever is riding in the bags, keyed 1-5. The full grids
## are the inventory screen's job; this is only the quick reference above the
## weapon panel.
func _draw_slots(at: Vector2) -> void:
	var kit: Inventory = _player.inventory
	if kit == null:
		return
	var x := at.x
	# Hands only: guns in the bags cannot be brought out with a key, so listing
	# them here would advertise a shortcut that does not exist.
	var entries: Array = [kit.primary, kit.secondary]

	for i in entries.size():
		var item: Item = entries[i]
		var in_hand := i == _weapon.slot and i <= Inventory.Slot.SECONDARY
		var text := "%d %s" % [i + 1, item.weapon.short_name if item else "-"]
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16.0
		var box := Rect2(Vector2(x, at.y - 16.0), Vector2(width, 22.0))
		draw_rect(box, _fade(ACCENT if in_hand else PANEL_BG))
		draw_string(_font, Vector2(x + 8.0, at.y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			_fade(Color(0.08, 0.09, 0.11) if in_hand else (TEXT if item else DIM)))
		x += width + 6.0
