class_name Target
extends StaticBody2D

## Practice dummy, so weapon damage and shot patterns are visible while testing.
## Flashes on hit, prints floating damage, breaks, and comes back.

@export var max_health := 120.0
@export var respawn_time := 3.0
@export var size := Vector2(44, 72)

var _health: float

@onready var _visual: Polygon2D = $Visual
@onready var _health_fill: Polygon2D = $HealthBar/Fill
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = Layers.TARGET
	collision_mask = 0
	var half := size * 0.5
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	(_shape.shape as RectangleShape2D).size = size
	$HealthBar.position = Vector2(0.0, -half.y - 12.0)
	_reset()


func take_damage(amount: float, at: Vector2, _direction: Vector2) -> void:
	if _health <= 0.0:
		return
	_health = maxf(_health - amount, 0.0)
	_health_fill.scale.x = _health / max_health
	_spawn_damage_number(amount, at)

	var tween := create_tween()
	_visual.color = Color(1, 1, 1)
	tween.tween_property(_visual, "color", _color_for_health(), 0.18)

	# The range targets confirm hits too - that is what they are for.
	Damage.report_hit(get_tree(), false, _health <= 0.0)
	if _health <= 0.0:
		_break()


func _color_for_health() -> Color:
	return Color(0.85, 0.35, 0.35).lerp(Color(0.4, 0.75, 0.55), _health / max_health)


func _break() -> void:
	# Leaving the group stops the vision system from drawing a corpse back in
	# just because it happens to be in line of sight.
	remove_from_group(&"hideable")
	visible = false
	_shape.set_deferred(&"disabled", true)
	await get_tree().create_timer(respawn_time).timeout
	_reset()


func _reset() -> void:
	_health = max_health
	_health_fill.scale.x = 1.0
	_visual.color = _color_for_health()
	_shape.set_deferred(&"disabled", false)
	if not is_in_group(&"hideable"):
		add_to_group(&"hideable")
	# Come back at whatever visibility line of sight says, so respawning in
	# cover does not flash a frame of free information.
	var vision := get_tree().get_first_node_in_group(&"vision_system") as VisionSystem
	visible = vision.is_seen(self) if vision else true


func _spawn_damage_number(amount: float, at: Vector2) -> void:
	# Hits on something you cannot see stay silent: a damage number floating out
	# of the dark would hand you the position for free.
	if not visible:
		return

	var label := Label.new()
	label.text = str(roundi(amount))
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.93, 0.6))
	label.z_index = 10
	# Onto the overlay layer if the level has one: a readout the ambient darkness
	# has dimmed to near-black is no readout at all.
	var overlay := get_tree().get_first_node_in_group(&"world_overlay")
	(overlay if overlay else get_parent()).add_child(label)
	label.global_position = at + Vector2(randf_range(-8, 8), -10)

	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position",
		label.global_position + Vector2(randf_range(-14, 14), -34), 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
