extends Control

## The screen before the level: kit out, then queue.
##
## There is one world and it is always up, so there is nothing here to decide
## about where you are going - only what you are taking. You fill your slots,
## press the button, and you are put into the next match that needs somebody.
## Nobody hosts anybody and there is no address to type: a matchmaking button
## that asks you for an IP is not matchmaking.
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

const MAIN_SCENE := "res://scenes/main.tscn"
const SHOP_SCRIPT := preload("res://scripts/shop.gd")

## Where to dial. The compiled-in server unless the command line says otherwise.
var _address := Net.MATCHMAKING_HOST
var _port := Net.DEFAULT_PORT

var _shop: Control
var _status: Label
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
##   godot --path . -- --join=127.0.0.1
##
## --join is also how you point the button at a server that is not the live one:
## it replaces the address and queues immediately, which is what testing against
## a box on your own machine wants.
##
##   godot --headless --path . -- --server
##   godot --headless --path . -- --server=27015
##
## --server is the only one of these that is not a convenience. A dedicated
## server has no menu to click, so the command line is its entire interface.
func _take_orders_from_the_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--server" or arg.begins_with("--server="):
			_on_serve(int(arg.get_slice("=", 1)) if arg.contains("=") else Net.DEFAULT_PORT)
			return
		if arg == "--solo":
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
	_shop.deploy_label = "JOIN MATCHMAKING"
	_shop.status = "one button, one world"
	_shop.deployed.connect(_on_queue)
	_shop.open(_kit)

	# Added after the shop so it is on top of it: the shop stops mouse input over
	# its whole rect, and a button underneath that would never be clicked.
	var alone := Button.new()
	alone.text = "play alone"
	alone.flat = true
	alone.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	alone.position = Vector2(56.0, -62.0)
	alone.custom_minimum_size = Vector2(120.0, 34.0)
	alone.pressed.connect(_on_solo)
	add_child(alone)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(190.0, -56.0)
	_status.text = "server %s" % _address
	_status.add_theme_font_size_override(&"font_size", 12)
	_status.add_theme_color_override(&"font_color", Color(0.48, 0.53, 0.6))
	add_child(_status)


# --- the ways in --------------------------------------------------------------


## Into the queue. What was bought goes with us: the level is a scene change
## away and the body it belongs to is a match away, so it waits on Net.
func _on_queue() -> void:
	Net.staged_kit = _kit
	if Net.join(_address, _port) != OK:
		_say("could not reach %s" % _address)
		return
	_say("finding a match on %s..." % _address)
	# The level is not loaded until the handshake finishes: it spawns characters
	# on arrival, and doing that mid-connection is how you end up with two of
	# them fighting over the same name.
	set_process(true)


func _on_solo() -> void:
	Net.staged_kit = _kit
	Net.play_solo()
	_enter_level()


## Opens the level as a server nobody is sitting at. Reached only from the
## command line: there is no button for it because the machine that wants it has
## no screen to put one on.
func _on_serve(port: int) -> void:
	if Net.serve(port) != OK:
		push_error("could not open port %d - is something already on it?" % port)
		get_tree().quit(1)
		return
	_enter_level()


func _process(_delta: float) -> void:
	if Net.in_session:
		set_process(false)
		_enter_level()


func _on_session_started(_as_host: bool) -> void:
	_say("in the match")


func _on_session_ended(reason: String) -> void:
	_say(reason)


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _enter_level() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)
