extends Node

## Autoload: the seam between the game and the network.
##
## Nothing else in the project talks to MultiplayerAPI directly. Gameplay asks
## this file three things - am I in a session, am I the host, and which player is
## mine - and everything else about peers, spawning and transport stays here.
##
## The model is a dedicated server: one box holds the world open and everybody
## dials it. That server is the authority on everything shared - guards, damage,
## loot - while each client owns its own character's movement. Players do not
## host each other and there is no address to type: you press one button and are
## put into the next match that needs somebody.
##
## Single player is not a special case. It is a session with one peer, hosted by
## you, and the same code runs - which is the only way multiplayer stays working,
## because the path you play every day is the multiplayer path.

signal player_spawned(player: Node)
signal players_changed()
signal session_started(as_host: bool)
signal session_ended(reason: String)
signal peer_joined(id: int)
signal peer_left(id: int)
signal match_changed(state: int, seconds_left: float)

## How a networked match runs. Nobody is put in the world on their own: the
## first player to arrive waits, and the moment there are two the countdown
## starts where everyone can see it. It exists so that a raid begins with both
## of you standing up at the same moment, at opposite ends of the map, rather
## than one of you having wandered the level alone for a minute first.
##
## Solo is exempt. It is a session of one and there is nobody to wait for, so it
## goes straight to LIVE.
enum Match { WAITING, COUNTDOWN, LIVE }

const MIN_PLAYERS := 2
const COUNTDOWN := 10.0

const DEFAULT_PORT := 27015
## Enough for a squad. Raising it is a number here and a spawn point per player
## in the level, nothing else.
const MAX_PLAYERS := 4

## Where JOIN MATCHMAKING goes. One address, compiled in, because a player has
## no use for the question: there is one world, it is always up, and the only
## thing pressing the button can mean is "put me in it". Overridden for a local
## session with `-- --join=127.0.0.1` - see lobby.gd.
const MATCHMAKING_HOST := "150.136.57.86"

## The one world that address holds open. Matchmaking never asks which map,
## because there is only ever this one on the other end of it.
const WORLD := "res://scenes/main.tscn"

## Every map you can open, in menu order, and what to call it on screen.
##
## The world is first: playing it alone is the same raid without the company.
## Everything after it is solo only - a map that no server is holding open is
## not somewhere two people can be matched into, and saying so in the menu is
## better than a button that finds nobody forever.
const LEVELS := [
	{"name": "the yard", "scene": WORLD},
	{"name": "the quarry", "scene": "res://scenes/quarry.tscn"},
]

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const HOOK_SCENE := preload("res://scenes/grapple_hook.tscn")
const PROJECTION_SCENE := preload("res://scenes/projection.tscn")

## The character this machine drives. Everything that used to ask the tree for
## "the player" wants this one specifically - the HUD, the map, the camera, the
## listener the sound is mixed for.
var local_player: Node2D = null

## What was bought in the menu, waiting for a body to put it on.
##
## Kitting out happens before you queue, which is a scene away from the level
## and minutes away from having a character. This autoload is the only thing
## alive across both, so the kit waits here and Screens hands it over the moment
## the countdown ends - see Player.give_kit.
var staged_kit: Inventory = null

## Set by the menu's TEST DRIVE button: go straight into the level, kitted, with
## no shop, no briefing and no intro.
##
## Consumed by Screens the moment it acts on it, so it cannot leak into the next
## run - a real raid that quietly skipped the briefing because of a button you
## pressed ten minutes ago would be a difficult thing to explain to yourself.
var test_drive := false

## Which of LEVELS the menu opens when you go in on your own.
##
## Parked here rather than on the menu because the menu does not survive a raid:
## dying builds a fresh one, and a map you picked should outlive the run you
## picked it for. The same reason staged_kit is here.
var solo_level := 0

## True once host() or join() has succeeded. Single player counts: it is a
## session of one.
var in_session := false
var is_host := true

## True when this process hosts a session it does not play in - a box somewhere
## running the world for four people who are all elsewhere. See serve().
var is_dedicated := false

var _players := {}

## Where the match is up to, and how long is left of the countdown. Held on every
## machine: the host decides, everyone else is told and then counts down its own
## clock so the number on screen moves smoothly between announcements.
var match_state := Match.WAITING
var seconds_left := 0.0
## How many players the host says are in this match. Clients cannot count them
## themselves - the roster is the host's - so it is sent with every announcement.
var players_here := 0

## Peers that have a level up and want a character. Not the same as _ready_peers,
## which is about who may be sent world state - a dedicated server is in that one
## and will never be in this one, because it is not playing.
var _waiting := {}

## Which insertion point each player came in at, so a latecomer can be told where
## everyone already standing started, and the same body lands in the same place
## on every machine.
var _insertion := {}

## Who to credit for the damage being resolved right now.
##
## Damage is worked out on the host, but the hitmarker belongs to whoever pulled
## the trigger, and that is no longer the machine doing the resolving. Threading
## a shooter through every take_damage in the game would touch guards, targets,
## players and blasts; setting it around the call is one line at each of the
## three places that can cause damage, and it is safe because resolving a hit is
## synchronous - nothing else runs between here and report_hit.
var attributing_to := 0
## How much of a plate the round being resolved ignores, 0 to 1.
##
## Set around the damage call and read back out by whoever works the hit out,
## exactly the way attributing_to is and for the same reason: every take_damage
## in the game would have to grow a parameter otherwise, including the ones on
## screens and ghosts that have no armour to think about.
var piercing := 0.0
## How hard the round being resolved is on armour, as a multiple. Set around the
## damage call and read back out exactly the way piercing is - see the note
## above it, which applies here word for word.
var armor_wear := 1.0


func _ready() -> void:
	# The countdown is not gameplay and must not stop when gameplay does.
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- starting and stopping ----------------------------------------------------


## Opens a session others can join, hosted by a machine that also plays in it.
##
## No longer reachable from the game: players queue for the dedicated server and
## nobody hosts anybody. It stays because it is serve() with a character - the
## two are one function - and because the two-process test harnesses need a
## session that comes up without a server beside them. Nothing player-facing
## should call it.
func host(port := DEFAULT_PORT) -> Error:
	return _open(port, false)


## Opens a session this machine hosts and does not play in. This is the game.
##
## The same socket and the same authority as host() - guards, physics and loot
## all still run here - with one thing left out: nobody asks for a character, so
## every body in the world belongs to somebody else. That absence is the whole
## feature. It is what lets the session outlive whoever started it and sit on a
## machine with no screen, no keyboard and nobody in front of it.
##
## It waits. A match does not start until MIN_PLAYERS have arrived, however long
## that takes, and when the last of them leaves it goes back to waiting for the
## next pair - see request_character and _on_peer_disconnected.
func serve(port := DEFAULT_PORT) -> Error:
	return _open(port, true)


func _open(port: int, dedicated: bool) -> Error:
	if not _ready_to_connect():
		return ERR_UNCONFIGURED
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_warning("Net: could not host on port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	in_session = true
	is_host = true
	# The host's level is up by definition - it is the one everyone else is
	# waiting on - so it is ready before anybody has connected to ask.
	_ready_peers[1] = true
	# Set before the signal, not after: what a listener does about a session
	# starting depends on whether there is anyone here to play it.
	is_dedicated = dedicated
	if is_dedicated:
		# stdout is the only interface a server has. Whoever is reading
		# journalctl at 2am needs to know the socket actually opened.
		print("[server] listening on udp/%d, up to %d players" % [port, MAX_PLAYERS])
	session_started.emit(true)
	return OK


## There is no MultiplayerAPI until the tree is running, and assigning a peer to
## it before then fails in a way that reads as success from the caller's side -
## create_server returns OK and the socket is simply never attached to anything.
func _ready_to_connect() -> bool:
	if multiplayer == null:
		push_warning("Net: asked to connect before the tree was up; ignoring")
		return false
	return true


func join(address: String, port := DEFAULT_PORT) -> Error:
	if not _ready_to_connect():
		return ERR_UNCONFIGURED
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_warning("Net: could not reach %s:%d (%s)" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK


## Plays on this machine alone, with no socket open at all. Still a session, so
## the rest of the game does not need a second code path.
func play_solo() -> void:
	# A dialled connection is not finished the moment join() returns - the peer
	# exists but connected_to_server has not arrived yet, so in_session is still
	# false. Anything that treats that gap as "nobody is playing" and drops into
	# solo would tear down the socket mid-handshake, which is exactly what the
	# level's own start-up did to every client that tried to join.
	if is_networked():
		return
	in_session = true
	is_host = true
	session_started.emit(true)


## Where playing alone goes, and what the menu calls it.
func solo_scene() -> String:
	return str(LEVELS[solo_level]["scene"])


func solo_name() -> String:
	return str(LEVELS[solo_level]["name"])


## The next map along, wrapping. The menu's map button and nothing else.
func cycle_solo_level() -> void:
	solo_level = (solo_level + 1) % LEVELS.size()


## The map whose name contains this text, or -1 for no such map. Loose on
## purpose: the command line should be able to say `quarry` rather than having
## to spell "the quarry" exactly the way the menu does.
func level_named(text: String) -> int:
	var wanted := text.strip_edges().to_lower()
	if wanted.is_empty():
		return -1
	for i in LEVELS.size():
		if str(LEVELS[i]["name"]).to_lower().contains(wanted):
			return i
	return -1


func leave(reason := "left the session") -> void:
	for id in _players.keys():
		var body: Node = _players[id]
		if is_instance_valid(body):
			body.queue_free()
	_players.clear()
	_ready_peers.clear()
	_waiting.clear()
	_insertion.clear()
	_searchers.clear()
	match_state = Match.WAITING
	seconds_left = 0.0
	local_player = null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	in_session = false
	is_dedicated = false
	session_ended.emit(reason)
	players_changed.emit()


## Our own peer id. 1 is the host; solo play is not connected to anything, so it
## answers 1 as well - it is the host of a session of one.
func peer_id() -> int:
	if not is_networked():
		return 1
	return multiplayer.get_unique_id()


## Whether there is a real connection, as opposed to the placeholder Godot leaves
## in place when there is not.
##
## multiplayer_peer is never null: an unconnected MultiplayerAPI holds an
## OfflineMultiplayerPeer, so every "is there a peer" test written the obvious way
## answers yes while playing alone. That silently made solo play look networked -
## and made play_solo() refuse to start, because it thought a connection was
## already in flight.
func is_networked() -> bool:
	var peer := multiplayer.multiplayer_peer if multiplayer else null
	return peer != null and not (peer is OfflineMultiplayerPeer)


# --- who is playing -----------------------------------------------------------


func players() -> Array[Node2D]:
	var list: Array[Node2D] = []
	for id in _players:
		var body := _players[id] as Node2D
		if is_instance_valid(body):
			list.append(body)
	return list


func player_count() -> int:
	return players().size()


## The nearest living player to a point. What a guard is looking for, and what
## anything in the world that used to assume a single player now asks instead.
func nearest_player(to: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for body in players():
		var alive: Variant = body.get(&"is_alive")
		if typeof(alive) == TYPE_BOOL and not alive:
			continue
		var distance := body.global_position.distance_to(to)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


func player_for(id: int) -> Node2D:
	var body := _players.get(id) as Node2D
	return body if is_instance_valid(body) else null


# --- spawning -----------------------------------------------------------------


## Tells the host this machine has the level up and wants a character.
##
## Spawning is driven by this rather than by the peer connecting, because
## connecting and having a level to stand in are different moments. A character
## created for a peer that is still on the menu has nowhere to go: the node it
## belongs under does not exist there yet, the spawn packet lands on nothing, and
## that peer spends the rest of the session unable to see anybody.
@rpc("any_peer", "call_local", "reliable")
func request_character() -> void:
	if not is_host:
		return
	var who := multiplayer.get_remote_sender_id() if is_networked() else 1
	if who == 0:
		who = 1
	_waiting[who] = true

	# Solo has nobody to wait for, so there is no match to run - it goes in at
	# once, at whichever insertion the level thinks is quietest.
	if not is_networked():
		match_state = Match.LIVE
		match_changed.emit(match_state, 0.0)
		_make_character(who, -1)
		return

	# The peer is holding the level, so it may be told about the world now - even
	# though it has no body in it yet. Waiting players still watch the guards
	# patrol, which is what makes the countdown feel like a place rather than a
	# loading screen.
	for id in _ready_peers.keys():
		_peer_ready.rpc_id(who, id)   # who everybody already is, told to the newcomer
	_peer_ready.rpc(who)              # and the newcomer, told to everybody

	# Everything that fell before they got here. Sent now rather than when they
	# deploy, because a player waiting out a countdown is already watching the
	# level and an empty floor is a lie about what has happened in it.
	_send_bodies(who)

	match match_state:
		Match.LIVE:
			# Said before they are put in it, and said to everybody. The newcomer
			# joined after the only announcement this match ever made, so without
			# this its own match_state sits at WAITING for the rest of the raid;
			# and the count of who is here has just changed for everyone else.
			_announce(Match.LIVE, 0.0)
			# A latecomer does not sit out the rest of the raid. It drops in.
			_assign_insertions([who])
			_deploy([who])
		Match.COUNTDOWN:
			_announce(Match.COUNTDOWN, seconds_left)
		_:
			if _waiting.size() >= MIN_PLAYERS:
				_announce(Match.COUNTDOWN, COUNTDOWN)
			else:
				_announce(Match.WAITING, 0.0)


# --- running a match ----------------------------------------------------------


## Ticks the countdown. Runs on every machine: the host is the one that decides
## when it has expired, but a client that only heard "ten seconds" once would
## show a frozen number for ten seconds, so everyone counts their own clock down
## between announcements and the host's word overrides it whenever it arrives.
func _process(delta: float) -> void:
	if match_state != Match.COUNTDOWN:
		return
	seconds_left = maxf(seconds_left - delta, 0.0)
	if not is_host:
		return
	if seconds_left <= 0.0:
		_begin_match()
	elif ceilf(seconds_left) != ceilf(seconds_left + delta):
		# Once a second, so a client that joined mid-count or drifted is pulled
		# back into line without a packet per frame.
		_announce(Match.COUNTDOWN, seconds_left)


## Everyone goes in at once, at the points chosen for them.
func _begin_match() -> void:
	var going := _waiting.keys()
	_assign_insertions(going)
	_announce(Match.LIVE, 0.0)
	_deploy(going)


## Tells every machine where the match is up to, and how many are in it. The
## count travels with the state because only the host knows it, and a waiting
## screen that cannot say "1 of 2" is not telling you the one thing you want to
## know.
func _announce(state: Match, left: float) -> void:
	if is_networked():
		_set_match.rpc(int(state), left, _waiting.size())
	else:
		_set_match(int(state), left, _waiting.size())


@rpc("authority", "call_local", "reliable")
func _set_match(state: int, left: float, players: int) -> void:
	match_state = state as Match
	seconds_left = left
	players_here = players
	match_changed.emit(match_state, seconds_left)


## How many players are in this match, waiting or deployed. Known everywhere.
func player_slots() -> int:
	return maxi(players_here, _waiting.size())


## Builds characters on every machine. Everyone already standing is rebuilt for
## the newcomers first, then the newcomers are built for everyone - the same
## order request_character always used, because a body has to exist on a machine
## before anything can be said about it.
func _deploy(newcomers: Array) -> void:
	for who in newcomers:
		for id in _players.keys():
			if id != who and is_instance_valid(_players[id]):
				_make_character.rpc_id(who, id, _insertion.get(id, -1))
	for who in newcomers:
		var where: int = _insertion.get(who, -1)
		if is_networked():
			_make_character.rpc(who, where)
		else:
			_make_character(who, where)


## Chooses where each player comes in, as far apart as the map allows.
##
## For a pair that means the two insertion points with the greatest distance
## between them, worked out rather than named - "one from each side" sounds
## equivalent and is not, because this map's spawns come in twos and picking one
## from each cluster can still land you within sight of each other.
func _assign_insertions(ids: Array) -> void:
	var points := _spawn_points()
	if points.is_empty():
		return

	# Everybody who still needs somewhere to come in. Anyone already placed keeps
	# their point: they may already be standing on it.
	var pending: Array = []
	for id in ids:
		if not _insertion.has(id):
			pending.append(id)
	if pending.is_empty():
		return

	# The pair case, solved exactly. Two players is the shape this game is
	# actually played in, and for two the right answer is simply the widest pair
	# of points on the map - which is worth the double loop to get right rather
	# than approaching one point at a time.
	if pending.size() == 2 and points.size() >= 2 and _insertion.is_empty():
		var best := Vector2i(0, 1)
		var furthest := -1.0
		for a in points.size():
			for b in range(a + 1, points.size()):
				var apart: float = points[a].distance_squared_to(points[b])
				if apart > furthest:
					furthest = apart
					best = Vector2i(a, b)
		_insertion[pending[0]] = best.x
		_insertion[pending[1]] = best.y
		return

	# Everyone else - a third and fourth player, or somebody dropping into a raid
	# already under way - takes the free point that is furthest from everyone
	# already placed. Handing out whatever happened to be unused put a latecomer
	# wherever the scene file listed first, which on this map is next door to
	# somebody. Furthest-from-the-crowd is the same rule the pair case follows,
	# applied one player at a time.
	for id in pending:
		var taken: Array[int] = []
		for placed in _insertion.values():
			taken.append(placed)

		var choice := -1
		var best_clearance := -1.0
		for i in points.size():
			if taken.has(i):
				continue
			var clearance := INF
			for other in taken:
				clearance = minf(clearance, points[i].distance_squared_to(points[other]))
			if clearance > best_clearance:
				best_clearance = clearance
				choice = i

		# More players than the map has points: start again from the far end
		# rather than stacking everyone on the last one.
		if choice < 0:
			choice = taken.size() % points.size()
		_insertion[id] = choice


## The insertion points, in an order every machine agrees on. Sorted by name
## rather than trusted to come back in scene order, because an index means
## nothing if two machines number the points differently.
func _spawn_points() -> Array[Vector2]:
	var found: Array[Node] = []
	for node in get_tree().get_nodes_in_group(&"spawn"):
		found.append(node)
	found.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	var out: Array[Vector2] = []
	for node in found:
		out.append((node as Node2D).global_position)
	return out


# --- who is allowed to be told about the world --------------------------------
#
# Every synchroniser in the game starts invisible to everyone, and is opened to
# a peer only once that peer is known to be holding the level. That sounds like
# an optimisation and is not: it is the fix for the worst bug in this file's
# history.
#
# A synchroniser addresses its target by node path, and the first thing it does
# with a peer is agree on a short id for that path. The server starts that
# conversation the instant a socket opens - which is while the client is still
# on the menu, with no level and nothing for the path to resolve to. It fails,
# quietly, once, and never tries again. Worse, the failed exchange leaves that
# peer's path cache out of step, so the damage is not limited to the one node
# that was early: eleven guards and the host's own character all go still, and
# the symptom reads as "replication does not work" rather than "we spoke three
# seconds too early".
#
# Connecting and being ready for the world are different moments. request_character
# is already the message that means "my level is up" - this hangs visibility off
# the same signal, so there is one definition of ready rather than two.


## Peers whose level is up. Anyone not in here gets told nothing, because there
## is nowhere for it to land.
var _ready_peers := {}


## Told to every machine when some peer's level comes up. Each one then opens
## the things it is authoritative for - your own character, and the guards if you
## are the host - to that peer.
@rpc("authority", "call_local", "reliable")
func _peer_ready(id: int) -> void:
	if id == peer_id():
		return
	_ready_peers[id] = true
	for sync in _my_synchronisers():
		sync.set_visibility_for(id, true)


## Opens one freshly built body to everyone already waiting. The counterpart to
## the loop above: that one handles a peer arriving after the world, this one a
## body arriving after the peers.
func _publish(body: Node) -> void:
	var sync := body.get_node_or_null(^"Sync") as MultiplayerSynchronizer
	if sync == null or not sync.is_multiplayer_authority():
		return
	for id in _ready_peers.keys():
		if id != peer_id():
			sync.set_visibility_for(id, true)


## Every synchroniser in the level this machine speaks for. Walked rather than
## kept in a list because it is only ever done when somebody joins, and a list
## is one more thing to keep true.
func _my_synchronisers() -> Array[MultiplayerSynchronizer]:
	var found: Array[MultiplayerSynchronizer] = []
	var scene := get_tree().current_scene
	if scene:
		_collect_synchronisers(scene, found)
	return found


func _collect_synchronisers(node: Node, into: Array[MultiplayerSynchronizer]) -> void:
	var sync := node as MultiplayerSynchronizer
	if sync and sync.is_multiplayer_authority():
		into.append(sync)
	for child in node.get_children():
		_collect_synchronisers(child, into)


## Builds one character, identically on every machine. Explicit rather than left
## to a MultiplayerSpawner: the spawner only replicates to peers that were
## already holding the level when the spawn happened, which is an ordering rule
## that is invisible until a client joins a fraction too early and simply never
## sees anyone.
@rpc("authority", "call_local", "reliable")
func _make_character(id: int, insertion: int) -> void:
	var field := _spawn_root()
	if field == null:
		return
	spawn_player(id, field, insertion)


## Puts a character in the world for a peer and hands that peer authority over it.
func spawn_player(id: int, into: Node, insertion := -1) -> Node2D:
	if _players.has(id) and is_instance_valid(_players[id]):
		return _players[id]
	if into.has_node(NodePath(str(id))):
		return into.get_node(NodePath(str(id))) as Node2D

	var body: Node2D = PLAYER_SCENE.instantiate()
	# The name *is* the peer id, and the character reads its own authority off it
	# as it enters the tree. That indirection looks odd and is not optional: a
	# synchroniser is handed its network id on entering the tree, so authority set
	# any later - from here, or in _ready - leaves the spawn without one and every
	# client silently drops the character. The name is the only thing that travels
	# early enough to say who it belongs to.
	body.name = str(id)
	# Set before the character enters the tree, because it reads it as it lands.
	# Sending the index rather than the position means every machine puts the
	# body in the same place on the frame it appears, instead of somewhere wrong
	# until the first sync tick corrects it.
	body.insertion_index = insertion
	# Registration happens from the character's own _ready, via note_player, so
	# host-spawned and client-replicated characters take exactly one path.
	into.add_child(body, true)
	_publish(body)
	return body


func _register(id: int, body: Node2D) -> void:
	if _players.get(id) == body:
		return
	_players[id] = body
	if id == peer_id():
		local_player = body
	player_spawned.emit(body)
	players_changed.emit()


## Called by a player as it enters the tree, so clients register the characters
## the spawner replicated to them without the host having to tell them twice.
func note_player(body: Node2D) -> void:
	var id := body.get_multiplayer_authority()
	if _players.get(id) == body:
		return
	_register(id, body)


func forget_player(body: Node2D) -> void:
	for id in _players.keys():
		if _players[id] == body:
			_players.erase(id)
			if local_player == body:
				local_player = null
			players_changed.emit()
			return


# --- things that fly ----------------------------------------------------------
#
# A round exists on every machine and only counts on one. The host's copy is the
# real one - it is the only copy allowed to do damage - and every other copy is a
# tracer, drawn so the shot is visible to everyone and incapable of hurting
# anybody.
#
# The shooter draws its own round the instant the trigger goes, before the host
# has heard about it. That is not prediction in any real sense, and it is not
# reconciled: it is one tracer that starts a few tens of milliseconds early. What
# it buys is that shooting feels immediate, which at 80 ms to Frankfurt it
# otherwise does not.
#
# The request up to the host is reliable, because a shot that is dropped is a
# shot that never happened. The broadcast back down is not, because a dropped
# tracer is a tracer nobody saw, and the damage was never riding on it.


## Fires a round from wherever the trigger was pulled. Guards call this too, on
## the host, with a shooter of 0 - nobody to credit.
func fire(origin: Vector2, angle: float, weapon_path: String, mask: int,
		damage_scale: float, shooter: int) -> void:
	_make_bullet(origin, angle, weapon_path, mask, damage_scale, shooter)
	if not is_networked():
		return
	if is_host:
		# To everyone but the shooter, which drew its own the moment it fired.
		for peer in multiplayer.get_peers():
			if peer != shooter:
				_make_bullet.rpc_id(peer, origin, angle, weapon_path, mask,
					damage_scale, shooter)
	else:
		_ask_to_fire.rpc_id(1, origin, angle, weapon_path, mask, damage_scale)


@rpc("any_peer", "reliable")
func _ask_to_fire(origin: Vector2, angle: float, weapon_path: String, mask: int,
		damage_scale: float) -> void:
	if not is_host:
		return
	fire(origin, angle, weapon_path, mask, damage_scale,
		multiplayer.get_remote_sender_id())


@rpc("authority", "unreliable")
func _make_bullet(origin: Vector2, angle: float, weapon_path: String, mask: int,
		damage_scale: float, shooter: int) -> void:
	var data := load(weapon_path) as WeaponData
	if data == null:
		return
	Bullet.spawn(get_tree(), origin, angle, data, mask, damage_scale, shooter)
	# Every machine that gets the round gets the report, which is the only way a
	# gunfight sounds like one from more than one seat. A shooter of 0 is a
	# guard - see fire() - and guards are pitched down so an ear can tell a
	# patrol from a person.
	var audio := get_node_or_null(^"/root/Audio")
	if audio:
		audio.gunshot(data, origin, shooter == 0)


## The same arrangement for a thrown gadget. The grenade itself falls under its
## own physics on every machine and will drift apart between them by a pixel or
## two; only the host's copy is allowed to go off and hurt anyone, so the drift
## costs nothing but the look of where it rolled to.
func throw_gadget(gadget_path: String, at: Vector2, velocity: Vector2, mask: int,
		thrower: int) -> void:
	_make_grenade(gadget_path, at, velocity, mask, thrower)
	if not is_networked():
		return
	if is_host:
		for peer in multiplayer.get_peers():
			if peer != thrower:
				_make_grenade.rpc_id(peer, gadget_path, at, velocity, mask, thrower)
	else:
		_ask_to_throw.rpc_id(1, gadget_path, at, velocity, mask)


@rpc("any_peer", "reliable")
func _ask_to_throw(gadget_path: String, at: Vector2, velocity: Vector2,
		mask: int) -> void:
	if not is_host:
		return
	throw_gadget(gadget_path, at, velocity, mask,
		multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func _make_grenade(gadget_path: String, at: Vector2, velocity: Vector2, mask: int,
		thrower: int) -> void:
	var data := load(gadget_path) as GadgetData
	if data == null:
		return
	var grenade := preload("res://scenes/grenade.tscn").instantiate()
	grenade.setup(data, velocity, mask)
	grenade.global_position = at
	grenade.thrower_id = thrower
	_effect_root().add_child(grenade)


# --- the projection -----------------------------------------------------------
#
# A ghost is built on every machine at once and simulated on exactly one of them:
# the caster's. That is the opposite bargain to a grenade, and it has to be. A
# grenade is a ballistic arc against static geometry, so both ends can run it and
# agree; a ghost makes decisions - where to walk, when to break cover, which
# cable to take - and two machines rolling those independently would produce two
# different people standing in two different places, which is the one failure a
# decoy cannot survive. So it is replicated the way a character is, off a
# synchroniser the caster owns, and every other copy is a drawing of it.
#
# There is one ghost per pair of hands, named after them, so anything said about
# one later reaches the same body on every machine. Casting again while one is
# still up takes the old one down first - see _build_projection.


## Puts a ghost in the world, on every machine. Returns this machine's copy.
func cast_projection(gadget_path: String, at: Vector2, look: Dictionary,
		caster: int) -> Node:
	var mine := _build_projection(gadget_path, at, look, caster)
	if not is_networked():
		return mine
	if is_host:
		for peer in multiplayer.get_peers():
			if peer != caster:
				_make_projection.rpc_id(peer, gadget_path, at, look, caster)
	else:
		_ask_to_project.rpc_id(1, gadget_path, at, look)
	return mine


## Screens, identified by a number the host mints.
##
## The identity is the whole reason this is not a copy of the projection path.
## A screen has to be able to die on every machine at once, and "the one that
## just got shot" is not something two peers can work out independently - so the
## host names each one and everybody refers to it by that name afterwards.
##
## Without it the host freed its own copy when a bullet landed and every client
## kept theirs: an invisible, solid, permanent wall standing in a room that the
## person who shot it can see straight through.
var _screen_serial := 0


func raise_screen(top: Vector2, bottom: Vector2, by: int) -> Node:
	if not is_networked():
		_screen_serial += 1
		return _build_screen(top, bottom, by, _screen_serial)
	if not is_host:
		# Asked for, not built. The host owns the numbering, and a sheet raised
		# here under a name of its own could never be taken down anywhere else.
		_ask_to_screen.rpc_id(1, top, bottom)
		return null
	_screen_serial += 1
	_make_screen.rpc(top, bottom, by, _screen_serial)
	return _build_screen(top, bottom, by, _screen_serial)


@rpc("any_peer", "reliable")
func _ask_to_screen(top: Vector2, bottom: Vector2) -> void:
	if not is_host:
		return
	raise_screen(top, bottom, multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func _make_screen(top: Vector2, bottom: Vector2, by: int, id: int) -> void:
	_build_screen(top, bottom, by, id)


func _build_screen(top: Vector2, bottom: Vector2, by: int, id: int) -> Node:
	var scene: PackedScene = load("res://scenes/screen.tscn")
	var sheet: Node2D = scene.instantiate()
	var into := get_tree().current_scene
	if into == null:
		return null
	into.add_child(sheet)
	sheet.setup(top, bottom, by, id)
	return sheet


## Takes one down everywhere. Only the host decides, the same as with damage.
##
## Where it was hit is passed in but deliberately not sent on. The sheet breaks
## up around the point of impact, and it would be tempting to put that on the
## wire so every copy came apart identically - except that they never do anyway:
## the pieces are rolled per machine, so the only thing the extra argument would
## buy is a changed rpc signature, and a changed signature on this node is the
## one thing that cannot ship on its own. A client still running the last
## release would reject the call, and a screen that is never taken down on a
## client is a permanent invisible wall. Copies elsewhere break from the middle,
## which nobody can tell apart from a shatter they did not cause.
func break_screen(id: int, at := Vector2.INF) -> void:
	_drop_screen_here(id, at)
	if is_networked() and is_host:
		_drop_screen.rpc(id)


@rpc("authority", "reliable")
func _drop_screen(id: int) -> void:
	_drop_screen_here(id, Vector2.INF)


func _drop_screen_here(id: int, at: Vector2) -> void:
	for node in get_tree().get_nodes_in_group(&"screen"):
		if is_instance_valid(node) and int(node.get(&"id")) == id:
			# Not freed here. The sheet leaves the group and its collision layer
			# the moment it is asked to break, so it has already stopped being a
			# screen by the time this returns; what is left is the animation, and
			# it frees itself at the end of it.
			node.shatter(at)


@rpc("any_peer", "reliable")
func _ask_to_project(gadget_path: String, at: Vector2, look: Dictionary) -> void:
	if not is_host:
		return
	cast_projection(gadget_path, at, look, multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func _make_projection(gadget_path: String, at: Vector2, look: Dictionary,
		caster: int) -> void:
	_build_projection(gadget_path, at, look, caster)


func _build_projection(gadget_path: String, at: Vector2, look: Dictionary,
		caster: int) -> Node:
	var data := load(gadget_path) as GadgetData
	if data == null:
		return null
	var root := _spawn_root()
	if root == null:
		return null

	# One at a time. The old one does not fade out politely - a second ghost
	# appearing while the first is still walking about would tell anybody
	# watching exactly what they are looking at.
	var wanted := "Ghost_%d" % caster
	var standing := root.get_node_or_null(NodePath(wanted))
	if standing:
		standing.name = "%s_spent" % wanted
		standing.queue_free()

	var ghost: Node2D = PROJECTION_SCENE.instantiate()
	# The name *is* the caster's peer id, and the ghost reads its own authority
	# off it as it enters the tree. Same indirection Net.spawn_player needs, and
	# for the same reason: a synchroniser is handed its network id on entering
	# the tree, and authority set any later leaves the spawn without one.
	ghost.name = wanted
	ghost.setup(data, look)
	ghost.position = at
	root.add_child(ghost)
	return ghost


## This machine's copy of somebody's ghost, or null.
func projection_for(caster: int) -> Node:
	var root := _spawn_root()
	if root == null:
		return null
	return root.get_node_or_null(NodePath("Ghost_%d" % caster))


## Tells a caster's own machine that the host worked out their ghost was hit.
##
## Same route, and the same reason, as tell_owner_hit: the host is the only
## machine allowed to decide a round connected, and the caster is the only
## machine allowed to decide what the ghost does about it - anything applied on
## the host is overwritten by the caster's next sync a frame later. Addressed to
## this autoload rather than to the ghost, because an RPC is delivered by node
## path and a body that appeared thirty seconds into the session is one the two
## machines have to agree a shorthand for first.
func tell_ghost_hit(caster: int, at: Vector2, direction: Vector2,
		from: int) -> void:
	_ghost_hit.rpc_id(caster, caster, at, direction, from)


@rpc("any_peer", "reliable")
func _ghost_hit(caster: int, at: Vector2, direction: Vector2, from: int) -> void:
	# Only the host resolves damage, so only the host may say this.
	if multiplayer.get_remote_sender_id() != 1:
		return
	var ghost := projection_for(caster)
	if ghost == null:
		return
	# Set around the call rather than threaded through it, exactly as _hit_body
	# does: the hitmarker is reported by the body that was hit, and this is the
	# only thing that knows whose round it was.
	attributing_to = from
	ghost.hit(at, direction)
	attributing_to = 0


# --- the line -----------------------------------------------------------------
#
# A hook is thrown on every machine at once and belongs to one of them. The
# thrower's copy is the one that does anything: it decides where the line bit and
# when it comes off, and the pull it applies moves a body whose position is
# already replicated. Every other copy is a drawing - the same hook, thrown from
# the same hand in the same direction, stepped against the same walls.
#
# Which means the line was the only part of this that was ever missing, and it
# was the whole of it. A grapple used to be built by the player who fired it and
# by nobody else: the man swinging across the yard was replicated perfectly and
# the rope holding him up did not exist anywhere but on his own screen.
#
# Simulated at both ends rather than streamed, the same bargain grenades make -
# the geometry it is thrown at is static and identical, so the two copies agree
# without a packet per frame. The anchor is the exception: a replica half a frame
# behind bites half a step further along the wall, and a rope that ends in the
# wrong place is the one error you can see from across the map. When the owner's
# hook bites it says exactly where, and every other copy is put on that point.


## Throws a hook, on every machine. Returns this machine's copy, which is the one
## the thrower holds on to - see Player._fire_grapple.
func fire_grapple(origin: Vector2, aim: Vector2, thrower: int) -> GrappleHook:
	var mine := _build_hook(origin, aim, thrower)
	if not is_networked():
		return mine
	if is_host:
		for peer in multiplayer.get_peers():
			if peer != thrower:
				_make_hook.rpc_id(peer, origin, aim, thrower)
	else:
		_ask_to_grapple.rpc_id(1, origin, aim)
	return mine


@rpc("any_peer", "reliable")
func _ask_to_grapple(origin: Vector2, aim: Vector2) -> void:
	if not is_host:
		return
	fire_grapple(origin, aim, multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func _make_hook(origin: Vector2, aim: Vector2, thrower: int) -> void:
	_build_hook(origin, aim, thrower)


## One line per pair of hands, named after them so anything said about it later
## reaches the same hook on every machine.
func _build_hook(origin: Vector2, aim: Vector2, thrower: int) -> GrappleHook:
	var body := player_for(thrower)
	if body == null:
		return null
	var root := _effect_root()
	var wanted := "Hook_%d" % thrower
	# The previous one is still reeling itself in. It is nobody's line any more -
	# it is only finishing an animation - so it gives up the name at once rather
	# than making the new hook wait for it.
	var spent := root.get_node_or_null(NodePath(wanted)) as GrappleHook
	if spent:
		spent.name = "%s_spent" % wanted
		spent.release()

	var hook: GrappleHook = HOOK_SCENE.instantiate()
	hook.name = wanted
	hook.setup(body, aim)
	root.add_child(hook)
	# After add_child: global_position needs the hook to be in a tree to mean
	# anything, and it is the muzzle it left rather than wherever the body is now.
	hook.global_position = origin
	return hook


## Says what this machine's line just did. A hook has two things to report after
## it leaves the hand - it bit, and where, or it came off - and both have to
## reach everyone or the rope is left hanging in the air.
##
## A finite anchor means it bit there. INF means it is off.
func grapple_news(anchor: Vector2) -> void:
	if not is_networked():
		return
	if is_host:
		for peer in multiplayer.get_peers():
			_hook_news.rpc_id(peer, peer_id(), anchor)
	else:
		_ask_hook_news.rpc_id(1, anchor)


@rpc("any_peer", "reliable")
func _ask_hook_news(anchor: Vector2) -> void:
	if not is_host:
		return
	var who := multiplayer.get_remote_sender_id()
	# The host's own copy of their hook, and then everybody else's - skipping the
	# machine that told us, which is where the news came from.
	_hook_news(who, anchor)
	for peer in multiplayer.get_peers():
		if peer != who:
			_hook_news.rpc_id(peer, who, anchor)


@rpc("authority", "reliable")
func _hook_news(who: int, anchor: Vector2) -> void:
	var hook := _effect_root().get_node_or_null(NodePath("Hook_%d" % who)) as GrappleHook
	if hook == null:
		return
	if anchor.is_finite():
		hook.bite(anchor)
	else:
		hook.release()


# --- landing hard -------------------------------------------------------------


## Somebody hit the ground from a height, and it carried.
##
## The mirror image of a recon arrow. An arrow is you painting other people;
## this is you painting yourself, which is why it is the only reveal in the game
## that has to reach every machine rather than staying on the one that worked it
## out - the point of it is what it does to *their* screens.
##
## Relayed through the host like the hook news, because a client's rpc() only
## reaches the server in this topology.
func fall_heard(at: Vector2, drop: float) -> void:
	if not is_networked():
		_fall_landed(peer_id(), at, drop)
		return
	if is_host:
		_fall_landed(peer_id(), at, drop)
		for peer in multiplayer.get_peers():
			_fall_news.rpc_id(peer, peer_id(), at, drop)
	else:
		# Here first, then ask the host to tell everybody else. The relay
		# deliberately skips whoever reported the landing, so if this machine did
		# not play its own it would be the one player in the session who never
		# heard it - the fall would be silent for the person who took it.
		_fall_landed(peer_id(), at, drop)
		_ask_fall_news.rpc_id(1, at, drop)


@rpc("any_peer", "reliable")
func _ask_fall_news(at: Vector2, drop: float) -> void:
	if not is_host:
		return
	var who := multiplayer.get_remote_sender_id()
	# Here first, then everybody else - skipping the machine that told us, which
	# has already played its own landing.
	_fall_landed(who, at, drop)
	for peer in multiplayer.get_peers():
		if peer != who:
			_fall_news.rpc_id(peer, who, at, drop)


@rpc("authority", "reliable")
func _fall_news(who: int, at: Vector2, drop: float) -> void:
	_fall_landed(who, at, drop)


## What a heavy landing does on this machine: it makes the noise, the guards
## near it go and look, and anybody close enough to have heard it gets to see
## who it was through the walls for a few seconds.
##
## How far it carries and how long it lasts are read off the faller's own node
## rather than sent. They are exports on player.tscn, so every machine already
## has the same numbers, and a client cannot quietly claim it was a quiet
## landing.
func _fall_landed(who: int, at: Vector2, drop: float) -> void:
	var faller := player_for(who)
	if faller == null:
		return
	var height: float = faller.fall_ping_height
	var radius: float = faller.fall_ping_radius
	var audio := get_node_or_null(^"/root/Audio")
	if audio:
		audio.hard_landing(at, clampf((drop - height) / maxf(height, 1.0), 0.0, 1.0))

	# The guards are the host's to think for, so only the host tells them.
	if is_host or not is_networked():
		for node in get_tree().get_nodes_in_group(&"hideable"):
			var guard := node as Node2D
			if guard == null or not guard.has_method(&"heard"):
				continue
			if guard.global_position.distance_to(at) <= radius:
				guard.heard(at)

	# And whoever was close enough to hear it now knows exactly where it came
	# from. You are never in your own hideable set, so you cannot light yourself
	# up - which is right: you already know where you are.
	if local_player == null or local_player == faller:
		return
	if local_player.global_position.distance_to(at) > radius:
		return
	faller.set_meta(&"revealed_until",
		Time.get_ticks_msec() * 0.001 + faller.fall_ping_time)


# --- bodies on the floor ------------------------------------------------------
#
# A guard dies on the host and nowhere else, so the corpse he leaves was created
# on the host and nowhere else: for everybody else he fell over and left nothing
# to search, in a game whose entire loop is searching things. This puts the same
# body, with the same kit in it, on the floor of every machine in the session.


## Leaves a body where somebody fell, on every machine at once.
##
## Only the host may call it - it is the host's guard that died - and the kit
## travels with it rather than being rolled again at the far end. See
## Inventory.to_wire for why regenerating it would not do.
func drop_body(kit: Inventory, at: Vector2, tint: Color, body_size: Vector2,
		who: NodePath) -> void:
	if not deals_damage() or kit == null or kit.is_empty():
		return
	var where := _body_path_for(who)
	if is_networked():
		_make_body.rpc(kit.to_wire(), at, tint, body_size, where, "guard")
	else:
		_make_body(kit.to_wire(), at, tint, body_size, where, "guard")


## Leaves a *player's* kit on the floor where they fell.
##
## The other direction from drop_body, and it has to be. A guard dies on the host
## and nowhere else; a player dies on their own machine - the host works out the
## hit and the body decides what that did to it - so the news travels up rather
## than out. What is on the body is sent rather than looked up, because the
## machine that was carrying it is the only one that knows: a whole raid's
## looting has been going into that pack and none of it was ever replicated.
##
## This is the half of the loop that was missing. Everything a player is carrying
## is what somebody else came here to take, and until now it left the world with
## them - killing someone paid nothing at all.
func drop_kit(kit: Inventory, at: Vector2, tint: Color, body_size: Vector2) -> void:
	if kit == null or kit.is_empty():
		return
	if is_networked() and not is_host:
		_ask_to_drop_kit.rpc_id(1, kit.to_wire(), at, tint, body_size)
		return
	_lay_out_kit(peer_id(), kit.to_wire(), at, tint, body_size)


@rpc("any_peer", "reliable")
func _ask_to_drop_kit(kit: Dictionary, at: Vector2, tint: Color,
		body_size: Vector2) -> void:
	if not is_host:
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = 1
	_lay_out_kit(who, kit, at, tint, body_size)


## Host side: names the body and puts it on every floor. The name is decided here
## for the same reason a guard's is - see _body_path_for.
func _lay_out_kit(who: int, kit: Dictionary, at: Vector2, tint: Color,
		body_size: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fell := player_for(who)
	# A body laid under Players, beside the character it came off. Falling back to
	# a name rather than a lookup covers the one case that beats us to it: a peer
	# whose character has already gone by the time the news arrives.
	var where := _body_path_for(scene.get_path_to(fell)) if fell \
		else NodePath("Players/Body_%d" % who)
	if is_networked():
		_make_body.rpc(kit, at, tint, body_size, where, "player")
	else:
		_make_body(kit, at, tint, body_size, where, "player")


## Where the body of whoever is at `who` should be laid down, as a path relative
## to the level.
##
## Decided by the host and sent, rather than worked out again at each end. Every
## machine could derive "next to him, named after him" for itself and they would
## agree - right up until a guard is killed twice in one raid, where the second
## body's name depends on whether the first is still lying there, which is a fact
## about *that* machine. A latecomer told about both at once would number them
## differently and then hold a path that means a different corpse to everybody
## else. The path is also the key a search is claimed against, so the two have to
## be the same string everywhere.
func _body_path_for(who: NodePath) -> NodePath:
	var scene := get_tree().current_scene
	var fell := scene.get_node_or_null(who) if scene else null
	if fell == null or scene == null:
		return who
	var parent := fell.get_parent()
	var wanted := "Body_%s" % fell.name
	# A guard who died earlier in the raid is still lying where he fell.
	if parent.has_node(NodePath(wanted)):
		var n := 2
		while parent.has_node(NodePath("%s_%d" % [wanted, n])):
			n += 1
		wanted = "%s_%d" % [wanted, n]
	# Written the way get_path_to would write it, because that is the form the
	# rest of the game keys a body by - see Player._body_path.
	if parent == scene:
		return NodePath(wanted)
	return NodePath("%s/%s" % [scene.get_path_to(parent), wanted])


@rpc("authority", "call_local", "reliable")
func _make_body(kit: Dictionary, at: Vector2, tint: Color, body_size: Vector2,
		where: NodePath, tag: String) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	# Told about the same body twice - a latecomer's replay racing the drop that
	# happened while it was joining. Two corpses on one machine and one on every
	# other is worse than a wasted packet.
	if scene.has_node(where):
		return

	var body: Lootable = preload("res://scenes/lootable.tscn").instantiate()
	# Before it enters the tree: Lootable draws itself from these in _ready.
	body.setup(Inventory.from_wire(kit), tint, body_size, tag)

	# Laid down where the host said, under the same parent and with the same name
	# on every machine. The path is relative to the level rather than absolute so
	# it resolves the same in a --script test harness as in the real game.
	var text := String(where)
	var parent := scene.get_node_or_null(text.get_base_dir()) if text.contains("/") else scene
	body.name = text.get_file()
	(parent if parent else scene).add_child(body)
	body.global_position = at


## Describes every body already on the floor to a peer that has just arrived.
##
## Bodies are put down by an RPC at the moment somebody dies, so a peer that was
## still on the menu when the shooting started was told about none of them: it
## drops into a raid where eleven guards have been killed and nothing on the
## floor says so. The corpses are the record of what has happened here, and half
## of them are still holding a rifle.
##
## Sent from the bodies themselves rather than from a log of drops, so what a
## latecomer is handed is what is on them *now* - picked clean if somebody has
## already been through them.
func _send_bodies(to: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node in get_tree().get_nodes_in_group(&"lootable"):
		var body := node as Lootable
		if body == null or not is_instance_valid(body):
			continue
		var kit := body.inventory.to_wire() if body.inventory else {}
		_make_body.rpc_id(to, kit, body.global_position, body.tint,
			body.body_size, scene.get_path_to(body), body.tag)


# --- going through a body -----------------------------------------------------
#
# The same body is now on the floor of every machine, but each machine holds its
# own copy of what is in it - so without this, two people go through the same
# pockets and both come away with the rifle. In a game whose whole economy is
# what you can carry out, duplicating kit is the only thing that really breaks.
#
# A body is searched by one person at a time. The host hands it out, holds it for
# as long as that screen is open, and broadcasts what is left when it closes.
#
# Per body rather than per item, and that is a decision rather than a shortcut.
# Dragging lifts an item clean out of its container and parks it on the cursor -
# nowhere at all - for as long as the mouse is held, and there is no honest answer
# to "who has it" during that time. A whole body held for the length of a search
# has one answer at every moment. It is also the truer picture: you are kneeling
# over somebody going through their pockets, and two people doing that to the same
# body at the same time was never what this was.


## Which peer is searching which body, on the host. Keyed by the body's path
## relative to the level, which every machine agrees on - see _make_body.
var _searchers := {}


## Asks to search a body. The answer comes back through
## Player.on_body_answer, because it can be no.
func ask_to_search(body: NodePath) -> void:
	if not is_networked():
		_answer_body(body, peer_id())
		return
	_ask_to_search.rpc_id(1, body)


@rpc("any_peer", "reliable")
func _ask_to_search(body: NodePath) -> void:
	if not is_host:
		return
	# A host asking itself arrives with a sender of 0 - see request_character.
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = 1
	var key := String(body)
	var holder: int = _searchers.get(key, 0)
	# Already yours is a yes: pressing the key twice on the same body should open
	# it, not tell you somebody else has it.
	if holder == 0 or holder == who:
		_searchers[key] = who
		holder = who
	_body_answer.rpc_id(who, body, holder)


@rpc("authority", "reliable")
func _body_answer(body: NodePath, holder: int) -> void:
	_answer_body(body, holder)


func _answer_body(body: NodePath, holder: int) -> void:
	if local_player and local_player.has_method(&"on_body_answer"):
		local_player.on_body_answer(body, holder)


## Says what is on a body being searched right now, while the search is still
## going on.
##
## The search itself is finished with done_searching, and for a search that
## finishes that is all that is needed. This is for the one that does not: pull
## the cable out with a rifle already dragged across onto yourself and the rifle
## is on your machine, while the body every remaining player can see reverts to
## what the host last heard - which was the state before you knelt down. One
## rifle, two copies, and the only thing an extraction game cannot survive is kit
## that multiplies.
##
## Sent as the body changes rather than on a timer, so the host is behind by at
## most the one item you were moving as the connection went. Nothing is
## broadcast: the other players are not allowed to see inside a body somebody
## else is holding, and would only be told the same thing again a moment later.
func searching_progress(body: NodePath, contents: Dictionary) -> void:
	if not is_networked():
		return
	_body_progress.rpc_id(1, body, contents)


@rpc("any_peer", "reliable")
func _body_progress(body: NodePath, contents: Dictionary) -> void:
	if not is_host:
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = 1
	if _searchers.get(String(body), 0) != who:
		return   # not theirs to describe
	# A listen server host searching a body is already editing the only copy that
	# matters. Handing it back a rebuilt inventory would swap the object out from
	# under its own open screen, which is holding a reference to it.
	if who == peer_id():
		return
	_apply_body_contents(body, contents)


## Finished with it. Hands the body back and tells everyone what is left on it -
## sent from here rather than worked out by the host, because this machine is the
## only one that knows what was taken. It is the one that did the taking.
func done_searching(body: NodePath, contents: Dictionary) -> void:
	if not is_networked():
		return
	_finished_searching.rpc_id(1, body, contents)


@rpc("any_peer", "reliable")
func _finished_searching(body: NodePath, contents: Dictionary) -> void:
	if not is_host:
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = 1
	var key := String(body)
	if _searchers.get(key, 0) != who:
		return   # not theirs to hand back
	_searchers.erase(key)
	_set_body_contents.rpc(body, contents)


@rpc("authority", "call_local", "reliable")
func _set_body_contents(body: NodePath, contents: Dictionary) -> void:
	_apply_body_contents(body, contents)


func _apply_body_contents(body: NodePath, contents: Dictionary) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var found := scene.get_node_or_null(body) as Lootable
	if found:
		found.set_contents(Inventory.from_wire(contents))


## Takes back everything a peer was searching and tells everyone what is on it.
##
## Called when that peer leaves rather than hands it back. Erasing the claim on
## its own is enough to let somebody else open the body, but not enough to make
## the body true: the host has been told what was being taken out of it as it
## happened (see searching_progress) and nobody else has heard any of it, so the
## state has to be pushed out or the next person to kneel down finds a rifle that
## walked out of the raid five seconds ago.
func _release_bodies_of(id: int) -> void:
	var scene := get_tree().current_scene
	for key in _searchers.keys():
		if _searchers[key] != id:
			continue
		_searchers.erase(key)
		if scene == null:
			continue
		var found := scene.get_node_or_null(NodePath(key)) as Lootable
		if found == null:
			continue
		var kit := found.inventory.to_wire() if found.inventory else {}
		_set_body_contents.rpc(NodePath(key), kit)


## Where rounds and grenades live. Named rather than guessed, so every machine
## puts them in the same place and nothing depends on who fired.
func _effect_root() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return get_tree().root
	var container := scene.get_node_or_null(^"Bullets")
	return container if container != null else scene


## Whether a projectile spawned here is the one that counts.
func deals_damage() -> bool:
	return not is_networked() or is_host


## Tells a player's own machine that the host worked out it was hit.
##
## A body is owned by the machine sitting behind it and its health replicates
## outward from there, so damage applied on the host is overwritten by the
## owner's next sync a frame later and the shot simply never happened. The host
## decides you were hit and says so; your machine decides what your body does
## about it.
##
## Addressed to this autoload rather than to the body, and that is not tidiness.
## An RPC is delivered by node path, and the path to a character that appeared
## thirty seconds into the session is one the two machines have to agree a
## shorthand for first. That negotiation is quiet when it does not happen: the
## call is not delivered, nothing is logged, and the symptom is that shooting
## another player does nothing at all while shooting a guard - resolved entirely
## on the host, no second hop - works perfectly. This file is at /root/Net on
## every machine from the moment it starts and has been exchanging rounds and
## match state since before anybody had a body.
func tell_owner_hit(owner_id: int, amount: float, at: Vector2, direction: Vector2,
		from: int, pierce := 0.0, wear := 1.0) -> void:
	_hit_body.rpc_id(owner_id, owner_id, amount, at, direction, from, pierce, wear)


@rpc("any_peer", "reliable")
func _hit_body(owner_id: int, amount: float, at: Vector2, direction: Vector2,
		from: int, pierce: float, wear: float) -> void:
	# Only the host resolves damage, so only the host may say this.
	if multiplayer.get_remote_sender_id() != 1:
		return
	var body := player_for(owner_id)
	if body == null:
		return
	# The round travels with the shot. What it does to a plate is a fact about
	# the round, and the machine that works the plate out is not the machine
	# holding the gun - so it has to come along rather than be looked up.
	attributing_to = from
	piercing = pierce
	armor_wear = wear
	body.take_damage(amount, at, direction)
	piercing = 0.0
	armor_wear = 1.0
	attributing_to = 0


## Hands a hitmarker to whoever actually fired, which is no longer necessarily
## the machine that worked out the hit.
func credit_hit(headshot: bool, killed: bool) -> void:
	var who := attributing_to
	# A guard's round, whoever it landed on. Nobody to congratulate - and now
	# that a player reports what a hit did to their own body, "nobody" has to be
	# checked before "is this my own machine", or being shot by a guard while
	# playing alone marks it up as a hit you scored.
	if who == 0:
		return
	if not is_networked() or who == peer_id():
		if local_player and local_player.has_method(&"on_hit_dealt"):
			local_player.on_hit_dealt(headshot, killed)
		return
	# Sent from wherever the hit was noticed, which is not always the host. A
	# player works out what a round did to their own body (see
	# Player.take_damage), so the mark for shooting somebody travels client to
	# client. It is a hitmarker: the worst a forged one buys you is a tick on
	# your own screen, and requiring it to go via the host would mean the one
	# hit that matters most is the one nobody is told about.
	_hit_landed.rpc_id(who, headshot, killed)


@rpc("any_peer", "unreliable")
func _hit_landed(headshot: bool, killed: bool) -> void:
	if local_player and local_player.has_method(&"on_hit_dealt"):
		local_player.on_hit_dealt(headshot, killed)


## Tells a player that somebody's recon arrow has just swept over them.
##
## The reveal itself is correctly one machine's business - an arrow paints the
## bodies *you* can then see through walls, and nobody else's screen changes -
## which is exactly why this has to be sent. Being watched is the one part of it
## the person being watched has any use for, and they are on the other machine.
##
## Client to client, like credit_hit and for the same reasons: the machine that
## loosed the arrow is the only one that worked out who it caught, and a forged
## one buys you nothing but a banner on your own screen. Reliable, because unlike
## a hitmarker there is no second chance to notice - the arrow lands once.
func tell_scanned(who: int) -> void:
	# You are never in your own hideable set, so your own arrow cannot paint you.
	if not is_networked() or who == peer_id():
		return
	_scanned.rpc_id(who)


@rpc("any_peer", "reliable")
func _scanned() -> void:
	if local_player and local_player.has_method(&"mark_scanned"):
		local_player.mark_scanned()


# --- peers coming and going ---------------------------------------------------


func _on_peer_connected(id: int) -> void:
	if is_dedicated:
		print("[server] peer %d connected (%d/%d)"
			% [id, multiplayer.get_peers().size(), MAX_PLAYERS])
	peer_joined.emit(id)
	# Nothing is spawned here on purpose. A peer that has connected has not
	# necessarily loaded the level - it asks for a character itself, once it has
	# somewhere to put one. See request_character.


func _on_peer_disconnected(id: int) -> void:
	var body := _players.get(id) as Node2D
	if is_instance_valid(body):
		body.queue_free()
	_players.erase(id)
	_ready_peers.erase(id)
	_waiting.erase(id)
	# Anything they were searching goes back in the pool, or nobody can ever open
	# it again - along with what the host was last told is on it, so that what
	# they took with them is gone from the body for everybody else too.
	_release_bodies_of(id)
	# Their insertion point goes back in the pool for whoever arrives next.
	_insertion.erase(id)
	# A countdown for two that is now a countdown for one goes back to waiting -
	# otherwise it runs out and drops a lone player into an empty raid.
	if is_host and match_state == Match.COUNTDOWN and _waiting.size() < MIN_PLAYERS:
		_announce(Match.WAITING, 0.0)
	if is_dedicated:
		print("[server] peer %d left (%d/%d)"
			% [id, multiplayer.get_peers().size(), MAX_PLAYERS])
		if _waiting.is_empty():
			_start_over()
	peer_left.emit(id)
	players_changed.emit()


## The last player has left. Put the world back and wait for the next two.
##
## Only a server does this, and only when it is empty. Without it the box keeps
## whatever the last match left behind: the state stays LIVE, so the next person
## to press the button is deployed alone into a map of eleven dead guards and
## somebody else's corpses. "Waits for two and starts" has to be true every time,
## not only the first time the process comes up.
func _start_over() -> void:
	print("[server] empty - resetting for the next match")
	match_state = Match.WAITING
	seconds_left = 0.0
	players_here = 0
	_insertion.clear()
	_searchers.clear()
	# Guards, bodies and everything shot off a wall come back with the level. It
	# is reloaded rather than tidied because a raid leaves marks in a dozen places
	# and only one of them is a list this file keeps.
	get_tree().reload_current_scene()


func _on_connected() -> void:
	in_session = true
	session_started.emit(false)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	session_ended.emit("could not reach the host")


func _on_server_disconnected() -> void:
	leave("the host left")


## Where characters go. Named rather than guessed so the spawner and this agree.
func _spawn_root() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(^"Players")
