@tool
class_name FPLight
extends Node3D

## Wraps a light so the *mount* is a dial rather than a scene restructure.
## Attach to a Node3D holding an OmniLight3D or SpotLight3D as its child, then
## pick a mount:
##
##   BODY  -- parented to Player, no aiming.       Lantern, glow, campfire carry.
##   HAND  -- HandRig. Aims roughly where you look, with lag.  Flashlight, torch.
##   HEAD  -- CameraRig. Aims exactly, bobs with you.          Helmet lamp.
##
## Energy and on/off are host-driven. This owns nothing but the fade and mount.

signal toggled(is_on: bool)

enum Mount { BODY, HAND, HEAD }

@export var mount: Mount = Mount.HAND:
	set(v):
		mount = v
		if is_inside_tree() and not Engine.is_editor_hint():
			_apply_mount()

@export var start_on: bool = false
@export var max_energy: float = 1.5
## Seconds to fade fully on or off. 0 is instant.
@export var fade_time: float = 0.15
## Optional InputMap action that toggles this light. Left blank = code-only.
@export var toggle_action: String = ""

var is_on: bool = false
var _energy: float = 0.0
var _light: Light3D


func _ready() -> void:
	_light = _find_light()
	if _light == null:
		push_warning("FPLight '%s' has no Light3D child." % name)
		set_process(false)
		return
	if Engine.is_editor_hint():
		return
	# Child _ready runs before the parent's, so the player's rigs don't exist yet.
	_apply_mount.call_deferred()
	is_on = start_on
	_energy = max_energy if is_on else 0.0
	_light.light_energy = _energy
	_light.visible = _energy > 0.001


func _process(delta: float) -> void:
	if _light == null:
		return
	var target := max_energy if is_on else 0.0
	if is_equal_approx(_energy, target):
		return
	if fade_time <= 0.0:
		_energy = target
	else:
		_energy = move_toward(_energy, target, (max_energy / fade_time) * delta)
	_light.light_energy = _energy
	_light.visible = _energy > 0.001


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action.is_empty() or not InputMap.has_action(toggle_action):
		return
	# Event-driven, not Input.is_action_just_pressed() -- polled state inside an
	# event handler double-fires when two events arrive in the same frame.
	if event.is_action_pressed(toggle_action):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	set_on(not is_on)


func set_on(v: bool) -> void:
	if v == is_on:
		return
	is_on = v
	toggled.emit(is_on)


## Host games drive brightness through this (fuel, charge, spell power).
func set_max_energy(v: float) -> void:
	max_energy = maxf(v, 0.0)


func _find_light() -> Light3D:
	for c in get_children():
		if c is Light3D:
			return c as Light3D
	return null


func _apply_mount() -> void:
	var player := _find_player()
	if player == null:
		return
	var target: Node3D
	match mount:
		Mount.BODY: target = player
		Mount.HAND: target = player.hand_rig
		Mount.HEAD: target = player.camera_rig
	if target == null or get_parent() == target:
		return
	var xform := transform
	get_parent().remove_child(self)
	target.add_child(self)
	transform = xform


func _find_player() -> FPPlayer:
	var n: Node = get_parent()
	while n != null:
		if n is FPPlayer:
			return n as FPPlayer
		n = n.get_parent()
	return null
