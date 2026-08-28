class_name VisionSystem
extends Node

## Hard line of sight. Every node in the "hideable" group is raycast from the
## player's eye each physics frame and hidden outright if no ray reaches it.
##
## This is deliberately not a lighting effect: a dimmed enemy is still an enemy
## you can see, which is no use for stealth. Anything out of sight is simply not
## drawn, so cover conceals completely.
##
## Only visuals are touched. Collision is untouched, so what you can shoot and
## what you can see never disagree: rounds aimed at something you cannot see
## still hit the cover in front of it.

signal spotted(node: Node2D)
signal lost(node: Node2D)

## Sight is blocked by solid geometry only. One-way platforms are thin catwalks:
## you can see under and over them, but rounds still stop dead against them.
const SIGHT_MASK := Layers.WORLD

## Floor for how far sight reaches. Only a floor: what actually decides the
## cut-off is how much world the camera is showing, worked out in _sight_reach().
##
## This used to be the whole answer, at the reach of the player's vision light,
## so that nothing could be drawn out where the level was pitch black. The level
## is not pitch black any more - main.tscn's Ambient is switched off - and a
## fixed radius had become something you could watch working: guards blinking out
## of existence in mid-air at a fixed distance, most obviously through a scope,
## which zooms out far enough to put the boundary well inside the frame.
##
## The numbers were never close. At the default 0.75 zoom the corner of a 1280x720
## screen is already about 980 px from the player; at a full bow draw it is past
## 1400. This was visible in ordinary play, not just while sniping.
@export var vision_range := 880.0

## Slack past the corner of the screen. Bodies are resolved slightly before they
## could scroll into view, rather than in the frame they arrive.
@export var offscreen_margin := 128.0

## Rays stop a few pixels short of their target, so something resting against a
## wall (an impact spark, a crate on the floor) is not judged to be inside it.
@export var probe_inset := 6.0

## Corner samples are pulled in by this much, so grazing a corner does not
## reveal a whole body.
@export var corner_inset := 5.0

## Sample points taken along each edge of a body's outline. Higher catches
## slivers of a body showing past cover; 4 gives 17 rays per body.
@export_range(1, 12) var samples_per_edge := 4

var _eye: Node2D
var _visible_set := {}
## How far sight reaches this frame. Recomputed once per physics frame rather
## than per body, because it is the same answer for all of them.
var _reach := 880.0


func _ready() -> void:
	# After gameplay has moved everything this frame, before PlayerInput (500)
	# clears its one-frame flags.
	process_physics_priority = 400


func _physics_process(_delta: float) -> void:
	if not _resolve_eye():
		return

	var space := _eye.get_world_2d().direct_space_state
	var origin := _eye.global_position
	_reach = _sight_reach()

	for node in get_tree().get_nodes_in_group(&"hideable"):
		var node_2d := node as Node2D
		if node_2d == null:
			continue
		var seen := is_revealed(node_2d) or _can_see(space, origin, node_2d)
		if node_2d.visible == seen:
			continue
		node_2d.visible = seen
		if seen:
			spotted.emit(node_2d)
		else:
			lost.emit(node_2d)

	# Scenery that the dark should swallow too. Its own group rather than
	# "hideable", which means "a body that can be revealed" - the recon arrow
	# paints those and pins a marker to each, and a diamond hovering over every
	# rope on the map is not what that gadget is for.
	for node in get_tree().get_nodes_in_group(&"shadowed"):
		var scenery := node as Node2D
		if scenery == null:
			continue
		var lit := _can_see(space, origin, scenery)
		if scenery.visible != lit:
			scenery.visible = lit


## Whether a straight line between two points is clear of everything that stops
## light: geometry, smoke and screens.
##
## Deliberately not _can_see and deliberately not is_seen. Both of those measure
## a *body* - they sample its outline, and they give up past _sight_reach, which
## is the corner of the screen plus a margin. This is asked about points, at any
## distance, by things that need to know whether two places can see each other
## rather than whether something is on screen. The sniper glint is the first
## caller: the whole value of it is that it reaches you from further away than
## you can see, so a reach cut-off would have quietly deleted the mechanic at
## exactly the ranges it is for.
func line_is_clear(from: Vector2, to: Vector2) -> bool:
	# The eye is only being used for the world it stands in - the line itself is
	# given. No eye means no session to ask about, and permissive is the right
	# way to be wrong: a mark that shows when it should not is a player looking
	# at the wrong window, and one that never shows is a mechanic that silently
	# does not exist.
	if not _resolve_eye():
		return true
	var space := _eye.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = SIGHT_MASK
	if not space.intersect_ray(query).is_empty():
		return false
	if Smoke.blocks_sight(get_tree(), from, to):
		return false
	return not Screen.blocks_sight(get_tree(), from, to)


## True if anything currently has line of sight on this node.
## Nodes revealed by a recon shot stay drawn even with no line of sight to them,
## until their reveal runs out.
func is_revealed(node: Node2D) -> bool:
	var until: Variant = node.get_meta(&"revealed_until", 0.0)
	return typeof(until) == TYPE_FLOAT and Time.get_ticks_msec() * 0.001 < until


func is_seen(node: Node2D) -> bool:
	if not _resolve_eye():
		return true
	# Asked outside the physics tick as well as inside it, so the reach is
	# refreshed here rather than trusted to be this frame's.
	_reach = _sight_reach()
	return _can_see(_eye.get_world_2d().direct_space_state, _eye.global_position, node)


func _resolve_eye() -> bool:
	if is_instance_valid(_eye):
		return true
	var player := Net.local_player
	if player == null:
		return false
	_eye = player.get_node_or_null(^"Vision")
	return _eye != null


## How far to bother looking: past the furthest corner of what is on screen, so
## the edge of the cut-off is always outside the frame.
##
## Kept as a cut-off rather than removed outright because it is what stops every
## body on the map being raycast seventeen times a frame. The point is not that
## there is a limit - it is that you can never see where it falls.
func _sight_reach() -> float:
	var viewport := _eye.get_viewport()
	if viewport == null:
		return vision_range
	var camera := viewport.get_camera_2d()
	if camera == null or camera.zoom.x <= 0.0 or camera.zoom.y <= 0.0:
		return vision_range
	# Viewport pixels divided by zoom is world units, so a zoom below 1 - which
	# is what aiming and the bow both do - widens this rather than narrowing it.
	var half_view := (viewport.get_visible_rect().size / camera.zoom) * 0.5
	# Measured from the eye rather than the lens: aiming leans the camera off the
	# body, which puts the far corner of the screen further away than the camera's
	# own half-diagonal admits.
	var lean := _eye.global_position.distance_to(camera.get_screen_center_position())
	return maxf(vision_range, half_view.length() + lean + offscreen_margin)


func _can_see(space: PhysicsDirectSpaceState2D, origin: Vector2, node: Node2D) -> bool:
	# Long things are measured point by point. A body is small enough that its
	# origin stands for all of it, but a cable is hundreds of pixels of rope: its
	# origin is one end, and a rope whose near half is in plain view would be
	# thrown out for having its far end out of range.
	var long := node.has_method(&"sight_points")
	if not long and origin.distance_squared_to(node.global_position) > _reach * _reach:
		return false

	for point in sample_points(node):
		if long and origin.distance_squared_to(point) > _reach * _reach:
			continue
		var probe := point
		var toward_eye := origin - point
		if toward_eye.length() > probe_inset:
			probe += toward_eye.normalized() * probe_inset

		var query := PhysicsRayQueryParameters2D.create(origin, probe)
		query.collision_mask = SIGHT_MASK
		if not space.intersect_ray(query).is_empty():
			continue
		# Geometry is not the only thing that hides people.
		if Smoke.blocks_sight(get_tree(), origin, probe, node):
			continue
		# A screen shows you the room without the people in it. Checked here,
		# against bodies, rather than added to SIGHT_MASK - a screen is not a
		# wall and must not read as one anywhere. The level behind it draws
		# exactly as it always did; only what is alive back there goes missing.
		if Screen.blocks_sight(get_tree(), origin, probe):
			continue
		return true
	return false


## Points sampled around the outline of anything with a size, otherwise a single
## point. Any one of them being reachable counts as seen. Sampling only the
## corners makes a body pop in and out as it slides past cover, so the outline is
## walked at a fixed spacing instead.
##
## Public because a blast asks the same geometric question - which parts of this
## body can a straight line reach - even though it asks it about shrapnel rather
## than about light, and must not use _can_see to do it: smoke hides you and does
## not stop a frag. See Grenade._reaches.
func sample_points(node: Node2D) -> Array[Vector2]:
	# Anything that is not shaped like a box says where to look for it itself.
	if node.has_method(&"sight_points"):
		return node.sight_points()

	# Where the middle of the body actually is. A guard's box is centred on his
	# origin, but a player's shrinks from the top as they crouch and crawl, so
	# the origin stops being the centre of what is left - and sampling around it
	# would test the empty air above somebody lying flat.
	var centre := node.global_position
	if node.has_method(&"sight_centre"):
		centre = node.sight_centre()
	var points: Array[Vector2] = [centre]

	var size_value: Variant = node.get(&"size")
	if typeof(size_value) != TYPE_VECTOR2:
		return points

	var half: Vector2 = (size_value as Vector2) * 0.5 - Vector2.ONE * corner_inset
	half.x = maxf(half.x, 0.0)
	half.y = maxf(half.y, 0.0)

	var steps := maxi(samples_per_edge, 1)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := lerpf(-half.x, half.x, t)
		var y := lerpf(-half.y, half.y, t)
		points.append(centre + Vector2(x, -half.y)) # top edge
		points.append(centre + Vector2(x, half.y))  # bottom edge
		points.append(centre + Vector2(-half.x, y)) # left edge
		points.append(centre + Vector2(half.x, y))  # right edge

	return points
