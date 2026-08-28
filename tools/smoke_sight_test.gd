extends SceneTree

## Smoke you cannot see should not be drawn - and a cloud must not be the thing
## that hides itself.
##
## The self-hiding trap is the whole reason this file exists. Sight is tested by
## drawing a line from the eye to a point on the target and asking every cloud on
## the map whether it crosses one. Point that at a cloud's own rim and the line
## ends inside the disc being asked about, so the honest answer is "blocked" and
## a smoke screen would be invisible to everybody, including whoever threw it.
## Smoke.blocks_sight takes an exception for exactly that, and this checks it in
## both directions - the cloud not hiding itself, and still hiding everything
## else.

const SMOKE_SCENE := "res://scenes/smoke.tscn"
const RADIUS := 120.0

var _failures: Array[String] = []


func _init() -> void:
	await process_frame
	var scene := load(SMOKE_SCENE) as PackedScene

	var cloud: Node2D = scene.instantiate()
	cloud.setup(RADIUS, 30.0)
	root.add_child(cloud)
	cloud.global_position = Vector2.ZERO

	# Let it billow, and thicken past the opacity that counts as cover.
	for i in 40:
		await process_frame

	_want("a real cloud joins the smoke group", cloud.is_in_group(&"smoke"))
	# The point of the change: it is scenery the dark swallows, not an overlay.
	_want("and the group the dark swallows", cloud.is_in_group(&"shadowed"))
	_want("it is thick enough to count as cover", cloud._opacity() >= 0.35)

	# --- the trap ------------------------------------------------------------
	var eye := Vector2(-600.0, 0.0)
	var rim: Array = cloud.sight_points()
	_want("it offers a rim rather than a point", rim.size() > 1)
	var r: float = cloud._current_radius()
	var on_rim := true
	for point in rim:
		if (point as Vector2).distance_to(cloud.global_position) > r + 0.01:
			on_rim = false
	_want("every point is on or inside the cloud", on_rim)

	var far_rim: Vector2 = cloud.global_position + Vector2(r, 0.0)
	_want("a line to its own edge is blocked by it, asked naively",
		Smoke.blocks_sight(self, eye, far_rim))
	_want("but not when the cloud is what you are looking at",
		not Smoke.blocks_sight(self, eye, far_rim, cloud))

	# --- and it still hides everything else ----------------------------------
	var behind := Vector2(600.0, 0.0)
	_want("it still hides what is behind it", Smoke.blocks_sight(self, eye, behind))
	_want("and still hides it when excepting a different cloud",
		Smoke.blocks_sight(self, eye, behind, cloud.duplicate()))
	_want("a line nowhere near it passes", not Smoke.blocks_sight(
		self, Vector2(-600.0, 900.0), Vector2(600.0, 900.0)))

	# --- a pop the rim sampling exists to prevent ----------------------------
	#
	# Not a line-of-sight test, an arithmetic one: the far rim of a cloud is a
	# radius away from its centre, so a wall that hides the centre does not
	# necessarily hide the cloud. Sampling one point would throw the whole thing
	# away; this is the property that stops it.
	var spread := 0.0
	for point in rim:
		spread = maxf(spread, (point as Vector2).distance_to(cloud.global_position))
	_want("the rim reaches out to the cloud's real size", spread > r * 0.9)

	cloud.queue_free()
	if _failures.is_empty():
		print("OK - smoke hides what is behind it, not itself")
	else:
		for line in _failures:
			print("FAIL - %s" % line)
		print("FAILED %d check(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _want(what: String, got: Variant) -> void:
	if typeof(got) != TYPE_BOOL:
		_failures.append("%s: did not answer (got %s)" % [what, got])
		print("  FAIL %-52s no answer" % what)
		return
	if got:
		print("  ok   %s" % what)
	else:
		_failures.append(what)
		print("  FAIL %s" % what)
