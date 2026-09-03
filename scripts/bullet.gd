class_name Bullet
extends Node2D

## Raycast-stepped projectile: it sweeps the segment it would travel each frame
## instead of relying on overlap, so a 5200 px/s sniper round cannot tunnel
## through a 20 px platform.

const IMPACT_SCENE := preload("res://scenes/impact.tscn")

## What a round looks like at the top of its heat, whatever gun it came from.
## An overtiered cell is still an electrical thing running past what it was
## built for, not a fire - so the round it feeds does not shift toward warm
## and red, it shifts toward a hot, saturated blue-white, the colour an
## overloaded circuit throws rather than a burning one. Bright rather than
## deep on purpose: this has to read as *more* light coming off the round,
## not just a different hue of the same amount.
const OVERHEAT_COLOR := Color(0.45, 0.85, 1.0)

var direction := Vector2.RIGHT
var speed := 2800.0
var range_left := 2000.0
## Distance covered so far, which is what damage falloff is measured against.
var travelled := 0.0
## Who this round is allowed to hit. Set by the weapon that fired it, so the same
## projectile serves both sides without ever hitting its own shooter.
var hit_mask := Layers.PLAYER_SHOT
## Set by the weapon that fired it. Guards shoot for less than the same gun does
## in the player's hands, so a looted rifle is an upgrade rather than a wash.
var damage_scale := 1.0

## Who fired, so the hitmarker goes to them rather than to whoever happens to be
## resolving the hit. 0 means a guard - nobody to credit.
var shooter_id := 0
## Whether this copy is the one that counts. The host's rounds hurt; every other
## machine's are tracers of the same shot, drawn so you can see it coming.
var deals_damage := true

var _data: WeaponData
## The shooter's own collision body, kept out of every raycast this round makes.
## Rounds can hit players now, and the muzzle sits inside the holder's own hitbox
## at steep angles - without this, aiming up is a shot into your own chest.
## Excluded on every machine, not just the one that does damage, or the tracer
## everyone else sees would stop dead at the shooter's feet.
var _exclude: Array[RID] = []

@onready var _visual: Polygon2D = $Visual


## Builds a round and puts it in the world. The one place that knows how, so the
## weapon that fires and the wire that replicates it cannot drift apart.
static func spawn(tree: SceneTree, origin: Vector2, angle: float, data: WeaponData,
		mask: int, damage_scale: float, shooter: int, speed_scale := 1.0,
		heat := 0.0) -> Bullet:
	var bullet: Bullet = preload("res://scenes/bullet.tscn").instantiate()
	bullet.global_position = origin
	bullet.setup(Vector2.RIGHT.rotated(angle), data, mask, damage_scale, speed_scale, heat)
	bullet.shooter_id = shooter
	bullet.deals_damage = Net.deals_damage()
	bullet.ignore_shooter(shooter)
	var scene := tree.current_scene
	var parent: Node = scene.get_node_or_null(^"Bullets") if scene else null
	(parent if parent else (scene if scene else tree.root)).add_child(bullet)
	return bullet


func setup(dir: Vector2, data: WeaponData, mask := Layers.PLAYER_SHOT,
		damage_multiplier := 1.0, speed_multiplier := 1.0, heat := 0.0) -> void:
	direction = dir.normalized()
	_data = data
	hit_mask = mask
	damage_scale = damage_multiplier
	# A tier-overclocked energy cell speeds a round up the same way it hits
	# harder - see Gunsmith's ENERGY_SPEED_SCALE - and speed_multiplier is
	# how that survives the trip to a machine that only has the unmodified
	# WeaponData to build a bullet from. See Net.fire().
	speed = data.bullet_speed * speed_multiplier
	range_left = data.bullet_range
	rotation = direction.angle()
	# _visual is not ready yet when the weapon calls this, so stash the look.
	# `heat` is the shooter's Weapon.heat at the instant this round left the
	# barrel, 0 unless it was fired on an overtiered cell - see Weapon.gd and
	# Net.fire(). It rides the wire the same way speed_scale does, so a round
	# reads the same on the machine that watches it as it does on the one
	# that fired it.
	set_meta(&"color", data.bullet_color)
	set_meta(&"length", data.bullet_length)
	set_meta(&"width", data.bullet_width)
	set_meta(&"heat", heat)


## Keeps the round from hitting whoever fired it. A guard answers 0 and needs
## nothing: Layers.ENEMY_SHOT already leaves guards out.
func ignore_shooter(id: int) -> void:
	_exclude.clear()
	if id == 0:
		return
	var body := Net.player_for(id) as CollisionObject2D
	if body:
		_exclude.append(body.get_rid())


func _ready() -> void:
	var length: float = get_meta(&"length", 16.0)
	var width: float = get_meta(&"width", 2.5)
	var color: Color = get_meta(&"color", Color.WHITE)
	var heat: float = get_meta(&"heat", 0.0)

	# A round fired hot does not just look like a faster version of the same
	# shot - it is meant to read as a different gun firing it. Colour carries
	# most of that: by the time heat is near the ceiling the tracer has left
	# its own bullet_color behind entirely for OVERHEAT_COLOR, and lightened
	# again on top of that lerp - the target colour is already bright, and a
	# round at the ceiling should look like it is throwing more light than
	# one only halfway there. Width and length climb hard with it too - a
	# burst that is running away from you looks like it, round by round,
	# well before the trigger actually locks, and a fully hot round is
	# unmistakably a bigger round rather than a subtly wider one.
	if heat > 0.0:
		var h := clampf(heat, 0.0, 1.0)
		color = color.lerp(OVERHEAT_COLOR, h).lightened(h * 0.4)
		width *= 1.0 + h * 2.2
		length *= 1.0 + h * 0.8

	_visual.color = color
	_visual.polygon = PackedVector2Array([
		Vector2(0.0, -width * 0.5),
		Vector2(length, -width * 0.5),
		Vector2(length, width * 0.5),
		Vector2(0.0, width * 0.5),
	])


func _physics_process(delta: float) -> void:
	var step := minf(speed * delta, range_left)
	var from := global_position
	var to := from + direction * step

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = hit_mask
	query.exclude = _exclude
	var hit := get_world_2d().direct_space_state.intersect_ray(query)

	if hit:
		# The impact spark is drawn everywhere - it is how the shot reads - but
		# only the host's copy of the round is allowed to have consequences.
		_impact(hit.position, hit.normal)
		var body: Object = hit.collider
		if deals_damage and body.has_method(&"take_damage"):
			var flight := travelled + from.distance_to(hit.position)
			# Set around the call rather than threaded through it: everything
			# downstream that wants to know who fired reads it from here.
			Net.attributing_to = shooter_id
			Net.piercing = _data.armor_pierce
			Net.armor_wear = _data.armor_wear_scale
			body.take_damage(_data.get_damage_at(flight) * damage_scale,
				hit.position, direction)
			Net.piercing = 0.0
			Net.armor_wear = 1.0
			Net.attributing_to = 0
		queue_free()
		return

	global_position = to
	travelled += step
	range_left -= step
	if range_left <= 0.0:
		queue_free()


func _impact(at: Vector2, normal: Vector2) -> void:
	var impact := IMPACT_SCENE.instantiate()
	impact.global_position = at
	impact.rotation = normal.angle()
	impact.modulate = _visual.color
	_get_effect_parent().add_child(impact)


func _get_effect_parent() -> Node:
	var parent := get_parent()
	return parent if parent != null else get_tree().root
