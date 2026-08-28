extends Label

## The key list in the corner, on the desktop build.
##
## Generated from the InputMap rather than typed out. The hand-written version
## this replaces had drifted badly: it was missing the plates (V), the surgical
## kit (X), the restart (ENTER), the middle mouse button on the grapple and the
## arrow keys on everything, and it still described five weapon slots as "1-2
## hands, 3-5 bags", which stopped being true when the slot list changed. None of
## that is surprising. A legend written by hand is a second copy of the bindings,
## and a second copy of anything drifts the moment somebody changes the first.
##
## So this reads the actual map. Every action carrying a real key is on screen,
## every key printed is the key that is bound right now, and rebinding one
## rewrites the legend without anybody remembering to. LAYOUT below is only about
## grouping and wording; if an action is not in it, the sweep at the bottom of
## _compose puts it on screen anyway under "ALSO". Missing from the legend is the
## one thing this file is not allowed to be.
##
## Desktop only. TouchControls flips `visible` from its _process - "A / D move,
## SPACE jump" is a lie on a phone, and it sits exactly where the thumb pads go.

## Rows, in reading order. Each entry is one printed pair: the actions it covers,
## and what to call them. Nothing here says what key anything is on - that comes
## out of the map, every time, which is the point.
const LAYOUT := [
	{"title": "MOVE", "pairs": [
		{"actions": [&"move_left", &"move_right"], "says": "walk"},
		{"actions": [&"jump"], "says": "jump (hold = higher)"},
		{"actions": [&"move_down"], "says": "down / ride a cable down"},
		{"actions": [&"crouch"], "says": "crouch - slower, quieter, smaller"},
		{"actions": [&"grapple"], "says": "grapple"},
	]},
	{"title": "FIGHT", "pairs": [
		{"actions": [&"fire"], "says": "fire"},
		{"actions": [&"aim"], "says": "aim - tighter cone, slower walk"},
		{"actions": [&"reload"], "says": "reload"},
		{"actions": [&"shield"], "says": "plates up / down"},
		{"actions": [&"weapon_1", &"weapon_2", &"weapon_3", &"weapon_4", &"weapon_5"],
			"says": "slots"},
	]},
	{"title": "KIT", "pairs": [
		{"actions": [&"ultimate"], "says": "ultimate 1"},
		{"actions": [&"ultimate_2"], "says": "ultimate 2"},
		{"actions": [&"throw_1", &"throw_2"], "says": "aim and throw"},
		{"actions": [&"heal"], "says": "medkit / get back up"},
		{"actions": [&"surgical"], "says": "surgical kit - clears a wound"},
	]},
	{"title": "WORLD", "pairs": [
		{"actions": [&"interact"], "says": "search a body / grab or drop a cable"},
		{"actions": [&"inventory"], "says": "inventory"},
		{"actions": [&"map"], "says": "map"},
		{"actions": [&"restart"], "says": "restart"},
		{"actions": [&"debug_charge"], "says": "debug: fill the ultimate"},
	]},
]

## Actions with no keyboard or mouse binding at all. The four stick axes are
## joypad-only by design - they are the right thumbstick, and there is no key to
## print for them - so they are named here rather than turning up under "ALSO"
## every time the sweep runs.
const PAD_ONLY := [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]

## Between a key and what it does, and between one pair and the next. Spaces
## rather than a grid because this is a Label: there is no column to align to,
## and the eye separates the pairs on the gap alone.
const GAP := "      "

## Only ever built once. The map does not change while the game is running, apart
## from the mouse bindings PlayerInput lifts out in touch mode - and in touch
## mode this label is not on screen at all.
var _built := false


func _ready() -> void:
	# Under everything else on the HUD, and never in the way of a click.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override(&"font_size", 13)
	_rebuild()
	# The mouse bindings come and go with the scheme, so the legend is rebuilt
	# when it does. It is four string joins, once, on a button press.
	PlayerInput.controls_changed.connect(_on_controls_changed)


func _on_controls_changed(_touch: bool) -> void:
	_built = false
	_rebuild()


func _rebuild() -> void:
	if _built:
		return
	_built = true
	text = _compose()


## The whole legend, and the guarantee that goes with it: every action in the map
## that a keyboard or a mouse can reach ends up in the returned string.
func _compose() -> String:
	var lines: PackedStringArray = []
	var covered := {}

	for row in LAYOUT:
		var printed: PackedStringArray = []
		for pair in row.pairs:
			var found: PackedStringArray = []
			for action in pair.actions:
				covered[action] = true
				if InputMap.has_action(action):
					found.append_array(_keys_for(action))
			var keys := " / ".join(found)
			if keys.is_empty():
				# Bound to nothing at all. Saying so beats printing a bare
				# description with no key in front of it.
				keys = "unbound"
			printed.append("%s  %s" % [keys, pair.says])
		if not printed.is_empty():
			lines.append("%-6s %s" % [row.title, GAP.join(printed)])

	# The sweep. Anything bound to a key that nobody thought to put in LAYOUT is
	# printed under its own name rather than quietly left off - which is the
	# whole reason this is generated and not written out.
	var missed: PackedStringArray = []
	for action in InputMap.get_actions():
		if covered.has(action) or action in PAD_ONLY:
			continue
		if str(action).begins_with("ui_"):
			continue # Godot's own menu actions, which are not this game's controls
		var keys := _keys_for(action)
		if keys.is_empty():
			continue
		missed.append("%s  %s" % [" / ".join(keys), str(action).replace("_", " ")])
	if not missed.is_empty():
		lines.append("%-6s %s" % ["ALSO", GAP.join(missed)])

	return "\n".join(lines)


## Every key and mouse button bound to an action, printed the way it is written
## on the key.
func _keys_for(action: StringName) -> PackedStringArray:
	var found: PackedStringArray = []
	for event in InputMap.action_get_events(action):
		var printed := _name_of(event)
		if not printed.is_empty() and not printed in found:
			found.append(printed)
	return found


## What one binding is called. Joypad events answer "", so they fall out of the
## legend: this is the keyboard list, and a controller face button has no name
## worth printing next to a key.
func _name_of(event: InputEvent) -> String:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
		return "MOUSE %d" % button.button_index

	var key := event as InputEventKey
	if key == null:
		return ""

	# Bindings in this project are physical: W is wherever W sits on this
	# keyboard, which is the right call for movement and the wrong thing to
	# print, because a physical code is a position rather than a letter. Asking
	# the display server what is actually printed on that key is what makes the
	# legend right on a layout that is not the one it was authored on.
	var code := key.keycode
	if code == KEY_NONE and key.physical_keycode != KEY_NONE:
		code = key.physical_keycode
		# Headless has no keyboard to ask, and asking anyway is an error per
		# binding per launch - which is every gameplay test in tools/ printing
		# thirty stack traces before it does anything. The physical code is a
		# US label already, so the fallback is the right answer there anyway.
		#
		# A browser has a keyboard and still cannot answer: the web display
		# server does not implement the question. Same error, same once per
		# binding, and there are forty-nine bindings - so a player who opens the
		# console on the web build sees forty-nine red lines before the menu has
		# finished drawing. Skipped there for the same reason and with the same
		# fallback.
		if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
			var mapped := DisplayServer.keyboard_get_keycode_from_physical(
				key.physical_keycode)
			if mapped != KEY_NONE:
				code = mapped
	if code == KEY_NONE:
		return ""
	return OS.get_keycode_string(code)
