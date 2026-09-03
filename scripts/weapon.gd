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
## Thermal lock, for a gun firing on an overtiered energy cell. `locked` only
## ever goes true on an automatic - see the header comment on `heat` - but the
## fraction is meaningful on a semi-auto too, so the HUD can draw the same bar
## for both and only the lock icon differs.
signal heat_changed(heat: float, locked: bool)


## What the player starts with, and nothing more: everything else is looted.
const STARTING_WEAPON := "res://resources/weapons/pistol.tres"

## How far a round that lands on you throws your own aim off, in degrees per 100
## damage that got through your armour. A rifle round to an unplated chest is 51
## of it, so a little over a degree and a half - most of an assault rifle's whole
## standing cone. Enough that a trade you were winning becomes a trade, and not
## so much that being shot at once ends your ability to shoot back.
const FLINCH_DEGREES_PER_100 := 3.0
## Ceiling, so a burst that catches you does not stack into a cone you cannot
## aim out of. Reached at about four rifle rounds.
const FLINCH_MAX_DEGREES := 6.0
## Degrees a second it washes out. "Directly after" is the whole mechanic: a
## rifle round's worth is gone in under a fifth of a second, which is long
## enough to spoil the shot you were in the middle of and short enough that the
## fight is still yours to win.
const FLINCH_RECOVERY_DEGREES := 9.0
## How much of it aiming buys back. A sight steadies the gun; it does not steady
## you, so this is deliberately a long way from the ads_spread_scale the rest of
## the cone is multiplied by.
const FLINCH_AIM_SCALE := 0.65

## What rounds from this weapon collide with. Enemies override it so their fire
## reaches the player instead of the practice dummies.
@export_flags_2d_physics var hit_mask := Layers.PLAYER_SHOT

## Scales the damage of everything this weapon fires. Guards carry the same guns
## the player can loot, and a looted rifle would be no prize if it were weaker in
## your hands - so the gun keeps its stats and the guard shoots for less.
@export_range(0.05, 2.0) var damage_scale := 1.0

## How much of the run-and-gun penalty survives while aiming.
@export_range(0.0, 1.0) var focus_move_penalty_scale := 0.35
## Extra cone with both feet off the ground, as a multiple of the full
## run-and-gun penalty. Deliberately several times it: running is a choice
## about how fast you cross open ground, but jumping into a fight is a way of
## being hard to hit, and that has to cost the shot or it is simply free.
@export_range(0.0, 8.0) var air_penalty_scale := 3.2
## How much aiming buys back while airborne. Much less than it buys on the
## ground, because a sight steadies a braced gun and you are not braced.
@export_range(0.0, 1.0) var focus_air_penalty_scale := 0.8

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
## Extra cone from being shot, radians. Set by whoever holds the gun when a round
## lands on them - see Player.take_damage - and washed out fast.
##
## Its own term rather than more bloom, and that is the whole point of it. Bloom
## is multiplied by ads_spread_scale, so a scoped sniper divides everything in
## that bucket by twenty and a man being shot at would have flinched by four
## hundredths of a degree. Being hit is not a recoil problem and a sight cannot
## brace you against it, so it is added after the sights have had their say and
## only partly bought back by aiming.
var flinch := 0.0

## Heat from firing on an overtiered energy cell, 0 to 1. Zero and inert on a
## same-tier cell - a same-tier shot never adds to it, full stop - so this is
## entirely a cost of the loadout decision to overtier a gun, never something
## an ordinary loadout has to think about.
##
## NOT the same thing as `_cooldown` below, which is the ordinary per-shot
## fire-rate gate every gun has regardless of what is feeding it. `heat` is
## what an overtiered cell costs on top of that - see try_fire() for how it
## stretches `_cooldown` on a semi-auto on the way up, and how either gun
## class locks outright once it tops out - see `heat_locked`.
var heat := 0.0
## True from the shot that fills the heat bar until it has bled back down
## under the gun's own unlock threshold - see
## WeaponData.get_heat_unlock_threshold(). Applies to both gun classes: an
## automatic has nothing else guarding it (there is no gap between shots to
## stretch, the trigger is held continuously), and a semi-auto pays the
## stretched-`_cooldown` tax on the way up to this and then the same flat
## refusal an automatic gets once it actually arrives - a semi-auto that
## reached full heat and kept firing right through it read as broken, not
## as a gun that had earned some slack.
var heat_locked := false

var _cooldown := 0.0
var _reload_left := 0.0
var _reload_total := 0.0
var _equip_left := 0.0
## Gun slung, both hands on a rope. Not a timer: it lasts as long as the rope
## does, and bring_up() starts the ordinary draw from it - so coming off a cable
## costs exactly what swapping to the same gun costs, which is a number the
## weapon already has an opinion about.
var stowed := false
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
	heat = 0.0
	heat_locked = false
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
		if held and held.is_gun(wanted):
			slot = slot_id
			_refresh(true)
			return true
	var stowed := inventory.stowed_weapons()
	for i in stowed.size():
		if stowed[i].is_gun(wanted):
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

	# Being shot washes out on its own clock, not the gun's: it is not recoil,
	# so it does not wait on a recovery delay and it is not scaled by how steady
	# the weapon is. Everything flinches alike and recovers alike.
	flinch = maxf(flinch - deg_to_rad(FLINCH_RECOVERY_DEGREES) * delta, 0.0)

	# Recoil only starts washing out once the gun has had a moment.
	if _since_shot >= data.get_recovery_delay():
		bloom = maxf(bloom - data.get_bloom_recovery() * delta, 0.0)
		kick = move_toward(kick, 0.0, kick * data.get_kick_recovery() * delta + 0.0005)

	# Heat rides the same grace timer, reusing `_since_shot` rather than a
	# clock of its own - the same shape bloom and kick recover on above, for
	# the same reason: a burst does not get to vent between rounds just
	# because the trigger let up for one frame.
	if heat > 0.0 and _since_shot >= data.get_heat_recovery_delay():
		# Slower while actually locked - see LOCKED_HEAT_RECOVERY_SCALE - so
		# reaching the lock costs more than almost reaching it does.
		heat = maxf(heat - data.get_heat_recovery(heat_locked) * delta, 0.0)
		if heat_locked and heat <= data.get_heat_unlock_threshold(_energy_delta()):
			heat_locked = false
			heat_changed.emit(heat, heat_locked)


## Current cone half-angle, including bloom, the run-and-gun penalty, whether the
## shooter's feet are on the ground, and however far into the sights they
## currently are.
func get_spread(move_factor := 0.0, air_factor := 0.0) -> float:
	if data == null:
		return 0.0
	var aimed := clampf(focus, 0.0, 1.0)
	var cone := data.get_base_spread() + bloom
	var penalty := data.get_move_penalty() * clampf(move_factor, 0.0, 1.0)
	# Its own term rather than more move factor: they are different mistakes,
	# and a sight does much less about this one.
	var airborne := data.get_move_penalty() * air_penalty_scale \
		* clampf(air_factor, 0.0, 1.0)
	return (cone * lerpf(1.0, data.ads_spread_scale, aimed)
		+ penalty * lerpf(1.0, focus_move_penalty_scale, aimed)
		+ airborne * lerpf(1.0, focus_air_penalty_scale, aimed)
		+ flinch * lerpf(1.0, FLINCH_AIM_SCALE, aimed))


## A round landed on the holder. `amount` is what got through their armour,
## because a plate that stopped most of it also stopped most of the shove.
##
## Called by the body that was hit rather than by whoever fired it, which is the
## rule report_hit already follows and for the same reason: on a client, the
## machine that knows a round landed on you is yours.
func take_flinch(amount: float) -> void:
	if amount <= 0.0:
		return
	flinch = minf(flinch + deg_to_rad(FLINCH_DEGREES_PER_100 * amount * 0.01),
		deg_to_rad(FLINCH_MAX_DEGREES))


func is_reloading() -> bool:
	return _reload_left > 0.0


func is_equipping() -> bool:
	return stowed or _equip_left > 0.0


## Puts it away. Nothing fires and nothing reloads until it comes back up: you
## are holding a cable with the hand the gun was in.
func put_away() -> void:
	stowed = true


## Back in your hands. Deliberately does not start an equip timer of its own:
## the draw is the arm coming up, and player.gd holds this stowed for exactly as
## long as that takes. Two clocks for one draw is how a gun ends up working a
## frame or two before it looks like it does.
func bring_up() -> void:
	stowed = false


func get_reload_progress() -> float:
	if _reload_total <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_left / _reload_total, 0.0, 1.0)


func get_heat() -> float:
	return heat


func is_heat_locked() -> bool:
	return heat_locked


## Where the heat bar's own unlock mark belongs, 0 to 1 - the HUD draws it as
## a line on the bar so "how far below this you need to be" is something a
## player can see rather than something they have to have memorised. Zero
## with nothing equipped or on a same-tier cell, where it means nothing.
## Meaningful for both gun classes now that both actually lock at the
## ceiling - see the header comment on `heat_locked`.
func get_heat_unlock_threshold() -> float:
	return data.get_heat_unlock_threshold(_energy_delta()) if data else 0.0


## How many tiers over its own base the fitted cell is running whatever is in
## hand. Zero with nothing equipped, which is also what a same-tier cell
## reads as - both mean "no overheat behaviour applies".
func _energy_delta() -> int:
	var item := _item()
	return item.energy_delta() if item else 0


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
		move_factor := 0.0, air_factor := 0.0) -> bool:
	var item := _item()
	if item == null:
		return false

	var wants_shot := held if data.automatic else (pressed and not _trigger_held)
	_trigger_held = held

	if not wants_shot or is_reloading() or is_equipping() or _cooldown > 0.0:
		return false

	# No cell, no fire. A magazine full of rounds with nothing feeding the
	# chamber is exactly as useless as an empty one, so it fails the same
	# way - a dry click, the one failure state every player already knows
	# how to read - rather than a jam or a silent refusal. See EnergyCellData
	# and Item.DEFAULT_ENERGY_BY_TIER for why this is reachable at all: only
	# by stripping the cell a gun starts with and never fitting another.
	if item.energy == null:
		if _audio and (pressed or not data.automatic):
			_audio.dry_fire(origin)
		return false

	var delta := item.energy_delta()

	# Full heat refuses the trigger outright on any gun now, automatic or
	# not - stays refused until it has bled back down past the gun's own
	# threshold. This used to be automatic-only, on the theory that a
	# semi-auto's stretched cooldown was punishment enough on its own; in
	# practice that left a semi-auto that reached the ceiling still firing
	# right through it, which read as the mechanic simply not working
	# rather than as a gun that had earned some slack. The stretch below is
	# still what a semi-auto pays on the way *up* to full heat - this is
	# what it pays once it gets there, the same as an automatic does.
	if heat_locked:
		if _audio and (pressed or not data.automatic):
			_audio.dry_fire(origin)
		return false

	if item.count <= 0:
		# Only click on the press, not on every frame of a held empty trigger.
		if _audio and (pressed or not data.automatic):
			_audio.dry_fire(origin)
		reload() # dry trigger pull tops the gun up instead of doing nothing
		return false

	item.count -= 1
	# The one piece that is still semi-auto-only: on the way *up* to a full
	# heat bar, every shot's own cooldown stretches by however hot the gun
	# already was the instant the trigger broke, capped per the gun's own
	# delta - so this bites gradually, before the lock above ever has
	# anything to say. An automatic has no equivalent, because the trigger
	# is held down continuously on one and there is no gap between shots to
	# stretch in the first place.
	var stretch := 1.0
	if not data.automatic and delta > 0:
		stretch += heat * data.get_heat_stretch_cap(delta)
	_cooldown = data.get_shot_interval() * stretch
	_since_shot = 0.0
	ammo_changed.emit(get_mag(), get_reserve())

	# Updated here, before the round is even spawned, rather than after - the
	# bullet this shot fires and the shove it gives the camera both read this
	# value, and both should read what firing it just cost rather than what
	# it cost one shot ago. Same-tier fire never reaches this at all:
	# get_heat_per_shot() answers zero for delta 0.
	if delta > 0:
		heat = minf(heat + data.get_heat_per_shot(delta), 1.0)
		if heat >= 1.0:
			heat_locked = true
		heat_changed.emit(heat, heat_locked)

	# The report is not played here. A shot exists on every machine as a bullet -
	# see Net._make_bullet - and that is where the noise belongs: fired from here
	# it was heard only by whoever pulled the trigger, so another player's gun was
	# silent and, on a client, so was every guard's.

	# A cone inside a cone. The outer one is the gun - accuracy, bloom, how hard
	# you were moving - and it is rolled once, for the shell rather than for each
	# pellet, so the whole pattern goes where the shot went. The inner one is the
	# shell, and it is the only thing between one pellet and the next.
	var aim := get_spread(move_factor, air_factor)
	var line := angle + randf_range(-aim, aim)
	if data.pellets <= 1:
		_spawn_bullet(origin, line)
	else:
		var pattern := data.get_pellet_spread()
		for i in data.pellets:
			_spawn_bullet(origin, line + _pellet_offset(i, pattern))

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


## Where one pellet sits inside the shell's own pattern.
##
## Laid out evenly across it rather than rolled per pellet, so a pattern stays a
## pattern instead of clumping at random - nine independent rolls give you a
## cluster and two stragglers about as often as they give you buckshot. A fifth
## of it is left to chance so no two shells are identical.
##
## Measured against the pattern, not against the aim cone. Which way the shell
## itself went has already been decided by the caller, once, for all of them.
func _pellet_offset(index: int, pattern: float) -> float:
	if data.pellets <= 1:
		return 0.0
	var t := float(index) / float(data.pellets - 1) * 2.0 - 1.0
	return t * pattern * 0.8 + randf_range(-pattern, pattern) * 0.2


## Every round goes through Net, which draws it here at once and gets it onto
## every other machine. A weapon does not know or care whether anyone is
## watching - the same call is the whole of single player and the whole of a
## four-player raid.
func _spawn_bullet(origin: Vector2, angle: float) -> void:
	# The path sent is the gun off the shelf, never the built copy: a modified
	# gun is a duplicate with no resource_path, and sending an empty one is how
	# every shot from an attached weapon quietly failed to exist.
	var item := _item()
	var shelf: WeaponData = item.base_weapon if item and item.base_weapon else data
	# Both the shelf path and the gun in hand: Net draws this one from the object
	# and sends the other end the path, and works out for itself what the parts
	# did to the damage - see Net.fire. `heat` and `_muzzle_reach_px` ride along
	# unmodified - see the header comment on Net.fire() for why neither needs
	# a shelf/built ratio the way damage and speed do.
	Net.fire(origin, angle, shelf.resource_path, hit_mask, damage_scale,
		_shooter_id(), data, 1.0, heat, _muzzle_reach_px(item))


## The baseline every gun's muzzle_reach() is measured against: the AR's own
## receiver (58) plus barrel (40). Not zero, because GunArt's gun-space
## numbers are not world pixels and have no reason to start at zero meaning
## "this rig's fixed Muzzle marker" - they need a reference point, and the
## AR is the one this whole file already benchmarks everything else against
## (see the damage model comment at the top of WeaponData). A gun shorter
## than that pulls the flash back toward the hand; a longer one - or a can
## screwed onto the end of any of them - pushes it out past the barrel.
const MUZZLE_REACH_BASELINE := 98.0
## Gun-space units to world pixels. Invented rather than derived - GunArt's
## numbers were never meant to describe the actual rig, only to draw a
## readable side-on diagram of one - so this is picked to put a sniper's
## much longer barrel a noticeable but not silly distance past where a
## pistol's flash sits, and wants a look in play to confirm.
const MUZZLE_REACH_SCALE := 0.4


## How far past the rig's fixed Muzzle marker this specific gun, with
## whatever is bolted to its muzzle, actually reaches - in world pixels,
## forward along the shot. Purely cosmetic: nothing about where the bullet
## itself begins reads this, only where the flash it leaves the barrel with
## is drawn. See GunArt.muzzle_reach() for the number this is built from.
func _muzzle_reach_px(item: Item) -> float:
	if item == null or item.base_weapon == null:
		return 0.0
	var reach := GunArt.muzzle_reach(item.base_weapon, item.parts)
	return (reach - MUZZLE_REACH_BASELINE) * MUZZLE_REACH_SCALE


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
