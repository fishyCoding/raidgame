extends SceneTree

## Does a touch_* flag set between frames survive to the character?
##
##   godot --headless --path . --script res://tools/touch_probe.gd
##
## PlayerInput exposes touch_* flags for a HUD to set and clears them all in its
## own _physics_process. It is an autoload, so it sits before the level in the
## tree and its _physics_process runs first. A UI callback lands outside the
## physics step, so the question is whether the flag survives the tick or is
## wiped by the very node that owns it before Player ever looks.
##
## Set straight rather than through a Button: a click has to be delivered by the
## GUI, which is one more thing that can be the reason nothing happened, and the
## claim here is only about ordering.

func _initialize() -> void:
	_run()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var input: Node = root.get_node("PlayerInput")
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
	await physics_frame

	var player: Node2D = net.local_player
	if player == null:
		print("touch | FAILED: never got a character")
		quit(1)
		return

	var settled := 0
	while not player.is_on_floor() and settled < 300:
		await physics_frame
		settled += 1
	print("touch | on the floor: %s" % player.is_on_floor())

	# --- a one-shot press, the way a HUD button would raise it ---------------
	var floor_y: float = player.global_position.y
	input.touch_jump_pressed = true
	await physics_frame
	print("touch | after one tick the flag reads %s" % input.touch_jump_pressed)

	var rose := 0.0
	for i in 25:
		await physics_frame
		rose = maxf(rose, floor_y - player.global_position.y)
	print("touch | one-shot press: rose %.0f px" % rose)

	# --- and a held one, for contrast ---------------------------------------
	#
	# touch_move_axis is a level, not an edge: nothing clears it, so it is read
	# whenever the character gets round to looking. Every harness in tools/ drives
	# movement with it and they all work, which is the other half of the evidence
	# - the held inputs are fine and only the one-shot ones are lost.
	var from_x: float = player.global_position.x
	input.touch_move_axis = 1.0
	for i in 30:
		await physics_frame
	input.touch_move_axis = 0.0
	var walked: float = absf(player.global_position.x - from_x)
	print("touch | held axis: walked %.0f px" % walked)

	print("touch | one-shot %s, held %s" % [
		"WORKS" if rose > 8.0 else "SWALLOWED",
		"works" if walked > 10.0 else "swallowed"])
	quit(0 if rose > 8.0 else 1)
