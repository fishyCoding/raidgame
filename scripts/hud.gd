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
## A scope catching the light. Nearly white on purpose - every other marker on
## this HUD is a tinted symbol you read, and this one is meant to be mistaken
## for something in the world for the half second before you understand it.
const GLINT := Color(0.92, 0.97, 1.0, 1.0)
const PROJECTION := Color(0.62, 0.78, 1.0)
## A headcount, on the screen of the man running one. Cold green, and the only
## green on this HUD that is not the health bar - it is the one readout that is
## about other people rather than about you.
const HEADCOUNT := Color(0.58, 0.94, 0.72)
## And on the screen of somebody being counted. The same hue washed most of the
## way out, because it is never drawn as a symbol - only as light on the glass.
const WATCHED := Color(0.62, 0.84, 0.76)
## The route line while a decoy is being placed. Red, and the only red on the
## screen that is not damage - it is a claim about where a body is going to walk,
## and it should read as a line drawn on a map rather than as part of the ghost.
const ROUTE_LINE := Color(0.95, 0.26, 0.24)

## Placing a screen: workable, and not.
const SCREEN_OK := Color(0.62, 0.86, 1.0)
const SCREEN_BAD := Color(0.95, 0.36, 0.32)

## The same planner the ghost walks with, so the drawn route and the walked route
## are one piece of code. See decoy_route.gd.
## The same surveyed map the decoy walks by, so the line and the walk are the
## same answer to the same question rather than two guesses that agree by luck.
const MAP := preload("res://scripts/decoy_map.gd")

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

## Inside this, a scope is not throwing you a glint - it is a man in the room
## with you.
const GLINT_MIN_RANGE := 620.0
## How near his aim has to be to you before the glass shows, radians. Was 0.10,
## about six degrees, which meant the mark appeared at roughly the moment he was
## ready to fire - technically fair and useless in practice, because the thing
## you want is not to be told you are being shot, it is a chance not to be.
const GLINT_AIM_CONE := 0.22
## And how near yours has to be to him before you catch it. Wide enough that
## sweeping a skyline finds it, rather than requiring you to have already
## guessed which window he is in.
const GLINT_LOOK_CONE := 0.85
## How far in from the edge an off-screen glint is pinned.
const GLINT_MARGIN := 26.0

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

## Seconds left of the mark a Headcount leaves on your screen. Kept here for the
## same reason _scanned_left is: it is a thing on a screen and nothing else, and
## dying should not leave it frozen mid-fade.
var _watched_left := 0.0

## How long that mark lingers after the last tap.
##
## Longer than Player.COUNT_PING, so a count that is still running draws as one
## unbroken swell rather than a strobe at the tick rate - and short enough that
## walking out of somebody's reach clears your screen in about a second, with no
## second message ever having to be sent to say you have gone.
const WATCHED_FADE := 1.35
## How far in from the edge the vignette reaches, as a fraction of the shorter
## side.
##
## A rim, not a wash. It was nearly a quarter of the screen deep, which put a
## green haze over the ground you actually fight on; pulled back to a band round
## the frame, and then back again to a hairline of one, it is something you catch
## rather than something you are shown.
const WATCHED_DEPTH := 0.065
## How dark that rim gets at the top of its breath.
##
## Low on purpose, and lower than it was. The counted player is not being warned,
## they are being given a feeling - and a feeling that is legible enough to read
## off is one they can act on precisely, which is exactly what the counter did
## not pay for. At this strength it is plainly there while you are still, and
## easy to lose while you are shooting, which is the right way round.
const WATCHED_PEAK := 0.17
## Seconds for the sweep line to cross the screen once.
##
## Slower than it was. A sweep you can time is a clock, and this should read as
## something passing over you rather than as an instrument with a period.
const WATCHED_SWEEP := 4.6

## The dial's radius on screen.
##
## Distance is not drawn at all. Every contact sits on this same ring whether it
## is a room away or on the far edge of reach - the gadget answers "which way",
## and a mark that crept inwards as somebody closed would answer "how far", which
## is most of a firing solution.
const COUNT_RING := 104.0

## How wide a mark is drawn, in radians, and how it fades out at the ends.
##
## The dial used to snap: twelve wedges, then eight, then four, with each contact
## rounded into the nearest one. Every step made it vaguer and every step made it
## worse, and quadrants made the fault plain - walking half the length of a
## building does not change which quadrant somebody is in, so the mark sat dead
## still while the world moved and read as a broken instrument rather than as a
## coarse one. Snapping cannot be the source of the vagueness, because a mark
## that only moves when it crosses a seam is a mark that is wrong right up until
## it jumps.
##
## So there are no sectors any more. A mark is centred on the live bearing and
## slides with it, and the vagueness is in its *width*: a band this wide has no
## point on it to aim along, and it is drawn flat rather than bright in the
## middle precisely so that its centre is not a reading. What you can take off it
## is a side of the compass, which is what was paid for.
##
## CORE is the flat middle, FLANK and FRINGE the two dimmer steps either side of
## it - together about a hundred and thirty degrees, a bit over a third of the
## ring, with soft ends so nothing about it looks measured.
const COUNT_CORE := 0.42
const COUNT_FLANK := 0.80
const COUNT_FRINGE := 1.14
## How far the drawn bearing wanders off the true one, radians, and how fast.
##
## Because a soft-ended band centred exactly on somebody is still centred exactly
## on somebody, and a patient player would learn to read the middle of it. The
## wobble is per-contact and slow - a long, shallow drift rather than a shake, so
## the mark still tracks anybody who is actually moving and still cannot be
## averaged out inside the fifteen seconds the count lasts.
const COUNT_WOBBLE := 0.22
const COUNT_WOBBLE_RATE := 0.31


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
		_player.counted.connect(_on_counted)


## Characters arrive after the level does now - spawned per peer rather than
## placed in the scene - so the HUD waits to be told which one is ours.
func _on_player_spawned(body: Node) -> void:
	if body != Net.local_player:
		return
	_player = body
	_weapon = _player.weapon
	if not _player.scanned.is_connected(_on_scanned):
		_player.scanned.connect(_on_scanned)
	if not _player.counted.is_connected(_on_counted):
		_player.counted.connect(_on_counted)


func _on_scanned() -> void:
	_scanned_left = SCANNED_TIME


func _on_counted() -> void:
	_watched_left = WATCHED_FADE


func _process(delta: float) -> void:
	# The bar needs the full duration, and only the player knows it - catch it on
	# the frame it starts rather than hard-coding eight seconds here.
	if _player and _ult_left() > _overload_span:
		_overload_span = _ult_left()
	_scanned_left = maxf(_scanned_left - delta, 0.0)
	_watched_left = maxf(_watched_left - delta, 0.0)
	queue_redraw()


## Panel colours run through this, so the whole readout can step back while you
## are aiming without touching the health bar or the reticle.
func _fade(color: Color) -> Color:
	return Color(color.r, color.g, color.b, color.a * _panel_fade)


func _draw() -> void:
	# Both of these before every early return below them, and the vignette under
	# the banner. Being watched is worth knowing whether you are holding a gun,
	# holding nothing, or lying on the floor bleeding - and on the floor it is
	# the most useful thing on the screen, because it means somebody is on their
	# way.
	if _watched_left > 0.0:
		_draw_watched()
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
	var at := _to_screen(from)
	if not at.is_finite():
		return size * 0.5
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
	# Not while you are on the floor. The clock is frozen down there along with
	# the rest of your kit - see Player._charge_ultimate - and a dial that has
	# stopped turning is worse than none, because every bearing on it is where
	# somebody was standing at the moment you were shot.
	if _player.count_left > 0.0 and not _player.is_downed:
		_draw_headcount()
	if _player.projection_aiming:
		_draw_projection_aim()
	if _player.screen_aiming:
		_draw_screen_aim()
	_draw_gadgets()
	if _player.bow_out:
		_draw_bow_meter(bar.position + Vector2(0.0, -52.0), bar.size.x)
	_draw_loot_prompt(bar.position.y - 34.0)

	if _player.is_downed:
		_draw_downed(bar)
		_draw_recon_pings()
		_draw_sniper_glints()
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
	_draw_using(bar)

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
	_draw_sniper_glints()
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


## The kit in your hands, filling up. Drawn over the health bar rather than
## beside it, because for as long as it is there it is the more urgent of the
## two numbers: it is the seconds you are choosing to spend not shooting back.
func _draw_using(bar: Rect2) -> void:
	if _player.using == Player.Using.NONE:
		return
	var strip := Rect2(bar.position + Vector2(0.0, -22.0), Vector2(bar.size.x, 6.0))
	draw_rect(strip, Color(0.1, 0.12, 0.15, 0.9))
	draw_rect(Rect2(strip.position,
		Vector2(strip.size.x * _player.use_progress(), strip.size.y)), GOOD)
	var what := "PATCHING UP"
	if _player.using == Player.Using.SURGICAL:
		what = "STITCHING"
	elif _player.using == Player.Using.REPAIR:
		what = "REPAIRING"
	draw_string(_font, strip.position + Vector2(0.0, -4.0), what,
		HORIZONTAL_ALIGNMENT_LEFT, strip.size.x, 11, GOOD)
	draw_string(_font, strip.position + Vector2(0.0, -4.0),
		"%.1fs" % maxf(_player.use_left, 0.0),
		HORIZONTAL_ALIGNMENT_RIGHT, strip.size.x, 11, DIM)


## A scope, pointed at you, from somewhere you happen to be looking.
##
## Three things have to be true at once, and the third is what makes it a
## mechanic rather than a warning light. They have to be looking down a scope
## (Player.scoped, one replicated bit); they have to be looking at *you*; and you
## have to be looking back at them. The sniper is not told any of this - the
## price of the shot is that taking it puts a mark on the map for exactly the
## person who is in a position to do something about it, and only for them.
##
## Pinned to the edge of the screen when he is off it, the way a recon ping is.
## It used to be dropped in that case, on the theory that a glint is light and
## has to reach your eye - which was tidy and made the mechanic worthless in the
## one situation it exists for. The camera pulls *back* while you are aiming, so
## a rifle far enough away to be dangerous is routinely outside the frame, and a
## warning you only get once the man is already on screen is not a warning.
##
## What replaces the on-screen test is a real one: the line between the two of
## you has to be clear. Light travels in straight lines, so a scope behind a
## wall, inside smoke, or on the far side of a screen throws you nothing - which
## the old version got wrong in the more alarming direction, marking snipers
## through solid geometry.
func _draw_sniper_glints() -> void:
	if _player == null or not _player.is_alive:
		return
	var canvas := get_viewport().get_canvas_transform()
	var clock := Time.get_ticks_msec() * 0.001
	var vision := get_tree().get_first_node_in_group(&"vision_system")

	for node in get_tree().get_nodes_in_group(&"player"):
		var them := node as Player
		if them == null or them == _player or not them.scoped or not them.is_alive:
			continue

		# Close up there is no glint to catch, he has to have picked you out, and
		# you have to be looking back - all three in Player.glint_shows, which is
		# where they can be tested.
		if not Player.glint_shows(them.global_position, them.aim_angle,
				_player.global_position, _player.aim_angle,
				GLINT_MIN_RANGE, GLINT_AIM_CONE, GLINT_LOOK_CONE):
			continue

		# Light travels in straight lines. Asked of the vision system rather
		# than worked out here, and asked with line_is_clear rather than is_seen,
		# because is_seen gives up past the corner of the screen and this mark
		# is at its most useful well beyond that.
		if vision != null and not vision.line_is_clear(
				_player.global_position, them.global_position):
			continue

		var at := canvas * them.global_position
		var off_screen := (at.x < GLINT_MARGIN or at.x > size.x - GLINT_MARGIN
			or at.y < GLINT_MARGIN or at.y > size.y - GLINT_MARGIN)
		at.x = clampf(at.x, GLINT_MARGIN, size.x - GLINT_MARGIN)
		at.y = clampf(at.y, GLINT_MARGIN, size.y - GLINT_MARGIN)

		# Off and on rather than a steady lamp: glass catches the light as it
		# moves, and a mark that blinks is one you notice in the corner of a
		# screen you are already busy reading.
		var pulse := 0.45 + 0.55 * absf(sin(clock * 7.0))
		# Dimmer against the edge, because a pinned mark is a bearing rather
		# than a place: it says which way he is, and pretending to a position it
		# does not have would send you looking at the wrong window.
		var reach := GLINT.a * pulse * (0.62 if off_screen else 1.0)
		var tint := Color(GLINT.r, GLINT.g, GLINT.b, reach)
		var arm := 7.0 + 4.0 * pulse
		draw_line(at - Vector2(arm, 0.0), at + Vector2(arm, 0.0), tint, 1.0, true)
		draw_line(at - Vector2(0.0, arm), at + Vector2(0.0, arm), tint, 1.0, true)
		var corner := arm * 0.38
		draw_line(at - Vector2(corner, corner), at + Vector2(corner, corner),
			Color(tint.r, tint.g, tint.b, tint.a * 0.5), 1.0, true)
		draw_line(at - Vector2(corner, -corner), at + Vector2(corner, -corner),
			Color(tint.r, tint.g, tint.b, tint.a * 0.5), 1.0, true)
		draw_circle(at, 2.0 + pulse, tint)


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


## A headcount running: how many people are inside it, and roughly where.
##
## Two pieces, and the split between them is the whole design. A tally, which is
## exact - the number is the thing you paid for, and "three" and "one" are
## different plans. And a dial, which is not: a ring around your own feet with a
## wide soft band on it for each person in reach, no distance in it at all, and
## no point on any band you could take a bearing off. A man on the boundary and a
## man in the next room are drawn the same way.
##
## Coarse on purpose. It is bought to answer "is that building empty" before you
## commit to crossing open ground, and an instrument that answered it precisely
## enough to shoot from would replace the crossing rather than inform it.
##
## Everything here is recomputed at draw time off live positions rather than
## cached at the ping. The taps that go out to the people being counted are on a
## clock because they cost traffic; a picture on your own screen costs nothing,
## and a dial lagging half a second behind the man walking past you is worse
## than no dial.
func _draw_headcount() -> void:
	var contacts: Array = _player.headcount_contacts()
	var clock := Time.get_ticks_msec() * 0.001
	# The last second dims rather than cutting out, so the dial reads as running
	# down instead of as having been switched off by something.
	var fade := clampf(_player.count_left, 0.0, 1.0)

	_draw_count_dial(clock, fade)

	# Above the slot the overload and projection banners share, so two ultimates
	# running at once do not print through each other.
	var box := Rect2(Vector2(size.x * 0.5 - 130.0, 76.0), Vector2(260.0, 46.0))
	var lit := Color(HEADCOUNT.r, HEADCOUNT.g, HEADCOUNT.b, fade)
	draw_rect(box, Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, PANEL_BG.a * fade))
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), lit)
	draw_string(_font, box.position + Vector2(14.0, 20.0), "HEADCOUNT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, lit)
	draw_string(_font, box.position + Vector2(0.0, 20.0), "%.1fs" % _player.count_left,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 15,
		Color(TEXT.r, TEXT.g, TEXT.b, fade))

	# The number is the readout. An empty count is worth saying in words rather
	# than as a nought, because "nobody" is the answer that changes what you do
	# next and it should not have to be read off a digit.
	var heard := contacts.size()
	var note := "nobody within reach"
	if heard > 0:
		note = "%d other%s within reach" % [heard, "" if heard == 1 else "s"]
	draw_string(_font, box.position + Vector2(14.0, 36.0), note,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(DIM.r, DIM.g, DIM.b, fade) if heard == 0 else lit)

	var bar := Rect2(box.position + Vector2(14.0, 40.0), Vector2(box.size.x - 28.0, 4.0))
	draw_rect(bar, Color(0.16, 0.18, 0.22, fade))
	var span: float = maxf(_ult_span(GadgetData.Kind.HEADCOUNT), 0.01)
	draw_rect(Rect2(bar.position, Vector2(
		bar.size.x * clampf(_player.count_left / span, 0.0, 1.0), bar.size.y)), lit)


## Where the dial is putting its marks, right now, in radians.
##
## Public and kept out of the drawing for the same reason flash_core_radius is:
## "does it point the right way" is the thing worth asserting about a compass,
## and it is not a question a headless run can answer by looking at a canvas.
##
## Zero is due east and they run clockwise on screen, because screen y is down -
## so straight up is -PI/2, not PI/2.
##
## These are the *drawn* bearings, wobble and all, rather than the true ones.
## That is the point of the function: the thing worth pinning down is that the
## mark follows a man who moves and still never sits exactly on him, and both
## halves of that are lost if this hands back the honest angle and the lying one
## is buried in a draw call.
func count_bearings() -> Array[float]:
	var marks: Array[float] = []
	if _player == null:
		return marks
	var clock := Time.get_ticks_msec() * 0.001
	for body in _player.headcount_contacts():
		# World angles, not screen ones. The camera in this game never rotates,
		# so the two agree - and a world delta is one subtraction rather than two
		# projections, one of which can fail when there is no camera yet.
		var offset: Vector2 = body.global_position - _player.global_position
		marks.append(offset.angle() + _wobble(body, clock))
	return marks


## The lie told about one contact's bearing, in radians.
##
## Seeded off the body so two people are wrong in different directions, and off a
## slow clock so each one's error drifts instead of sitting still. Sine rather
## than noise because it wants to be smooth: a bearing that jitters frame to
## frame reads as a rendering fault, and this has to read as an instrument that
## is honestly imprecise.
func _wobble(body: Node, clock: float) -> float:
	var seed := float(body.get_instance_id() % 1000) * 0.017
	return COUNT_WOBBLE * sin(clock * COUNT_WOBBLE_RATE * TAU + seed)


## The bearings, as bands of light on a ring around your own feet.
##
## Drawn on the character rather than in a corner of the screen, because every
## angle on it is measured from where you are standing - a compass parked in the
## corner would be read against the middle of the frame, which is not where you
## are once the camera leans out to aim.
func _draw_count_dial(clock: float, fade: float) -> void:
	var here := _to_screen(_player.global_position)
	if not here.is_finite():
		return

	# The unlit ring first, faint. It is what makes a dark stretch read as
	# "checked, nobody there" instead of as a dial that has not come on yet.
	draw_arc(here, COUNT_RING, 0.0, TAU, 72,
		Color(HEADCOUNT.r, HEADCOUNT.g, HEADCOUNT.b, 0.10 * fade), 1.5, true)

	# One slow pulse across the whole dial rather than one per contact, so three
	# people read as three marks rather than as three separate flashing things
	# competing for the corner of your eye.
	var pulse := 0.72 + 0.28 * sin(clock * 3.4)
	for middle in count_bearings():
		# Outside in, and flat across the middle. A band that was brightest at
		# its centre would be a needle with a glow around it - the eye finds the
		# peak, and the peak is exactly the reading this must not give. Drawn as
		# three even steps, the only thing it says is "somewhere along here".
		_draw_count_band(here, middle, COUNT_FLANK, COUNT_FRINGE,
			0.07 * pulse * fade)
		_draw_count_band(here, middle, COUNT_CORE, COUNT_FLANK,
			0.15 * pulse * fade)
		draw_arc(here, COUNT_RING, middle - COUNT_CORE, middle + COUNT_CORE, 24,
			Color(HEADCOUNT.r, HEADCOUNT.g, HEADCOUNT.b, 0.3 * pulse * fade),
			9.0, true)


## One symmetrical pair of arcs either side of a bearing - `from` out to `to`,
## clockwise and anticlockwise. The steps of a band, drawn as two pieces because
## the middle of it is already lit by the step inside this one.
func _draw_count_band(here: Vector2, middle: float, from: float, to: float,
		alpha: float) -> void:
	var shade := Color(HEADCOUNT.r, HEADCOUNT.g, HEADCOUNT.b, alpha)
	draw_arc(here, COUNT_RING, middle + from, middle + to, 14, shade, 9.0, true)
	draw_arc(here, COUNT_RING, middle - to, middle - from, 14, shade, 9.0, true)


## Somebody near you is counting heads.
##
## The whole of what the counted are told, and it is deliberately less than the
## counter gets: no number, no bearing, no name, and not one word of text. What
## it says is "you are on somebody's list, now" - which is enough to make you
## move or make you wait, and not enough to tell you which of those is right.
##
## A vignette and a sweep, both very faint. The vignette breathes so it does not
## read as a graphics setting somebody left on; the sweep is the only part with a
## direction to it, and it is what keeps the effect from being mistaken for
## damage. You are not hurt. You are being looked for.
##
## Everything here is pitched under the threshold where you would call it an
## alert. It should be the sort of thing you notice you have been seeing, a
## second after it started - because a warning you read cleanly is one you act on
## cleanly, and the whole gadget is built on the counted player knowing something
## is happening without knowing enough to answer it.
func _draw_watched() -> void:
	var t := clampf(_watched_left / WATCHED_FADE, 0.0, 1.0)
	# About a second and a half a cycle - a breath, not a strobe. Fast enough to
	# be alive in the corner of your eye, slow enough that it never becomes the
	# thing you are looking at.
	var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0007 * TAU)
	var peak := WATCHED_PEAK * t * (0.55 + 0.45 * breath)
	var depth := minf(size.x, size.y) * WATCHED_DEPTH

	# Four trapezoids, mitred at the corners, each one shading from the edge
	# colour to nothing as it comes inwards.
	#
	# The first version of this was a stack of nested rectangle frames, which is
	# the obvious way to fake a gradient out of draw_rect and does not survive
	# being looked at: the steps between bands read as concentric rings drawn
	# round the screen, and the corners - where two frames overlap - stack into a
	# bright staircase. Per-vertex colour is the actual gradient, in four calls
	# instead of sixty, and mitring means no pixel is painted twice.
	var edge := Color(WATCHED.r, WATCHED.g, WATCHED.b, peak)
	var gone := Color(WATCHED.r, WATCHED.g, WATCHED.b, 0.0)
	var shade := PackedColorArray([edge, edge, gone, gone])
	var w := size.x
	var h := size.y
	draw_polygon(PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0),
		Vector2(w - depth, depth), Vector2(depth, depth)]), shade)
	draw_polygon(PackedVector2Array([Vector2(w, h), Vector2(0.0, h),
		Vector2(depth, h - depth), Vector2(w - depth, h - depth)]), shade)
	draw_polygon(PackedVector2Array([Vector2(0.0, h), Vector2(0.0, 0.0),
		Vector2(depth, depth), Vector2(depth, h - depth)]), shade)
	draw_polygon(PackedVector2Array([Vector2(w, 0.0), Vector2(w, h),
		Vector2(w - depth, h - depth), Vector2(w - depth, depth)]), shade)

	# The sweep. A hairline with a soft shoulder either side, crossing top to
	# bottom over and over for as long as somebody is counting. It is the only
	# part of this with a direction to it, and that is what keeps the effect from
	# reading as damage: you are not hurt, you are being looked for.
	var y := fmod(Time.get_ticks_msec() * 0.001, WATCHED_SWEEP) / WATCHED_SWEEP * h
	draw_rect(Rect2(Vector2(0.0, y - 14.0), Vector2(w, 28.0)),
		Color(WATCHED.r, WATCHED.g, WATCHED.b, 0.016 * t))
	draw_rect(Rect2(Vector2(0.0, y - 1.0), Vector2(w, 2.0)),
		Color(WATCHED.r, WATCHED.g, WATCHED.b, 0.035 * t))


## How long a gadget of this kind runs for, taken off the one actually in the
## kit. The drain bars need it and the item is the only thing that knows.
func _ult_span(kind: int) -> float:
	var box: Inventory = _player.inventory if _player else null
	if box == null:
		return 0.0
	var item := box.get_ultimate(box.slot_of_kind(kind))
	return item.gadget.active_time if item and item.gadget else 0.0


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
## Seconds left of whichever ultimate is currently burning, or 0. Used by the
## screen-wide effects, which do not care which slot a thing came out of.
func _ult_left() -> float:
	if _player == null:
		return 0.0
	return maxf(_player.overload_left, _player.projection_left)


## What colour to say it in. Overload is a fire; a projection is a picture.
func _ult_colour() -> Color:
	return PROJECTION if _player and _player.projection_left > 0.0 else OVERLOAD


## Seconds left of one particular gadget, which is the question a tile asks.
##
## Asked per item since there are two slots. It used to be one number for the
## whole screen on the grounds that only one ultimate could be equipped - true
## when it was written, and it would have lit both tiles at once now.
func _ult_running(item: Item) -> float:
	if _player == null or item == null or item.gadget == null:
		return 0.0
	match item.gadget.kind:
		GadgetData.Kind.OVERLOAD:
			return _player.overload_left
		GadgetData.Kind.PROJECTION:
			return _player.projection_left
		GadgetData.Kind.HEADCOUNT:
			return _player.count_left
	return 0.0


## The colour for one gadget, whether or not it happens to be running.
func _ult_tint(item: Item) -> Color:
	if item == null or item.gadget == null:
		return OVERLOAD
	match item.gadget.kind:
		GadgetData.Kind.PROJECTION:
			return PROJECTION
		GadgetData.Kind.HEADCOUNT:
			return HEADCOUNT
	return OVERLOAD


## The screen being placed: the line you are drawing, and its two ends.
##
## Drawn because a screen is invisible once it is up. If you cannot see it while
## you are placing it you are guessing, and a gadget you guess at is one you
## waste - you get one, and it dies to a single bullet.
##
## Amber while it is a legal sheet, red while it is not, so "too short" reads
## before you click rather than after.
func _draw_screen_aim() -> void:
	var to: Vector2 = _player.screen_to
	if not to.is_finite():
		return
	var lit: Color = SCREEN_OK if _player.screen_ok else SCREEN_BAD
	var here := _to_screen(to)
	if not here.is_finite():
		return

	var first: Vector2 = _player.screen_first
	if first.is_finite():
		var start := _to_screen(first)
		if start.is_finite():
			draw_line(start, here, Color(lit, 0.85), 3.0, true)
			draw_circle(start, 5.0, lit)
	# The loose end, always: before the first click it is the only thing there is
	# to look at, and it is what tells you the crosshair has snapped to a wall.
	draw_circle(here, 5.0, Color(lit, 0.9))


## One ultimate slot: what is in it, what it is doing, and the key that fires it.
func _draw_ult_tile(box: Rect2, ult: Item, key: String) -> void:
	var burning := _ult_running(ult)
	var running := burning > 0.0
	var lit := _ult_tint(ult)
	var ready := ult != null and ult.charge >= 1.0

	draw_rect(box, PANEL_BG)
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)),
		lit if running else (ACCENT if ready else Color(DIM, 0.5)))
	draw_string(_font, box.position + Vector2(12.0, 18.0), key,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)

	if ult == null:
		draw_string(_font, box.position + Vector2(30.0, 18.0), "empty",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(DIM, 0.8))
		return

	draw_string(_font, box.position + Vector2(30.0, 18.0), ult.gadget.short_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		lit if running else (ACCENT if ready else TEXT))

	# Dashes in hand beat a charge meter: the meter is how you get more, and the
	# number is what you can actually spend right now.
	var held := 0
	if ult.gadget.kind == GadgetData.Kind.DASH and _player:
		held = int(_player.dashes_left)
	var idle := "READY" if ready else "%d%%" % roundi(ult.charge * 100.0)
	if held > 0:
		idle = "x%d" % held
	var right := "%.1fs" % burning if running else idle
	draw_string(_font, box.position + Vector2(0.0, 18.0), right,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 12.0, 12,
		lit if running else (ACCENT if (ready or held > 0) else DIM))

	# Draining while it runs, filling while it charges. Same bar either way,
	# because it is the same question asked from the two ends.
	# The gadget's own duration rather than the remembered one. _overload_span is
	# a single high-water mark shared by every tile on the strip, so a fifteen
	# second ultimate in one slot left the eight second one beside it drawing a
	# bar pinned at full for its first seven seconds.
	var spent := clampf(burning / maxf(ult.gadget.active_time, 0.01), 0.0, 1.0)
	var fraction := spent if running else clampf(ult.charge, 0.0, 1.0)
	var bar := Rect2(box.position + Vector2(12.0, 28.0), Vector2(box.size.x - 24.0, 6.0))
	draw_rect(bar, Color(0.16, 0.18, 0.22))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)),
		lit if running else (ACCENT if ready else Color(0.45, 0.62, 0.75)))


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


## The placing view: where the click will send it, and what it is deciding
## between.
##
## Drawn on the HUD rather than in the world so it survives the concealment
## system - the point you are choosing is frequently a room you cannot currently
## see, which is most of the reason for choosing it, and a marker that vanished
## behind cover would be useless exactly when it matters.
func _draw_projection_aim() -> void:
	var spot: Vector2 = _player.projection_mark
	if not spot.is_finite():
		return
	var at := _to_screen(spot)
	if not at.is_finite():
		return

	_draw_projection_route(spot)

	var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	draw_arc(at, lerpf(16.0, 22.0, beat), 0.0, TAU, 32, PROJECTION, 2.0, true)
	draw_arc(at, 30.0, 0.0, TAU, 40, Color(PROJECTION, 0.35), 1.5, true)
	draw_line(at - Vector2(40.0, 0.0), at + Vector2(40.0, 0.0),
		Color(PROJECTION, 0.5), 1.5, true)
	draw_line(at - Vector2(0.0, 40.0), at + Vector2(0.0, 40.0),
		Color(PROJECTION, 0.5), 1.5, true)

	var hint := "click to send it here"
	if PlayerInput.is_touch():
		hint = "drag to place it, SEND to commit"
	draw_string(_font, Vector2(0.0, size.y * 0.16), hint,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(PROJECTION, 0.85))


## The route it will actually walk, in red, over the level.
##
## Not a straight line from you to the cursor. The thing that makes this control
## worth having is that a decoy sent upstairs *takes the rope* - and a straight
## line implies it flies, which is both wrong and much more useful than what
## really happens. Every corner drawn here is a corner the body turns.
##
## Computed by DecoyRoute, the same file the ghost plans with, so the two cannot
## drift apart. It is planned from where the ghost is if one is already out -
## re-sending an existing decoy is a journey from wherever it has got to, not
## from you - and from the caster otherwise.
##
## Red on purpose. Everything else this gadget draws is the pale blue that means
## "projection"; the route is the one part that is a claim about the future, and
## it wants to read as a line on a map rather than as more of the ghost.
func _draw_projection_route(to: Vector2) -> void:
	var out := Net.projection_for(Net.peer_id())
	var from: Vector2 = _player.global_position
	if out and not bool(out.get("gone")):
		from = out.global_position

	var legs: Array = MAP.route(get_tree(), from, to)
	if legs.is_empty():
		# The map says there is no way from here to there. Better to say so at
		# the far end than to draw a hopeful line to a place it cannot reach.
		_draw_route_stop(to)
		return

	for leg in legs:
		if leg.kind == "cable":
			# A rope genuinely is a straight line through the air, so this one
			# is drawn straight - and drawn heavier, because it is the part of
			# the plan worth reading. Everything else is "and then it walks".
			_draw_route_leg([leg.from, leg.to] as PackedVector2Array, 4.0, 0.9)
			_draw_route_knot(leg.from)
			_draw_route_knot(leg.to)
			continue
		if leg.kind != "walk":
			# A step up or a drop off a lip: a couple of frames of air, drawn as
			# the corner it is so the line reads as one continuous journey.
			_draw_route_leg([leg.from, leg.to] as PackedVector2Array, 2.0, 0.7)
			continue

		# A walk is not straight. Drawn along the floor the map surveyed, so the
		# line rises over a ramp and dips into a hollow instead of cutting the
		# corner - a straight segment between two points that are both on the
		# ground still goes through the ground everywhere in between.
		_draw_route_leg(MAP.walk_line(get_tree(), leg.from, leg.to), 2.0, 0.5)


## One run of the route, in screen space. Silently drops any leg the camera
## cannot place, which headless is all of them.
func _draw_route_leg(points: PackedVector2Array, width: float, alpha: float) -> void:
	if points.size() < 2:
		return
	var screen := PackedVector2Array()
	for point in points:
		var at := _to_screen(point)
		if not at.is_finite():
			return
		screen.append(at)
	draw_polyline(screen, Color(ROUTE_LINE, alpha), width, true)


## A corner it turns - getting on or off a rope.
func _draw_route_knot(world: Vector2) -> void:
	var at := _to_screen(world)
	if at.is_finite():
		draw_circle(at, 5.0, Color(ROUTE_LINE, 0.85))


## Where the walk gives out. A cross rather than a dot: this is the one mark on
## the line that means "and no further", and it should not read as another
## corner.
func _draw_route_stop(world: Vector2) -> void:
	var at := _to_screen(world)
	if not at.is_finite():
		return
	var arm := 9.0
	draw_line(at - Vector2(arm, arm), at + Vector2(arm, arm), ROUTE_LINE, 3.0, true)
	draw_line(at - Vector2(arm, -arm), at + Vector2(arm, -arm), ROUTE_LINE, 3.0, true)


## World space to screen space, through whichever camera is live. INF when there
## is no camera to ask, which is every headless run.
func _to_screen(world: Vector2) -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera == null or camera.zoom.x <= 0.0 or camera.zoom.y <= 0.0:
		return Vector2.INF
	return (world - camera.get_screen_center_position()) * camera.zoom + size * 0.5


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
	# Asked of the ghost itself rather than tracked here. It is the caster's own
	# machine that owns the body, so both the count and the fact that there still
	# is a body are sitting in the level already and do not need a second copy
	# kept in step with them.
	#
	# No body, no panel. The clock was a guess at how long the ghost had, and a
	# ghost that has been shot out makes the guess a lie - so the whole readout
	# goes rather than counting off seconds of something that is not there. The
	# player is meant to be short of the panel, not reading a stopped one.
	var ghost := Net.projection_for(Net.peer_id())
	if ghost == null or ghost.dying_at > 0.0:
		return

	var left: float = _player.projection_left
	var span := maxf(_overload_span, 0.01)

	var box := Rect2(Vector2(size.x * 0.5 - 130.0, 132.0), Vector2(260.0, 52.0))
	draw_rect(box, PANEL_BG)
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), PROJECTION)
	draw_string(_font, box.position + Vector2(14.0, 20.0), "PROJECTION",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, PROJECTION)
	draw_string(_font, box.position + Vector2(0.0, 20.0), "%.1fs" % left,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 14.0, 15, TEXT)

	var note := "walking, unshot"
	var tint := DIM
	if ghost.hits > 0:
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
	# Two rows of two: ultimates above, throwables below. Four across in one
	# strip does not fit beside the health bar - the second ultimate either ran
	# off the edge of the screen or pushed the row back over the bar it is meant
	# to sit beside.
	#
	# Written with a local rather than a line continuation. Backslashes at the
	# ends of lines do not survive being written to this file by tooling - they
	# collapse the statement onto one line, which still parses and is unreadable.
	var wide := tile.x * Inventory.THROWABLE_SLOTS + gap
	var origin := Vector2(size.x * 0.5 + 150.0, size.y - MARGIN - tile.y)
	if PlayerInput.is_touch():
		origin = Vector2(size.x * 0.5 - wide * 0.5,
			size.y - MARGIN - tile.y - 56.0)

	for i in kit.ultimates.size():
		var at := origin + Vector2((tile.x + gap) * i, -tile.y - gap)
		_draw_ult_tile(Rect2(at, tile), kit.get_ultimate(i), "Q" if i == 0 else "Z")

	for i in Inventory.THROWABLE_SLOTS:
		var item: Item = kit.get_throwable(i)
		var slot := Rect2(origin + Vector2((tile.x + gap) * i, 0.0), tile)
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
