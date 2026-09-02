extends Control

## The screen before the level: kit out, then queue.
##
## There is one world and it is always up, so the queue asks you nothing about
## where you are going - only what you are taking. You fill your slots, press the
## button, and you are put into the next match that needs somebody. Nobody hosts
## anybody and there is no address to type: a matchmaking button that asks you
## for an IP is not matchmaking.
##
## The map button is the exception, and it is not on that path. Maps that no
## server is holding open can still be played alone, and going in alone is the
## only way they can be played at all - so the button sits with the two that go
## in alone and says nothing about the queue.
##
## It exists because of an ordering problem as much as for its own sake. The
## level opens a session as it loads - it has to, or a character never appears -
## so by the time you are looking at the game it is already too late to join
## anyone. Connecting has to happen first, and kitting out is the thing worth
## doing while it does: it is minutes of decisions, and it used to be crammed
## into a ten-second countdown you shared with everybody else's.
##
## What is bought here is parked on Net, which is the only thing alive across the
## scene change, and handed to the body when the countdown ends.

const SHOP_SCRIPT := preload("res://scripts/shop.gd")

## Where to dial. The compiled-in server unless the command line says otherwise.
var _address := Net.MATCHMAKING_HOST
var _port := Net.DEFAULT_PORT

var _shop: Control
var _status: Label
var _controls: Button
var _map: Button
var _kit: Inventory


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	_build()
	_take_orders_from_the_command_line.call_deferred()


## Lets a launch skip the menu, so a session can be started without anybody
## clicking anything:
##
##   godot --path . -- --solo
##   godot --path . -- --solo=quarry
##   godot --path . -- --join=127.0.0.1
##
## --solo takes a map, because the maps that are not the world can only be
## reached that way and a headless test of one should not have to click.
##
## --join is also how you point the button at a server that is not the live one:
## it replaces the address and queues immediately, which is what testing against
## a box on your own machine wants.
##
##   godot --headless --path . -- --server
##   godot --headless --path . -- --server=27015
##   godot --headless --path . -- --server --level=quarry
##
## --server is the only one of these that is not a convenience. A dedicated
## server has no menu to click, so the command line is its entire interface.
##
## --level is how a match is played on something other than the world. It is a
## server-side flag and deliberately has no client half: the server announces
## what it is holding open and clients follow, because two machines choosing a
## map independently is two machines in different buildings.
func _take_orders_from_the_command_line() -> void:
	# Read before --server acts on it, whatever order they were typed in: the
	# map has to be chosen before the socket opens, because the first thing the
	# server says to a peer is which one it is holding open.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			_choose_map(arg.get_slice("=", 1))
			Net.match_level = Net.solo_scene()
	for arg in OS.get_cmdline_user_args():
		if arg == "--server" or arg.begins_with("--server="):
			_on_serve(int(arg.get_slice("=", 1)) if arg.contains("=") else Net.DEFAULT_PORT)
			return
		if arg == "--solo" or arg.begins_with("--solo="):
			if arg.contains("="):
				_choose_map(arg.get_slice("=", 1))
			_on_solo()
			return
		if arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
		if arg.begins_with("--join"):
			# Bare --join means the same machine, which is the common case when
			# you are testing against a server you started in the next window.
			_address = arg.get_slice("=", 1) if arg.contains("=") else "127.0.0.1"
			# Deferred so a --port= after it on the line is read first.
			_on_queue.call_deferred()


func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.08)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	# The same shop the level used to put over the countdown, on the screen where
	# it belongs. One script, so what you buy here is bought exactly as it always
	# was - slots, refunds, the lot.
	_kit = Weapon.starting_inventory()
	_shop = Control.new()
	_shop.set_script(SHOP_SCRIPT)
	_shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shop)
	# A browser cannot open a UDP socket, and this game's session model is ENet
	# from end to end - so on the web the one button that means "put me in a
	# match" cannot mean that, and pretending otherwise buys a player thirty
	# seconds of watching a connection that was never going to arrive.
	#
	# It becomes the solo button instead, and says why on the line underneath.
	# The alternative - a second transport, WebSocket or WebRTC, and a server
	# listening on both - is a real thing to build and not a label change; see
	# server/README.md.
	if in_a_browser():
		_shop.deploy_label = "DEPLOY (SOLO)"
		_shop.status = "browser build - no matchmaking, a browser has no UDP"
		_shop.deployed.connect(_on_solo)
	else:
		_shop.deploy_label = "JOIN MATCHMAKING"
		_shop.status = "one button, one world"
		_shop.deployed.connect(_on_queue)
	_shop.open(_kit)

	# Added after the shop so they are on top of it: the shop stops mouse input
	# over its whole rect, and a button underneath it would never be clicked.
	var alone := Button.new()
	alone.text = "play alone"
	alone.flat = true
	alone.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	alone.position = Vector2(56.0, -62.0)
	alone.custom_minimum_size = Vector2(120.0, 34.0)
	alone.pressed.connect(_on_solo)
	add_child(alone)

	var test := Button.new()
	test.text = "test drive"
	test.flat = true
	test.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	test.position = Vector2(186.0, -62.0)
	test.custom_minimum_size = Vector2(120.0, 34.0)
	test.tooltip_text = "straight into an empty level, fully kitted - no shop, no briefing"
	test.pressed.connect(_on_test_drive)
	add_child(test)

	# Which map the two buttons to the left of it open. Matchmaking is not on it:
	# there is one world and the queue always goes there, so a map picker that
	# looked like it applied to the big button would be lying about where you are
	# about to be put.
	_map = Button.new()
	_map.flat = true
	_map.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_map.position = Vector2(316.0, -62.0)
	_map.custom_minimum_size = Vector2(180.0, 34.0)
	_map.tooltip_text = "which map you go into on your own - matchmaking is always the yard"
	_map.pressed.connect(_on_cycle_map)
	add_child(_map)
	_refresh_map_label()

	# Cycles auto / touch / desktop and remembers the answer. On this screen
	# rather than buried in a settings menu because the reason to touch it is to
	# look at the on-screen controls on a PC, which you do constantly while they
	# are being built and never again afterwards.
	_controls = Button.new()
	_controls.flat = true
	_controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_controls.position = Vector2(-232.0, -62.0)
	_controls.custom_minimum_size = Vector2(200.0, 34.0)
	_controls.tooltip_text = "auto follows the device; force touch to see the thumbsticks on a PC"
	_controls.pressed.connect(_on_cycle_controls)
	add_child(_controls)
	_refresh_controls_label()

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(56.0, -92.0)
	_status.text = ("solo only in a browser" if in_a_browser()
		else "server %s" % _address)
	_status.add_theme_font_size_override(&"font_size", 12)
	_status.add_theme_color_override(&"font_color", Color(0.48, 0.53, 0.6))
	add_child(_status)


# --- the ways in --------------------------------------------------------------


## Into the queue. What was bought goes with us: the level is a scene change
## away and the body it belongs to is a match away, so it waits on Net.
## Whether this is running in a browser, where there is no UDP to have.
##
## A function rather than a constant read once: it is asked from _build and from
## the command line path, and a feature test is cheap enough that caching it
## would only be a second thing that can be wrong.
func in_a_browser() -> bool:
	return OS.has_feature("web")


func _on_queue() -> void:
	# Reachable from the command line as well as the button, so the refusal
	# lives here too rather than only on the thing that was relabelled.
	if in_a_browser():
		_say("no matchmaking in a browser - use the desktop build")
		return
	Net.staged_kit = _kit
	if Net.join(_address, _port) != OK:
		_say("could not reach %s" % _address)
		return
	_say("finding a match on %s..." % _address)
	# The level is not loaded until the handshake finishes: it spawns characters
	# on arrival, and doing that mid-connection is how you end up with two of
	# them fighting over the same name.
	set_process(true)


func _on_cycle_controls() -> void:
	PlayerInput.cycle_controls()
	_refresh_controls_label()


func _refresh_controls_label() -> void:
	if _controls:
		_controls.text = "controls: %s" % PlayerInput.scheme_name()


func _on_cycle_map() -> void:
	Net.cycle_solo_level()
	_refresh_map_label()


## Picks a map by name, for the command line. Loose about how it is spelled -
## see Net.level_named - and it says so and carries on if there is no such map,
## because a typo in a launch argument should not cost you the launch.
func _choose_map(wanted: String) -> void:
	var found := Net.level_named(wanted)
	if found < 0:
		push_warning("no map called '%s' - staying on %s" % [wanted, Net.solo_name()])
		return
	Net.solo_level = found
	_refresh_map_label()


func _refresh_map_label() -> void:
	if _map:
		_map.text = "map: %s" % Net.solo_name()


## Alone, on whichever map the button says. A real run: everything carried in
## was bought at the counter, and the map is the only thing chosen for free.
func _on_solo() -> void:
	Net.staged_kit = _kit
	Net.play_solo()
	_enter_level(Net.solo_scene())


## An empty level, one of you, everything already in your hands.
##
## Not the same thing as playing alone, which is a real run and therefore starts
## at the counter - everything you take in has to be bought, and that rule is the
## whole game. This deliberately breaks it, because what it is for is not a raid:
## it is jumping, grappling, shooting a wall and seeing how the camera feels,
## which you want to do fifty times in a row without buying a rifle each time.
##
## The status quo it replaces is four screens and a countdown between changing a
## number and feeling the difference. On a phone, where the loop already runs
## through a deploy, that gap is most of the cost of trying anything.
func _on_test_drive() -> void:
	Net.staged_kit = _test_kit()
	Net.test_drive = true
	Net.play_solo()
	_enter_level(Net.solo_scene())


## One of everything, so nothing goes untested for want of affording it. Built by
## hand rather than bought, because the shop is exactly what this path skips.
func _test_kit() -> Inventory:
	var kit := Weapon.starting_inventory()
	kit.set_slot(Inventory.Slot.PRIMARY,
		Item.from_weapon(load("res://resources/weapons/assault_rifle.tres")))
	kit.set_worn(Inventory.Wear.HELMET,
		Item.from_armor(load("res://resources/armor/light_helmet.tres")))
	kit.set_worn(Inventory.Wear.VEST,
		Item.from_armor(load("res://resources/armor/light_vest.tres")))
	# The bag first: rounds need somewhere to go, and five pockets do not hold a
	# session's worth of shooting at things.
	kit.set_backpack(Item.from_backpack(load("res://resources/backpacks/patrol_pack.tres")))
	# The rack before the thing that goes in it: an ultimate has nowhere to be
	# without a power source, which is the whole point of the slot.
	kit.set_power(Item.from_power(load("res://resources/power/power_cell.tres")))
	kit.set_ultimate(Item.from_gadget(load("res://resources/gadgets/overload.tres")))
	kit.set_throwable(0, Item.from_gadget(load("res://resources/gadgets/frag.tres")))
	kit.set_throwable(1, Item.from_gadget(load("res://resources/gadgets/smoke.tres")))
	kit.add_rounds(&"5.56", 200)
	kit.add_rounds(&"9mm", 100)
	return kit


## Opens the level as a server nobody is sitting at. Reached only from the
## command line: there is no button for it because the machine that wants it has
## no screen to put one on.
func _on_serve(port: int) -> void:
	if Net.serve(port) != OK:
		push_error("could not open port %d - is something already on it?" % port)
		get_tree().quit(1)
		return
	# Whichever map --level named, defaulting to the world. A server holds open
	# the map its clients are going to load, and now it says which one that is
	# instead of everybody assuming.
	print("[server] holding open %s" % Net.match_level)
	_enter_level(Net.match_level)


## A client waits to be told which map before it opens one. Connecting and
## knowing where you are going are different moments - Net sends the map to a
## peer the instant it connects, but that is a round trip, and loading the wrong
## level in the gap puts the two machines in different buildings with every
## synchroniser pointing at a node path the other end does not have.
func _process(_delta: float) -> void:
	if Net.in_session and Net.level_settled():
		set_process(false)
		_enter_level(Net.match_level)


func _on_session_started(_as_host: bool) -> void:
	_say("in the match")


func _on_session_ended(reason: String) -> void:
	_say(reason)


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _enter_level(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
