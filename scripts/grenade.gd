class_name Grenade
extends Node2D

## Something thrown: it arcs, it bounces off the level, and after its fuse it
## either kills people or blinds them.
##
## Movement is stepped by hand rather than given to the physics engine, for the
## same reason bullets are: a grenade that tunnels through a floor at speed is
## worse than one that is slightly less bouncy.

const GRAVITY := 1300.0
const BOUNCE := 0.42
const SMOKE_SCENE := preload("res://scenes/smoke.tscn")
## Least fraction of full damage anything inside the blast takes, however close
## to the edge it was standing. Being clipped by a frag is never nothing.
const KILL_FLOOR := 0.22
## How far back from a sampled point the line-of-blast ray stops. Matches the
## vision system's probe_inset, and for the same reason: a ray that ends exactly
## on a surface is a coin flip about whether it hit it.
const PROBE_INSET := 4.0

var data: GadgetData
var velocity := Vector2.ZERO
## Who threw it, so a frag does not blame the thrower for its own damage mask.
var hit_mask := Layers.PLAYER_SHOT

## Who threw it, for the hitmarker. 0 is a guard's.
var thrower_id := 0

var _fuse := 0.0
@onready var _visual: Polygon2D = $Visual


func setup(gadget: GadgetData, throw_velocity: Vector2, mask: int) -> void:
	data = gadget
	velocity = throw_velocity
	hit_mask = mask
	_fuse = gadget.fuse


func _ready() -> void:
	if data == null:
		queue_free()
		return
	_visual.color = data.tint


func _physics_process(delta: float) -> void:
	_fuse -= delta
	if _fuse <= 0.0:
		_detonate()
		return

	velocity.y += GRAVITY * delta
	var step := velocity * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step)
	query.collision_mask = Layers.WORLD
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		# Bounce off the surface and lose most of the energy, so grenades settle
		# in a corner rather than pinballing around the level.
		global_position = hit.position + (hit.normal as Vector2) * 2.0
		velocity = velocity.bounce(hit.normal) * BOUNCE
	else:
		global_position += step

	rotation += velocity.x * delta * 0.02


func _detonate() -> void:
	var audio := get_node_or_null(^"/root/Audio")
	match data.kind:
		GadgetData.Kind.SMOKE:
			var cloud := SMOKE_SCENE.instantiate()
			cloud.setup(data.radius, data.duration)
			cloud.global_position = global_position
			_field().add_child(cloud)
			# A smoke grenade is a dull thump and a long hiss, not a bang - but it
			# is still a grenade going off, and it still gives your position away.
			if audio:
				audio.explosion(global_position, 0.45)
		_:
			_blast()
			if audio:
				audio.explosion(global_position, 1.0)
	queue_free()


## Damage falling off from the centre, to anything the blast can actually reach.
##
## Solid geometry stops it. A shape query answers "is inside the radius", which
## is a circle drawn straight through walls - so a frag dropped in a stairwell
## used to kill the room above, the room below and everyone on the far side of a
## foot of concrete. Cover is most of what this level is made of, and a grenade
## that ignores it makes standing behind any of it pointless.
##
## Deliberately *not* VisionSystem._can_see, which is the other half of the same
## question and the wrong half: it also stops at smoke, and a smoke grenade must
## not be armour. Only the geometry mask - and only WORLD, not ONE_WAY, so the
## catwalk you can see through is one you can be fragged through too.
func _blast() -> void:
	# Everyone sees the flash; only the host's copy of the grenade decides what
	# it did. Without this every machine resolves the same blast against its own
	# replicas and the damage is applied as many times as there are players.
	if not Net.deals_damage():
		_flash()
		return

	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = data.radius
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = hit_mask

	for touch in space.intersect_shape(query, 16):
		var body: Object = touch.collider
		if body == null or not body.has_method(&"take_damage"):
			continue
		var target := body as Node2D
		if not _reaches(space, target):
			continue
		var distance := global_position.distance_to(target.global_position)
		var falloff := clampf(1.0 - distance / maxf(data.radius, 1.0), 0.0, 1.0)
		# Squaring the falloff meant a grenade landing an arm's length away did
		# a quarter of its damage, which made the whole radius decorative - you
		# effectively had to score a direct hit. The gentler curve, plus a floor
		# under anything caught at all, makes the blast worth its fuse: close is
		# lethal, and being inside the radius at all is being hurt.
		var amount := data.damage * pow(falloff, 1.35)
		if falloff > 0.0:
			amount = maxf(amount, data.damage * KILL_FLOOR)
		if amount <= 1.0:
			continue
		# Aimed at the body, never the head: a grenade should not headshot you
		# from below the floor.
		Net.attributing_to = thrower_id
		body.take_damage(amount, target.global_position + Vector2(0.0, 8.0),
			(target.global_position - global_position).normalized())
		Net.attributing_to = 0

	_flash()


## Whether a straight line from the blast gets to any part of this body.
##
## Any one point is enough, and the whole outline is sampled rather than the
## centre alone: leaning out of a doorway, most of you is behind the frame, and a
## centre-only test would say the wall saved you when a shoulder is in the open.
## The same sampler concealment uses, so what counts as cover from a grenade and
## what counts as cover from a guard's eyes are the same shape.
func _reaches(space: PhysicsDirectSpaceState2D, target: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = Layers.WORLD
	for point in _points_on(target):
		# Pulled a little back towards the blast, so a body pressed flat against a
		# wall is not tested at a point that is inside it.
		var probe := point
		var toward := global_position - point
		if toward.length() > PROBE_INSET:
			probe += toward.normalized() * PROBE_INSET
		query.from = global_position
		query.to = probe
		if space.intersect_ray(query).is_empty():
			return true
	return false


## The outline of a body, from the vision system if the level has one - it owns
## the tuning for how finely to walk it - and the centre alone if not, which is
## what a level with no vision system in it wants anyway.
func _points_on(target: Node2D) -> Array[Vector2]:
	var vision := get_tree().get_first_node_in_group(&"vision_system")
	if vision and vision.has_method(&"sample_points"):
		return vision.sample_points(target)
	return [target.global_position] as Array[Vector2]


func _flash() -> void:
	var flash := SMOKE_SCENE.instantiate()
	flash.setup(data.radius * 0.5, 0.35, Color(1.0, 0.86, 0.5, 0.55), false)
	flash.global_position = global_position
	_field().add_child(flash)


func _field() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root
