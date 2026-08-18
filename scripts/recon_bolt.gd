class_name ReconBolt
extends Node2D

## The recon bow's arrow.
##
## It flies rather than teleports: fast, but it drops over distance and takes
## time to arrive, so painting a room across the level means leading the shot.
## Where it sticks is where the sweep is centred, so a bad arrow is a wasted
## ultimate - which is the price of it being an ultimate rather than a gadget.

## Muzzle velocity, pixels per second.
@export var speed := 1500.0
## Arrows drop. Not much, but enough that a long shot has to be aimed high.
@export var gravity := 260.0

var velocity := Vector2.ZERO
var data: GadgetData
## How far the bow was drawn, 0 to 1. A half-drawn arrow flies slower, drops
## sooner and sweeps a smaller area - the shot is worth what you put into it.
var power := 1.0

var _stuck := false
var _age := 0.0


func setup(gadget: GadgetData, draw_strength := 1.0) -> void:
	data = gadget
	power = clampf(draw_strength, 0.0, 1.0)


## Muzzle velocity for the draw it was loosed at.
func launch_speed() -> float:
	return lerpf(speed * 0.42, speed, power)


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
