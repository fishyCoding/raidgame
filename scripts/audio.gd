extends Node

## Autoload: everything that makes a noise goes through here.
##
## Gameplay code says what happened and where - "this gun fired at this point" -
## and never touches an AudioStreamPlayer. That keeps the mixing decisions
## (volume, distance falloff, how many of a sound may overlap) in one place, and
## means swapping the synthesised placeholders for recorded audio is a change to
## this file alone.
##
## Sounds play from a fixed pool of positional players, so a firefight cannot
## spawn nodes without limit. When the pool is full the oldest sound is cut off,
## which is the right trade: the newest shot is the one you need to hear.

## Recorded sound effects. Where one of these exists it replaces the synthesised
## placeholder for that event; everything without a recording still comes out of
## SoundBank, so the two live side by side and a new file is a one-line swap.
const RECORDINGS := {
	"footstep": "res://scenes/footstep.mp3",
	"reload": "res://scenes/reload.mp3",
	"suppressed": "res://scenes/silenced-gunshot.mp3",
	"rifle": "res://scenes/rifleshot.mp3",
	"hit": "res://scenes/hitmarker.mp3",
	"explosion": "res://scenes/freesound_community-explosion-6055.mp3",
	"zipline": "res://scenes/freesound_community-ropemvmt_rope-zip-slow_mp_6-96318.mp3",
}

## Per-recording level trim, in dB. Recorded files arrive at whatever level they
## were mastered at, which is never the level the game wants - this is where that
## gets corrected, rather than by re-exporting the files.
const RECORDING_TRIM := {
	"footstep": 0.0,
	"reload": -8.0,
	"suppressed": 0.0,
	"rifle": 4.0,
	"hit": 0.0,
	"explosion": 4.0,
	"zipline": 2.0,
}

## Positional players. Enough for a busy fight, few enough to stay cheap.
const POOL_SIZE := 20
## Feedback players. Hits come in bursts, so a few, but they never stack deep.
const UI_POOL_SIZE := 6

## Gap between the two ticks of a kill. Short enough to read as one event, long
## enough that they do not smear into a single click.
const KILL_TICK_GAP := 0.085

## How far each kind of sound carries. This is the game's hearing model, and it
## is deliberately not one number: what a sound tells you depends entirely on how
## far away it can possibly be.
##
## Footsteps are the short one on purpose. If you can hear boots, someone is
## close enough to matter - near enough to be on your screen, at the framing the
## camera actually uses. A footstep audible across the level tells you only that
## the level has guards in it, which you already knew.
const HEARING := {
	"footstep": 900.0,
	"reload": 760.0,
	"gunshot": 1500.0,
	## A suppressed weapon is loud enough in your hands and dead a room away.
	## That gap is the whole reason to carry one, so it gets its own range rather
	## than being a quiet gunshot that still travels like a rifle.
	"suppressed": 700.0,
	## Explosions carry: a frag going off is the loudest thing in the game and
	## should pull attention from anywhere on the map.
	"explosion": 3000.0,
}

## Fallback for anything that does not name a range.
const MAX_DISTANCE := 1500.0

# --- who made the noise -------------------------------------------------------
#
# In a raid with eleven guards and another player in it, the single most useful
# thing a sound can tell you is which of those two it was. Distance and direction
# already work; "is that a person" did not, because a remote player used the
# guard's own footstep and both fired the same report.
#
# Two cues, deliberately, because either alone is ambiguous. Guards are pitched
# **down**, which reads as bigger and duller and survives being far away where a
# few dB of level does not. Players are a few dB **up**, which reads as closer
# and more urgent even when the pitch is masked by everything else going on.

## Multiplied into a guard's pitch. Far enough to be a different voice, not so
## far that a footstep stops sounding like a boot - see guard_footstep, which
## learnt that the hard way.
const GUARD_PITCH := 0.88
## And a little quieter, so a player is the louder of the two at equal distance.
const GUARD_TRIM := -3.0
## Anything a person did, yours or another player's.
const PLAYER_TRIM := 2.0

# --- distance ------------------------------------------------------------------
#
# Falloff and panning only. Sounds used to raycast to the listener and be scored
# on the walls in between - a clear line boosted, each surface taking a bite -
# which was a good model and is gone for now: it made a sound's level depend on
# level geometry in a way that was hard to predict while everything else about
# the mix was still moving. Distance is honest and legible. The occlusion is in
# the history if it is wanted back.

## Put back flat when the occlusion pass went.
##
## Every positional sound used to get +4 dB for having a clear line to the
## listener, which in practice was most of them - so deleting the raycasts
## quietened the entire game by that much as a side effect. This restores it, so
## dropping occlusion changed what you hear about *walls* and nothing else.
const CLEAR_LINE_TRIM := 4.0

## How sharply sound drops with distance. Above 1 means a fast initial falloff.
##
## Was 1.4, alongside an occlusion pass that handed a clear line +4 dB back. With
## that gone every unobstructed sound lost those 4 dB and the curve underneath it
## was doing all the work, which put anything past mid-range too far down.
const ATTENUATION := 0.9

## Footsteps fall away faster than anything else. A gunshot at half its range
## should still be clearly a gunshot; boots at half their range should be well on
## their way out, because the thing boots tell you is "someone is close" and a
## flat curve just smears vague shuffling across the level.
##
## Godot's 2D falloff is (1 - distance/max) ^ attenuation. Against the 900 px
## footstep range that works out as, in dB below the close volume:
##
##            225 px    450 px    675 px
##   1.4       -3.5      -8.4     -16.9   (the shared curve)
##   2.2       -5.5     -13.2     -26.5   (where this was, with occlusion helping)
##   1.6       -4.0      -9.6     -19.3   (here: still steeper than the rest, audible further)
##
## Pick another row and put the number here if it still is not sitting right.
const FOOTSTEP_ATTENUATION := 1.6

## How hard sound pans left and right with its position on screen.
const PANNING := 2.0

@export_range(-40.0, 6.0) var master_db := 0.0

var _players: Array[AudioStreamPlayer2D] = []
var _next := 0
## Non-positional players, for the handful of sounds that are feedback rather
## than events in the world. A hitmarker is not somewhere - it is confirmation,
## and it belongs in your ears at the same volume wherever the target was.
var _ui_players: Array[AudioStreamPlayer] = []
var _next_ui := 0
## One synthesised gunshot per weapon, built the first time it fires.
var _shots := {}

## Body pitch per calibre. Two guns in the same calibre are meant to sound
## related; a pistol and a .338 are not meant to be confusable at any distance.
const CALIBRE_BODY := {
	&"9mm": 235.0,
	&"5.56": 155.0,
	&"7.62": 110.0,
	&"12g": 82.0,
	&".338": 62.0,
}
var _footstep: AudioStreamWAV
var _footstep_soft: AudioStreamWAV
var _boot: AudioStreamWAV
var _reload_start: AudioStreamWAV
var _reload_end: AudioStreamWAV
var _dry: AudioStreamWAV
var _kill: AudioStreamWAV
## The gear jingle that used to be baked into the synthesised boot. Kept as its
## own layer now that the boot itself is a recording: it is the part that says
## "not you", and it has to survive whatever footstep sample is in use.
var _gear: AudioStreamWAV
## Loaded recordings, by the keys in RECORDINGS. Missing files simply leave the
## synthesised version in play rather than breaking anything.
var _clips := {}
## The zipline is the one sound that is a state rather than an event, so it gets
## a player of its own that is started and stopped instead of fired.
var _zip: AudioStreamPlayer2D
## Who the single rope sound currently belongs to, and when they last asked for
## it. See _claim_zip.
var _zip_owner := 0
var _zip_frame := -1000


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer2D.new()
		player.max_distance = MAX_DISTANCE
		player.attenuation = ATTENUATION
		# Hard panning: which side a shot came from is information, and in a
		# building full of corners it is often the only information you get.
		player.panning_strength = PANNING
		player.bus = &"Master"
		add_child(player)
		_players.append(player)

	for i in UI_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_ui_players.append(player)

	for key in RECORDINGS:
		var path: String = RECORDINGS[key]
		if ResourceLoader.exists(path):
			_clips[key] = load(path)
		else:
			push_warning("Audio: no recording at %s, using the synthesised one" % path)

	_footstep = SoundBank.footstep(95.0)
	_footstep_soft = SoundBank.footstep(78.0, 0.075)
	_boot = SoundBank.boot()
	_gear = SoundBank.gear_rattle()
	_kill = SoundBank.kill_chime()

	# The zipline clip has to run for as long as the ride does, so it loops on a
	# copy of the stream - setting loop on the loaded resource itself would change
	# it for anything else that ever played it.
	if _clips.has("zipline"):
		_zip = AudioStreamPlayer2D.new()
		_zip.max_distance = HEARING.gunshot
		_zip.attenuation = ATTENUATION
		_zip.panning_strength = PANNING
		_zip.bus = &"Master"
		var looped: AudioStream = (_clips.zipline as AudioStream).duplicate()
		if "loop" in looped:
			looped.loop = true
		_zip.stream = looped
		add_child(_zip)
	# Reloads are metal on metal: a ringing clack, nothing like the noise burst
	# of a shot or the dull thud of a boot.
	_reload_start = SoundBank.clack(1.15, 0.10)
	# The magazine seating. Was a clack - two ringing sine partials with a long
	# tail, which is a bell however it is labelled, and it rang at the end of
	# every reload. Both of these are now atonal snaps: mechanical noises should
	# not have a note in them, least of all ones that fire on a timer.
	_reload_end = SoundBank.snap(0.5, 0.08)
	_dry = SoundBank.snap(0.15, 0.045)


# --- what the game asks for ---------------------------------------------------


## A gun going off. The report is derived from the weapon's own stats, so every
## weapon sounds like what it is without anyone tuning a sound per gun.
func gunshot(data: WeaponData, at: Vector2, from_guard := false) -> void:
	if data == null:
		return
	var trim := GUARD_TRIM if from_guard else PLAYER_TRIM
	var bias := GUARD_PITCH if from_guard else 1.0
	# Heavier guns are louder; fast little ones are pulled down so a held trigger
	# does not drown everything else out.
	var loudness := lerpf(-13.0, -3.0, clampf(data.get_burst_damage() / 120.0, 0.0, 1.0))

	# A gun can name its own recording; a suppressed one falls back to the
	# silenced report. Anything with neither is still synthesised from its stats,
	# because no single sample suits seven very different guns.
	var key: String = data.report_sound
	if key.is_empty() and data.suppressed:
		key = "suppressed"
	if _clips.has(key):
		# Suppressed weapons sit below the curve; a recorded report that was chosen
		# for the gun does not need the stats second-guessing it. Quiet here means
		# "does not carry", not "cannot be heard" - it is close and present in your
		# hands, and gone by the next room. See HEARING.suppressed.
		var base := -1.0 if key == "suppressed" else loudness
		var carries: float = HEARING.suppressed if key == "suppressed" else HEARING.gunshot
		_play(_clips[key], at, base + RECORDING_TRIM[key] + data.loudness_trim + trim,
			randf_range(0.94, 1.06) * bias, carries)
		return

	if not _shots.has(data.short_name):
		_shots[data.short_name] = _build_gunshot(data)
	if data.suppressed:
		loudness -= 14.0
	loudness += data.loudness_trim
	_play(_shots[data.short_name], at, loudness + trim,
		randf_range(0.94, 1.06) * bias, HEARING.gunshot)


## Your own boots. `loudness` scales the step down without changing its
## character - crouching uses it, so sneaking is quiet rather than silent.
func footstep(at: Vector2, heavy := true, loudness := 1.0) -> void:
	var base := -8.0 if heavy else -12.0
	# Volume in dB, so a fraction of "loudness" is a subtraction, not a multiply.
	var quieting := linear_to_db(clampf(loudness, 0.01, 1.0))
	if _clips.has("footstep"):
		_play(_clips.footstep, at, base + quieting + RECORDING_TRIM.footstep,
			randf_range(0.94, 1.08), HEARING.footstep, FOOTSTEP_ATTENUATION)
		return
	_play(_footstep if heavy else _footstep_soft, at, base + quieting,
		randf_range(0.88, 1.12), HEARING.footstep, FOOTSTEP_ATTENUATION)


## Someone else's boots: your footstep recording, at your pitch, with the gear
## jingle laid over the top and a few dB more weight behind it.
##
## Pitching it down was the wrong tool. Far enough down to be its own note, the
## sample stops sounding like a footstep at all and becomes an anonymous thud -
## which throws away the recording. The gear does the telling instead, which is
## the honest reason a guard sounds different anyway: he is wearing webbing and
## carrying a rifle, and you are not.
func guard_footstep(at: Vector2, loudness := 1.0) -> void:
	var quieting := linear_to_db(clampf(loudness, 0.01, 1.0))
	if _clips.has("footstep"):
		_play(_clips.footstep, at, 2.0 + quieting + RECORDING_TRIM.footstep + GUARD_TRIM,
			randf_range(0.94, 1.08) * GUARD_PITCH, HEARING.footstep,
			FOOTSTEP_ATTENUATION)
		_play(_gear, at, -7.0 + quieting, randf_range(0.9, 1.15) * GUARD_PITCH,
			HEARING.footstep, FOOTSTEP_ATTENUATION)
		return
	_play(_boot, at, -7.0 + quieting, randf_range(0.82, 1.18) * GUARD_PITCH,
		HEARING.footstep, FOOTSTEP_ATTENUATION)


## Another player's boots.
##
## Used to be guard_footstep, which meant the most important sound in the game -
## somebody who can shoot back is in the room - was indistinguishable from the
## eleven patrolling men who cannot surprise you. Same recording, at its own
## pitch, louder, and without the webbing jingle a guard carries.
func player_footstep(at: Vector2, loudness := 1.0) -> void:
	var quieting := linear_to_db(clampf(loudness, 0.01, 1.0))
	if _clips.has("footstep"):
		_play(_clips.footstep, at, 2.0 + quieting + RECORDING_TRIM.footstep + PLAYER_TRIM,
			randf_range(0.98, 1.12), HEARING.footstep, FOOTSTEP_ATTENUATION)
		return
	_play(_footstep, at, -4.0 + quieting, randf_range(0.98, 1.12),
		HEARING.footstep, FOOTSTEP_ATTENUATION)


## A grenade going off: the loudest thing in the game, and the furthest carrying.
func explosion(at: Vector2, scale := 1.0) -> void:
	var loudness := 3.0 + linear_to_db(clampf(scale, 0.2, 1.5))
	# Walls do not save you from a grenade, and they should not save you from
	# hearing one: a blast is felt through the building, not around it.
	if _clips.has("explosion"):
		_play(_clips.explosion, at, loudness + RECORDING_TRIM.explosion,
			randf_range(0.9, 1.1), HEARING.explosion)
		return
	_play(SoundBank.explosion(), at, loudness, randf_range(0.9, 1.1),
		HEARING.explosion)


## Your round landed. Not positional: this is confirmation, not an event out in
## the world, and it should sound the same whether the target was near or far.
func hit(headshot := false) -> void:
	if _clips.has("hit"):
		# Headshots come back higher and a shade louder, so the good hits are
		# audible as good hits without a second sample.
		_play_ui(_clips.hit, (-7.0 if headshot else -10.0) + RECORDING_TRIM.hit,
			1.28 if headshot else randf_range(0.97, 1.03))
		return
	_play_ui(SoundBank.tick(2500.0 if headshot else 1750.0),
		-12.0 if headshot else -15.0, randf_range(0.97, 1.03))


# --- the zipline, which is a state rather than an event ----------------------


## Called every frame you are on a cable. Starts the ride sound the first time,
## and pauses it while you hang still - a rope zip with nobody moving on it is
## the wrong sound, and silence is the right one.
## One rope, one sound, and with two people on cables at once it belongs to
## whichever of them is nearer the listener - otherwise the two riders fight over
## a single player's position and it jumps between them every frame.
##
## `source` is the rider's instance id. A source that stops calling loses the
## claim after a couple of frames, so nothing has to announce that it is done.
func zipline(at: Vector2, moving: bool, source := 0) -> void:
	if _zip == null or not _claim_zip(source, at):
		return
	_zip.global_position = at
	_zip.volume_db = RECORDING_TRIM.zipline + master_db + CLEAR_LINE_TRIM
	# Stopped and restarted rather than paused: stream_paused does not reliably
	# take, and a zip picking up from the top when you start moving again sounds
	# more like a rope than one resuming from the middle of a sample would.
	if moving:
		if not _zip.playing:
			_zip.play()
	elif _zip.playing:
		_zip.stop()


func _claim_zip(source: int, at: Vector2) -> bool:
	var frame := Engine.get_physics_frames()
	# Ours already, or nobody has spoken for it lately.
	if _zip_owner == source or frame - _zip_frame > 2:
		_zip_owner = source
		_zip_frame = frame
		return true
	var listener := Net.local_player
	if listener == null:
		return false
	if listener.global_position.distance_to(at) 			>= listener.global_position.distance_to(_zip.global_position):
		return false
	_zip_owner = source
	_zip_frame = frame
	return true


func zipline_stopped(source := 0) -> void:
	if _zip == null:
		return
	# Somebody else's rope keeps playing when you step off yours.
	if source != 0 and _zip_owner != source:
		return
	_zip.stop()
	_zip_owner = 0


## A kill, on the same sample as a hit rather than a sound of its own - one tick
## means you hurt him, two means he is down. Doubling it keeps the two readable
## apart without the confirmation changing character halfway through a fight,
## which is what a separate chime did.
func kill() -> void:
	if _clips.has("hit"):
		_play_ui(_clips.hit, -4.0 + RECORDING_TRIM.hit, 0.88)
		# The second tick rides just behind the first, higher and softer, so the
		# pair lands as one gesture rather than as two separate hits.
		var beat := get_tree().create_timer(KILL_TICK_GAP)
		beat.timeout.connect(func() -> void:
			_play_ui(_clips.hit, -7.0 + RECORDING_TRIM.hit, 1.18))
		return
	_play_ui(_kill, -8.0, randf_range(0.99, 1.01))


## The magazine change. The recording covers the whole action, so the short
## synthesised clack is kept only for the seat at the end of it.
func reload_started(at: Vector2) -> void:
	if _clips.has("reload"):
		_play(_clips.reload, at, -6.0 + RECORDING_TRIM.reload,
			randf_range(0.98, 1.02), HEARING.reload)
		return
	_play(_reload_start, at, -11.0, randf_range(0.97, 1.03), HEARING.reload)


func reload_finished(at: Vector2) -> void:
	_play(_reload_end, at, -11.0, randf_range(0.97, 1.03), HEARING.reload)


func dry_fire(at: Vector2) -> void:
	_play(_dry, at, -14.0, randf_range(0.95, 1.05), HEARING.reload)


# --- plumbing -----------------------------------------------------------------


## The report is built from three separate things, so no two guns land on the
## same sound: the calibre sets the pitch of the body, the rate of fire sets how
## short and sharp it is, and the damage sets how much weight is behind it.
func _build_gunshot(data: WeaponData) -> AudioStreamWAV:
	var body := CALIBRE_BODY.get(data.ammo_type, 150.0) as float
	var heft := clampf(data.get_burst_damage() / 120.0, 0.0, 1.0)
	# Fast guns are clipped and bright; slow ones ring out.
	var quickness := clampf(data.rounds_per_minute / 900.0, 0.0, 1.0)

	if data.suppressed:
		# No crack, no tail, no body to speak of: a cough.
		return SoundBank.gunshot(body * 0.8, 0.075, 0.35, 0.2, 0.0, 0.0)

	return SoundBank.gunshot(
		body,
		lerpf(0.34, 0.12, quickness) * lerpf(0.85, 1.25, heft),
		lerpf(0.45, 0.95, quickness),
		lerpf(0.35, 0.85, heft),
		lerpf(0.5, 0.15, heft),            # small fast rounds crack hardest
		lerpf(0.05, 0.4, heft),            # heavy ones rattle
	)


## `carries` is how far this particular sound reaches. Set per call rather than
## once on the player, because the pool is shared and the last sound to use a
## player would otherwise dictate the range of the next one.
##
func _play(stream: AudioStream, at: Vector2, volume_db: float, pitch: float,
		carries := MAX_DISTANCE, falloff := ATTENUATION) -> void:
	if stream == null:
		return

	# Anything past its own range is silent when it gets there, so it should not
	# take a slot on the way. With a dozen guards pacing, footsteps from across
	# the level would otherwise cycle the pool several times a second and cut off
	# the gunfire next to you - the one sound that had to survive.
	# Mixed for the person at this machine: another player standing next to the
	# sound does not make it audible here.
	var listener := Net.local_player
	if listener and listener.global_position.distance_to(at) > carries:
		return

	var player := _players[_next]
	_next = (_next + 1) % _players.size()

	player.stream = stream
	player.global_position = at
	player.max_distance = carries
	# Set per call, not once on the player: the pool is shared, so the last sound
	# to use a slot would otherwise dictate the curve of the next one.
	player.attenuation = falloff
	player.volume_db = volume_db + master_db + CLEAR_LINE_TRIM
	player.pitch_scale = pitch
	player.play()




func _play_ui(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if stream == null:
		return
	var player := _ui_players[_next_ui]
	_next_ui = (_next_ui + 1) % _ui_players.size()

	player.stream = stream
	player.volume_db = volume_db + master_db + CLEAR_LINE_TRIM
	player.pitch_scale = pitch
	player.play()
