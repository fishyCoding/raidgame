class_name DashTrail
extends Node2D

## The streak a dash leaves behind you, and nobody else.
##
## A dash is a tenth of a second long and covers about a hundred and twenty
## pixels, which is fast enough that the body is simply somewhere else by the
## time you have registered it moving. Without something left in the air behind
## it there is nothing to read the move off at all: you press, the screen jumps,
## and whether you went where you meant to is a question you answer by looking
## around afterwards. The trail is the answer, and it is worth drawing for that
## alone.
##
## It is drawn for its owner and for nobody else, which is the whole reason it
## lives on the player's Overlay layer rather than out in the world. That layer
## is switched off on every machine but the owner's - see Player._ready, the same
## line that turns off everyone else's camera, crosshair and torch - so a trail
## can never be the thing that tells a rival where somebody went.
##
## Which matters more here than it does for a crosshair. A dash is a commitment:
## you have spent one of two charges, you cannot steer, and for a tenth of a
## second you cannot shoot. A streak hanging in the air afterwards would mark the
## exact line you took and the exact moment you took it, and it would still be
## there when you arrived - so the one move in the game that is supposed to break
## contact would be the one that draws a map to where you went. It would be worse
## than the ropes were, because a rope at least costs the person reading it a
## look at the right patch of wall; this would be painted over your own body.
##
## Nothing about it crosses the wire, and nothing needs to. Marks are laid from
## the owner's own physics tick, which no replica runs, so a copy of somebody
## else's body has an empty trail on top of a hidden layer.

## How long a mark stays in the air after it is laid. Long enough to still be
## there when the dash finishes - the whole dash is 0.14s, so the head of the
## trail outlives the move by about twice its own length - and short enough that
## it is gone before you have done anything else.
const HOLD := 0.30

## The soft body of the streak, and the hard line up its middle. Two passes over
## the same marks, the way every other drawn thing in this game is done: the
## wide one is the smear, the narrow one is what your eye actually lands on.
const SMEAR := Color(1.0, 0.68, 0.28)
const CORE := Color(1.0, 0.87, 0.66)

## How much of its height the tail end keeps. The band narrows as it goes back,
## which is most of what makes it read as speed rather than as a wall - a streak
## of even height is a shape somebody left behind, a tapering one is a shape that
## was moving when it did.
const TAIL_SCALE := 0.55

## Where the body was, and how much of it there was, oldest first. Each mark
## keeps its own remaining life rather than a timestamp, so ageing is a
## subtraction and there is no clock to agree with.
var _marks: Array[Dictionary] = []


## Records where the body is this frame. Called once per physics tick for as
## long as a dash is in flight, by the owner and only by the owner.
func lay(at: Vector2, half: Vector2) -> void:
	_marks.append({"at": at, "half": half, "life": HOLD})
	queue_redraw()


## Wipes it without letting it fade. For the ends a fade would be wrong: coming
## out of a match, or dying mid-dash, the streak is not something that should
## outlive the thing that made it.
func clear() -> void:
	if _marks.is_empty():
		return
	_marks.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _marks.is_empty():
		return
	# Oldest first, so the expired ones are always a prefix and dropping them is
	# a walk from the front rather than a search.
	var spent := 0
	for mark in _marks:
		mark.life -= delta
		if mark.life <= 0.0:
			spent += 1
	if spent > 0:
		_marks = _marks.slice(spent)
	queue_redraw()


## One band, stretched between the marks, with a bright line up the middle of it.
##
## Drawn as the gaps between marks rather than as the marks themselves. Bodies
## stamped one per frame was the obvious way to do it and looked like a picket
## fence: eight upright bars fifteen pixels apart, each with its own hard edge,
## so the eye counted them instead of reading a move. Filling between them gives
## one continuous shape that tapers and dims toward the tail, which is what a
## thing going nine hundred pixels a second leaves behind.
func _draw() -> void:
	if _marks.size() < 2:
		return
	for i in range(1, _marks.size()):
		var back: Dictionary = _marks[i - 1]
		var front: Dictionary = _marks[i]
		var back_glow := _glow(back)
		var front_glow := _glow(front)
		var back_top: float = back.half.y * lerpf(TAIL_SCALE, 1.0, back_glow)
		var front_top: float = front.half.y * lerpf(TAIL_SCALE, 1.0, front_glow)
		var lit := (back_glow + front_glow) * 0.5
		draw_colored_polygon(PackedVector2Array([
			back.at - Vector2(0.0, back_top),
			front.at - Vector2(0.0, front_top),
			front.at + Vector2(0.0, front_top),
			back.at + Vector2(0.0, back_top),
		]), Color(SMEAR, 0.20 * lit))
		# The line your eye actually follows. Along the path rather than across
		# it: this is the one mark on screen that says which way you went.
		draw_line(back.at, front.at, Color(CORE, 0.34 * lit), 2.0)


## How strongly a mark is still drawn, 0 to 1.
##
## Squared, so the tail is gone well before the head has dimmed. Faded linearly
## over eight marks the oldest is still clearly there, and a streak with a hard
## end on it looks like a wall rather than a trail.
func _glow(mark: Dictionary) -> float:
	var life := clampf(float(mark.life) / HOLD, 0.0, 1.0)
	return life * life
