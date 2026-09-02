extends SceneTree

## A gun with parts on it still fires, and still hurts people.
##
##   godot --headless --path . --script res://tools/attached_fire_test.gd
##
## Written because it did not. A gun with an attachment is a *duplicate* of the
## catalogue resource with its resource_path cleared, and rounds were spawned by
## asking Net to load that path - `load("")` returns null, the spawn returned
## early, and a modified weapon produced no bullet, no tracer, no report and no
## hit. From the seat it read as hit registration being broken, which is the
## worst kind of bug: nothing errors, the gun just does nothing.
##
## So this asserts the whole chain from the trigger down: a round exists, it
## carries the modified damage, and a body in front of it loses health.

var _ok := true
## Where rounds land in the tree. Bullet.spawn parents them here - they are not
## in a group, so counting them means counting children.
var _bullets: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var net: Node = root.get_node("Net")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 8:
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
		print("no character - cannot run")
		quit(1)
		return
	var waited := 0
	while not player.is_on_floor() and waited < 240:
		await physics_frame
		waited += 1

	_bullets = current_scene.get_node_or_null(^"Bullets")
	if _bullets == null:
		print("no Bullets node in the level - cannot count rounds")
		quit(1)
		return

	var maker: Object = (load("res://scripts/item.gd") as GDScript).new()
	var rifle: Object = maker.from_weapon(load("res://resources/weapons/assault_rifle.tres"))
	player.inventory.set_slot(0, rifle)
	# Into the hands, not just into the kit. A raid starts with the sidearm held,
	# so putting a rifle in the primary slot and firing tests the pistol - which
	# is exactly what this test did on its first run, and it passed the parts of
	# itself that were meant to fail.
	player.weapon.slot = 0
	player.weapon.refresh()
	await _ready_to_shoot(player)

	# --- bare, as the baseline ------------------------------------------------
	var bare := await _fire_once(player)
	_say("bare rifle: %d round(s) in the air" % bare)
	_check(bare > 0, "a gun off the shelf puts a round in the air")

	# --- and with a can on it -------------------------------------------------
	rifle.fit(load("res://resources/attachments/suppressor.tres"))
	rifle.count = rifle.weapon.mag_size
	player.weapon.refresh()
	await _ready_to_shoot(player)
	_check(rifle.weapon.resource_path.is_empty(),
		"a modified gun is a copy with no path - which is what broke this")
	var fitted := await _fire_once(player)
	_say("suppressed rifle: %d round(s) in the air" % fitted)
	_check(fitted > 0, "and a gun with a part on it puts one in the air too")

	# --- the part's numbers travel with the round -----------------------------
	var round_data := await _fire_and_read(player)
	if round_data.is_empty():
		_check(false, "the round could be read back")
	else:
		var base: Resource = load("res://resources/weapons/assault_rifle.tres")
		# The gun's own damage_scale is a global tuning knob on the Weapon node
		# and applies to every round; what is being checked here is that the
		# *part's* share of the number survived the trip out of the muzzle.
		var knob: float = player.weapon.damage_scale
		_say("round %.1f from '%s'   bare would be %.1f   built says %.1f (x%.2f)" % [
			round_data["damage"], round_data["from"],
			base.damage * knob, rifle.weapon.damage * knob, knob])
		# The local round is built from the gun in hand, which is a copy with no
		# path - so an empty one here is the *right* answer, and a pistol path
		# would mean the test was shooting the wrong gun again.
		_check(round_data["from"].is_empty(),
			"the round is the gun in hand, not a catalogue copy of something else")
		_check(round_data["damage"] < base.damage * knob - 0.5,
			"a suppressed round hits for less than a bare one")
		_check(absf(round_data["damage"] - rifle.weapon.damage * knob) < 0.6,
			"and for exactly what the workshop said it would")

	# --- and it lands on somebody --------------------------------------------
	var guards: Node = main.get_node("Enemies")
	var target: Node2D = null
	for guard in guards.get_children():
		if guard.get(&"is_alive") != false:
			target = guard
			break
	if target == null:
		_check(false, "there is a guard to shoot at")
	else:
		# Pinned first. A guard left running walks out of the line between the
		# muzzle and where it was put, and the rounds sail past a target that is
		# no longer there.
		target.set_physics_process(false)
		target.set_process(false)
		# And put somewhere the rounds can actually reach. The yard has walls in
		# it, and the first version of this stood the guard 220 px east - on the
		# far side of WallEast, where every round struck masonry and the test
		# reported that damage did not register.
		var placed := await _clear_shot(player, target)
		_say("stood him %s" % placed)
		if placed.is_empty():
			_check(false, "somewhere in this level has a clear line of fire")

		var before: float = target.get(&"net_health")
		player.aim_angle = 0.0
		player.aim_direction = Vector2.RIGHT
		# One round at a time with the climb wound back between them. Firing a
		# burst with the cooldown forced to zero walks the muzzle above the
		# target within three shots, and a test that misses on purpose proves
		# nothing about whether hits register.
		var fired := 0
		for i in 6:
			player.weapon.kick = 0.0
			player.weapon._cooldown = 0.0
			player.weapon._trigger_held = false
			var line := player.global_position.angle_to_point(target.global_position)
			player.aim_angle = line
			player.aim_direction = Vector2.RIGHT.rotated(line)
			player.weapon.try_fire(player.global_position, line, true, true)
			fired += _bullets.get_child_count()
			for j in 8:
				await physics_frame
		_say("rounds seen in flight: %d   mag left %d   guard _health %.0f" % [
			fired, player.weapon.get_mag(), float(target.get(&"_health"))])
		var after: float = target.get(&"net_health")
		_say("guard health %.0f -> %.0f" % [before, after])
		_check(after < before, "and a body in front of it loses health")

	print("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


## Finds somewhere near the player with nothing in the way, and puts the guard
## there. Returns a description of where, or "" if the level would not oblige.
func _clear_shot(player: Node2D, target: Node2D) -> String:
	for reach in [90.0, 130.0, 170.0, 60.0]:
		for way in [1.0, -1.0]:
			var spot := player.global_position + Vector2(reach * way, 0.0)
			target.global_position = spot
			await physics_frame
			var probe := PhysicsRayQueryParameters2D.create(player.global_position, spot)
			probe.collision_mask = player.weapon.hit_mask
			probe.exclude = [player.get_rid()]
			var seen: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(probe)
			if seen.get("collider", null) == target:
				return "%.0f px %s" % [reach, "east" if way > 0.0 else "west"]
	return ""


## Waits out the draw. A gun that has just been put in your hands is still coming
## up, and try_fire refuses while it is - so a test that fires immediately reads
## as "the gun does not work" whatever is wrong with it.
func _ready_to_shoot(player: Node2D) -> void:
	for i in 240:
		await physics_frame
		if not player.weapon.is_equipping() and not player.weapon.is_reloading():
			player.weapon._cooldown = 0.0
			return


## Fires one round and counts what is in the air a frame later.
##
## Through try_fire, which is the function the trigger actually calls - a test
## that reaches past it into _spawn_bullet would have passed all the way through
## the bug it exists to catch.
func _fire_once(player: Node2D) -> int:
	_clear()
	await physics_frame
	player.aim_angle = 0.0
	player.aim_direction = Vector2.RIGHT
	player.weapon._cooldown = 0.0
	player.weapon._trigger_held = false
	player.weapon.try_fire(player.global_position, 0.0, true, true)
	await physics_frame
	return _bullets.get_child_count()


## Fires one and reads the damage off the round itself, which is the only way to
## prove the attachment's numbers made it out of the muzzle.
func _fire_and_read(player: Node2D) -> Dictionary:
	_clear()
	await physics_frame
	player.weapon._cooldown = 0.0
	player.weapon._trigger_held = false
	player.weapon.try_fire(player.global_position, 0.0, true, true)
	# Read on the frame it was fired. A round travels forty-odd pixels a physics
	# frame and the yard has walls close enough to swallow one inside a single
	# step, which made this look intermittently like the gun had not fired.
	for shot in _bullets.get_children():
		var data: Variant = shot.get(&"_data")
		var scale: Variant = shot.get(&"damage_scale")
		if data != null:
			return {"damage": float(data.damage) * float(scale),
				"from": String(data.resource_path)}
	return {}


func _clear() -> void:
	if _bullets == null:
		return
	for old in _bullets.get_children():
		old.free()


func _say(line: String) -> void:
	print("-- %s" % line)


func _check(pass_: bool, says: String) -> void:
	print("   %s  %s" % ["ok  " if pass_ else "FAIL", says])
	if not pass_:
		_ok = false
