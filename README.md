# fp_player

Drop-in first person controller for Godot 4. Copy `fp_player/` to the project root
(paths inside assume `res://fp_player/`), open `demo/demo.tscn`, press play.

Nothing else is required. No autoloads, no editor plugin, no input setup.

---

## The three levels

**Level one — complete, tuned only by dials. Don't open these again.**
Move / look / jump / gravity, slope handling, step-up, ground state, coyote time
and jump buffering, edge snap, mouse capture, input registration, the config resource.

**Level two — functional, replaceable from outside.**
Crouch, the three light mounts, AimRay + Interactable, awareness tiers,
fly/noclip, head bob, landing dip, sprint FOV. Each works out of the box and each
can be superseded by a host system without touching the player.

**Level three — scaffolding only. No behavior.**
`HoldPoint` marker, `check_overhead()`, `probe_forward()`, `landed(impact_velocity)`,
`footstep(collider, normal)`, `sprint_gate`. Mount points and signals for fall damage,
shelter, mantling, stamina, footstep audio.

---

## Scene tree

```
Player (CharacterBody3D)         fp_player.gd
├─ BodyShape (CollisionShape3D)  capsule, height driven by crouch
├─ Head (Node3D)                 EYE HEIGHT ONLY — crouch writes here
│  ├─ CameraRig (Node3D)         bob / dip / lean / recoil — additive offsets
│  │  └─ Camera3D
│  │     └─ AimRay (RayCast3D)
│  └─ HandRig (Node3D)           fp_hand_rig.gd — lerp-follows Head. No bob.
│     ├─ HoldPoint (Marker3D)
│     └─ Flashlight (Node3D)     fp_light.gd, mount = HAND
│        └─ SpotLight3D
├─ Lantern (Node3D)              fp_light.gd, mount = BODY
│  └─ OmniLight3D
├─ GroundCast (ShapeCast3D)      floor normal, collider, ledge detection
├─ CeilingCast (ShapeCast3D)     "can I stand up"
└─ Awareness (Area3D)            fp_awareness.gd
```

Each camera effect gets its own writer. Head is eye height, CameraRig is effects,
HandRig is held things. Adding weapon recoil later is a new writer on CameraRig,
not a rewrite. A flashlight on HandRig never inherits head bob, because you don't
get bob on a light you're holding in your hand.

The player rebuilds any missing child at runtime, so a bare `CharacterBody3D` with
`fp_player.gd` attached still runs, and restructuring the scene won't break it.

---

## Input policy

**Required actions auto-register if the project doesn't define them.** Existing
bindings always win; nothing is overwritten.

`walk_forward` `walk_backward` `strafe_left` `strafe_right` `jump` `sprint` `crouch` `interact_general`

**Optional actions are never registered. Binding one is the opt-in.**

`mouse_release` `toggle_fly` `fly_up` `fly_down` `toggle_lantern` `toggle_flashlight`

Ship a build without binding `toggle_fly` and debug flight is unreachable. No build
flags, no dead code to remember to strip.

Suggest backtick or F1 for `mouse_release`, **not** Escape — Escape is the pause key
in nearly everything, and you'll end up with two systems fighting over one key.

---

## Interactables

Drop an `Interactable` node as a **child** of anything. Deliberately not a base
class: a door wants AnimatableBody3D, an item wants RigidBody3D, an NPC wants
CharacterBody3D. As a child it composes onto any of them, and one object can carry
several (a car with a driver seat and a trunk).

```gdscript
extends Interactable

func default_action(who: Node) -> void:
    open()
```

That's the whole contract. `prompt`, `required_tier`, `allow_remote`, `enabled`,
`can_interact()`, and the focus/tier signals are inherited. Objects that need no
logic can skip the script entirely and connect to the `interacted` signal.

The AimRay says *what* you're looking at. Awareness says whether it's *close
enough*. Keeping those separate is what lets you read a machine's status from 20m
and still have to walk up to pull the lever.

---

## Awareness tiers

One Area3D sized to the largest tier, tracking what's inside it, resolving tier per
node by distance at 10Hz. Not three nested Areas — that would mean three sets of
enter/exit bookkeeping per object and the radii baked into the scene.

`awareness_tiers` is a `PackedFloat32Array`, so the tier *count* is config, not
structure. Three for one project, one for another, same node.

```gdscript
player.awareness.tier_changed.connect(func(it, new_tier, old):
    if new_tier == 0: show_full_readout(it)
    elif new_tier == 1: show_basic_label(it)
    else: hide_readout(it)
)
```

---

## Signals

| Signal | Use |
|---|---|
| `state_changed(new, old)` | animation, audio, UI |
| `landed(impact_velocity)` | fall damage |
| `footstep(collider, normal)` | surface-aware footstep audio |
| `aim_target_changed(target, prev)` | interaction prompt UI |
| `interacted(target)` | logging, quest triggers |
| `crouch_changed(is_crouched)` | stance UI, noise level |
| `stepped_up(height)`, `edge_snapped()` | debug / feel tuning |
| `mouse_capture_changed(captured)` | UI coordination |

Gating in the other direction uses a Callable, not a poll:

```gdscript
player.sprint_gate = func(): return stamina > 10.0
```

---

## The dials that matter

| Dial | Default | Why |
|---|---|---|
| `max_step_height` | 0.4 | Real stair risers cap near 0.2. This clears those plus terrain seams and modular-kit lips. **0 disables step-up** — correct for projects built purely from authored ramps. |
| `floor_snap_length` | 0.5 | Must be ≥ step height or you go airborne between stairs on the way *down*. That's the bouncing descent you've felt in a lot of games. |
| `floor_max_angle_deg` | 50 | Not 45. A ramp authored at exactly 45 against a 45 limit is a float coin-flip, and that's the "why can't I walk up this" moment. |
| `body_radius` | 0.35 | Smaller = less of the capsule's rounded bottom sliding you off ledge corners. The cheap half of the ledge-landing fix. |
| `coyote_time` / `jump_buffer` | 0.12 / 0.10 | Permissive by default. Buffering is the one nobody notices until it's missing. |
| `jump_height` / `time_to_apex` | 1.1 / 0.38 | Gravity is derived. "How high, how floaty" is the tunable you actually think in. |
| `hand_follow_speed` | 12 | ~25 reads as a helmet lamp, ~6 as a lantern on a strap. |

---

## Step-up, edge snap, mantle

Three separate problems. None replaces another.

**Step-up** — three `test_move` probes (up by step height, forward by the blocked
motion, down again). Only runs when a wall stopped you, so flat ground costs nothing.
Guarded to grounded-only and direction-of-motion, or you could climb any wall by
jumping into it. Cliffs are excluded for free: the down probe finds no walkable
surface, so the only thing you can climb is a stack of short things, i.e. stairs.

**Edge snap** — a sharp edge has no surface. Contact with a corner produces a normal
pointing diagonally away, and the solver can't tell a 2cm lip from a hillside, so
gravity gets projected along it and you slide off something you visibly landed on.
The snap probes inboard and down, and pulls you onto the ledge if floor is there.

**Mantle** — not implemented. `probe_forward()` and `landed()` are the hooks.

Slope friction was considered and cut: kinematic bodies have no friction (PhysicsMaterial
only affects rigid bodies — `move_and_slide` is vector projection, there's no coefficient
in the math), and the custom version only earns its keep in games where sliding is a
designed mechanic. `floor_stop_on_slope` covers the common case.

---

## Demo test rig

The demo geometry is a test rig, not a showcase. Everything wears a world-space
grid material so heights and motion are legible; warm-tinted objects are the ones
that exercise something specific.

| Object | Where | What it tests |
|---|---|---|
| `Stair1/2/3` | x -4 | Step-up on 18cm risers, and descent smoothness. |
| `TooTall` | x -8 | A 70cm ledge. Should **stop** you — proves step-up doesn't climb walls. |
| `Lip` | x +6 | 6cm floor seam. Should be unnoticeable — no snap, no step trigger. |
| `Ledge` | x -12 | 80cm-deep shelf at 1.0m, against a 1.1m jump. Too narrow to land in the middle, so you have to catch the lip. See below. |
| `Ramp25 / 45 / 55` | x +8 / +13 / +18 | Walkable, walkable, and not — the 50° limit sits between the last two. |
| `Overhang` | z -8 | Crouch under it and try to stand. Should stay crouched. |
| `Crate` | z -4 | The Interactable. Look at it, press E. |
| `PostA-D` | x +6, z 3/9/20/28 | Awareness tiers. Walk the line and watch tiers change in the HUD; PostD sits outside the 30m area entirely until you approach. |

A debug overlay (`demo/debug_hud.gd`) shows state, speed, FOV, ground/climb/crouch
flags, the current aim target and whether it's in range, every tracked object with
its tier and distance, and a rolling event log. It lives in `demo/` and isn't part
of the package — but it copies into a host project as-is, which is worth doing
during integration. Delete the demo folder and nothing under `scripts/` breaks.

**Testing edge snap properly:** it only fires when you land on a *corner*, so a
comfortable landing proves nothing. The real test is A/B — set `edge_snap_enabled`
to false on the config, jump at the `Ledge` lip a dozen times and count how many
times you visibly touch it and slide off. Turn it back on and repeat. If the
numbers are the same, the snap isn't doing anything.

## Known caveats

Written against Godot 4.6 and iterated against play testing, but not exhaustively
tuned. Confirmed: 4.6 has no built-in step offset, so `_try_step()` stays.

`FPLight` reparenting is deferred, because child `_ready` runs before the parent's.
Verifying via the scene tree at runtime is the right check — the lantern should sit
under Player, the flashlight under Head/HandRig.

---

## Distribution

Make this its own git repo and pull it into projects as a submodule rather than
copying the folder. You have several Godot projects; the moment you fix something in
`_try_step()` you want that fix everywhere, and copy-paste guarantees five diverging
versions inside a year.

`class_name` puts `FPPlayer`, `Interactable`, `FPLight` and the rest in the Add Node
dialog without needing an editor plugin, so a plain folder is structurally enough.

```
git submodule add <url> fp_player
git submodule update --init --recursive     # in each clone
git submodule update --remote fp_player     # pull package updates
```

**The path matters.** Scenes and resources here reference each other as
`res://fp_player/...`. Mount the submodule anywhere else and every reference
breaks. Pick the path once and keep it identical across projects.

**Never edit inside the submodule.** This is the footgun that bites on project
three, not project one:

- `resources/default_config.tres` is a **template**. Duplicate it into the host
  project (`res://game/player_config.tres`) and assign that to the player. Editing
  the template in place makes your tuning submodule-local — shared with every
  other project, shown as dirty submodule state, and lost on update.
- `player.tscn` is likewise a template. **Instance** it and override properties on
  the instance, or make an inherited scene. Don't edit it.

Anything you'd otherwise change inside the submodule is a sign the package needs
a new exported property — add it here, commit, and pull it everywhere.
