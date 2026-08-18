class_name Lootable
extends Node2D

## A body on the floor with its kit still on it.
##
## Nothing is dropped when a guard dies - his inventory simply stops moving, and
## everything he was carrying is still where he left it: the gun in his hands,
## the spare in his pack, the rounds in his pockets. Looting is a transfer
## between two inventories, so what you get is exactly what he had.
##
## A body that has been picked clean stays on the floor as scenery. It stops
## offering a prompt, because there is nothing left to offer.

## The dead man's kit. Set by whoever spawned the body.
var inventory: Inventory
## What he looked like. Kept rather than only drawn with, because the host has to
## be able to describe this body to somebody who joins after it fell - see
## Net.request_character.
var tint := Color(0.5, 0.3, 0.25)
var body_size := Vector2(30, 52)
## Who this was: "guard" or "player". Only ever changes what the prompt reads,
## but it is worth reading - a player's body is the one carrying a raid's worth
## of somebody else's luck, and walking past it by mistake is expensive.
var tag := "guard"

@onready var _visual: Polygon2D = $Visual
@onready var _label: Label = $Label


## Set before the body enters the tree: the children below are not ready yet, so
## this only records what _ready will draw with.
func setup(kit: Inventory, body_color: Color, size: Vector2, whose := "guard") -> void:
	inventory = kit
	tint = body_color
	body_size = size
	tag = whose


func _ready() -> void:
	add_to_group(&"lootable")
	# Laid out flat: as wide as the guard was tall, and only as tall as he was
	# wide. The silhouette alone says that whoever this was is not getting up.
	var half := Vector2(body_size.y, body_size.x) * 0.5
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	_visual.color = Color(tint.r * 0.55, tint.g * 0.55, tint.b * 0.55)
	_refresh_label()


func _refresh_label() -> void:
	# Never the contents. What a body is carrying is exactly the thing worth
	# crossing open ground to find out, and printing it over the corpse hands
	# that decision to you for free.
	_label.text = "" if inventory == null or inventory.is_empty() else tag.to_upper()


## Replaces what is on this body wholesale: what the host says is left after
## somebody finished going through it. A body is searched by one person at a
## time (Net.ask_to_search), so this only ever lands between searches, never
## underneath one in progress.
func set_contents(kit: Inventory) -> void:
	inventory = kit
	if _label:
		_refresh_label()


func has_loot() -> bool:
	return inventory != null and not inventory.is_empty()


## What the prompt reads while you are standing over it. Deliberately says who
## it was, not what they had: you find that out by searching.
func get_prompt() -> String:
	return tag if has_loot() else "picked clean"


## Hands everything over that the taker has room for, and keeps the rest.
func loot_into(taker: Inventory) -> Dictionary:
	if not has_loot():
		return {}
	var moved := taker.take_everything_from(inventory)
	_refresh_label()
	return moved
