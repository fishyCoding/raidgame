extends SceneTree

## Gives the input map a gamepad, so the game can be driven without a keyboard.
##
##   godot --headless --path . --script res://tools/add_joypad_bindings.gd
##
## Run once; it is idempotent and says what it did. Editing project.godot by hand
## is not really an option - input events are serialised as inline `Object(...)`
## blobs, and one wrong field is a corrupt input map.
##
## This exists for Xogot. Testing on an iPhone means the Xogot app's iOS Virtual
## Controller, which is Apple's GCVirtualController: two thumbsticks and A/B/X/Y,
## delivered as a **gamepad**, not as touches. Every action in this project was
## bound to keys and mouse buttons only, so the on-screen controller moved
## nothing at all. See [[mobile-target]].
##
## Four buttons does not cover a game with sixteen actions. The ones chosen are
## the ones that make a build worth deploying: walk, jump, shoot, grab, and get
## a hook out. Reload, medkits, gadgets and the inventory stay on the keyboard
## until there is a real touch HUD.

const BUTTONS := {
	"jump": JOY_BUTTON_A,
	"interact": JOY_BUTTON_B,
	"fire": JOY_BUTTON_X,
	"grapple": JOY_BUTTON_Y,
}

## action -> [axis, direction]. The left stick walks; down on it is the
## drop-through-a-platform input, which pairs with jump exactly as S + SPACE does.
const AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

## The right stick, which needs four actions that did not exist - the whole input
## map was keys and mouse buttons. Read live by PlayerInput.get_stick_aim rather
## than polled as presses: aiming is a direction, and an action can only say
## pressed or not.
const AIM_AXES := {
	"aim_left": [JOY_AXIS_RIGHT_X, -1.0],
	"aim_right": [JOY_AXIS_RIGHT_X, 1.0],
	"aim_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"aim_down": [JOY_AXIS_RIGHT_Y, 1.0],
}


func _initialize() -> void:
	var added := 0
	var already := 0

	for action in BUTTONS:
		var event := InputEventJoypadButton.new()
		event.button_index = BUTTONS[action]
		if _add(action, event):
			added += 1
			print("joypad | %s -> button %d" % [action, BUTTONS[action]])
		else:
			already += 1

	for action in AXES:
		var event := InputEventJoypadMotion.new()
		event.axis = AXES[action][0]
		event.axis_value = AXES[action][1]
		if _add(action, event):
			added += 1
			print("joypad | %s -> axis %d %+.0f" % [action, AXES[action][0], AXES[action][1]])
		else:
			already += 1

	for action in AIM_AXES:
		var event := InputEventJoypadMotion.new()
		event.axis = AIM_AXES[action][0]
		event.axis_value = AIM_AXES[action][1]
		if _add(action, event, true):
			added += 1
			print("joypad | %s -> axis %d %+.0f (new action)" % [
				action, AIM_AXES[action][0], AIM_AXES[action][1]])
		else:
			already += 1

	if added > 0:
		var err := ProjectSettings.save()
		print("joypad | saved project.godot (%s)" % ("ok" if err == OK else error_string(err)))
	print("joypad | %d added, %d already there" % [added, already])
	quit(0)


## Appends an event to an action, unless something equivalent is already bound.
## Compared by kind and index rather than by object, because a second run builds
## new event instances that are equal in every way that matters and identical in
## none.
func _add(action: String, event: InputEvent, create := false) -> bool:
	var key := "input/%s" % action
	if not ProjectSettings.has_setting(key):
		if not create:
			push_warning("no such action: %s" % action)
			return false
		# The same shape the editor writes. The deadzone here is the input map's
		# own, below what get_stick_aim applies - one gate is enough, and it is
		# better placed where the vector can be judged as a whole.
		ProjectSettings.set_setting(key, {"deadzone": 0.2, "events": []})

	var config: Dictionary = ProjectSettings.get_setting(key)
	var events: Array = config.get("events", [])
	for existing in events:
		if existing is InputEventJoypadButton and event is InputEventJoypadButton:
			if existing.button_index == event.button_index:
				return false
		elif existing is InputEventJoypadMotion and event is InputEventJoypadMotion:
			if existing.axis == event.axis and signf(existing.axis_value) == signf(event.axis_value):
				return false

	events.append(event)
	config["events"] = events
	ProjectSettings.set_setting(key, config)
	return true
