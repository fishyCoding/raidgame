extends SceneTree

## Does any of it survive a real socket?
##
## Two of these are run at once, one with --host, over a real ENet connection -
## the same arrangement net_peer_test uses. That one proves two characters can
## see each other move; this one takes the things that were changed since and
## asks whether each of them actually crosses the wire.
##
##   godot --headless --path . --script res://tools/mp_changes_test.gd -- --host
##   godot --headless --path . --script res://tools/mp_changes_test.gd
##
## Four claims, one per section:
##
##   the dash streak   - laid off replicated `dash_left`, so the other machine
##                       draws it for a body it is not simulating
##   the screen        - raised under a host-minted id and taken down everywhere
##                       by that id, animation and all
##   buckshot          - nine pellets are nine bullets, each with its own angle,
##                       and all nine arrive
##   the ghost's ping  - a hitmarker for shooting somebody else's projection,
##                       routed host to caster to shooter, and none at all for
##                       shooting your own
##
## The host does the acting and the client does the watching, because "does it
## cross the wire" only needs one direction and two of these are host-authority
## paths anyway. Phases are paced by plain waits rather than by messages between
## the two processes: a handshake here would be a second thing that can fail and
## would tell us nothing about the game.

const SHOTGUN := "res://resources/weapons/shotgun.tres"
const PROJECTION := "res://resources/gadgets/projection.tres"
const SLUG := "res://resources/weapons/slug_shotgun.tres"
const PLATE := "res://resources/armor/heavy_vest.tres"

var _net: Node
var _main: Node
var _hosting := false
var _ok := true
var _tag := "CLIENT"


func _initialize() -> void:
	_hosting = "--host" in OS.get_cmdline_user_args()
	_tag = "HOST  " if _hosting else "CLIENT"
	_run()


func _say(text: String) -> void:
	print("%s | %s" % [_tag, text])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
	_say("%s  %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	_net = root.get_node("Net")
	await physics_frame

	if _hosting:
		var err: int = _net.host(27788)
		_say("hosting on 27788 -> %s" % ("ok" if err == OK else "FAILED"))
		if err != OK:
			quit(1)
			return
	else:
		await _wait(45)
		var err: int = _net.join("127.0.0.1", 27788)
		if err != OK:
			_say("could not dial the host")
			quit(1)
			return
		var waited := 0
		while not _net.in_session and waited < 300:
			await physics_frame
			waited += 1
		if not _net.in_session:
			_say("never connected - is the host up?")
			quit(1)
			return

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	var waited_bodies := 0
	while _net.player_count() < 2 and waited_bodies < 1800:
		await physics_frame
		waited_bodies += 1
	if _net.player_count() < 2:
		_say("FAILED: never saw both characters")
		quit(1)
		return

	var shop: Node = _main.get_node("HUD/Shop")
	shop.deployed.emit()
	await physics_frame
	var map: Node = get_first_node_in_group(&"map_screen")
	if map:
		map.dismiss()
	paused = false
	shop.visible = false
	await _wait(10)

	var mine: Node2D = _net.local_player
	var theirs: Node2D = null
	for body in _net.players():
		if body != mine:
			theirs = body
	_say("mine=%s theirs=%s" % [mine.name, theirs.name])

	# Guards are off in a match on purpose, and this is the session where that is
	# supposed to be true - so it is worth saying out loud rather than assuming.
	var guards: int = _main.get_node("Enemies").get_child_count()
	_say("guards in this match: %d" % guards)
	_check(guards == 0, "a networked raid has no guards in it at the moment")

	await _dash_streak(mine, theirs)
	await _screen(mine, theirs)
	await _buckshot(mine, theirs)
	await _ghost_ping(mine, theirs)
	await _slug_through_a_plate(mine, theirs)

	_say("PASS" if _ok else "FAIL")
	await _wait(30)
	quit(0 if _ok else 1)


## The streak is laid from `dash_left`, which is replicated. So a machine that
## never simulates somebody else's dash still has to draw one.
func _dash_streak(mine: Node2D, theirs: Node2D) -> void:
	_say("-- the dash streak --")
	var watched: Node2D = theirs if not _hosting else mine
	var trail: Node = watched.get_parent().get_node_or_null(
		"DashTrail_%s" % watched.name)
	_check(trail != null, "this machine built a streak for the body it is watching")
	if trail == null:
		return

	if _hosting:
		mine.dashes_left = 1
		mine.dash_ready = true
		await physics_frame
		var input: Node = root.get_node("PlayerInput")
		input.touch_dash = true
		input.touch_dash_way = Vector2(1.0, 0.0)

	# Watched over the whole window rather than sampled at the end: a streak is
	# gone three tenths of a second after the last mark, so "how many are there
	# now" is a question with a wrong answer most of the time.
	var most := 0
	for i in 90:
		await physics_frame
		most = maxi(most, trail._marks.size())
	_say("most marks seen on that streak at once: %d" % most)
	_check(most > 2, "a dash on one machine leaves a streak on the other")
	_check(trail.is_in_group(&"shadowed"), "and it is scenery the dark can take")


## Screens are minted by the host under an id and taken down everywhere by it.
## The break animation runs on every copy, which is the part that was added.
func _screen(mine: Node2D, theirs: Node2D) -> void:
	_say("-- the screen --")
	if _hosting:
		var at: Vector2 = mine.global_position + Vector2(90.0, 0.0)
		_net.raise_screen(at + Vector2(0.0, -70.0), at + Vector2(0.0, 70.0),
			_net.peer_id())
	await _wait(30)

	var sheets := get_nodes_in_group(&"screen")
	_say("screens standing here: %d" % sheets.size())
	_check(sheets.size() == 1, "a screen raised on the host stands on both machines")
	if sheets.is_empty():
		return
	var sheet: Node2D = sheets[0]
	var id: int = sheet.id

	if _hosting:
		sheet.take_damage(10.0, sheet.global_position, mine.global_position)
	# Caught mid-break rather than after it. The node lives on for the animation,
	# and what is being checked is that the animation happened here too and not
	# only where the round was resolved.
	var broke := false
	var left_group := false
	for i in 40:
		await physics_frame
		if is_instance_valid(sheet):
			broke = broke or sheet._breaking > 0.0
			left_group = left_group or not sheet.is_in_group(&"screen")
		else:
			left_group = true
	_say("it came apart here: %s, and stopped being a screen: %s" % [
		broke, left_group])
	_check(broke, "a screen shot on the host breaks up on both machines")
	_check(left_group, "and stops hiding anybody everywhere, not just there")
	await _wait(40)
	_check(get_nodes_in_group(&"screen").is_empty(),
		"and is gone from both when the pieces have fallen")
	_check(id != 0 or not _net.is_networked(),
		"the host minted it a name, which is what let it die in two places")


## Nine pellets are nine bullets. Each carries its own angle over the wire, so
## the pattern the shooter rolled is the pattern everybody sees.
func _buckshot(mine: Node2D, theirs: Node2D) -> void:
	_say("-- buckshot --")
	var bullets: Node = _main.get_node("Bullets")
	for old in bullets.get_children():
		old.queue_free()
	await physics_frame

	if _hosting:
		var kit := Inventory.new()
		kit.set_backpack(Item.from_backpack(
			load("res://resources/backpacks/heavy_rucksack.tres")))
		var gun := load(SHOTGUN) as WeaponData
		kit.store(Item.from_weapon(gun))
		kit.add_rounds(gun.ammo_type, 200)
		mine.weapon.set_inventory(kit)
		mine.inventory = kit
		mine.weapon.equip_data(gun)
		await physics_frame
		mine.weapon._equip_left = 0.0
		mine.weapon.stowed = false
		mine.weapon._cooldown = 0.0
		mine.weapon._trigger_held = false
		mine.weapon.try_fire(mine.global_position, 0.0, true, true, 0.0, 0.0)

	# Counted across a few frames, because rounds travel five thousand pixels a
	# second and free themselves on the first thing they touch.
	var most := 0
	for i in 8:
		most = maxi(most, bullets.get_child_count())
		await physics_frame
	_say("most pellets in the air here at once: %d" % most)
	_check(most >= 9, "all nine pellets of a shell cross the wire")


## The hitmarker for shooting a ghost, and the silence for shooting your own.
##
## Driven by handing the ghost a round attributed to the other peer rather than
## by firing one, because what is under test is the routing - host works out the
## hit, caster's machine decides what the body does about it, shooter gets the
## tick - and a bullet is only a slower way of starting it.
func _ghost_ping(mine: Node2D, theirs: Node2D) -> void:
	_say("-- the ghost's ping --")
	if _hosting:
		var gadget := load(PROJECTION) as GadgetData
		_net.cast_projection(gadget.resource_path, mine.global_position,
			{"facing": 1, "aim_angle": 0.0, "stowed": false, "crouch": 0.0,
			"speed_scale": 1.0, "send_x": mine.global_position.x + 200.0,
			"send_y": mine.global_position.y}, _net.peer_id())
	await _wait(30)

	var ghost: Node = _net.projection_for(1)
	_check(ghost != null, "the host's ghost is standing on both machines")
	if ghost == null:
		return
	ghost.life_left = 90.0

	var reticle: Node = mine.get_node("Overlay/Reticle")
	reticle._mark = 0

	# The client's round into the host's ghost. Fired from the host because the
	# host is where damage is resolved - which is exactly the hop being checked:
	# the tick has to end up on the machine that pulled the trigger.
	if _hosting:
		_net.attributing_to = theirs.get_multiplayer_authority()
		ghost.take_damage(40.0, ghost.sight_centre(), Vector2.RIGHT)
		_net.attributing_to = 0
	await _wait(20)
	var ticked: bool = reticle._mark != 0
	_say("reticle after a round attributed to the client: %s" % ticked)
	if _hosting:
		_check(not ticked, "the caster gets nothing for their own ghost being shot")
	else:
		_check(ticked, "the shooter gets their tick from across the wire")

	# And the host shooting its own.
	reticle._mark = 0
	if _hosting:
		_net.attributing_to = _net.peer_id()
		ghost.take_damage(40.0, ghost.sight_centre(), Vector2.RIGHT)
		_net.attributing_to = 0
	await _wait(20)
	var self_tick: bool = reticle._mark != 0
	_say("reticle after the caster shot their own ghost: %s" % self_tick)
	_check(not self_tick, "nobody is told anything for shooting their own ghost")


## A slug ignores most of a plate, and the plate is on the other machine.
##
## This is the hop worth checking. What a round does to armour is a fact about
## the round, and the machine holding the gun is not the machine that works the
## plate out - a body decides for itself what a hit did to it, because health
## replicates outwards from its owner. So the piercing has to travel with the
## shot, and if it does not, a slug arrives as an ordinary round and the plate
## eats two thirds of it.
##
## Measured against the same round fired without it rather than against a
## remembered number: what matters is the difference, and a health bar has other
## things happening to it.
func _slug_through_a_plate(mine: Node2D, theirs: Node2D) -> void:
	_say("-- a slug through a plate --")
	# Reached through the tree, never by name. A --script tool compiles without
	# the autoloads, and one Net in a new section is enough to fail the whole
	# file - which is exactly how this section first ran, or rather did not.
	var slug := load(SLUG) as WeaponData
	var vest := load(PLATE) as ArmorData

	# The client wears the plate, and the host does the shooting - so every
	# number in this crosses the wire on its way to being decided.
	if not _hosting:
		if mine.inventory == null:
			mine.inventory = Inventory.new()
			mine.weapon.set_inventory(mine.inventory)
		mine.inventory.set_worn(Inventory.Wear.VEST, Item.from_armor(vest))
		mine.health = mine.max_health
		# Owning a plate is not wearing one. A vest only counts while the plates
		# are actually up - Player.take_damage passes a null kit otherwise, which
		# is the whole point of the V key - and the ramp takes a moment, so this
		# waits for shield rather than for armored.
		mine.armored = true
	await _wait(60)

	if not _hosting:
		_check(mine.inventory.get_worn(Inventory.Wear.VEST) != null,
			"the plate is actually on for this")
		_check(mine.is_shielded(), "and the plates are up, or armour does nothing")

	# An ordinary round of the same size first, for the comparison.
	if _hosting:
		_net.attributing_to = _net.peer_id()
		_net.piercing = 0.0
		theirs.take_damage(slug.damage, theirs.sight_centre() + Vector2(0.0, 12.0),
			Vector2.RIGHT)
		_net.piercing = 0.0
		_net.attributing_to = 0
	await _wait(30)
	var plain := 0.0
	if not _hosting:
		plain = mine.max_health - mine.health
		mine.health = mine.max_health
		# A fresh plate for the second round. The first one spent durability on
		# what it stopped, and comparing a worn plate against a new one would be
		# measuring the wear rather than the piercing.
		mine.inventory.set_worn(Inventory.Wear.VEST, Item.from_armor(vest))
		mine._invulnerable = 0.0
	await _wait(20)

	if _hosting:
		_net.attributing_to = _net.peer_id()
		_net.piercing = slug.armor_pierce
		theirs.take_damage(slug.damage, theirs.sight_centre() + Vector2(0.0, 12.0),
			Vector2.RIGHT)
		_net.piercing = 0.0
		_net.attributing_to = 0
	await _wait(30)
	if _hosting:
		_say("(the shooting end - the numbers are read on the other machine)")
		return

	var pierced: float = mine.max_health - mine.health
	_say("a %.0f round through a plate: %.0f plain, %.0f as a slug" % [
		slug.damage, plain, pierced])
	_check(plain > 0.0 and pierced > 0.0, "both rounds have to have landed")
	_check(pierced > plain * 1.5,
		"the slug's piercing crosses the wire with the shot")


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
