extends Control

## The two moments that frame a run: going in, and not coming back.
##
## This is an extraction game, so death is not a setback to be undone - it ends
## the run and everything carried is gone with it. The death screen says so
## plainly, and the only way on is to start again.
##
## Both animations are drawn rather than keyframed: a fade and a couple of lines
## of type, driven by one clock, because a prototype should not need an
## AnimationPlayer to tell you the raid has started.

const INTRO_TIME := 2.6
const DEATH_FADE := 1.8
const LOBBY_SCENE := "res://scenes/lobby.tscn"

const TITLE := Color(0.95, 0.86, 0.62)
const TEXT := Color(0.82, 0.87, 0.93)
const DIM := Color(0.5, 0.55, 0.62)
const BLOOD := Color(0.42, 0.06, 0.07)

enum Phase { SHOP, WAITING, BRIEFING, INTRO, PLAYING, DEAD, EXTRACTED }

var phase := Phase.SHOP
var _clock := 0.0
var _knocked_out := false
## Whether a squadmate could still bring this death back - see
## Player._death_is_recoverable. Softens the death screen while true: this
## is not the end of the run yet, just the end of standing up on your own.
var _recoverable := false
## What was on you as the run ended, as text. Read once, when it ends, rather
## than off the body every frame: dying hands the kit to the corpse immediately,
## and leaving the session frees the body out from under a screen that is still
## being drawn.
var _carried := ""
## Set by a tap on the screens that otherwise wait for a key. See _input.
var _tapped := false
var _player: Player
var _shop: Node
var _map: Node
## The loadout waiting for a body to put it on.
##
## Kitting out happens in the menu, before you queue - there is no character to
## write into at that point and there will not be one for another minute, so what
## was bought waits on Net across the scene change and is handed over the moment
## a body appears. See lobby.gd and Player.give_kit.
##
## Single player is the exception, and only when the level is loaded on its own:
## every test harness opens main.tscn directly with nothing staged, and for those
## the shop in the level still opens over a paused tree the way it always did.
var _kit: Inventory


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	Net.player_spawned.connect(_on_player_spawned)
	Net.match_changed.connect(_on_match_changed)
	# A networked raid does not open on a shop. It opens on an empty level and a
	# count of who is here, because there is nothing to do until somebody else
	# arrives.
	if Net.is_networked():
		phase = Phase.WAITING
	# Characters are spawned per peer now rather than placed in the level, so
	# something has to open the session. Starting the game straight from the
	# editor means a session of one, hosted by you - the same path a host takes,
	# with nobody else in it.
	_start_session.call_deferred()


## Puts our own character in the world. On a client the host does the spawning
## and the scene replicates it here, so this only ever acts for the host.
func _start_session() -> void:
	# A dedicated server holds the level open for other people and takes no part
	# in it. Asking for a character here is the one thing that would make it a
	# player, and everything else follows from not doing it: no character means
	# _wire_shop never runs, which means the tree is never paused behind a shop
	# nobody can click, and the guards get on with their patrol.
	if Net.is_dedicated:
		return
	# play_solo refuses if a connection is already in flight, so joining a host
	# and then loading the level does not knock the socket over.
	if not Net.in_session:
		Net.play_solo()
	# The level is up, so ask for a character. Host or client, the request goes to
	# the host and it decides - which is also how a client picks up everyone who
	# was already in the world before it arrived.
	if Net.is_networked():
		Net.request_character.rpc_id(1, Net.wants_duos)
	else:
		Net.request_character(Net.wants_duos)
	# Whatever was bought in the menu, waiting for the body it belongs to. Taken
	# rather than copied: nothing else is going to use it, and leaving it on Net
	# would hand the same rifle to the next raid started without going back
	# through the shop.
	_kit = Net.staged_kit
	Net.staged_kit = null


func _on_player_spawned(body: Node) -> void:
	if body != Net.local_player:
		return
	_player = body
	if not _player.died.is_connected(_on_player_died):
		_player.died.connect(_on_player_died)
		_player.extracted.connect(_on_extracted)
		# A squadmate can bring you back from the death screen itself - see
		# Player._resurrect. Harmless while merely knocked (revived also fires
		# for that, and phase is already PLAYING then, so this is a no-op).
		_player.revived.connect(_on_player_revived)
	# Deferred because the shop is created after this node - it has to draw over
	# the HUD, so it sits later in the scene and is not in the tree yet.
	_wire_shop.call_deferred()


## The raid does not start until the shop says so: nothing moves, and the world
## sits paused behind the counter.
func _wire_shop() -> void:
	# In a match the kitting out already happened, in the menu. All that is left
	# is to put on what was bought and go.
	if Net.is_networked():
		_deploy_with_kit()
		return
	# Alone, but kitted out in the menu on the way in. Same thing: put it on and
	# take the briefing. The shop in the level is for the other way of starting -
	# main.tscn opened on its own, which is how every test harness runs.
	if _kit != null:
		if _player:
			_player.give_kit(_kit)
		# Trying the controls out rather than playing: straight in, no map, no
		# fade. Cleared as it is read so it cannot carry into a real run.
		if Net.test_drive:
			Net.test_drive = false
			get_tree().paused = false
			phase = Phase.PLAYING
			_clock = 0.0
			return
		get_tree().paused = true
		_on_deployed()
		return
	_shop = get_tree().get_first_node_in_group(&"shop")
	if _shop == null or _player == null:
		phase = Phase.INTRO # no shop in this scene: straight into the raid
		return
	if _shop.deployed.is_connected(_on_deployed):
		return # already open for this run
	_shop.deployed.connect(_on_deployed)
	_shop.open(_player.inventory)
	get_tree().paused = true


## The countdown has run out and a body has appeared. It gets what the shop sold
## you, the screen comes down whether or not READY was ever pressed, and the raid
## is on.
func _deploy_with_kit() -> void:
	if _player and _kit:
		_player.give_kit(_kit)
	if _shop:
		_shop.close()
	get_tree().paused = false
	phase = Phase.INTRO
	_clock = 0.0


## Deploying does not drop you straight in: the map comes up first, so you know
## where you landed and which way home is before anything can shoot at you.
func _on_deployed() -> void:
	phase = Phase.BRIEFING
	_clock = 0.0
	_map = get_tree().get_first_node_in_group(&"map_screen")
	if _map:
		_map.show_briefing()
	else:
		_start_raid()


func _start_raid() -> void:
	if _map:
		_map.dismiss()
	get_tree().paused = false
	phase = Phase.INTRO
	_clock = 0.0


func _on_extracted(_from_point) -> void:
	phase = Phase.EXTRACTED
	_carried = _player.inventory.summary() if _player and _player.inventory else ""
	_clock = 0.0
	get_tree().paused = true


## The host has moved the match on. Nothing spawns from here - Net does that -
## this only decides what is on screen while it happens.
func _on_match_changed(state: int, _left: float) -> void:
	if state == Net.Match.LIVE:
		return   # the character arriving is what takes us out of WAITING
	phase = Phase.WAITING
	queue_redraw()


func _process(delta: float) -> void:
	if phase == Phase.SHOP:
		return
	if phase == Phase.WAITING:
		# The countdown has to move every frame, so this redraws rather than
		# waiting to be told.
		queue_redraw()
		return
	_clock += delta

	if phase == Phase.BRIEFING:
		# Any of the obvious keys gets you moving - or a tap, on a device that
		# has none of them.
		if _clock > 0.4 and (Input.is_action_just_pressed(&"restart")
				or Input.is_action_just_pressed(&"map")
				or Input.is_action_just_pressed(&"jump")
				or _took_tap()):
			_start_raid()
		return

	if phase == Phase.EXTRACTED and _clock > 1.0 \
			and (Input.is_action_just_pressed(&"restart") or _took_tap()):
		_back_to_the_kit_menu()
		return
	if phase == Phase.INTRO and _clock >= INTRO_TIME:
		phase = Phase.PLAYING
	# Dead is dead: the only input that means anything now is "again".
	if phase == Phase.DEAD and _clock > 1.2 \
			and (Input.is_action_just_pressed(&"restart") or _took_tap()):
		_back_to_the_kit_menu()
	queue_redraw()


## A tap anywhere, for the screens that otherwise sit and wait for a key.
##
## These three all told you to press ENTER, which on a phone is advice you cannot
## take - the briefing in particular would hold the raid shut forever. Only read
## in touch mode, so a stray click on a desktop cannot skip a death screen you
## were still reading.
func _input(event: InputEvent) -> void:
	if not PlayerInput.is_touch():
		return
	if phase != Phase.BRIEFING and phase != Phase.DEAD and phase != Phase.EXTRACTED:
		return
	var touch := event as InputEventScreenTouch
	var click := event as InputEventMouseButton
	if (touch and touch.pressed) \
			or (click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT):
		_tapped = true
		get_viewport().set_input_as_handled()


func _took_tap() -> bool:
	if not _tapped:
		return false
	_tapped = false
	return true


## Out of the raid and back to the counter. The only way out of a run, whichever
## way the run ended.
##
## This used to reload the level, which is the one thing an extraction game must
## not do: it dropped you straight back into a raid with a free starting kit and
## no visit to the shop, so the bet you had just lost cost you nothing and the
## whole economy was optional. Everything you take in has to be bought, every
## time - which means going back to the place you buy it, every time.
##
## Leaving the session is part of it rather than a tidy-up. Your run is over
## either way, and holding the socket open would leave a body in a match you are
## no longer playing; dropping it now is also what frees the server for the next
## pair - see Net._start_over.
func _back_to_the_kit_menu() -> void:
	get_tree().paused = false
	Net.leave("your run ended")
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_player_died(knocked_out: bool, recoverable: bool) -> void:
	phase = Phase.DEAD
	_knocked_out = knocked_out
	_recoverable = recoverable
	_carried = _player.lost_kit if _player else ""
	_clock = 0.0


## Brought back - either a knockdown revive (phase is already PLAYING, so
## this changes nothing) or a squadmate's one-time resurrection from the
## death screen itself, which is the case this exists for: nothing else ever
## takes the DEAD phase down again except the player choosing to leave.
func _on_player_revived() -> void:
	if phase == Phase.DEAD:
		phase = Phase.PLAYING
		_recoverable = false
		_clock = 0.0


func _draw() -> void:
	match phase:
		Phase.WAITING:
			_draw_waiting()
		Phase.INTRO:
			_draw_intro()
		Phase.DEAD:
			_draw_death()
		Phase.EXTRACTED:
			_draw_extracted()


## Before the raid: who is here, and how long until the doors open.
##
## Drawn over the live level rather than over black, because the level is
## running - the guards are already walking their rounds behind this - and
## watching that happen is what makes the wait feel like standing somewhere
## instead of staring at a progress bar.
func _draw_waiting() -> void:
	var font := ThemeDB.fallback_font
	var centre := size * 0.5
	# Opaque once the countdown is actually running - these ten seconds are
	# for looking at what you and your squad brought in, not at the level
	# through a haze. Merely waiting for a second player stays translucent,
	# so the level going on behind it is still what makes that wait feel like
	# standing somewhere rather than staring at a loading screen.
	var counting := Net.match_state == Net.Match.COUNTDOWN
	draw_rect(Rect2(Vector2.ZERO, size),
		Color(0.02, 0.025, 0.035, 1.0 if counting else 0.72))

	if counting:
		var seconds := int(ceilf(Net.seconds_left))
		draw_string(font, Vector2(0.0, centre.y - 54.0), "DEPLOYING IN",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, DIM)
		# The number is the whole screen at this point - it is the only thing
		# anyone is looking at.
		draw_string(font, Vector2(0.0, centre.y + 26.0), str(seconds),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 86, TITLE)
		draw_string(font, Vector2(0.0, centre.y + 74.0),
			"you and %d other going in at opposite ends" % maxi(Net.player_slots() - 1, 1),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, DIM)
		_draw_kit_footer()
		return

	# Queued duos with nobody paired yet: say so plainly rather than the
	# generic count, which would otherwise show "1 of 2" while somebody
	# else's solo queue silently fills the raid without you - see
	# Net._is_ready, which is what actually keeps you off the level for it.
	var stuck_alone := Net.wants_duos and Net.teammate(Net.peer_id()) == 0
	draw_string(font, Vector2(0.0, centre.y - 16.0),
		"WAITING FOR A SQUADMATE" if stuck_alone else "WAITING FOR PLAYERS",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, TITLE)
	if stuck_alone:
		draw_string(font, Vector2(0.0, centre.y + 22.0),
			"queued for duos - matched the instant somebody else queues the same way",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, TEXT)
	else:
		draw_string(font, Vector2(0.0, centre.y + 22.0),
			"%d of %d" % [Net.player_slots(), Net.MIN_PLAYERS],
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, TEXT)
		draw_string(font, Vector2(0.0, centre.y + 62.0),
			"the raid starts when someone else arrives",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, DIM)
	_draw_kit_footer()


## What you are carrying in with you. The kit was bought before you queued and
## the bill is already paid, so this is a reminder rather than an offer - but it
## is the last thing on screen before the doors open, and knowing what is on your
## back is most of what the wait is for.
func _draw_kit_footer() -> void:
	if _kit == null:
		return
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0.0, size.y - 40.0),
		"going in with:  %s" % _kit.summary(),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, DIM)
	# Known the moment the host pairs the squad - see Net._set_teammates -
	# which is well before either of you has a body, so there is nothing to
	# wait on here beyond the message having arrived yet.
	if not Net.teammate_kit_text.is_empty():
		draw_string(font, Vector2(0.0, size.y - 22.0),
			"your teammate:  %s" % Net.teammate_kit_text,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, DIM)


## Black, lifting off the level, with the brief on top of it.
func _draw_intro() -> void:
	var t := clampf(_clock / INTRO_TIME, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	# Holds solid for a moment, then lifts - so the first thing seen is the text.
	var cover := 1.0 - smoothstep(0.35, 1.0, t)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035, cover))

	var fade := smoothstep(0.05, 0.3, t) * (1.0 - smoothstep(0.75, 1.0, t))
	var centre := size * 0.5
	draw_string(font, Vector2(0.0, centre.y - 30.0), "INFILTRATION",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 42, Color(TITLE, fade))
	draw_string(font, Vector2(0.0, centre.y + 10.0),
		"get in    take what you can carry    get out alive",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color(TEXT, fade))
	draw_string(font, Vector2(0.0, centre.y + 52.0),
		"there is no second chance - what you lose here is lost",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(DIM, fade))


## Made it. The counterpart to the death screen, and the only one that lets you
## keep anything: what is listed here is what you carried out.
func _draw_extracted() -> void:
	var t := clampf(_clock / 1.2, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.05, smoothstep(0.0, 1.0, t) * 0.92))

	var fade := smoothstep(0.2, 0.9, t)
	var centre := size * 0.5
	draw_string(font, Vector2(0.0, centre.y - 40.0), "EXTRACTED",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, Color(0.5, 0.92, 0.66, fade))
	draw_string(font, Vector2(0.0, centre.y + 4.0), "out, and everything on you came with you",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(TEXT, fade))

	if not _carried.is_empty():
		draw_string(font, Vector2(0.0, centre.y + 44.0), "carried out:  %s" % _carried,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(DIM, fade))

	draw_string(font, Vector2(0.0, centre.y + 96.0), ("TAP  kit up for the next one" if PlayerInput.is_touch() else "ENTER  kit up for the next one"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(TITLE, fade * 0.9))


## A squadmate could still bring this one back - see
## Player._death_is_recoverable - so it is not shown as the run ending.
## Deliberately light: no blood, no black takeover, the level still drawing
## behind it exactly the way the WAITING screen leaves it visible. Giving up
## and buying another kit is still on the table, just no longer the only
## thing this screen is telling you.
func _draw_down_waiting() -> void:
	var font := ThemeDB.fallback_font
	var centre := size * 0.5
	var pulse := 0.6 + 0.4 * sin(_clock * 2.4)
	var lit := Color(0.74, 0.56, 0.94)
	var box := Rect2(Vector2(centre.x - 220.0, centre.y - 70.0), Vector2(440.0, 128.0))
	draw_rect(box, Color(0.04, 0.05, 0.07, 0.82))
	draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), Color(lit, pulse))

	draw_string(font, box.position + Vector2(20.0, 36.0), "DOWN - NOT OUT",
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 40.0, 28, lit)
	draw_string(font, box.position + Vector2(20.0, 62.0),
		"your squad can still bring you back with a revive kit",
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 40.0, 14, TEXT)
	if not _carried.is_empty():
		draw_string(font, box.position + Vector2(20.0, 86.0), "on the body:  %s" % _carried,
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 40.0, 12, DIM)
	draw_string(font, box.position + Vector2(20.0, 112.0),
		("TAP  give up and buy another kit" if PlayerInput.is_touch()
			else "ENTER  give up and buy another kit"),
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 40.0, 12, DIM)


## Red bleeding in, then the verdict. No timer, no respawn.
func _draw_death() -> void:
	if _recoverable:
		_draw_down_waiting()
		return
	var t := clampf(_clock / DEATH_FADE, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	# Blood first, then black over it: the colour reads as the hit, the dark as
	# the run ending.
	draw_rect(Rect2(Vector2.ZERO, size), Color(BLOOD, smoothstep(0.0, 0.45, t) * 0.55))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, smoothstep(0.3, 1.0, t) * 0.9))

	var fade := smoothstep(0.45, 0.9, t)
	var centre := size * 0.5
	draw_string(font, Vector2(0.0, centre.y - 40.0),
		"KNOCKED OUT" if _knocked_out else "YOU DIED",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, Color(0.86, 0.3, 0.28, fade))
	draw_string(font, Vector2(0.0, centre.y + 4.0),
		"a round to the head, and no helmet worth the name" if _knocked_out
		else "you bled out short of the way home",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(TEXT, fade))

	if not _carried.is_empty():
		draw_string(font, Vector2(0.0, centre.y + 44.0), "lost on the body:  %s" % _carried,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(DIM, fade))

	draw_string(font, Vector2(0.0, centre.y + 96.0), ("TAP  buy another kit" if PlayerInput.is_touch() else "ENTER  buy another kit"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(TITLE, fade * 0.9))
