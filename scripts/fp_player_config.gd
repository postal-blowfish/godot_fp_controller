class_name FPPlayerConfig
extends Resource

## Every tunable for the FP player package.
## Duplicate this resource per-project (or per-character) instead of editing scripts.

# ---------------------------------------------------------------- BODY
@export_group("Body")
## Capsule height while standing. Eye height is derived from this.
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.0
## Capsule radius. Smaller values reduce how much the rounded bottom slides you
## off ledge corners -- this is the cheap half of the ledge-landing fix.
@export var body_radius: float = 0.35
## Eyes sit this far below the top of the capsule.
@export var eye_offset: float = -0.15
@export var crouch_transition_speed: float = 12.0

# ---------------------------------------------------------------- MOVEMENT
@export_group("Movement")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.0
@export var crouch_speed: float = 2.0
@export var ground_accel: float = 50.0
@export var ground_decel: float = 60.0
@export var air_accel: float = 14.0
## 0 = no steering in the air, 1 = full ground control while airborne.
@export_range(0.0, 1.0) var air_control: float = 0.45

# ---------------------------------------------------------------- JUMP
@export_group("Jump")
## Jump is authored in human terms; gravity is derived from these two.
@export var jump_height: float = 1.1
@export var time_to_apex: float = 0.38
## Falling is faster than rising. 1.0 disables the asymmetry.
@export var fall_gravity_multiplier: float = 1.35
@export var max_fall_speed: float = 60.0
## Grace period to still jump after walking off a ledge.
@export var coyote_time: float = 0.12
## Pressing jump this long before landing still jumps.
@export var jump_buffer: float = 0.10

# ---------------------------------------------------------------- GROUND
@export_group("Ground")
## Vertical lip the controller will climb without a jump. 0 disables step-up
## entirely (correct for projects built purely from authored ramps).
## Real stair risers cap near 0.2m; 0.4 clears those plus terrain seams and rubble.
@export var max_step_height: float = 0.4
## Deliberately above 45 -- a ramp authored at exactly 45 against a 45 limit is a
## float coin-flip, and that is exactly the "why can't I walk up this" moment.
@export var floor_max_angle_deg: float = 50.0
## Must be >= max_step_height or descending stairs goes airborne between steps.
@export var floor_snap_length: float = 0.5
## Pulls you onto a ledge when you land on its corner instead of sliding off.
@export var edge_snap_enabled: bool = true
## Distance walked between footstep signals. Game walk speeds are unrealistically
## fast, so this is longer than a real human stride on purpose -- 0.85 against a
## 4.5 m/s walk is over five footfalls a second, which is machine-gun cadence.
@export var stride_length: float = 1.8
## How far past body_radius the step-height ray samples.
@export var step_forward_margin: float = 0.02
## Vertical climb rate while stepping, m/s. Scales up with movement speed.
## Too low and you stall against stairs at a run; too high and it reads as a
## teleport again. The body never moves horizontally during a climb.
@export var step_climb_speed: float = 8.0
## How far ahead to look for a step, in seconds of travel. One physics frame
## (~0.016s) means the climb only starts after you've already stopped dead
## against the riser, which reads as a hitch on every single step.
@export var step_lookahead: float = 0.05
## Hold full speed regardless of incline. Off by default: with it on, climbing a
## slope feels powered rather than effortful, because you keep the horizontal
## speed that projection would otherwise take away.
@export var constant_speed_on_slopes: bool = false

# ---------------------------------------------------------------- LOOK
@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var pitch_min_deg: float = -89.0
@export var pitch_max_deg: float = 89.0
@export var invert_y: bool = false
## Grab the mouse on ready. Turn this off the moment the project has real UI.
@export var auto_capture_mouse: bool = true

# ---------------------------------------------------------------- CAMERA FX
@export_group("Camera FX")
@export var bob_enabled: bool = true
@export var bob_amplitude: float = 0.045
@export var bob_sway: float = 0.02
## Multiplier on bob cadence, independent of footstep spacing. Tune to taste.
@export var bob_speed_scale: float = 1.0
@export var land_dip_scale: float = 0.014
@export var land_dip_recovery: float = 9.0
## The body has to teleport when it steps up or the collision goes wrong -- but
## the camera doesn't. This is how fast the view catches back up. Lower = softer.
@export var step_smooth_recovery: float = 14.0
@export var base_fov: float = 75.0
@export var sprint_fov_add: float = 6.0
@export var fov_lerp_speed: float = 6.0

# ---------------------------------------------------------------- HAND RIG
@export_group("Hand Rig")
## How fast the hand rig catches up to where you're looking. The lag IS the sway.
## High (~25) reads as a helmet lamp, low (~6) as a lantern on a strap.
@export var hand_follow_speed: float = 12.0

# ---------------------------------------------------------------- FLY
@export_group("Fly (debug)")
@export var fly_speed: float = 12.0
@export var fly_sprint_multiplier: float = 3.0

# ---------------------------------------------------------------- AWARENESS
@export_group("Awareness")
## Tier radii, ascending. Tier 0 is the innermost. Tier -1 means out of range.
## Length is arbitrary -- one entry is a perfectly valid config.
@export var awareness_tiers: PackedFloat32Array = PackedFloat32Array([4.0, 12.0, 30.0])
@export var awareness_tick_hz: float = 10.0

# ---------------------------------------------------------------- INTERACTION
@export_group("Interaction")
@export var aim_distance: float = 30.0
## Tier the aim target must be within for `interact` to fire.
@export var interact_tier: int = 0

# ---------------------------------------------------------------- DERIVED
func rise_gravity() -> float:
	return (2.0 * jump_height) / max(time_to_apex * time_to_apex, 0.0001)

func jump_velocity() -> float:
	return (2.0 * jump_height) / max(time_to_apex, 0.0001)

func eye_height(current_body_height: float) -> float:
	return current_body_height + eye_offset

func max_awareness_radius() -> float:
	var m := 0.0
	for r in awareness_tiers:
		m = maxf(m, r)
	return m

## Tier index for a distance, or -1 if beyond every tier.
func tier_for_distance(d: float) -> int:
	for i in awareness_tiers.size():
		if d <= awareness_tiers[i]:
			return i
	return -1
