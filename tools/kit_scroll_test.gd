extends SceneTree

## The kit menu, driven by a thumb.
##
##   godot --headless --path . --script res://tools/kit_scroll_test.gd
##
## Scrolling it on a phone did nothing at all, and every touch bought whatever
## it landed on, because the screen only ever read the mouse Godot emulates from
## the first touch - which arrives on press, before a drag exists to notice.
##
## Touches go in with root.push_input(event, true). Input.parse_input_event()
## applies the screen-to-viewport transform, and a headless window is 64 px
## against a 1280 px viewport, so a touch aimed at the shelf lands off the map.

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	for i in 4:
		await process_frame

	var shop: Control = lobby._shop
	# Pinned to the design viewport. Headless gives the root whatever size it
	# likes, and a shelf tall enough to hold every gun at once has nothing to
	# scroll - the test would pass by having no work to do.
	shop.set_anchors_preset(Control.PRESET_TOP_LEFT)
	shop.position = Vector2.ZERO
	shop.size = Vector2(1280, 720)
	# Pretend to be a phone: the emulated mouse is ignored and touches drive.
	shop._mouse_is_an_echo = true
	await process_frame

	print("-- open the primary shelf --")
	# Tapped rather than set, so the tap path is what puts us here.
	var slot := _region(shop, "primary")
	_tap(shop, slot.get_center())
	await process_frame
	await process_frame
	print("  open=%s  scroll_max=%.0f  shelf=%s" % [
			shop._open.get("id", "NONE"), shop._scroll_max, str(shop._shelf)])
	_check("a tap opens the slot it landed on", shop._open.get("id", "") == "primary")
	_check("the shelf has somewhere to scroll to", shop._scroll_max > 0.0)

	print("\n-- drag the shelf --")
	var spent: int = shop.credits
	var from: Vector2 = shop._shelf.get_center()
	var before: float = shop._scroll
	_drag(shop, from, Vector2(0, -120))
	await process_frame
	print("  scroll %.0f -> %.0f, credits %d -> %d" % [
			before, shop._scroll, spent, shop.credits])
	_check("dragging up moves the shelf down the list", shop._scroll > before + 50.0)
	_check("and buys nothing on the way", shop.credits == spent)

	print("\n-- drag it back --")
	before = shop._scroll
	_drag(shop, from, Vector2(0, 400))
	await process_frame
	print("  scroll %.0f -> %.0f" % [before, shop._scroll])
	_check("dragging down comes back", shop._scroll < before)
	_check("and stops at the top", shop._scroll >= 0.0)

	print("\n-- a tap on the shelf still buys --")
	spent = shop.credits
	var card := _region(shop, "buy")
	_tap(shop, card.get_center())
	await process_frame
	print("  credits %d -> %d   (%s)" % [spent, shop.credits, shop._message])
	_check("a card that was tapped, not dragged, is bought", shop.credits < spent)

	print("\n-- the wheel still works for a mouse --")
	shop._open = {}
	_tap(shop, _region(shop, "primary").get_center())
	await process_frame
	await process_frame
	# Back to a machine with no touchscreen, after the touches that got us here.
	shop._mouse_is_an_echo = false
	shop._saw_touch = false
	before = shop._scroll
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = shop._shelf.get_center()
	root.push_input(wheel, true)
	await process_frame
	print("  scroll %.0f -> %.0f" % [before, shop._scroll])
	_check("a wheel notch still moves the shelf", shop._scroll > before)

	if _failures > 0:
		print("\nkit_scroll | %d FAILED" % _failures)
		quit(1)
		return
	print("\nkit_scroll | PASS")
	quit()


## The first drawn region of a kind, or the slot with that id.
func _region(shop: Control, id: String) -> Rect2:
	for region in shop._regions:
		if region.id == id or region.kind == id:
			return region.rect
	_failures += 1
	print("  FAIL no region %s was drawn" % id)
	return Rect2(Vector2.ZERO, Vector2.ONE)


func _tap(shop: Control, at: Vector2) -> void:
	var where: Vector2 = shop.get_global_transform() * at
	_touch(where, true)
	_touch(where, false)


func _drag(shop: Control, from: Vector2, by: Vector2) -> void:
	var start: Vector2 = shop.get_global_transform() * from
	_touch(start, true)
	var steps := 6
	var last := start
	for i in steps:
		var at := start + by * (float(i + 1) / steps)
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = at
		drag.relative = at - last
		last = at
		root.push_input(drag, true)
	_touch(last, false)


func _touch(at: Vector2, down: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = down
	root.push_input(touch, true)


func _check(what: String, passed: bool) -> void:
	if passed:
		print("  ok   %s" % what)
		return
	_failures += 1
	print("  FAIL %s" % what)
