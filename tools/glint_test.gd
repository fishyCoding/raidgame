extends SceneTree

## Checks the sniper glint's three conditions, which are easy to get backwards.
##
## The geometry lives in Player.glint_shows precisely so it can be called here
## with plain numbers - no bodies, no session, no camera. What is being defended
## is that the mark is *mutual*: a scope pointed at you shows nothing unless you
## happen to be looking back, and looking at a sniper who is aiming somewhere
## else shows nothing either. Get either sign wrong and the mechanic still looks
## like it works from one side of the map.
##
## Loaded rather than named, and the same trap as tools/damage_model_test.gd:
## naming `Player` from a --script tool compiles player.gd before the autoloads
## exist, it fails on "Identifier not found: Net", and every call on the result
## quietly returns null. A null read as a bool is `false`, so a test written the
## obvious way reports that nine of its nine cases show no glint and calls that
## a pass. Hence both the load below and the guard in _want.

const MIN_RANGE := 620.0
const AIM_CONE := 0.10
const LOOK_CONE := 0.38

var _failures: Array[String] = []
## An instance of player.gd, because statics are reached through one.
var _player: Node = null


func _init() -> void:
	# One frame, so the autoloads player.gd names are on the root before it is
	# compiled. See the note above.
	await process_frame
	var script: GDScript = load("res://scripts/player.gd")
	if script == null or not script.has_method(&"glint_shows"):
		print("FAIL - player.gd did not compile, or has no glint_shows on it")
		quit(1)
		return
	_player = script.new()

	var watcher := Vector2.ZERO
	var sniper := Vector2(1400.0, 0.0)
	# Facing each other down a flat line: he aims left (PI), you aim right (0).
	var at_you := PI
	var at_him := 0.0

	_want("both looking at each other, across the map", true,
		sniper, at_you, watcher, at_him)
	_want("he has you, you are looking away", false,
		sniper, at_you, watcher, PI)
	_want("you have him, he is aiming somewhere else", false,
		sniper, PI * 0.5, watcher, at_him)
	_want("neither of you is looking", false,
		sniper, 0.0, watcher, PI)
	# Same geometry, close enough to see him with your eyes.
	_want("close up there is nothing to catch", false,
		watcher + Vector2(MIN_RANGE - 20.0, 0.0), at_you, watcher, at_him)

	# The cones, at their edges. His is the tight one on purpose.
	_want("just inside his cone", true,
		sniper, at_you + AIM_CONE * 0.9, watcher, at_him)
	_want("just outside his cone", false,
		sniper, at_you + AIM_CONE * 1.1, watcher, at_him)
	_want("your cone is the generous one", true,
		sniper, at_you, watcher, at_him + AIM_CONE * 2.0)
	_want("but not unlimited", false,
		sniper, at_you, watcher, at_him + LOOK_CONE * 1.1)

	_player.free()

	if _failures.is_empty():
		print("OK - the glint is mutual")
	else:
		for line in _failures:
			print("FAIL - %s" % line)
		print("FAILED %d check(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _want(what: String, expected: bool, sniper_at: Vector2, sniper_aim: float,
		watcher_at: Vector2, watcher_aim: float) -> void:
	var answer: Variant = _player.glint_shows(sniper_at, sniper_aim, watcher_at,
		watcher_aim, MIN_RANGE, AIM_CONE, LOOK_CONE)
	# A call that did not happen comes back null, and null tests equal to false
	# for the half of these cases that expect false. Refuse it outright rather
	# than let it pass for the wrong reason.
	if typeof(answer) != TYPE_BOOL:
		_failures.append("%s: glint_shows did not answer (got %s)" % [what, answer])
		print("  FAIL %-46s no answer" % what)
		return
	var got: bool = answer
	if got == expected:
		print("  ok   %-46s %s" % [what, "glint" if got else "nothing"])
	else:
		_failures.append("%s: got %s, wanted %s" % [what, got, expected])
		print("  FAIL %-46s %s" % [what, got])
