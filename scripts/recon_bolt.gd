class_name ReconBolt
extends Node2D

## The recon bow's arrow, which is not an arrow.
##
## It flies rather than teleports: fast, but it drops over distance and takes
## time to arrive, so painting a room across the level means leading the shot.
## Where it sticks is where the sweep is centred, so a bad arrow is a wasted
## ultimate - which is the price of it being an ultimate rather than a gadget.
##
## Drawn as a piece of kit rather than as a fletched shaft. It used to be three
## static polygons - a stick, a broadhead and feathers - which is a fine arrow
## and the wrong object: nothing else in this loadout is medieval, and the thing
## it actually does is scan a room and radio back who is in it. So it is a dart
## with a machined casing, hard swept fins instead of fletching, a spike on the
## nose, and a lit strip down the side that is doing something at all times.
##
## The strip is the whole idea. A device you can tell is powered reads as a
## device; a silhouette does not, however good the silhouette is. In flight it
## breathes slowly. The moment it bites it throws its struts out, goes bright,
## and then burns down: the lit length is exactly the paint it has left, so the
## thing that tells you the sweep is about to lapse is the object itself rather
## than a number somewhere else on the screen.

## Muzzle velocity, pixels per second.
@export var speed := 3000.0
## Arrows drop. Not much, but enough that a long shot has to be aimed high.
## Nine times what it started at, because speed flattens an arc hard: at double
## the speed a shot crosses the same ground in half the time, so the same gravity
## would only pull it a quarter as far down. Four times over would merely have
## restored the original arc at the new speed - everything past that is the curve
## being asked for.
##
## For a sense of it: across the bow's 640 px reach the arrow drops about 55 px.
## It is a lobbed shot that has to be aimed above what you want to hit, not a
## flat one.
@export var gravity := 2400.0

var velocity := Vector2.ZERO
var data: GadgetData
## How far the bow was drawn, 0 to 1. A half-drawn arrow flies slower, drops
## sooner and sweeps a smaller area - the shot is worth what you put into it.
var power := 1.0

var _stuck := false
var _age := 0.0
## Free-running clock for the lit parts. Its own rather than `_age`, which is
## reset when the dart lands and is needed for the paint countdown.
var _lit_clock := 0.0
## How far the struts have swung out, 0 to 1. They deploy on landing.
var _struts := 0.0

## The casing, its edge, and the parts that are powered.
const CASE := Color(0.13, 0.17, 0.21)
const EDGE := Color(0.55, 0.85, 0.95)
const LIT := Color(0.82, 0.97, 1.0)

## How long the struts take to swing out once it bites. Fast enough to read as
## sprung rather than unfolded.
const STRUT_TIME := 0.12


func setup(gadget: GadgetData, draw_strength := 1.0) -> void:
	data = gadget
	power = clampf(draw_strength, 0.0, 1.0)


## Muzzle velocity for the draw it was loosed at.
func launch_speed() -> float:
	return lerpf(speed * 0.42, speed, power)


func _process(delta: float) -> void:
	_lit_clock += delta
	if _stuck:
		_struts = minf(_struts + delta / STRUT_TIME, 1.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_age += delta
	if _stuck:
		# Sticks in the wall for a moment as a marker, then is gone.
		if _age > data.active_time:
			queue_free()
		return

	velocity.y += gravity * delta
	var step := velocity * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step)
	query.collision_mask = Layers.WORLD | Layers.ONE_WAY | Layers.ENEMY
	var hit := get_world_2d().direct_space_state.intersect_ray(query)

	if hit:
		global_position = hit.position
		_land()
		return

	global_position += step
	rotation = velocity.angle()
	# An arrow that never hits anything is still an arrow: give up eventually.
	if _age > 6.0:
		queue_free()


## How wide a sweep this arrow paints, given how hard it was drawn.
func sweep_radius() -> float:
	return data.radius * lerpf(0.45, 1.0, power)


## Paints everyone near where it stuck, for as long as the gadget says.
func _land() -> void:
	_stuck = true
	_age = 0.0
	velocity = Vector2.ZERO

	var until := Time.get_ticks_msec() * 0.001 + data.active_time
	var revealed := 0
	for node in get_tree().get_nodes_in_group(&"hideable"):
		var target := node as Node2D
		if target and target.global_position.distance_to(global_position) <= sweep_radius():
			target.set_meta(&"revealed_until", until)
			revealed += 1
			# A guard does not care that he has been seen. A person does, and this
			# arrow exists only on the machine that loosed it - so the only way the
			# other end finds out is if we say so.
			if target.is_in_group(&"player"):
				Net.tell_scanned(target.get_multiplayer_authority())

	var pulse: Smoke = load("res://scenes/smoke.tscn").instantiate()
	pulse.setup(sweep_radius(), 0.9, Color(0.55, 0.85, 0.95, 0.32), false)
	pulse.global_position = global_position
	get_parent().add_child(pulse)
	set_meta(&"revealed_count", revealed)


## How much of the paint is left, 1 the moment it bites and 0 as it lapses.
func _charge_left() -> float:
	if not _stuck or data == null or data.active_time <= 0.0:
		return 1.0
	return clampf(1.0 - _age / data.active_time, 0.0, 1.0)


## The dart, nose along +x.
##
## Four parts, and every one of them is meant to look machined: a spike, a
## chamfered casing, two hard swept fins, and the strip. Nothing here is
## symmetrical-organic the way fletching is - the fins are straight lines at
## angles, because a straight line at an angle is what reads as manufactured at
## this size.
func _draw() -> void:
	var live := _charge_left()

	# The fins. Swept back off the tail, drawn before the casing so the casing
	# sits over their roots and they read as fixed to it rather than stuck on.
	for way in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-6.0, 1.4 * way),
			Vector2(-11.0, 6.2 * way),
			Vector2(-14.5, 6.2 * way),
			Vector2(-13.0, 1.4 * way),
		]), CASE)
		draw_polyline(PackedVector2Array([
			Vector2(-6.0, 1.4 * way),
			Vector2(-11.0, 6.2 * way),
			Vector2(-14.5, 6.2 * way),
			Vector2(-13.0, 1.4 * way),
		]), Color(EDGE, 0.7), 1.0)

	# The struts, which spring out when it bites. Nothing in flight, so a dart in
	# the air and a dart in a wall are two different silhouettes.
	if _struts > 0.0:
		# Short, and swept back rather than out. Long ones crossed the casing and
		# the dart read as a pair of open scissors - two barbs biting backwards
		# into the surface is the shape that says it is anchored there.
		var swing := _struts * _struts
		for way in [-1.0, 1.0]:
			var root := Vector2(4.5, 2.2 * way)
			var out := root + Vector2(-4.5, 4.2 * way) * swing
			draw_line(root, out, Color(EDGE, 0.9 * live), 1.6)

	# The casing: a slab with the nose chamfered off it.
	var shell := PackedVector2Array([
		Vector2(9.0, -1.6),
		Vector2(11.0, 0.0),
		Vector2(9.0, 1.6),
		Vector2(-13.0, 2.6),
		Vector2(-13.0, -2.6),
	])
	draw_colored_polygon(shell, CASE)
	var outline := shell.duplicate()
	outline.append(shell[0])
	draw_polyline(outline, Color(EDGE, 0.9), 1.0)

	# The spike. Short, bright and off-centre in weight - it is the part that has
	# to look like it goes into masonry.
	draw_colored_polygon(PackedVector2Array([
		Vector2(18.0, 0.0),
		Vector2(10.0, -1.7),
		Vector2(10.0, 1.7),
	]), Color(0.72, 0.88, 0.95))

	_draw_strip(live)


## The lit strip down the casing, and the nose lamp.
##
## In flight it breathes: a slow sine, the whole strip lit, which says powered
## and nothing else. Landed, the length of it *is* the paint remaining - it burns
## back from the nose as the sweep lapses, and blinks faster the less is left.
func _draw_strip(live: float) -> void:
	var from := -10.5
	var to := 7.5
	var lit_from := from
	var pulse := 0.55 + 0.2 * sin(_lit_clock * 3.4)
	if _stuck:
		# Burnt back from the nose, so what stays lit is the end with the lamp on
		# it. Draining the other way leaves the bright part stranded at the tail,
		# which reads as a dart with its light on the wrong end rather than as a
		# gauge running out.
		lit_from = to - (to - from) * live
		# Quickens as it runs out. A steady blink says "working"; one that speeds
		# up says "not for much longer", and that is the only warning there is
		# that a room is about to stop being painted.
		var rate := lerpf(14.0, 4.0, live)
		pulse = 0.55 + 0.45 * absf(sin(_lit_clock * rate))
	if lit_from < to:
		draw_line(Vector2(lit_from, 0.0), Vector2(to, 0.0), Color(LIT, pulse), 2.2)
	# The spent part is still drawn, faintly, so the strip is a gauge you read
	# against its own full length rather than a line that is simply shorter.
	if lit_from > from:
		draw_line(Vector2(from, 0.0), Vector2(lit_from, 0.0), Color(EDGE, 0.18), 2.2)

	# The lamp on the nose, which is the brightest thing on it either way.
	draw_circle(Vector2(9.4, 0.0), 2.6, Color(LIT, 0.20 * pulse))
	draw_circle(Vector2(9.4, 0.0), 1.3, Color(LIT, pulse))
