extends Node2D

## The spark at the end of the barrel: a short burst that fades itself out and
## frees the node, code-drawn the same way Impact is - see impact.gd, which
## this is built on the same pattern as.
##
## Two live numbers decide what it looks like rather than one fixed picture
## for every gun. Size starts from WeaponData.loudness_trim, which is
## already the one field on the built gun that answers "how much noise does
## this shot actually make" - a hotter energy cell raises it (see
## Gunsmith.ENERGY_LOUDNESS_DELTA) and a suppressor buries it near the floor
## (AttachmentData.loudness_delta, and `suppressed` on top of that) - so a
## flash that reads the same number the sound already answers to needs no
## second opinion about what "quiet" means for this particular gun. `heat`
## then pushes size and colour further on top of that: a shot fired hot
## grows well past whatever its loudness alone would draw and shifts toward
## Bullet.OVERHEAT_COLOR, the same colour the tracer itself is shifting
## toward, so the two effects of one overtiered round read as one thing
## happening rather than two.
##
## Drawn in layers rather than as one shape, because that is what actually
## reads as a flash rather than as a sprite: a white-hot point that only
## exists for an instant, a softer coloured bloom around it that lags a
## little behind, and a handful of flame tongues - not lines, which are a
## ray, but tapered petals, which are gas burning - fanned mostly forward
## with two short ones out to the sides, because a real muzzle vents around
## the barrel as well as past the end of it.

@export var lifetime := 0.08
## Largest a flash gets to be at heat 0, in world pixels - the loudest shot
## on the loudest cell, before heat_size_mult below has anything to say
## about it.
@export var max_radius := 20.0
## Smallest a flash still shows at all, before the suppressed cut below -
## nothing is ever fully invisible, or a shot with no muzzle flash at all
## reads as a rendering fault rather than as a quiet gun.
@export var min_radius := 4.5
## What a suppressor - or a pistol built quiet to begin with - leaves of it.
@export_range(0.0, 1.0) var suppressed_scale := 0.3
## How much bigger a fully-hot shot's flash gets, on top of whatever its
## loudness already earned it - quadruple, at the ceiling. This is the
## number that has to sell "this gun is about to get away from you" on its
## own, since by the time heat is this high the colour has already said so
## too.
@export var heat_size_mult := 3.0

var _age := 0.0
var _radius := 10.0
var _color := Color(0.78, 0.9, 1.0)
## One entry per flame tongue - [angle, length scale, width scale] - rolled
## once per flash so the burst is lopsided and organic rather than a
## perfectly symmetric star drawn from a formula.
var _tongues: Array = []


## `data` is the built weapon - already carries whatever an energy cell or an
## attachment did to loudness_trim, not the number off the shelf. `heat` is
## the shooter's Weapon.heat at the instant of this exact shot, 0 on a
## same-tier cell always.
func setup(data: WeaponData, heat: float) -> void:
	# -24..12 dB is the same span Gunsmith clamps a folded loudness_trim
	# into, so this reads the whole range that number can actually reach.
	var loud := clampf((data.loudness_trim + 24.0) / 36.0, 0.0, 1.0)
	_radius = lerpf(min_radius, max_radius, loud)
	if data.suppressed:
		_radius *= suppressed_scale
	if heat > 0.0:
		var h := clampf(heat, 0.0, 1.0)
		_color = _color.lerp(Bullet.OVERHEAT_COLOR, h).lightened(h * 0.4)
		# Eased rather than linear: a shot at half heat should barely look
		# different from a cold one, and the growth wants to be concentrated
		# in the last stretch before the gun actually locks, not spread
		# evenly across the whole bar - the flash getting a lot bigger is
		# what should tell you the ceiling is close, not a gun that has
		# already been swelling gradually since the first shot.
		var size_ease := h * h
		_radius *= 1.0 + size_ease * heat_size_mult

	# One long tongue straight down the bore, two shorter ones fanning off
	# it, and a pair of small side puffs roughly perpendicular to it. Angle,
	# length and width all get their own jitter so no two shots draw alike.
	_tongues = [
		[randf_range(-0.06, 0.06), randf_range(0.95, 1.15), randf_range(0.8, 1.0)],
		[randf_range(0.32, 0.48), randf_range(0.5, 0.68), randf_range(0.45, 0.6)],
		[randf_range(-0.48, -0.32), randf_range(0.5, 0.68), randf_range(0.45, 0.6)],
		[randf_range(1.3, 1.55), randf_range(0.2, 0.3), randf_range(0.3, 0.4)],
		[randf_range(-1.55, -1.3), randf_range(0.2, 0.3), randf_range(0.3, 0.4)],
	]


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := 1.0 - clampf(_age / lifetime, 0.0, 1.0)
	if t <= 0.0:
		return

	# The glow: four washes standing in for a radial gradient, since a flat
	# draw_circle has no falloff of its own. Each one smaller and brighter
	# than the last is what makes the middle read as hotter than the edge
	# rather than as one evenly-lit disc - a fourth step over what this
	# started with, because three left visible rings up close instead of a
	# smooth fall-off.
	draw_circle(Vector2.ZERO, _radius * 0.95 * t, Color(_color.darkened(0.25), t * 0.16))
	draw_circle(Vector2.ZERO, _radius * 0.62 * t, Color(_color.darkened(0.05), t * 0.32))
	draw_circle(Vector2.ZERO, _radius * 0.34 * t, Color(_color, t * 0.55))
	draw_circle(Vector2.ZERO, _radius * 0.14 * t, Color(1.0, 1.0, 1.0, t * 0.85))

	# The tongues, each drawn twice - the full coloured petal, and a
	# narrower near-white one down its middle, so every tongue carries the
	# same hot-core-to-coloured-edge layering the glow behind it does rather
	# than reading as a flat wedge of one colour. Based a little off centre
	# rather than every one sharing the glow's own origin exactly, so the
	# cluster reads as several separate licks of flame instead of one fan
	# folded out of a single point.
	for tongue in _tongues:
		var angle: float = tongue[0]
		var length := _radius * (tongue[1] as float) * t
		var width := _radius * (tongue[2] as float) * 0.5 * t
		if length < 0.6:
			continue
		var dir := Vector2.RIGHT.rotated(angle)
		var base := dir * _radius * 0.08 * t
		draw_colored_polygon(_petal(base, dir, length, width), Color(_color, t * 0.72))
		draw_colored_polygon(_petal(base, dir, length * 0.58, width * 0.4),
			Color(1.0, 1.0, 1.0, t * 0.6))


## A flame-tongue silhouette along `dir` from `base`: rounded at the
## shoulder, waisted, and tapered to a soft, blunt point rather than a sharp
## one - a curve approximated with enough points to read as one, not a
## seven-point wedge. Sine-shaped rather than a straight taper, which is
## what keeps this looking like gas burning off a barrel instead of a shard
## of glass or a ray drawn as a triangle.
func _petal(base: Vector2, dir: Vector2, length: float, width: float) -> PackedVector2Array:
	var perp := dir.rotated(PI * 0.5)
	var segments := 8
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in segments + 1:
		var s := float(i) / float(segments)
		var w := width * sin(PI * (1.0 - s) * 0.5 + 0.16) * (1.0 - s * 0.15)
		var along := base + dir * length * s
		top.append(along + perp * w)
		bottom.append(along - perp * w)
	var out := PackedVector2Array()
	out.append_array(top)
	for i in range(bottom.size() - 1, -1, -1):
		out.append(bottom[i])
	return out
