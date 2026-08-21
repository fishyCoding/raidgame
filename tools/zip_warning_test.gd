extends SceneTree

## A cable with somebody on it, seen from the end they are heading for.
##
##   godot --headless --path . --script res://tools/zip_warning_test.gd
##
## A zipline is scenery for the whole raid until the moment a rider is on it, and
## the rider arrives on top of whoever is standing at the end. The cable turns
## amber to say so - but only for the person about to be landed on, or every
## cable in the level would be a light show for the whole match.
##
## Driven by planting a second rider directly rather than by joining a session:
## what is being tested is the *reading* of a replicated flag, and `riding` and
## the position it is read against are already replicated. See Zipline._process.

var _ok := true


func _initialize() -> void:
	_run()


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
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(20)

	var me: Node2D = net.local_player
	if me == null:
		_say("FAILED: never got a character")
		quit(1)
		return

	var cable: Node2D = _find_cable(main)
	_check("the level has a cable", cable != null)
	if cable == null:
		_finish()
		return
	_say("%s runs %.0f px" % [cable.name, cable.cable_length()])

	var top: Vector2 = cable.world_top()
	var bottom: Vector2 = cable.world_bottom()
	var middle: Vector2 = (top + bottom) * 0.5

	# --- an empty cable is scenery -------------------------------------------
	me.global_position = bottom
	await _wait(12)
	_check("an empty cable is not lit", not cable._warning_lit)

	# --- somebody else gets on it --------------------------------------------
	var rider := _plant_rider(net, main, middle)
	await _wait(12)
	_check("standing at the bottom, a rider lights it", cable._warning_lit)

	# --- but only for the person at the end ----------------------------------
	#
	# The whole point of the range. Every cable in the level lighting up whenever
	# anyone touched one would be worse than no warning at all: it is a jump
	# scare you are being warned about, and a warning you always see is scenery
	# again.
	me.global_position = bottom + Vector2(cable.WARN_RANGE + 400.0, 0.0)
	await _wait(12)
	_check("from across the yard it is not", not cable._warning_lit)

	# --- either end, not just the far one ------------------------------------
	me.global_position = top
	await _wait(12)
	_check("the top end warns too", cable._warning_lit)

	# --- and it goes out when they step off ----------------------------------
	rider.riding = false
	await _wait(12)
	_check("stepping off puts it out", not cable._warning_lit)

	# --- riding it yourself is not a warning ---------------------------------
	#
	# You start a ride at an end of the cable, so counting yourself would flash
	# the warning every time you grabbed one.
	rider.queue_free()
	net._players.erase(99)
	me.global_position = bottom
	me.riding = true
	await _wait(12)
	_check("your own ride does not warn you", not cable._warning_lit)
	me.riding = false

	_finish()


func _plant_rider(net: Node, main: Node, at: Vector2) -> Node2D:
	# A stand-in for a replica of another player: the cable reads `riding` and a
	# position off whatever Net hands back, and nothing else about a body.
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar riding := true\n"
	script.reload()
	var rider := Node2D.new()
	rider.set_script(script)
	rider.name = "PlantedRider"
	main.add_child(rider)
	rider.global_position = at
	net._players[99] = rider
	return rider


func _find_cable(node: Node) -> Node2D:
	for child in node.get_children():
		if child is Node2D and child.has_method(&"world_top"):
			return child
		var found := _find_cable(child)
		if found:
			return found
	return null


func _check(what: String, ok: bool) -> void:
	if not ok:
		_ok = false
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(text: String) -> void:
	print("zipwarn | %s" % text)


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
