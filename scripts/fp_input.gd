class_name FPInput
extends RefCounted

## Input policy for the package:
##
##   REQUIRED actions are auto-registered if the project doesn't define them,
##   so the player works in a brand new empty project with zero setup.
##
##   OPTIONAL actions are NEVER registered. Their presence in the project's
##   InputMap *is* the opt-in. Ship a build without binding `toggle_fly` and
##   debug flight is simply unreachable -- no build flags, no dead code to strip.
##
## An existing project's own bindings always win; nothing here overwrites.

const REQUIRED := {
	"walk_forward": [KEY_W, KEY_UP],
	"walk_backward": [KEY_S, KEY_DOWN],
	"strafe_left": [KEY_A, KEY_LEFT],
	"strafe_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"interact_general": [KEY_E],
}

## Documented, deliberately unregistered. Bind any of these yourself to enable it.
const OPTIONAL := [
	"mouse_release",     # suggested: KEY_QUOTELEFT or KEY_F1. NOT Escape -- that's pause.
	"toggle_fly",
	"fly_up",
	"fly_down",
	"toggle_lantern",
	"toggle_flashlight",
]

static func register_defaults() -> void:
	for action in REQUIRED:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in REQUIRED[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

## True if an optional feature has been opted into.
static func enabled(action: String) -> bool:
	return InputMap.has_action(action)
