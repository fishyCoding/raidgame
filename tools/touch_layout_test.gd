extends SceneTree

## Every touch control has to be on the screen and reachable, on the screens the
## game will actually be held in.
##
##   godot --headless --path . --script res://tools/touch_layout_test.gd
##
## Checked by geometry rather than by eye, at several aspect ratios, because a
## layout tuned at 16:9 on a desktop is not the layout a 19.5:9 phone draws - and
## a button that has slid under the aim stick or off the edge is not a button.
##
## The sticks are the hazard: they sit in the bottom corners and are the largest
## things on the screen, so anything drifting into their reach becomes a control
## that sometimes moves you instead.

## Width, height, and what is being held. Design units, after Godot's stretch.
const SCREENS := [
	[1280.0, 720.0, "16:9 desktop / iPad-ish"],
	[1560.0, 720.0, "19.5:9 iPhone landscape"],
	[1624.0, 750.0, "iPhone Pro Max landscape"],
	[1280.0, 800.0, "16:10"],
	[1024.0, 768.0, "4:3 old iPad"],
]

var _ok := true
var _pad: Control


func _initialize() -> void:
	_run()


func _run() -> void:
	var input: Node = root.get_node("PlayerInput")
	input.control_scheme = input.Controls.TOUCH

	# The pad on its own - no level needed to measure a layout, and loading one
	# would only tie this to a spawn point.
	_pad = Control.new()
	_pad.set_script(load("res://scripts/touch_controls.gd"))
	root.add_child(_pad)
	await physics_frame

	# Every screen in every state the pad has. The contextual controls - the LOOT
	# button that appears over a body, the UP/DOWN/LET GO that replace the left
	# hand on a cable - are exactly the ones nobody looks at while moving things
	# around, and exactly the ones that can end up under a thumb already busy.
	for state in [["normal", false, false], ["over a body", true, false],
			["on a cable", false, true], ["a body, on a cable", true, true]]:
		_pad._looting = state[1]
		_pad._riding = state[2]
		for screen in SCREENS:
			_pad.size = Vector2(screen[0], screen[1])
			await physics_frame
			_say("")
			_say("-- %s, %s (%.0f x %.0f)" % [state[0], screen[2], screen[0], screen[1]])
			_measure(Vector2(screen[0], screen[1]))
	_pad._looting = false
	_pad._riding = false

	input.control_scheme = input.Controls.AUTO
	_say("")
	_say("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _measure(screen: Vector2) -> void:
	var controls: Array = []
	for button in _pad._button_rects():
		controls.append({
			"name": String(button.action),
			"rect": Rect2(button.at - Vector2.ONE * button.r, Vector2.ONE * button.r * 2.0),
		})
	for pill in _pad._pill_rects():
		controls.append({"name": String(pill.action), "rect": pill.rect})

	# Only one stick now, and none at all while riding: the aim stick is gone and
	# the move stick is replaced by the cable controls.
	var sticks: Array = []
	if not _pad._riding:
		sticks.append({"name": "move stick", "rect": _ring(_pad._move_home())})

	# --- on the screen at all -------------------------------------------------
	var off: Array[String] = []
	for control in controls + sticks:
		var rect: Rect2 = control.rect
		if rect.position.x < 0.0 or rect.position.y < 0.0 \
				or rect.end.x > screen.x or rect.end.y > screen.y:
			off.append(control.name)
	_check("everything is on screen", off.is_empty(), " ".join(off))

	# --- and not on top of each other ----------------------------------------
	var clashes: Array[String] = []
	var all: Array = controls + sticks
	for i in all.size():
		for j in range(i + 1, all.size()):
			if (all[i].rect as Rect2).intersects(all[j].rect as Rect2):
				clashes.append("%s/%s" % [all[i].name, all[j].name])
	_check("nothing overlaps", clashes.is_empty(), " ".join(clashes))

	# --- and a thumb aiming for a button cannot grab a stick instead ---------
	#
	# The grab radius is wider than the drawn ring, which is what makes the
	# sticks usable - and what makes this worth checking separately.
	var grabbed: Array[String] = []
	var reach: float = _pad.STICK_RADIUS * _pad.STICK_GRAB
	for control in controls:
		var centre: Vector2 = (control.rect as Rect2).get_center()
		# One stick, not two. This asked about a second one on the aiming side
		# that no longer exists, so the call errored and took the whole check
		# with it - it has been quietly not running, while still reporting PASS.
		if centre.distance_to(_pad._move_home()) <= reach:
			grabbed.append(control.name)
	_check("no button sits inside a stick's grab", grabbed.is_empty(), " ".join(grabbed))


func _ring(centre: Vector2) -> Rect2:
	var r: float = _pad.STICK_RADIUS
	return Rect2(centre - Vector2.ONE * r, Vector2.ONE * r * 2.0)


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_ok = false
	_say("   %s %s%s" % ["ok  " if ok else "FAIL", what,
		"" if detail.is_empty() else "  -> " + detail])


func _say(text: String) -> void:
	print("layout | %s" % text)
