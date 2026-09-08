# Changelog

## v0.1.0

First working version. Validated in the demo scene: movement, look, jump, slopes,
stairs, edge snap, crouch, lights on all three mounts, fly, aim and interaction,
awareness tiers.

Notes on decisions that took iteration, so they don't get relitigated:

- **Step-up moves the body vertically, never horizontally.** An earlier version
  probed with the capsule and teleported the whole transform, which forced a
  ~0.37m sideways jump (the capsule must clear its own radius or the down-probe
  lands on the step's edge and gets rejected as unwalkable). Rays have no radius,
  so the height can be sampled without moving horizontally at all.
- **Horizontal speed is held through a climb.** Wall contact zeroes velocity, and
  re-accelerating from a standstill cost ~90ms per step — twice the climb itself,
  and the real source of stair-by-stair hitching.
- **`floor_constant_speed` is off.** With it on, climbing a slope keeps full
  horizontal speed and reads as powered rather than effortful.
- **`floor_max_angle` is 50, not 45.** A ramp authored at exactly 45 against a 45
  limit is a float coin-flip.
- **Step-up only fires on surfaces too steep to walk.** A capsule natively climbs
  `radius * (1 - cos(floor_max_angle))` — 12.5cm at the defaults. Firing the step
  on anything below that turns an invisible floor seam into a felt teleport.
- **`Interactable.find_on()` search depth is bounded.** An unbounded walk reaches
  the scene root and can match an unrelated sibling's Interactable.
