class_name FPHandRig
extends Node3D

## Sits under Head alongside CameraRig, but *lerps* toward where you're looking
## instead of matching it. That lag is the sway that reads as "held in a hand,"
## and because it lives outside CameraRig it never inherits head bob -- you don't
## get bob on a flashlight you're carrying, which is the whole point.
##
## Position follows exactly; only rotation lags.

var follow_speed: float = 12.0
var _basis: Basis = Basis.IDENTITY
var _initialised: bool = false


func _process(delta: float) -> void:
	var parent := get_parent_node_3d()
	if parent == null:
		return
	var target := parent.global_transform.basis.orthonormalized()
	if not _initialised:
		_basis = target
		_initialised = true
	var t: float = 1.0 - exp(-maxf(follow_speed, 0.01) * delta)
	_basis = Basis(_basis.get_rotation_quaternion().slerp(target.get_rotation_quaternion(), t))
	global_transform = Transform3D(_basis, parent.global_transform.origin)


## Snap instantly -- use after teleports so the rig doesn't whip around.
func snap() -> void:
	_initialised = false
