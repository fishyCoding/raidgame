@tool
extends Node

## Editor-only convenience: makes the level editable.
##
## Two things about this game are deliberately hostile to laying out geometry.
## The ambient tint drops everything to near-black so that the vision light
## means something, and the player sits in the middle of the scene with a camera
## and a light attached, on top of whatever you are trying to click.
##
## Both are switched off while editing and switched straight back on when the
## game runs. The runtime pass is not optional: if the scene is saved while the
## editor has them hidden, the .tscn stores that, and only this bringing them
## back keeps the game looking the way it should.

## The darkness. Hidden in the editor so the level is lit flat.
@export var ambient_path := NodePath("../Ambient")
## The player, with its camera and vision light. Hidden in the editor so it
## cannot be clicked instead of the thing behind it.
@export var player_path := NodePath("../Player")
## The lit air plane, which reads as a grey sheet over everything while editing.
@export var air_path := NodePath("../Air")


func _ready() -> void:
	_apply()
	# Nothing to poll at runtime; in the editor, keep it applied through undo,
	# scene reloads and anything else that puts the nodes back.
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var editing := Engine.is_editor_hint()
	for path in [ambient_path, player_path, air_path]:
		var node := get_node_or_null(path) as CanvasItem
		if node and node.visible == editing:
			node.visible = not editing
