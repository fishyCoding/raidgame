class_name SoundBank
extends RefCounted

## Synthesises the prototype's sound effects as raw waveforms, so the game has
## audio without carrying any audio files.
##
## The art is untextured polygons and the guns are numbers on a curve; these are
## the same idea for the ears. Every sound is built from noise, a decaying tone
## and an envelope, shaped by the weapon's own stats - so a new gun gets a
## fitting report the moment its .tres exists, with nothing to author.
##
## Replacing these with recordings is a drop-in: hand audio.gd an AudioStream
## from disk instead of calling in here. Nothing else knows the difference.

const RATE := 22050


## Gunshot: a bright noise crack over a body tone that drops in pitch, both
## decaying fast. Heavy rounds get a lower, longer body; fast little rounds get a
## short bright snap.
static func gunshot(body_hz: float, length: float, brightness: float,
		punch: float, crack := 0.0, rattle := 0.0) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var decay := maxf(length * 0.26, 0.01)
	var filtered := 0.0
	# One-pole low pass: low values muffle the noise into a thump, high values
	# leave it as a crack.
	var smoothing := clampf(brightness, 0.02, 0.95)

	for i in count:
		var t := float(i) / RATE
		var envelope := exp(-t / decay)
		filtered = lerpf(filtered, randf_range(-1.0, 1.0), smoothing)
		# The body drops about an octave as it decays, which is what stops it
		# sounding like a beep.
		var pitch := body_hz * lerpf(1.0, 0.5, clampf(t / decay, 0.0, 1.0))
		var body := sin(TAU * pitch * t)
		var attack := 1.0 if t < 0.004 else 0.0 # transient click off the front

		# The crack is the supersonic snap off the front of a fast round: a very
		# short, very bright burst that a subsonic or suppressed weapon has none
		# of. It is most of what tells two rifles apart by ear.
		var snap := 0.0
		if crack > 0.0 and t < 0.03:
			snap = randf_range(-1.0, 1.0) * crack * exp(-t / 0.008)

		# A slow wobble on the tail, which reads as the mechanism working - more
		# of it on heavy, slow weapons.
		var wobble := 1.0 + rattle * sin(TAU * 42.0 * t) * envelope

		samples[i] = clampf(
			((filtered * (0.75 + attack * 0.25) + body * punch) * wobble + snap)
			* envelope, -1.0, 1.0)

	return _to_stream(samples)


## Footstep: a short muffled thud. Quiet, because these play constantly.
static func footstep(body_hz: float, length := 0.09) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var filtered := 0.0
	for i in count:
		var t := float(i) / RATE
		var envelope := exp(-t / (length * 0.22))
		filtered = lerpf(filtered, randf_range(-1.0, 1.0), 0.12)
		var body := sin(TAU * body_hz * t)
		samples[i] = clampf((filtered * 0.8 + body * 0.5) * envelope, -1.0, 1.0)

	return _to_stream(samples)


## A guard's boot: the same thud as a footstep with kit on top of it. Guards
## wear webbing and carry a rifle, and the difference has to be audible in the
## first step - hearing whether the boots are yours or someone else's is the
## whole point of quiet movement.
static func boot(body_hz := 62.0, length := 0.16) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var filtered := 0.0
	for i in count:
		var t := float(i) / RATE
		var envelope := exp(-t / (length * 0.20))
		# Darker and heavier than a player step: more body, less noise.
		filtered = lerpf(filtered, randf_range(-1.0, 1.0), 0.07)
		var body := sin(TAU * body_hz * t) * 0.85
		var scuff := filtered * 0.55

		# Gear rattle: a high, sparse jingle after the heel lands. This is the
		# tell - your own boots have nothing hanging off them.
		var rattle := 0.0
		if t > 0.02:
			var ring := sin(TAU * 3100.0 * t) + sin(TAU * 4300.0 * t) * 0.6
			rattle = ring * 0.16 * exp(-(t - 0.02) / 0.045)

		samples[i] = clampf((body + scuff) * envelope + rattle, -1.0, 1.0)

	return _to_stream(samples)


## Webbing and a slung rifle, jingling as someone puts their weight down. Laid
## over a footstep it turns "a step" into "a step by someone carrying kit", which
## is the whole of telling a guard's boots from your own. Kept separate from the
## boot itself so it works over a recorded footstep just as well.
## This used to be two sine waves under an exponential decay, which is the exact
## recipe for a bell - and it rang like one, on every footstep every guard took.
## A buckle knocking against a rifle sling is broadband and atonal: several very
## short bright noise ticks at uneven spacing, with no pitch to hang on to.
static func gear_rattle(length := 0.14) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	# Uneven on purpose. Evenly spaced ticks read as a rhythm, and a rhythm is
	# another thing the ear tries to identify.
	var ticks := [0.0, 0.028, 0.061, 0.099]
	var filtered := 0.0
	for i in count:
		var t := float(i) / RATE
		# High smoothing leaves the noise bright, so it reads as metal rather
		# than as another thud on top of the boot.
		filtered = lerpf(filtered, randf_range(-1.0, 1.0), 0.85)

		var hit := 0.0
		for j in ticks.size():
			var at: float = ticks[j]
			if t >= at:
				hit += exp(-(t - at) / 0.005) * (1.0 - j * 0.19)

		samples[i] = clampf(filtered * hit * 0.55, -1.0, 1.0)

	return _to_stream(samples)


## An explosion: a very low body that drops away, a wide noise burst, and a long
## rumbling tail. Longer and lower than any gunshot, so it never gets confused
## for one however far away it goes off.
static func explosion(body_hz := 46.0, length := 1.1) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var filtered := 0.0
	var slow := 0.0
	for i in count:
		var t := float(i) / RATE
		# Two envelopes: a hard crack off the front, and a much longer rumble
		# underneath it that is most of what makes it read as big.
		var crack := exp(-t / 0.045)
		var rumble := exp(-t / (length * 0.38))

		filtered = lerpf(filtered, randf_range(-1.0, 1.0), 0.55)
		slow = lerpf(slow, randf_range(-1.0, 1.0), 0.045)

		# The body sags nearly two octaves as it goes, which is the difference
		# between a bang and a boom.
		var pitch := body_hz * lerpf(1.0, 0.3, clampf(t / (length * 0.5), 0.0, 1.0))
		var body := sin(TAU * pitch * t)

		samples[i] = clampf(
			filtered * 0.75 * crack
			+ (body * 0.85 + slow * 0.7) * rumble, -1.0, 1.0)

	return _to_stream(samples)


## Hit confirmation: a short bright tick. Deliberately tiny - it plays on every
## round that lands, so anything with a tail would turn a burst into a mess.
static func tick(pitch_hz := 1750.0, length := 0.055) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	for i in count:
		var t := float(i) / RATE
		var envelope := exp(-t / (length * 0.18))
		# Two tones a fifth apart: reads as a deliberate blip rather than a beep.
		var tone := sin(TAU * pitch_hz * t) * 0.7 + sin(TAU * pitch_hz * 1.5 * t) * 0.3
		samples[i] = clampf(tone * envelope, -1.0, 1.0)

	return _to_stream(samples)


## The kill sound: two tones, the second higher than the first, over a soft
## thump. Rising is the whole trick - it lands as an answer rather than as one
## more noise in the fight.
static func kill_chime() -> AudioStreamWAV:
	var length := 0.34
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var first := 880.0
	var second := 1320.0  # a fifth up
	var filtered := 0.0
	for i in count:
		var t := float(i) / RATE
		filtered = lerpf(filtered, randf_range(-1.0, 1.0), 0.3)

		var a := sin(TAU * first * t) * exp(-t / 0.055)
		var b := 0.0
		if t > 0.065:
			b = sin(TAU * second * (t - 0.065)) * exp(-(t - 0.065) / 0.11)
		# A low thump under the chime, so it has weight and does not read as UI.
		var thump := sin(TAU * 150.0 * t) * exp(-t / 0.07) * 0.55

		samples[i] = clampf((a * 0.55 + b * 0.6 + thump + filtered * 0.1 * exp(-t / 0.03)),
			-1.0, 1.0)

	return _to_stream(samples)


## A metallic clack: two closely spaced transients with a ringing tail, which is
## what makes a magazine sound like metal rather than like a quiet gunshot.
static func clack(pitch := 1.0, length := 0.12) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var ring_a := 1850.0 * pitch
	var ring_b := 2640.0 * pitch
	var filtered := 0.0
	for i in count:
		var t := float(i) / RATE
		filtered = lerpf(filtered, randf_range(-1.0, 1.0), 0.8)
		# Two hits: the catch, then the seat.
		var first := exp(-t / 0.012)
		var second := 0.0 if t < 0.055 else exp(-(t - 0.055) / 0.018)
		var hit := first + second * 0.9
		var ring := sin(TAU * ring_a * t) * 0.5 + sin(TAU * ring_b * t) * 0.3
		samples[i] = clampf((filtered * 0.45 + ring * 0.55) * hit, -1.0, 1.0)

	return _to_stream(samples)


## A mechanical snap with no pitch in it at all: a bright transient over a short
## low thump, both built from noise rather than from a tone.
##
## The pitched click below is fine in isolation but it is still a note, and a
## note that fires on a timer - at the end of every reload, say - is the kind of
## thing the ear starts hunting for. `weight` lengthens and darkens the thump.
static func snap(weight := 0.5, length := 0.08) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var bright := 0.0
	var dull := 0.0
	for i in count:
		var t := float(i) / RATE
		bright = lerpf(bright, randf_range(-1.0, 1.0), 0.8)
		# Heavily smoothed noise: a body with weight but no fixed pitch.
		dull = lerpf(dull, randf_range(-1.0, 1.0), 0.06)

		var crack := exp(-t / 0.004)
		var body := exp(-t / (0.010 + weight * 0.022))
		samples[i] = clampf(bright * 0.7 * crack + dull * 0.9 * body, -1.0, 1.0)

	return _to_stream(samples)


## Mechanical click, for magazines and charging handles. `weight` lowers the tone
## and lengthens the tail.
static func click(weight := 0.5, length := 0.07) -> AudioStreamWAV:
	var count := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var body_hz := lerpf(900.0, 260.0, clampf(weight, 0.0, 1.0))
	var filtered := 0.0
	for i in count:
		var t := float(i) / RATE
		var envelope := exp(-t / (length * 0.16))
		filtered = lerpf(filtered, randf_range(-1.0, 1.0), 0.55)
		samples[i] = clampf(
			(filtered * 0.5 + sin(TAU * body_hz * t) * 0.6) * envelope, -1.0, 1.0)

	return _to_stream(samples)


## Two clicks in a row: magazine out, magazine in.
static func double_click(weight := 0.5, gap := 0.11) -> AudioStreamWAV:
	var first := click(weight * 0.7, 0.06)
	var second := click(weight, 0.09)
	return _concat(first, second, gap)


static func _concat(a: AudioStreamWAV, b: AudioStreamWAV, gap: float) -> AudioStreamWAV:
	var lead := int(RATE * gap)
	var a_count := a.data.size() / 2
	var b_count := b.data.size() / 2
	var samples := PackedFloat32Array()
	samples.resize(maxi(a_count, lead + b_count))

	for i in a_count:
		samples[i] = a.data.decode_s16(i * 2) / 32767.0
	for i in b_count:
		var at := lead + i
		samples[at] = clampf(samples[at] + b.data.decode_s16(i * 2) / 32767.0, -1.0, 1.0)

	return _to_stream(samples)


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
