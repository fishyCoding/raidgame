class_name Weapon
extends Node

## The gun in the holder's hands: rate of fire, reloading, and the live recoil
## state (bloom + kick) that the reticle and the aim code read back.
##
## It owns none of the kit. Which guns are carried and how much ammunition is
## left lives in the holder's Inventory, and this node only ever holds a
## reference to it plus which of the two hand slots is up. That is what lets a
## body be looted: the guard's inventory outlives the guard, and the weapon node
## dies with him.

signal weapon_changed(data: WeaponData, slot: int)
signal ammo_changed(mag: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished()
signal shot_fired(recoil_shake: float, knockback: float)


## What the player starts with, and nothing more: everything else is looted.
const STARTING_WEAPON := "res://resources/weapons/pistol.tres"

## What rounds from this weapon collide with. Enemies override it so their fire
## reaches the player instead of the practice dummies.
@export_flags_2d_physics var hit_mask := Layers.PLAYER_SHOT

## Scales the damage of everything this weapon fires. Guards carry the same guns
## the player can loot, and a looted rifle would be no prize if it were weaker in
## your hands - so the gun keeps its stats and the guard shoots for less.
@export_range(0.05, 2.0) var damage_scale := 1.0

## How much of the run-and-gun penalty survives while aiming.
@export_range(0.0, 1.0) var focus_move_penalty_scale := 0.35

## The holder's kit. Assigned by the player or the guard before this node is
## used; a default one is built in _ready if nobody supplied it.
var inventory: Inventory

var data: WeaponData
var slot := Inventory.Slot.PRIMARY
## 0 hip-fire, 1 fully aimed. Written by whoever holds the gun.
var focus := 0.0
## Extra cone from firing, radians. Grows per shot, decays with stability.
var bloom := 0.0
## Upward aim offset from firing, radians. Same idea, separate curve.
var kick := 0.0

var _cooldown := 0.0
var _reload_left := 0.0
var _reload_total := 0.0
var _equip_left := 0.0
var _since_shot := 0.0
## Semi-auto guns need the trigger released before they will fire again.
var _trigger_held := false
## Looked up by path rather than used as the `Audio` global: naming the autoload
## here would make this script fail to compile for any --script tool harness,
## which runs before autoloads are registered. Null when there is no audio.
@onready var _audio: Node = get_node_or_null(^"/root/Audio")


func _ready() -> void:
	if inventory == null:
		set_inventory(starting_inventory())
	else:
		_refresh(true)


## A sidearm and a pocketful of rounds for it.
##
## Static, because the shop needs one before there is a character to hang it on:
## in a match you kit out during the countdown, and what you buy is bought into a
## kit that is handed to the body when it finally appears. One definition of
## "what you start with", whether it is built here or filled in the shop first.
static func starting_inventory() -> Inventory:
	var kit := Inventory.new()
	var pistol := load(STARTING_WEAPON) as WeaponData
	# On the hip, not in the hands: a pistol is a sidearm, and starting with
	# nothing in the primary slot is the point of an extraction run.
	kit.secondary = Item.from_weapon(pistol)
	kit.add_rounds(pistol.ammo_type, pistol.reserve_ammo)
	return kit


func set_inventory(kit: Inventory) -> void:
	if inventory and inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.disconnect(_on_inventory_changed)
	inventory = kit
	if inventory:
		inventory.changed.connect(_on_inventory_changed)
	# Hold whichever hand has something in it: with only a sidearm carried, that
	# is the secondary.
	slot = Inventory.Slot.PRIMARY
	if inventory and inventory.primary == null and inventory.secondary != null:
		slot = Inventory.Slot.SECONDARY
	_refresh(true)


## The kit can change under the gun - looted, dragged, swapped on the inventory
## screen - so the held weapon is re-read whenever it does.
func _on_inventory_changed() -> void:
	# An empty hand is not something to hold: if what you were carrying moved,
	# fall through to the other hand rather than aiming an empty fist.
	if inventory and inventory.get_slot(slot) == null:
		var other := Inventory.Slot.SECONDARY if slot == Inventory.Slot.PRIMARY \
			else Inventory.Slot.PRIMARY
		if inventory.get_slot(other) != null:
			slot = other
	_refresh()


## Forces a re-read, for when the caller knows something changed.
func refresh() -> void:
	_refresh(true)


## Re-reads what is in hand after the inventory changed under us: a swap, a
## loot, a gun taken away.
func _refresh(force := false) -> void:
	var item := _item()
	var new_data: WeaponData = item.weapon if item else null
	if new_data == data and not force:
		return

	data = new_data
	_reload_left = 0.0
	bloom = 0.0
	kick = 0.0
	if data:
		_equip_left = data.get_equip_time()
	weapon_changed.emit(data, slot)
	ammo_changed.emit(get_mag(), get_reserve())


func _item() -> Item:
	return inventory.get_slot(slot) if inventory else null


# --- what is in hand ----------------------------------------------------------


## Switches between the two hand slots. An empty hand is not equipped: with only
## a primary carried, pressing 2 leaves you holding the primary.
func equip(new_slot: int, force := false) -> void:
	if inventory == null:
		return
	var wanted := Inventory.Slot.SECONDARY if new_slot == Inventory.Slot.SECONDARY \
		else Inventory.Slot.PRIMARY
	if inventory.get_slot(wanted) == null:
		return
	if wanted == slot and not force:
		return
	slot = wanted
	_refresh(true)


## Brings a gun out of the backpack and into the primary hand.
func equip_backpack(index: int) -> bool:
	if inventory == null or not inventory.equip_stowed(index):
		return false
	slot = Inventory.Slot.PRIMARY
	_refresh(true)
	return true


## Brings a specific carried gun to hand, wherever it currently sits.
func equip_data(wanted: WeaponData) -> bool:
	if inventory == null:
		return false
	for slot_id in [Inventory.Slot.PRIMARY, Inventory.Slot.SECONDARY]:
		var held := inventory.get_slot(slot_id)
		if held and held.weapon == wanted:
			slot = slot_id
			_refresh(true)
			return true
	var stowed := inventory.stowed_weapons()
	for i in stowed.size():
		if stowed[i].weapon == wanted:
			return equip_backpack(i)
	return false


func get_mag() -> int:
	var item := _item()
	return item.count if item else 0


## Loose rounds in the pockets that fit what is in hand.
func get_reserve() -> int:
	if data == null or inventory == null:
		return 0
	return inventory.rounds_of(data.ammo_type)


func tick(delta: float) -> void:
	if data == null:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	_equip_left = maxf(_equip_left - delta, 0.0)
	_since_shot += delta

	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

	# Recoil only starts washing out once the gun has had a moment.
	if _since_shot >= data.get_recovery_delay():
		bloom = maxf(bloom - data.get_bloom_recovery() * delta, 0.0)
		kick = move_toward(kick, 0.0, kick * data.get_kick_recovery() * delta + 0.0005)


## Current cone half-angle, including bloom, the run-and-gun penalty, and however
## far into the sights the shooter currently is.
func get_spread(move_factor := 0.0) -> float:
	if data == null:
		return 0.0
	var aimed := clampf(focus, 0.0, 1.0)
	var cone := data.get_base_spread() + bloom
	var penalty := data.get_move_penalty() * clampf(move_factor, 0.0, 1.0)
	return cone * lerpf(1.0, data.ads_spread_scale, aimed) \
		+ penalty * lerpf(1.0, focus_move_penalty_scale, aimed)


func is_reloading() -> bool:
	return _reload_left > 0.0


func is_equipping() -> bool:
	return _equip_left > 0.0


func get_reload_progress() -> float:
	if _reload_total <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_left / _reload_total, 0.0, 1.0)


# --- firing -------------------------------------------------------------------


## Refills the magazine out of the pockets. Only what is loose is available, so
## a gun whose calibre you have run out of stays empty however long you hold R.
func reload() -> void:
	var item := _item()
	if item == null or is_reloading() or is_equipping():
		return
	if item.count >= data.mag_size or get_reserve() <= 0:
		return
	_reload_total = data.get_reload_duration()
	_reload_left = _reload_total
	if _audio:
		_audio.reload_started(_sound_position())
	reload_started.emit(_reload_total)


func _finish_reload() -> void:
	_reload_left = 0.0
	var item := _item()
	if item == null:
		return
	var wanted := data.mag_size - item.count
	item.count += inventory.take_rounds(data.ammo_type, wanted)
	if _audio:
		_audio.reload_finished(_sound_position())
	ammo_changed.emit(get_mag(), get_reserve())
	reload_finished.emit()


## Called every physics frame with the current trigger state.
## Returns true on the frame a shot actually leaves the barrel.
func try_fire(origin: Vector2, angle: float, pressed: bool, held: bool,
		move_factor := 0.0) -> bool:
	var item := _item()
	if item == null:
		return false

	var wants_shot := held if data.automatic else (pressed and not _trigger_held)
	_trigger_held = held

	if not wants_shot or is_reloading() or is_equipping() or _cooldown > 0.0:
		return false

	if item.count <= 0:
		# Only click on the press, not on every frame of a held empty trigger.
		if _audio and (pressed or not data.automatic):
			_audio.dry_fire(origin)
		reload() # dry trigger pull tops the gun up instead of doing nothing
		return false

	item.count -= 1
	_cooldown = data.get_shot_interval()
	_since_shot = 0.0
	ammo_changed.emit(get_mag(), get_reserve())

	if _audio:
		_audio.gunshot(data, origin)

	var spread := get_spread(move_factor)
	for i in data.pellets:
		_spawn_bullet(origin, angle + _pellet_offset(i, spread))

	# Both ease into their ceilings instead of slamming into them. Adding a flat
	# amount and clamping means a long burst climbs hard and then, at one
	# particular round, stops dead - which reads as the recoil switching itself
	# off mid-burst. Scaling each shot by the headroom left makes the climb taper
	# as it approaches the limit, so it keeps creeping and never has an edge.
	bloom += data.get_bloom_per_shot() * _headroom(bloom, data.get_max_bloom())
	kick += data.get_kick_per_shot() * _headroom(kick, data.get_max_kick())
	shot_fired.emit(data.get_shake(), data.get_knockback())
	return true


## How much of the way to a ceiling is left, 1 at rest and 0 once there. Used to
## fade recoil growth in near its limit rather than cutting it off.
func _headroom(value: float, ceiling: float) -> float:
	return clampf(1.0 - value / maxf(ceiling, 0.0001), 0.0, 1.0)


## Single rounds jitter anywhere in the cone; buckshot is spread evenly across it
## so a shotgun pattern stays a pattern instead of clumping at random.
func _pellet_offset(index: int, spread: float) -> float:
	if data.pellets <= 1:
		return randf_range(-spread, spread)
	var t := float(index) / float(data.pellets - 1) * 2.0 - 1.0
	return t * spread * 0.8 + randf_range(-spread, spread) * 0.2


## Every round goes through Net, which draws it here at once and gets it onto
## every other machine. A weapon does not know or care whether anyone is
## watching - the same call is the whole of single player and the whole of a
## four-player raid.
func _spawn_bullet(origin: Vector2, angle: float) -> void:
	Net.fire(origin, angle, data.resource_path, hit_mask, damage_scale, _shooter_id())


## The peer to credit for this shot. A gun held by a guard answers 0: guards are
## the host's, and nobody wants a hitmarker for them.
func _shooter_id() -> int:
	var holder := get_parent()
	if holder and holder.is_in_group(&"player"):
		return holder.get_multiplayer_authority()
	return 0


## Reloads have no muzzle to fire from, so they sound from whoever is holding
## the gun - this node hangs off the player or a guard.
func _sound_position() -> Vector2:
	var holder := get_parent() as Node2D
	return holder.global_position if holder else Vector2.ZERO
