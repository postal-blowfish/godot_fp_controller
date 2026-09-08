class_name Interactable
extends Node

## Drop this as a CHILD of any node you want the player to be able to use.
##
## Deliberately not a base class: a door wants to be AnimatableBody3D, a dropped
## item wants RigidBody3D, an NPC wants CharacterBody3D. Forcing a shared ancestor
## fights the engine. As a child node it composes onto anything, and one object
## can carry several (a car with a driver seat and a trunk).
##
## The player finds it by checking the collider it aimed at, that collider's
## children, and then walking up its parents.
##
## Subclass this and override `default_action` -- or don't, and just connect to
## the `interacted` signal from anywhere.

signal interacted(who: Node)
signal focus_entered(who: Node)
signal focus_exited(who: Node)
signal tier_changed(new_tier: int, old_tier: int)

## Shown by the host game's prompt UI. The package never draws this.
@export var prompt: String = "Use"
## Awareness tier the player must be within to trigger this. -1 = any range.
@export var required_tier: int = 0
## Whether this can be triggered without the player looking at it
## (telekinesis, remote machine control, terminals).
@export var allow_remote: bool = false
@export var enabled: bool = true

var current_tier: int = -1

## Override for per-object conditions (locked, powered off, missing key item).
func can_interact(_who: Node) -> bool:
	return enabled

## Override this. Default just fires the signal so simple objects need no script.
func default_action(who: Node) -> void:
	interacted.emit(who)

## Called by the player. Don't override this -- override `default_action`.
func try_interact(who: Node) -> bool:
	if not can_interact(who):
		return false
	default_action(who)
	return true

## Called by the player's awareness system.
func set_tier(t: int) -> void:
	if t == current_tier:
		return
	var old := current_tier
	current_tier = t
	tier_changed.emit(t, old)

## Called by the player when it starts or stops looking at this.
func notify_focus(focused: bool, who: Node) -> void:
	if focused:
		focus_entered.emit(who)
	else:
		focus_exited.emit(who)


## The node this Interactable represents -- its parent, for most uses.
func get_subject() -> Node:
	return get_parent()

## How far up the tree to search from the collider that was hit. Bounded on
## purpose: an unbounded walk reaches the scene root, and then aiming at the
## floor can match some unrelated sibling's Interactable. Two levels covers the
## real case (a body nested under the node that owns the Interactable).
const MAX_SEARCH_DEPTH := 2

## Walks a hit collider to find an attached Interactable, if any.
static func find_on(node: Node) -> Interactable:
	if node == null:
		return null
	var n: Node = node
	var depth := 0
	while n != null and depth <= MAX_SEARCH_DEPTH:
		if n is Interactable:
			return n as Interactable
		for child in n.get_children():
			if child is Interactable:
				return child as Interactable
		n = n.get_parent()
		depth += 1
	return null
