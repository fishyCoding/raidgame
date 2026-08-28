class_name DashTrail
extends Node2D

## The streak a dash leaves behind it.
##
## A dash is a tenth of a second long and covers about a hundred and twenty
## pixels, which is fast enough that a body is simply somewhere else by the time
## you have registered it moving. Without something left in the air behind it
## there is nothing to read the move off at all - your own or anybody else's.
##
## Everybody sees it, and the dark takes it away. It is in the "shadowed" group,
## which is the group for scenery that only exists while somebody has line of
## sight on it - the same group the grapple ropes are in - so a streak laid down
## in a room you cannot see into is not drawn on your screen. Cover hides a dash
## exactly as completely as it hides the person who took it.
##
## Not in "hideable", which is a different promise: that group means "a body the
## recon arrow can paint and pin a marker to", and a diamond hovering over the
## place somebody dashed four seconds ago is not what that gadget is for.
##
## A sibling of the body rather than a child of it. Children of a hidden node are
## hidden with it, and a replica's body is hidden the moment it loses line of
## sight - so parented to the player, a streak left out in the open would vanish
## the instant its owner reached cover, which is the one moment it is worth
## anything. It is asked about separately, from the marks themselves.
##
## Every machine builds its own. Nothing here crosses the wire: the marks are
## laid from `dash_left` on the body, which is replicated, so the same streak is
## drawn everywhere off the same clock without a message of its own.

## How long a mark stays in the air after it is laid. Long enough to still be
## there when the dash finishes - the whole dash is 0.14s, so the head of the
## trail outlives the move by about twice its own length - and short enough that
## it is gone before its owner has done anything else.
const HOLD := 0.30

## The soft body of the streak, and the hard line along it.
##
## Carried at nearly twice the alpha it was drawn at while it lived on the
## player's own overlay. That layer sits above the world's darkness and this one
## is inside it, so the same colours came back a dull brown once the streak was
## something the level could shade.
const SMEAR := Color(1.0, 0.68, 0.28)
const CORE := Color(1.0, 0.87, 0.66)

## How much of its height the tail end keeps. The band narrows as it goes back,
## which is most of what makes it read as speed rather than as a wall - a streak
## of even height is a shape somebody left behind, a tapering one is a shape that
## was moving when it did.
const TAIL_SCALE := 0.55

## The body this belongs to. Set by Player before this is put in the tree.
var body: Node2D

## Where the body was, and how much of it there was, oldest first. Each mark
## keeps its own remaining life rather than a timestamp, so ageing is a
## subtraction and there is no clock to agree with.
var _marks: Array[Dictionary] = []
## The body's position last frame, kept whether it is dashing or not - it is
## what the first mark of a dash is laid at. See _physics_process.
var _was_at := Vector2.INF
var _was_dashing := false


func _ready() -> void:
	# After the bodies have moved this frame and before VisionSystem (400) works
	# out what can be seen, so a mark laid this frame is tested this frame rather
	# than spending its first frame drawn through a wall.
	process_physics_priority = 300
	add_to_group(&"shadowed")
	# Starts hidden. The vision pass turns it on the moment there is anything to
	# see, and an empty trail that begins life visible is a blank node the dark
	# has to be told about rather than one it has never lit.
	visible = false


## Watches the body and lays a mark for every frame of a dash.
##
## Driven from here rather than called from Player._update_dash, because that
## function is a tick only the owner runs. Read off `dash_left` instead, which
## every machine has, and the streak is laid the same way on all of them.
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(body):
		# The body has gone - blown up, extracted, disconnected. What is already
		# in the air is left to fade rather than cut, because it is a record of
		# something that happened rather than a part of the thing that did it.
		if _marks.is_empty():
			queue_free()
		return

	var dashing: bool = body.dash_left > 0.0
	if dashing:
		# The first mark of a dash goes where the body was *last* frame, not
		# where it is now. By the time a dash is visible here the body has
		# already taken a step of it, and a streak that starts fifteen pixels
		# along the move never quite reaches back to the place it left.
		if not _was_dashing and _was_at.is_finite():
			_lay(_was_at)
		_lay(body.global_position)
	_was_dashing = dashing
	_was_at = body.global_position


## Wipes it without letting it fade. For the ends a fade would be wrong: dying
## mid-dash, the streak is not something that should outlive the move.
func clear() -> void:
	if _marks.is_empty():
		return
	_marks.clear()
	queue_redraw()


## Where to look for a streak, for line of sight: at every mark in it.
##
## The same protocol a grapple rope answers, and for the same reason. A trail is
## a hundred and twenty pixels of it: judged by its origin alone, one laid across
## a doorway would be thrown out whole because the far end of it is inside a
## wall. Any one mark being reachable is enough, so what you see is a streak the
## moment any part of it is in the open.
func sight_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for mark in _marks:
		points.append(mark.at)
	return points


func _lay(at: Vector2) -> void:
	var half: Vector2 = body.size * 0.5
	if body.has_method(&"dash_half"):
		half = body.dash_half()
	_marks.append({"at": at, "half": half, "life": HOLD})
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


## One band, stretched between the marks, with a bright line along it.
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
		var back_at: Vector2 = to_local(back.at)
		var front_at: Vector2 = to_local(front.at)
		draw_colored_polygon(PackedVector2Array([
			back_at - Vector2(0.0, back_top),
			front_at - Vector2(0.0, front_top),
			front_at + Vector2(0.0, front_top),
			back_at + Vector2(0.0, back_top),
		]), Color(SMEAR, 0.34 * lit))
		# The line your eye actually follows. Along the path rather than across
		# it: this is the one mark on screen that says which way somebody went.
		draw_line(back_at, front_at, Color(CORE, 0.62 * lit), 2.0)


## How strongly a mark is still drawn, 0 to 1.
##
## Squared, so the tail is gone well before the head has dimmed. Faded linearly
## over eight marks the oldest is still clearly there, and a streak with a hard
## end on it looks like a wall rather than a trail.
func _glow(mark: Dictionary) -> float:
	var life := clampf(float(mark.life) / HOLD, 0.0, 1.0)
	return life * life
