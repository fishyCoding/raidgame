extends SceneTree

## Every zipline in a map, checked for the two ways one actually breaks in
## play: climbing it sends you the wrong way, or the top has nowhere to
## arrive into.
##
##   godot --headless --path . --script res://tools/zipline_audit.gd
##   godot --headless --path . --script res://tools/zipline_audit.gd -- --scene=res://scenes/main.tscn
##
## Orientation is the one Player._update_zipline actually depends on: holding
## the climb key moves the rider toward world_top(), so for "up" to be
## physically up, world_top().y has to be the smaller of the two - Y grows
## downward in Godot 2D. A cable with top/bottom swapped sends a climbing
## rider down instead.
##
## Two other checks were tried here and dropped:
##
## Box-overlap at each endpoint and a raycast along the whole span, against
## real physics rather than hand-read coordinates, flagged 106 of 108 quarry
## cables on the first run. Ziplines here are routinely mounted flush against
## whatever they connect to - the anchor touching the dock it is bolted to is
## the normal case, not a bug - and a rider's position is set directly onto
## the endpoint every frame (Player._update_zipline, `global_position =
## pinned`) with no swept collision along the way, so a rope's drawn line
## passing near a wall corner has no gameplay consequence at all.
##
## tools/cable_probe.gd's 900px-down floor check was tried too. Its own
## docstring says what it is actually for: the *decoy/projection AI's
## routing* - whether a ghost can pathfind to use a cable - not whether a
## player can. A player grabs a cable directly by walking into grab_range
## (Zipline.in_reach/nearest), no floor check anywhere in that path, and this
## map's whole reason for having ziplines is fast travel between floors that
## are - intentionally - far apart. Reusing it here flagged 57 of 108 cables,
## nearly all of them ordinary multi-storey lifts working as designed.
##
## Ceiling clearance at the top is the one shape of "runs into a block" left
## that is a real, checkable problem: arriving there hands control back to
## ordinary physics, and a ceiling close enough to overlap a standing player
## leaves them shoved out or wedged the instant they let go.

## Solid geometry only, matching zipline.gd's own sight-check mask.
const SOLID_MASK := 1  # Layers.WORLD
## How much clear air a standing player needs above the top point. A little
## over PLAYER_SIZE.y so a rider is not left with their head in the ceiling.
const CEILING_CLEARANCE := 56.0


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene_path := "res://scenes/quarry.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.get_slice("=", 1)

	var level: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for i in 6:
		await physics_frame

	var space: PhysicsDirectSpaceState2D = level.get_world_2d().direct_space_state
	var lines := get_nodes_in_group(&"zipline")
	print("%s | %d ziplines" % [scene_path, lines.size()])

	var failures := 0
	for node in lines:
		var line: Node2D = node
		var top: Vector2 = line.world_top()
		var bottom: Vector2 = line.world_bottom()
		var bad: Array[String] = []

		if top.y >= bottom.y:
			bad.append("UPSIDE DOWN (top.y %.0f >= bottom.y %.0f)" % [top.y, bottom.y])

		var headroom: Variant = _ceiling_clearance(space, top)
		if headroom != null and headroom < CEILING_CLEARANCE:
			bad.append("top has only %.0fpx of headroom (want %.0f) - climbing into it" %
				[headroom, CEILING_CLEARANCE])

		if not bad.is_empty():
			failures += 1
			print("  %s" % line.name)
			for line_text in bad:
				print("    - %s" % line_text)

	print("\n%d of %d ziplines clean" % [lines.size() - failures, lines.size()])
	quit(1 if failures > 0 else 0)


## How far off the exact top point the ray starts. A cable's top usually sits
## right on the surface of the platform it lands you on - that is the point,
## not a bug - and a ray that starts exactly on a boundary can register that
## same surface as a zero-distance hit. One pixel of clearance is nowhere near
## enough to hide an actual low ceiling, only enough to stop measuring the
## floor the rider is about to be standing on.
const START_INSET := 2.0


## Clear air straight up from the top point, or null if there is nothing
## within CEILING_CLEARANCE to hit at all (which just means "plenty of room").
func _ceiling_clearance(space: PhysicsDirectSpaceState2D, top: Vector2) -> Variant:
	var from := top - Vector2(0.0, START_INSET)
	var query := PhysicsRayQueryParameters2D.create(from, top + Vector2(0.0, -CEILING_CLEARANCE))
	query.collision_mask = SOLID_MASK
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return top.y - (hit.position as Vector2).y
