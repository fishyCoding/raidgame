extends Control

## The corner map: always up, unlike map_screen.gd's full-screen one, and
## much smaller. Shows the same geometry, plus what map_screen does not -
## your squadmate's position and every live ping.
##
## Deliberately a separate node from MapScreen rather than a second mode of
## it: MapScreen's visibility is read by PlayerInput.wants_cursor() to decide
## whether the mouse is free, and a minimap that is always visible would free
## the cursor permanently if it shared that flag. This one never joins the
## "map_screen" group and never sets `visible` to mean anything.

const BG := Color(0.04, 0.05, 0.07, 0.82)
const BORDER := Color(0.4, 0.46, 0.55, 0.6)
const SOLID := Color(0.42, 0.48, 0.58)
const CATWALK := Color(0.35, 0.46, 0.55, 0.85)
const EXIT := Color(0.45, 0.9, 0.62)
const YOU := Color(0.95, 0.95, 1.0)
const TEAMMATE := Color(0.55, 0.78, 0.98)
const PING := Color(0.98, 0.82, 0.32)
const REVEAL := Color(0.55, 0.85, 0.95)
## The quarry's objective chain. Same gold hud.gd's OBJECTIVE and
## central_objective.gd's unlocked tint already use - one colour for the
## whole thing, wherever it is drawn.
const OBJECTIVE := Color(0.95, 0.78, 0.25)
const OBJECTIVE_LOCKED := Color(0.42, 0.46, 0.52)

## Where it sits and how big it is - top-right, clear of the gadget strip and
## the headcount dial, which both live centred or bottom.
const BOX := Rect2(Vector2(20.0, 20.0), Vector2(200.0, 150.0))
const MARGIN := 14.0

var _player: Node2D
var _blocks: Array[Node2D] = []
var _bounds := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = Net.local_player
	Net.player_spawned.connect(func(body: Node) -> void:
		if body == Net.local_player:
			_player = body)
	var scene := get_tree().current_scene
	if scene:
		_collect(scene)
	_measure()


## Same test map_screen.gd uses to find the level's blocks - see its own
## comment for why "one_way" is what marks a node as one.
func _collect(node: Node) -> void:
	for child in node.get_children():
		var block := child as Node2D
		if block != null and typeof(block.get(&"size")) == TYPE_VECTOR2 \
				and typeof(block.get(&"one_way")) == TYPE_BOOL:
			_blocks.append(block)
		elif child.get_child_count() > 0:
			_collect(child)


func _measure() -> void:
	var measured := false
	for block in _blocks:
		for corner in _quad(block):
			_bounds = Rect2(corner, Vector2.ZERO) if not measured else _bounds.expand(corner)
			measured = true
	if measured:
		_bounds = _bounds.grow(120.0)


func _quad(block: Node2D) -> PackedVector2Array:
	var half: Vector2 = (block.get(&"size") as Vector2) * 0.5
	var at := block.global_transform
	return PackedVector2Array([
		at * Vector2(-half.x, -half.y), at * Vector2(half.x, -half.y),
		at * Vector2(half.x, half.y), at * Vector2(-half.x, half.y),
	])


func _to_map(at: Vector2) -> Vector2:
	if _bounds.size == Vector2.ZERO:
		return BOX.get_center()
	var frame := BOX.grow(-MARGIN)
	var scale := minf(frame.size.x / _bounds.size.x, frame.size.y / _bounds.size.y)
	var offset := frame.position + frame.size * 0.5 - _bounds.size * scale * 0.5
	return offset + (at - _bounds.position) * scale


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _player == null or _bounds.size == Vector2.ZERO:
		return
	# The full map already covers this corner - no point drawing under it.
	var full_map := get_tree().get_first_node_in_group(&"map_screen")
	if full_map and full_map.visible:
		return

	draw_rect(BOX, BG)
	draw_rect(BOX, BORDER, false, 1.5)
	_draw_geometry()
	_draw_exits()
	_draw_objectives()
	_draw_teammate()
	_draw_pings()

	var here := _to_map((_player as Node2D).global_position)
	draw_circle(here, 3.5, YOU)
	draw_arc(here, 6.0, 0.0, TAU, 16, YOU, 1.2, true)


func _draw_geometry() -> void:
	for block in _blocks:
		var outline := PackedVector2Array()
		for corner in _quad(block):
			outline.append(_to_map(corner))
		var one_way: Variant = block.get(&"one_way")
		var solid: bool = not (typeof(one_way) == TYPE_BOOL and one_way)
		draw_colored_polygon(outline, SOLID if solid else CATWALK)


func _draw_exits() -> void:
	for node in get_tree().get_nodes_in_group(&"spawn"):
		var point := node as SpawnPoint
		if point == null or not point.is_extraction:
			continue
		draw_circle(_to_map(point.global_position), 3.0, EXIT)


## The quarry's three subobjectives and the central object, all drawn
## unconditionally - the same "map briefing knowledge, not a stealth reveal"
## treatment an extraction point already gets above. The object itself is the
## one the user asked to be visible to everyone regardless of concealment;
## the three sites are drawn alongside it for the same reason a raid's exits
## already are - map knowledge, not a thing you have to have seen to know
## about.
func _draw_objectives() -> void:
	for node in get_tree().get_nodes_in_group(&"objective"):
		var point := node as Node2D
		if point == null:
			continue
		var captured: Variant = point.get(&"captured")
		draw_circle(_to_map(point.global_position), 3.0,
			EXIT if typeof(captured) == TYPE_BOOL and captured else OBJECTIVE)

	var centre := get_tree().get_first_node_in_group(&"central_objective") as Node2D
	if centre == null:
		return
	var at := _to_map(centre.global_position)
	var lit := Net.objective_unlocked
	draw_arc(at, 5.0, 0.0, TAU, 16, OBJECTIVE if lit else OBJECTIVE_LOCKED, 2.0, true)
	draw_circle(at, 2.5, OBJECTIVE if lit else OBJECTIVE_LOCKED)


## Your squadmate's own dot, tinted the same way the HUD's own health widget
## is - see hud.gd's TEAMMATE colour. Dimmed while they are down or dead
## rather than hidden: knowing roughly where the body is matters just as
## much then.
func _draw_teammate() -> void:
	var mate := Net.my_teammate()
	if mate == null or not is_instance_valid(mate):
		return
	var alive: Variant = mate.get(&"is_alive")
	var downed: Variant = mate.get(&"is_downed")
	var faded: bool = (typeof(alive) == TYPE_BOOL and not alive) \
		or (typeof(downed) == TYPE_BOOL and downed)
	var at := _to_map((mate as Node2D).global_position)
	draw_circle(at, 3.5, Color(TEAMMATE, 0.4 if faded else 1.0))
	draw_arc(at, 6.0, 0.0, TAU, 16, Color(TEAMMATE, 0.4 if faded else 1.0), 1.2, true)


## Everything worth marking that is not a person standing where you can see
## them: recon-bow/rail-bomb reveals (never your own squadmate - both call
## sites filter that out before the meta is ever set) and manual pings.
func _draw_pings() -> void:
	for node in get_tree().get_nodes_in_group(&"hideable"):
		var target := node as Node2D
		if target == null:
			continue
		var until: Variant = target.get_meta(&"revealed_until", 0.0)
		if typeof(until) != TYPE_FLOAT or until <= Time.get_ticks_msec() * 0.001:
			continue
		draw_circle(_to_map(target.global_position), 2.6, REVEAL)

	var pings: Variant = _player.get(&"pings")
	if typeof(pings) != TYPE_ARRAY:
		return
	for ping in pings:
		var at: Vector2 = (ping as Dictionary).get("at", Vector2.INF)
		if at.is_finite():
			var p := _to_map(at)
			draw_arc(p, 4.0, 0.0, TAU, 12, PING, 1.5, true)
			draw_line(p - Vector2(5.0, 0.0), p + Vector2(5.0, 0.0), PING, 1.0, true)
			draw_line(p - Vector2(0.0, 5.0), p + Vector2(0.0, 5.0), PING, 1.0, true)
