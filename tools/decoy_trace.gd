extends SceneTree

## Watches one decoy journey closely, a line every few frames.
##
## The soak says how many arrive; this says why one of them did not. Kept as its
## own tool rather than a verbose flag on the soak, because the useful form here
## is a wall of per-frame state that would drown the summary.

## The journey to watch, overridable from the command line as x,y x,y.
var _from := Vector2(-2421.0, -80.0)
var _to := Vector2(-1053.0, 173.0)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_from = _point(args[0])
		_to = _point(args[1])
	_run()


func _point(text: String) -> Vector2:
	var bits := text.split(",")
	return Vector2(float(bits[0]), float(bits[1]))


func _run() -> void:
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await physics_frame
	var shop: Node = main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var screen: Node = get_first_node_in_group(&"map_screen")
	if screen:
		screen.dismiss()
	paused = false
	shop.visible = false
	await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("no character")
		quit(1)
		return
	for guard in main.get_node("Enemies").get_children():
		guard.set_physics_process(false)
		guard.set_process(false)

	var ghost: Node2D = (load("res://scenes/projection.tscn") as PackedScene).instantiate()
	ghost.name = "Ghost_trace"
	main.get_node("Players").add_child(ghost)
	ghost.global_position = _from
	ghost.velocity = Vector2.ZERO
	ghost.life_left = 90.0
	await physics_frame
	var _sent: bool = ghost.order_to(_to)

	print("-- %s -> %s --" % [str(_from), str(_to)])
	var map: GDScript = load("res://scripts/decoy_map.gd")
	print("   start run %d, finish run %d" % [
		map.run_at(self, _from), map.run_at(self, _to)])
	for leg in map.route(self, _from, _to):
		print("   %-6s %s -> %s" % [leg.kind, str(leg.from.round()), str(leg.to.round())])

	print("\n  frame  position                 target                  kind   floor ride vx     refuse")
	for i in 600:
		await physics_frame
		if not is_instance_valid(ghost):
			break
		if i % 10 == 0:
			print("  %5d  %-24s %-24s %-6s %-5s %-4s %-6.0f %-3d %-4d %.1f" % [
				i, str(ghost.global_position.round()), str(ghost._target.round()),
				ghost._leg_kind(), str(ghost.is_on_floor()), str(ghost.riding),
				ghost.velocity.x, ghost._refusals, ghost._legs.size(),
				ghost._detour_left])
		var gap := ghost.global_position - _to
		if absf(gap.x) <= 140.0 and absf(gap.y) <= 100.0:
			print("  arrived on frame %d" % i)
			break
	quit(0)
