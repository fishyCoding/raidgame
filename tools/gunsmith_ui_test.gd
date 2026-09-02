extends SceneTree

## The workshop as a screen: the way in, the money, and the way back.
##
##   godot --headless --path . --script res://tools/gunsmith_ui_test.gd
##
## The arithmetic of a part is tools/gunsmith_test.gd. What is asserted here is
## everything around it - that MODIFY opens the thing, that a part is paid for
## out of the same pocket the guns came out of, that swapping one for another
## charges the difference rather than the whole price, and that taking one off
## gives the money back. A screen that quietly overcharges is the worst kind of
## bug in a game about deciding what you can afford.

const ATT := "res://resources/attachments/%s.tres"

var _ok := true


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	for i in 12:
		await process_frame

	var shop: Node = lobby._shop
	shop.credits = 16000
	# A rifle, bought the ordinary way.
	# The whole region dictionary, not a stub: the picker draws _open.label, and a
	# half-built one turns every redraw for the rest of the run into an error.
	shop._open = {"id": "primary", "list": "primary", "label": "PRIMARY"}
	shop._buy(shop.CATALOGUE["primary"][1])
	var rifle: Object = shop._inventory.primary
	_check(rifle != null and rifle.is_weapon(), "a rifle in the primary slot")

	# --- the way in -----------------------------------------------------------
	shop.queue_redraw()
	await process_frame
	var pill := Rect2()
	for region in shop._regions:
		if region.get("kind", "") == "smith":
			pill = region.rect
			break
	_check(pill.size.x > 0.0, "the kit screen draws a MODIFY button on a filled gun slot")
	shop._press(pill.get_center())
	await process_frame
	var smith: Node = shop._smith
	_check(smith != null and smith.visible, "pressing it opens the workshop")
	_check(not shop.visible, "and takes the kit screen away, so nothing behind can be clicked")
	_check(smith.is_in_group(&"gunsmith") and not smith.is_in_group(&"shop"),
		"in its own group - the raid finds the shop by asking for the first one")

	# --- the money ------------------------------------------------------------
	var dot: Resource = load(ATT % "red_dot")
	var four: Resource = load(ATT % "marksman_4x")
	var purse: int = shop.credits
	smith._fit(dot)
	_say("red dot at %d: %d -> %d" % [dot.price, purse, shop.credits])
	_check(shop.credits == purse - dot.price, "a part is paid for out of the shop's credits")
	_check(rifle.part_in(AttachmentData.Slot.OPTIC) == dot, "and ends up on the gun")

	purse = shop.credits
	smith._fit(four)
	_say("swapped for a 4x at %d: %d -> %d" % [four.price, purse, shop.credits])
	_check(shop.credits == purse - (four.price - dot.price),
		"swapping charges the difference, not the whole price again")
	_check(rifle.parts.size() == 1, "and there is still only one optic on it")

	purse = shop.credits
	smith._slot = AttachmentData.Slot.OPTIC
	smith._take_off()
	_say("taken off: %d -> %d" % [purse, shop.credits])
	_check(shop.credits == purse + four.price, "taking a part off refunds it in full")
	_check(rifle.part_in(AttachmentData.Slot.OPTIC) == null, "and it is off the gun")

	# --- and what it will not sell you ----------------------------------------
	shop.credits = 10
	smith._fit(four)
	_check(rifle.part_in(AttachmentData.Slot.OPTIC) == null,
		"a part you cannot afford is not fitted")
	_check(shop.credits == 10, "and costs nothing to be refused")
	_check(smith._message.contains("short"), "and says how short you are")
	shop.credits = 16000

	# --- and it works with a thumb -------------------------------------------
	#
	# The kit screen is on its way to a phone, and the workshop is a full screen
	# of small targets. A tap is not a click: it arrives as a press and a release
	# at the same point, and a screen that only listens for InputEventMouseButton
	# is one that does nothing at all on a phone while looking perfectly fine on a
	# desk.
	smith.open(shop, rifle)
	smith._slot = -1
	var optic := Rect2()
	for region in smith._regions:
		if region.get("kind", "") == "slot" and int(region.slot) == AttachmentData.Slot.OPTIC:
			optic = region.rect
			break
	_check(optic.size.x > 0.0, "the workshop draws a tappable optic slot")
	_tap(smith, optic.get_center())
	await process_frame
	_check(smith._slot == AttachmentData.Slot.OPTIC, "a thumb opens the slot it lands on")

	smith.queue_redraw()
	await process_frame
	var card := Rect2()
	for region in smith._regions:
		if region.get("kind", "") == "buy":
			card = region.rect
			break
	purse = shop.credits
	_tap(smith, card.get_center())
	await process_frame
	_check(shop.credits < purse, "and buying a part off the shelf works the same way")

	# --- the way back ---------------------------------------------------------
	smith._press(smith._back.get_center())
	await process_frame
	_check(not smith.visible and shop.visible, "BACK TO KIT closes it and brings the shop back")

	# --- and it is the gun you carry in ---------------------------------------
	smith.open(shop, rifle)
	smith._fit(load(ATT % "suppressor"))
	smith._press(smith._back.get_center())
	await process_frame
	var staged: Object = shop._inventory.primary
	_check(staged.weapon.suppressed,
		"the gun in the kit is the gun that was worked on - not a copy of it")
	_check(staged.to_wire().has("parts"), "and it takes its parts with it when it travels")

	print("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


## A thumb going down and coming up in the same place, which is what a tap is.
## Routed through the control's own handler rather than the viewport, so the test
## does not depend on where the window happens to be.
func _tap(screen: Control, at: Vector2) -> void:
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = pressed
		touch.position = at
		screen._gui_input(touch)


func _say(line: String) -> void:
	print("-- %s" % line)


func _check(pass_: bool, says: String) -> void:
	print("   %s  %s" % ["ok  " if pass_ else "FAIL", says])
	if not pass_:
		_ok = false
