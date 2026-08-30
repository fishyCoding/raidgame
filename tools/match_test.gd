extends SceneTree

## Drives a whole match against a real dedicated server: wait, countdown, deploy
## at opposite ends, then shoot a guard and check the damage was real.
##
## Run as two clients against a server started the usual way:
##
##   godot --headless --path . -- --server=27780
##   godot --headless --path . --script res://tools/match_test.gd -- --peer=1 --port=27780
##   godot --headless --path . --script res://tools/match_test.gd -- --peer=2 --port=27780
##
## `server/test_match.ps1` does all three.
##
## The things this is here to catch, in the order they broke while it was being
## written: a lone player being deployed instead of made to wait, the countdown
## running out into an empty raid, both players landing on the same insertion
## point, a client's rounds being tracers on every machine including the host's,
## a guard who takes every hit and never dies because the last word about him is
## published from a process that death switches off, and rounds passing straight
## through the other player because the shot mask never had PLAYER in it.
##
## The last two are the reason the shooting checks here go all the way to a body:
## "health went down" passed for weeks while nothing on the map could be killed.

const FAR_ENOUGH := 3000.0
## What a client buys during the countdown, to prove the kit screen's purchases
## reach the character that appears ten seconds later.
const KIT_PRIMARY := 1   # the assault rifle, in the shop's primary catalogue

var _tag := "CLIENT"
var _host := "127.0.0.1"
var _port := 27780
var _first := false
var _net: Node
var _main: Node
var _ok := true


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer="):
			_tag = "CLIENT%s" % arg.get_slice("=", 1)
			_first = arg.ends_with("1")
		elif arg.begins_with("--host="):
			_host = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
	_run()


## A loadout with a rifle in it, filled the way the shop fills one. Built through
## the shop's own code path rather than assembled by hand, so this fails if
## buying breaks and not only if carrying the kit over does.
func _bought_kit() -> Inventory:
	# Loaded rather than named. A --script harness compiles before the autoloads
	# are registered as script globals, and naming Weapon here makes weapon.gd
	# compile too early - where its one reference to Net fails, leaving the whole
	# class broken for the rest of the process. It reads as every guard in the
	# level losing its weapon node. See the note at the top of solo_test.
	var weapon_script: GDScript = load("res://scripts/weapon.gd")
	var kit: Inventory = weapon_script.starting_inventory()
	var shop: Control = Control.new()
	shop.set_script(load("res://scripts/shop.gd"))
	root.add_child(shop)
	shop.open(kit)
	shop._open = {"kind": "slot", "id": "primary", "list": "primary", "label": "PRIMARY"}
	shop._buy(shop.CATALOGUE["primary"][KIT_PRIMARY])
	shop.queue_free()
	return kit


func _run() -> void:
	_net = root.get_node("Net")
	await physics_frame

	# Kitted out before queuing, which is what the menu does: it fills an
	# Inventory, parks it on Net and then dials. This harness has no menu, so it
	# does the same two things by hand - see queue_test for the button itself.
	_net.staged_kit = _bought_kit()

	if _net.join(_host, _port) != OK:
		_say("FAILED: could not dial %s:%d" % [_host, _port])
		quit(1)
		return
	var waited := 0
	while not _net.in_session and waited < 600:
		await physics_frame
		waited += 1
	if not _net.in_session:
		_say("FAILED: never connected - is the server up?")
		quit(1)
		return

	# Whichever map the server says it is holding open, the way the menu does it.
	# Loading main.tscn regardless is what this used to do, and it only worked
	# because there was only ever one map - on any other the two machines would
	# have been in different buildings with every synchroniser pointing at a node
	# path the other end does not have.
	var told := 0
	while not _net.level_settled() and told < 600:
		await physics_frame
		told += 1
	_check("server said which map", _net.level_settled())
	_say("map %s" % _net.match_level)

	_main = (load(_net.match_level) as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await physics_frame

	# --- nobody deploys alone ------------------------------------------------
	#
	# Only the first client can check this, and only before the second one has
	# arrived. Two seconds is long enough that a server which was going to spawn
	# us immediately would have done it.
	if _first:
		await _wait(120)
		_check("alone: still waiting", _net.match_state != _net.Match.LIVE)
		_check("alone: no character", _net.local_player == null)

	# --- waiting, with nothing in the way ------------------------------------
	#
	# The wait is a wait now: you kitted out before you queued, so there is no
	# screen over the level and nothing to pause. The guards keep walking and you
	# watch them do it.
	await _wait(20)
	var shop: Node = _main.get_node_or_null("HUD/Shop")
	_check("no kit screen over the wait", shop == null or not shop.visible)
	_check("tree is not paused", not paused)

	# --- the countdown -------------------------------------------------------
	var saw_countdown := false
	waited = 0
	while _net.match_state != _net.Match.LIVE and waited < 1800:
		if _net.match_state == _net.Match.COUNTDOWN:
			saw_countdown = true
		await physics_frame
		waited += 1
	_check("saw a countdown", saw_countdown)
	_check("match went live", _net.match_state == _net.Match.LIVE)

	waited = 0
	while _net.player_count() < 2 and waited < 900:
		await physics_frame
		waited += 1
	_check("two characters", _net.player_count() == 2)
	if _net.player_count() < 2:
		_finish()
		return

	# --- opposite ends -------------------------------------------------------
	await _wait(20)
	var mine: Node2D = _net.local_player
	var theirs: Node2D = null
	for body in _net.players():
		if body != mine:
			theirs = body
	if mine == null or theirs == null:
		_say("FAILED: missing a body after deploy")
		_finish()
		return
	var apart := mine.global_position.distance_to(theirs.global_position)
	_say("deployed %.0f px apart (want > %.0f)" % [apart, FAR_ENOUGH])
	_check("opposite ends", apart > FAR_ENOUGH)

	# --- and not standing in the doorway -------------------------------------
	#
	# Landing at opposite ends means each player's way home is across the map -
	# which is where the *other* player is standing. That is the design, and it
	# is only survivable because exits are per-player: your exit being under
	# somebody else's feet must do nothing at all to them.
	_say("my exits: %s / theirs: %s" % [_names(mine._exits), _names(theirs._exits)])
	_check("different ways home", _names(mine._exits) != _names(theirs._exits))
	_check("not extracting on arrival", mine.extracting == null)
	_check("nobody left on arrival", not mine.extracted_out and not theirs.extracted_out)

	# --- one lamp, and it is yours -------------------------------------------
	#
	# Every character carries a shadow-casting light because none of them knows
	# whose it is until it is in the tree. Left lit on somebody else's body it
	# throws a second set of shadows off every wall, from a place you are not
	# standing - so the darkness stops meaning "what I can see", which is the only
	# thing it is there to say.
	_check("my lamp is lit", (mine.get_node("Vision") as Light2D).enabled)
	_check("theirs is not", not (theirs.get_node("Vision") as Light2D).enabled)
	_check("and their camera is off", not (theirs.get_node("Camera2D") as Camera2D).enabled)

	# --- and out of sight of each other --------------------------------------
	#
	# The same hard concealment the guards get. Drawn through walls, another
	# player is a standing answer to the only question this level asks - is there
	# anybody in that room - and half a mile of cover stops meaning anything.
	# Checked here because this is the one moment the test knows for certain
	# where they both are: opposite ends, with the whole map in between.
	await _wait(20)
	_check("they are concealed by the map", not theirs.visible)
	_check("I am still drawn", mine.visible)
	_check("they are in the vision system", theirs.is_in_group(&"hideable"))
	_check("and I am not", not mine.is_in_group(&"hideable"))

	# Longer than hold_time, so an exit that was quietly counting would have
	# fired by now.
	await _wait(360)
	_check("still in the raid after 6s", not mine.extracted_out)
	_check("and so are they", not theirs.extracted_out)

	# --- what we went in with ------------------------------------------------
	#
	# The rifle was bought a scene ago, before there was a session to join, let
	# alone a body to hang it on. It should be holding one.
	_check("bought kit came in with me", mine.inventory != null
		and mine.inventory.primary != null)
	# And this machine must not be resolving its own hits. A client that thinks
	# its rounds count is the failure that looks exactly like shooting working.
	_check("damage is not decided here", not _net.deals_damage())

	# --- shooting the guards -------------------------------------------------
	#
	# Fired through Net rather than through the input stack, because Net.fire is
	# exactly the seam being tested: everything above it is the same code single
	# player has always run.
	var guard: Node2D = _nearest_guard(mine.global_position)
	if guard == null:
		_say("FAILED: no guard to shoot")
		_finish()
		return
	var before: float = guard.net_health
	var weapon: Node = mine.weapon
	# Fired from arm's length. The starting sidearm does not carry across the
	# map, and a test that misses because of weapon range is a test that says
	# nothing about replication.
	var muzzle: Vector2 = guard.global_position - Vector2(80.0, 0.0)
	var angle := (guard.global_position - muzzle).angle()
	_say("shooting %s with %s from %.0f px, health %.0f" % [
		guard.name, weapon.data.resource_path.get_file(),
		muzzle.distance_to(guard.global_position), before])

	# Kept firing until he goes down rather than a fixed dozen rounds. "Health
	# went down" is the assertion that passed all the way through a bug where
	# nothing on the map could be killed - the guard is only really dead when
	# this machine, which is not the one that decided it, has been told so.
	for i in 60:
		if not guard.net_alive:
			break
		_net.fire(muzzle, angle, weapon.data.resource_path, weapon.hit_mask,
			weapon.damage_scale, _net.peer_id())
		await _wait(4)
	await _wait(90)

	_say("guard health %.0f -> %.0f, alive=%s" % [before, guard.net_health,
		guard.net_alive])
	_check("the guard took the hits", guard.net_health < before)
	_check("and actually died of them", not guard.net_alive)
	_check("with the health to match", guard.net_health <= 0.0)
	# Not `visible`: a guard out of your line of sight is invisible while very
	# much alive. Leaving the vision system's list is what only a corpse does.
	_check("and left the vision system", not guard.is_in_group(&"hideable"))

	# --- and left a body to search -------------------------------------------
	#
	# The corpse is built on the server - the only machine that watched him spend
	# his magazine - and sent from there. Both clients should end up holding an
	# identical copy of both bodies, including the one they did not kill.
	waited = 0
	while get_nodes_in_group(&"lootable").size() < 2 and waited < 900:
		await physics_frame
		waited += 1
	_check("both bodies are on the floor", get_nodes_in_group(&"lootable").size() >= 2)
	var fell := _body_near(guard.global_position)
	_check("the one I shot left a body", fell != null)
	if fell:
		_check("with his kit still on him", fell.has_loot())
	# Printed for the runner to compare between the two clients. It is the only
	# check that catches a body whose contents depend on who is looking at it,
	# which is exactly what rolling the kit locally would produce.
	_say("bodies %s" % _bodies())

	# --- and only one of us may go through it --------------------------------
	#
	# Both clients pick the same body and ask for it on the same network event -
	# the second corpse arriving - so the two requests are genuinely in flight at
	# once. Exactly one may be granted. If both are, everything on that body
	# exists twice, which in a game about carrying things out is the only bug
	# that really matters.
	var shared := _first_body()
	# Printed for the runner, which checks the two clients picked the *same* body
	# before it checks that only one of them got it. Two clients quietly kneeling
	# over two different corpses is a pair of granted searches that are both
	# correct, and it reads in the log exactly like the duplication bug this is
	# here to catch.
	var raw: Array[String] = []
	for node in get_nodes_in_group(&"lootable"):
		raw.append(str(node.name))
	raw.sort()
	_say("chose %s out of %s" % [shared.name if shared else "-", " ".join(raw)])
	_check("there is a body to fight over", shared != null)
	if shared == null:
		_finish()
		return

	_check("and there is kit on it", shared.has_loot())
	var was := _kit_of(shared.inventory)
	_say("fighting over %s, carrying: %s" % [shared.name, was])

	# Standing over it, because that is the only way to search one - and because
	# walking away from an open body hands it back, which would end the race
	# before it started.
	mine.global_position = shared.global_position + Vector2(0.0, -24.0)
	await _wait(10)
	mine._begin_search(shared)
	await _wait(90)

	var searching: bool = mine._searching != null
	_say("search %s" % ("granted" if searching else "refused"))
	if searching:
		# Take what will fit and hand the body back. What is left is broadcast
		# from here: this machine is the only one that knows what was taken.
		shared.loot_into(mine.inventory)
		mine._close_screen()
	await _wait(300)
	_say("after %s" % _kit_of(shared.inventory))
	_check("nobody is still holding it", mine._searching == null)
	# True on both sides, and it is the whole point on the losing one: its copy
	# of the body emptied without it ever having touched the thing.
	_check("what is on it changed", _kit_of(shared.inventory) != was)

	# --- and each other ------------------------------------------------------
	#
	# Two people in the same raid at opposite ends of it. One shoots, and the
	# check is made from both sides: the shooter watching their health fall, and
	# the target watching its own. Neither machine worked the hit out - the
	# server did - so agreement between them is the whole point.
	await _shield_travels(mine, theirs)
	await _pvp(mine, theirs)
	_finish()


## The plates, seen from the other end of the map.
##
## `armored` is the only part of the shield that is sent - the 0.3s ramp is
## re-derived on each machine - so what has to be true is that one player putting
## them up is a thing the other player can see. It is the difference between a
## body you can kill in one round and one you cannot, and worth nothing at all if
## it stops at the machine it happened on.
##
## Client 1 raises and **never drops**, and client 2 polls until it sees it. That
## asymmetry is not laziness: the two clients do not arrive here in step - they
## shot different guards, and one of them started ten seconds later - so a raise
## that was later undone gets read by the other side at whatever point in the
## sequence it happens to have reached. The first draft did exactly that and
## caught the replica mid-drop: `armored` already false, ramp still falling
## through 0.83. A state that only ever goes one way can be sampled at any time.
##
## Which is why dropping is checked in tools/shield_test.gd instead, where there
## is one machine and no clock to race.
func _shield_travels(mine: Node2D, theirs: Node2D) -> void:
	if _first:
		mine.armored = true
		await _ramped(mine)
		_check("my own plates came up", mine.is_shielded())
		return

	var waited := 0
	while not theirs.armored and waited < 900:
		waited += 1
		await physics_frame
	_say("their plates arrived after %.1fs, ramp %.2f" % [waited / 60.0, theirs.shield])
	_check("I can see their plates go up", theirs.armored)
	# The ramp is local, so a replica has to run it out to full on its own off
	# the bool rather than being told each step of it.
	await _ramped(theirs)
	_check("and the ramp ran out on this machine too", theirs.is_shielded())


## Long enough for the plates to finish coming up, read off the body rather than
## fixed. This was a flat second, which was three times the ramp when the ramp
## was 0.3s and half of it the day it became 2s - a test that fails because a
## designer changed a number is a test that has to be re-read to be believed.
func _ramped(body: Node2D) -> void:
	await _wait(roundi(float(body.shield_raise_time) * 60.0) + 10)


## Client 1 shoots client 2. Both run this; which side you are decides whether
## you are holding the gun or standing in front of it.
func _pvp(mine: Node2D, theirs: Node2D) -> void:
	var weapon: Node = mine.weapon
	# Measured against full health rather than against health-when-this-started.
	# The two clients do not arrive here in step - they shot different guards -
	# so a before/after reading on the receiving side races the shooting.
	var start: float = theirs.max_health if _first else mine.max_health

	if _first:
		_say("they are at %s, I am at %s" % [theirs.global_position,
			mine.global_position])
		# From both sides, at their body rather than their head - a knockout ends
		# the run and this is a test about damage landing. Both sides because an
		# insertion point is a place on a real map: one of them has a container
		# an arm's length to one side, and a test that fires into it reads as
		# "players cannot hurt each other" when it means "I shot a crate".
		for side in [-70.0, 70.0]:
			var muzzle: Vector2 = theirs.global_position + Vector2(side, 0.0)
			var angle := (theirs.global_position - muzzle).angle()
			_say("shooting them from %.0f px away on the %s" % [
				absf(side), "left" if side < 0.0 else "right"])
			# Spaced past Player.invulnerable_time, or every round after the
			# first is swallowed and the test measures one hit however many it
			# fires.
			for i in 3:
				_net.fire(muzzle, angle, weapon.data.resource_path,
					weapon.hit_mask, weapon.damage_scale, _net.peer_id())
				await _wait(30)

	# The side being shot at has to outlast the side doing the shooting, whatever
	# order the two of them got here in.
	await _wait(180 if _first else 800)

	if _first:
		_say("their health %.0f -> %.0f" % [start, theirs.health])
		_check("shot the other player", theirs.health < start)
	else:
		_say("my health %.0f -> %.0f" % [start, mine.health])
		_check("was shot by the other player", mine.health < start)


## Every body on the floor and what is on it, in an order both machines agree
## on, so the two clients' lines can be compared character for character.
##
## Item *labels*, not a summary of names: "SMG 17/30" and "VEST 62%" are numbers
## that only the machine which watched him fight and get shot at could know. A
## list of names would match between two machines that had each rolled the same
## guard the same rifle, which is the thing this is here to rule out.
func _bodies() -> String:
	var lines: Array[String] = []
	for node in get_nodes_in_group(&"lootable"):
		lines.append("%s[%s]" % [node.name, _kit_of(node.inventory)])
	lines.sort()
	return " ".join(lines)


func _kit_of(kit: Inventory) -> String:
	if kit == null:
		return "-"
	var what: Array[String] = []
	for item in kit.all_items():
		what.append(item.label())
	what.sort()
	return ", ".join(what)


## The body both clients will fight over. By name, so the two of them
## independently pick the same one.
##
## Compared as Strings rather than as the StringNames a node's name arrives as.
## The two clients were once seen picking different corpses out of an identical
## pair, which this ordering is the only candidate for and which has not
## reproduced since; StringName comparison measures as lexicographic on 4.7.1, so
## that is not an explanation, only the one step here whose contract is about
## sorting interned names cheaply rather than about the text. Converting costs
## nothing on two nodes and takes it off the table.
func _first_body() -> Lootable:
	var found: Array[Lootable] = []
	for node in get_nodes_in_group(&"lootable"):
		var body := node as Lootable
		if body:
			found.append(body)
	found.sort_custom(func(a: Lootable, b: Lootable) -> bool:
		return String(a.name) < String(b.name))
	return found[0] if not found.is_empty() else null


func _body_near(at: Vector2) -> Node2D:
	for node in get_nodes_in_group(&"lootable"):
		var body := node as Node2D
		if body and body.global_position.distance_to(at) < 140.0:
			return body
	return null


func _names(points: Array) -> String:
	var out: Array[String] = []
	for p in points:
		if is_instance_valid(p):
			out.append(str(p.name))
	out.sort()
	return ",".join(out)


func _nearest_guard(to: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for g in _main.get_node("Enemies").get_children():
		var body := g as Node2D
		if body == null or not body.net_alive:
			continue
		var d := body.global_position.distance_to(to)
		if d < best_d:
			best_d = d
			best = body
	return best


func _check(what: String, passed: bool) -> void:
	_say("%-32s %s" % [what, "ok" if passed else "WRONG"])
	if not passed:
		_ok = false


func _finish() -> void:
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _say(text: String) -> void:
	print("%s | %s" % [_tag, text])


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame
