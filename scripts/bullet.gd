class_name Bullet
extends Node2D

## Raycast-stepped projectile: it sweeps the segment it would travel each frame
## instead of relying on overlap, so a 5200 px/s sniper round cannot tunnel
## through a 20 px platform.

const IMPACT_SCENE := preload("res://scenes/impact.tscn")

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
		mask: int, damage_scale: float, shooter: int) -> Bullet:
	var bullet: Bullet = preload("res://scenes/bullet.tscn").instantiate()
	bullet.global_position = origin
	bullet.setup(Vector2.RIGHT.rotated(angle), data, mask, damage_scale)
	bullet.shooter_id = shooter
	bullet.deals_damage = Net.deals_damage()
	bullet.ignore_shooter(shooter)
	var scene := tree.current_scene
	var parent: Node = scene.get_node_or_null(^"Bullets") if scene else null
	(parent if parent else (scene if scene else tree.root)).add_child(bullet)
	return bullet


func setup(dir: Vector2, data: WeaponData, mask := Layers.PLAYER_SHOT,
		damage_multiplier := 1.0) -> void:
	direction = dir.normalized()
	_data = data
	hit_mask = mask
	damage_scale = damage_multiplier
	speed = data.bullet_speed
	range_left = data.bullet_range
	rotation = direction.angle()
	# _visual is not ready yet when the weapon calls this, so stash the look.
	set_meta(&"color", data.bullet_color)
	set_meta(&"length", data.bullet_length)
	set_meta(&"width", data.bullet_width)


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
	_visual.color = get_meta(&"color", Color.WHITE)
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
			body.take_damage(_data.get_damage_at(flight) * damage_scale,
				hit.position, direction)
			Net.piercing = 0.0
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
