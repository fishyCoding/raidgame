extends SceneTree

## Buy a stim, get shot down, stick it in, get back up.
##
## Runs solo, because none of this is networked code: health and is_downed
## replicate outwards from whoever owns the body, so a player standing itself up
## on its own machine is a player standing up on all of them. What needs testing
## is the item, the shop entry, and the one path out of the downed state.

var _net: Node
var _main: Node
var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	_net = root.get_node("Net")
	_net.play_solo()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	var waited := 0
	while _net.local_player == null and waited < 600:
		await physics_frame
		waited += 1
	var player: Node2D = _net.local_player
	if player == null:
		print("revive | FAILED: no character")
		quit(1)
		return

	# --- the shop sells them -------------------------------------------------
	var shop: Node = _main.get_node("HUD/Shop")
	var sold := 0
	var price := -1
	for list_name in shop.CATALOGUE:
		for entry in shop.CATALOGUE[list_name]:
			if entry.get("kind", "") == "revive":
				sold += 1
				price = entry.price
	_check("on sale", sold > 0)
	_check("cheap enough to spam", price >= 0 and price <= 50)
	print("revive | sold in %d list(s) at %d credits for x%d"
		% [sold, price, shop.REVIVES_PER_STACK])

	# Past the shop and briefing so the world runs.
	#
	# The wait is load-bearing. screens.gd wires the shop from a deferred call
	# once a character exists, and a `deployed` emitted before that lands is
	# emitted at nobody - the wiring then arrives afterwards, opens the shop and
	# pauses the tree, and every hit below is absorbed by a physics process that
	# is not running.
	await _wait(15)
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(10)

	# --- carry a stack -------------------------------------------------------
	var stim := Item.from_revive(shop.REVIVES_PER_STACK)
	var stowed := false
	for grid in player.inventory.grids():
		if grid.add(stim):
			stowed = true
			break
	_check("fits in a pocket", stowed)
	_check("stacks", player.revives_left() == shop.REVIVES_PER_STACK)

	# --- go down -------------------------------------------------------------
	await _put_down(player)
	if not player.is_downed:
		print("revive | state: paused=%s alive=%s health=%.0f invuln=%.2f"
			% [paused, player.is_alive, player.health, player._invulnerable])
	_check("went down", player.is_downed)
	if not player.is_downed:
		_finish()
		return
	print("revive | down with %.0f health, %d stims" % [
		player.health, player.revives_left()])

	# --- get up --------------------------------------------------------------
	player._use_revive()
	await _wait(4)
	_check("back on your feet", not player.is_downed)
	_check("at full health", is_equal_approx(player.health, player.max_health))
	_check("still alive", player.is_alive)
	_check("spent exactly one", player.revives_left() == shop.REVIVES_PER_STACK - 1)
	print("revive | up with %.0f/%.0f health, %d stims left" % [
		player.health, player.max_health, player.revives_left()])

	# --- and again, until they run out ---------------------------------------
	var used := 1
	while player.revives_left() > 0 and used < 20:
		await _put_down(player)
		if not player.is_downed:
			break
		player._use_revive()
		await _wait(4)
		used += 1
	_check("used the whole stack", used == shop.REVIVES_PER_STACK)
	_check("empty stack is gone", player.revives_left() == 0)

	# The last one has to fail, or "many revives" is really "infinite revives".
	await _put_down(player)
	player._use_revive()
	await _wait(4)
	_check("no stim, no getting up", player.is_downed)

	_finish()


## Shoots the player until they are on the floor.
##
## The wait first is not padding: going down and standing up both hand out 0.35s
## of invulnerability, and a loop that starts hitting immediately spends its
## whole budget inside that window and concludes the damage system is broken.
## Hard enough that the vest cannot save them. A body shot through starting
## armour lands about a tenth of its damage, so polite little 30-point hits
## chip health down and stall just short of the floor.
func _put_down(player: Node2D) -> void:
	await _wait(30)
	for i in 40:
		if player.is_downed or not player.is_alive:
			return
		player.take_damage(500.0, player.global_position, Vector2.RIGHT)
		await _wait(2)


func _check(what: String, passed: bool) -> void:
	print("revive | %-28s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _finish() -> void:
	print("revive | %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
