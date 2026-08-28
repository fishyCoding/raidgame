class_name Layers
extends RefCounted

## Physics layer bits. Keep in sync with Project Settings > Layer Names > 2D Physics.

const WORLD := 1 << 0
const ONE_WAY := 1 << 1
const PLAYER := 1 << 2
const TARGET := 1 << 3
const ENEMY := 1 << 4
## A deployed screen. Its own layer so it can stop light and bullets without
## stopping anything else - most importantly not sound, which does no raycasting
## at all and is therefore left alone for free.
const SCREEN := 1 << 5

## Bit indices, for set_collision_mask_value() / set_collision_layer_value().
const WORLD_BIT := 1
const ONE_WAY_BIT := 2
const PLAYER_BIT := 3
const TARGET_BIT := 4
const ENEMY_BIT := 5
const SCREEN_BIT := 6

## What a round fired by the player is allowed to hit.
##
## PLAYER is in here, so players can shoot each other. It has to be: this is a
## raid two people go into at opposite ends of the same map, and a round that
## passes through another player is not a design decision, it is hit detection
## that does not work. The shooter's own body is excluded per round rather than
## by layer - see Bullet - because the muzzle sits inside your own hitbox at
## some angles and a mask cannot tell "me" from "him".
const PLAYER_SHOT := WORLD | ONE_WAY | TARGET | ENEMY | PLAYER | SCREEN

## What a round fired by an enemy is allowed to hit. Enemies do not shoot each
## other, so friendly fire never becomes the player's problem-solver.
const ENEMY_SHOT := WORLD | ONE_WAY | PLAYER | SCREEN
