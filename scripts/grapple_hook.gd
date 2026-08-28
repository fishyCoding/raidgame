class_name GrappleHook
extends Node2D

## The hook on the end of the line: it flies, it bites into solid geometry, and
## then it holds while you are reeled in.
##
## Stepped by hand against the world the same way bullets and grenades are, for
## the same reason - a hook that tunnels through a wall at speed and anchors to
## the sky is worse than one that is a little less exact.
##
## It knows nothing about the player beyond who fired it. Whether being attached
## means you get pulled, or swing, or let go and fly, is the player's business -
## this is a line with a point on the end.
##
## One of these exists on every machine in the session for every hook thrown, and
## only the thrower's copy is listened to. The rest step themselves against the
## same static walls from the same muzzle in the same direction, which gets them
## to the same place; where the owner's copy actually bit is sent, because a rope
## that ends a few pixels inside a wall is visible from across the map. See
## Net.fire_grapple.

signal attached(anchor: Vector2)
## Ran out of line, or the anchor was lost. Either way there is nothing on the
## end of it any more.
signal missed()

## Pixels per second on the way out. Fast enough to feel like a shot rather than
## a thrown rope, slow enough that you watch it travel and know if it will reach.
@export var speed := 2200.0
## Furthest it will reach before giving up and falling away.
@export var max_range := 900.0
## How fast the line retracts on a miss, purely cosmetic.
@export var retract_speed := 3000.0

@export var line_colour := Color(0.78, 0.82, 0.88, 0.9)
@export var hook_colour := Color(0.95, 0.8, 0.45)

var owner_body: Node2D
var direction := Vector2.RIGHT

var _travelled := 0.0
var _anchored := false
var _retracting := false


func setup(from: Node2D, aim: Vector2) -> void:
	owner_body = from
	# A hook with no direction never travels, never runs out of line and never
	# frees itself - so an aim of nothing is thrown forward rather than nowhere.
	direction = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT


func _ready() -> void:
	z_index = 4
	# Hidden by the dark, like a body. Somebody else's rope drawn across an
	# unlit room tells you where they are, which way they are going and how fast
	# - all of it for free, and none of it earned by looking.
	add_to_group(&"shadowed")


func _physics_process(delta: float) -> void:
	# The hand it was thrown from can leave the raid while the line is still in
	# the air. There is nothing to reel back to and nothing to draw to, so it goes.
	if not is_instance_valid(owner_body):
		queue_free()
		return

	if _anchored:
		queue_redraw()
		return

	if _retracting:
		# Reeling the empty line back in. Nothing rides on it, so when it reaches
		# the hand it simply goes away.
		if global_position.distance_to(owner_body.global_position) < 24.0:
			queue_free()
			return
		var home := (owner_body.global_position - global_position).normalized()
		global_position += home * retract_speed * delta
		queue_redraw()
		return

	var step := direction * speed * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step)
	query.collision_mask = Layers.WORLD
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		# Sits a little proud of the surface so the line does not disappear into
		# the block it is holding on to.
		global_position = hit.position + (hit.normal as Vector2) * 3.0
		_anchored = true
		attached.emit(global_position)
		queue_redraw()
		return

	global_position += step
	_travelled += step.length()
	if _travelled >= max_range:
		_retracting = true
		missed.emit()
	queue_redraw()


## Called by the player when it lets go, or dies, or is otherwise done with it.
func release() -> void:
	if _anchored:
		queue_free()
		return
	_retracting = true


## Where the hook that counts actually bit.
##
## Only ever called on a copy that is watching somebody else's line. Its own
## raycast has almost certainly found the same wall a few pixels along - the
## hook moves 36 px in a frame and the two machines are not on the same frame -
## and "almost" is the difference between a rope that ends on a ledge and one
## that ends in mid-air next to it.
func bite(at: Vector2) -> void:
	global_position = at
	_retracting = false
	_anchored = true
	queue_redraw()


func is_anchored() -> bool:
	return _anchored


## Where to look for a hook, for line of sight: along the rope, hand to point.
##
## The rope is the giveaway rather than the hook itself. A line stretched a
## hundred pixels across a dark room says somebody is at the far end of it and
## roughly how fast they are travelling, which is more than you learn from seeing
## the person.
##
## Your own is always visible, and falls out of this rather than being a special
## case: one end of it is in your hand, so there is always a point on it you can
## see.
func sight_points() -> Array[Vector2]:
	var points: Array[Vector2] = [global_position]
	if not is_instance_valid(owner_body):
		return points
	var hand: Vector2 = owner_body.global_position
	points.append(hand)
	var span := hand.distance_to(global_position)
	var steps := clampi(int(span / 64.0), 1, 16)
	for i in range(1, steps):
		points.append(hand.lerp(global_position, float(i) / float(steps)))
	return points


func _draw() -> void:
	if not is_instance_valid(owner_body):
		return
	# Drawn in the hook's own space, so the line is a single segment back to the
	# hand however far either end has moved.
	var hand := to_local(owner_body.global_position)
	draw_line(hand, Vector2.ZERO, line_colour, 1.5, true)
	draw_circle(Vector2.ZERO, 4.0, hook_colour)
	if _anchored:
		# A bitten hook reads differently from one still in flight.
		draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 16, hook_colour, 1.5, true)
