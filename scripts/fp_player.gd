class_name FPPlayer
extends CharacterBody3D

## Drop-in first person controller.
##
## Movement, look and crouch live together because they're one system -- crouch
## changes the capsule, which changes what movement can do. Everything genuinely
## separable (hand rig, awareness, lights, interactables) is its own node.
##
## The package emits signals and never calls into game systems. Health, stamina,
## inventory, weapons and HUD are all host-side; connect to what's below.

# ------------------------------------------------------------------ SIGNALS
signal state_changed(new_state: State, old_state: State)
## impact_velocity is positive metres/sec downward. Host decides fall damage.
signal landed(impact_velocity: float)
## Emitted every `stride_length` of ground travel. Host decides audio.
signal footstep(collider: Node, surface_normal: Vector3)
signal aim_target_changed(target: Interactable, previous: Interactable)
signal interacted(target: Interactable)
signal crouch_changed(is_crouched: bool)
signal stepped_up(height: float)
signal edge_snapped()
signal mouse_capture_changed(captured: bool)

enum State { IDLE, WALK, SPRINT, CROUCH, AIR, FLY }

# ------------------------------------------------------------------ EXPORTS
@export var config: FPPlayerConfig
## Layers the aim ray and ground/ceiling probes test against.
@export_flags_3d_physics var world_mask: int = 1

# ------------------------------------------------------------------ NODES
var head: Node3D
var camera_rig: Node3D
var hand_rig: FPHandRig
var camera: Camera3D
var aim_ray: RayCast3D
var hold_point: Marker3D
var ground_cast: ShapeCast3D
var ceiling_cast: ShapeCast3D
var awareness: FPAwareness
var body_shape: CollisionShape3D

# ------------------------------------------------------------------ STATE
var state: State = State.IDLE
var is_crouched: bool = false
var flying: bool = false
var mouse_captured: bool = false
var aim_target: Interactable = null

## Host-settable gate. Assign a Callable returning bool to block sprinting
## (stamina, encumbrance, injury). Left unset means always allowed.
var sprint_gate: Callable = Callable()

var _yaw: float = 0.0
var _pitch: float = 0.0
var _body_height: float = 1.8
var _coyote: float = 0.0
var _buffer: float = 0.0
var _was_grounded: bool = true
var _fall_speed: float = 0.0
var _stride_accum: float = 0.0
var _bob_phase: float = 0.0
var _dip: float = 0.0
var _smooth_offset: Vector3 = Vector3.ZERO
var _climbing: bool = false
var _climb_target_y: float = 0.0
var _climb_time: float = 0.0
var _floor_angle_rad: float = 0.87
var _capsule: CapsuleShape3D

var _has_fly := false
var _has_fly_up := false
var _has_fly_down := false
var _has_mouse_release := false


# ================================================================== LIFECYCLE
func _ready() -> void:
	if config == null:
		config = FPPlayerConfig.new()
	FPInput.register_defaults()
	_cache_optional_actions()
	_ensure_nodes()
	_apply_config()

	_yaw = rotation.y
	_pitch = head.rotation.x if head else 0.0
	_body_height = config.stand_height

	if config.auto_capture_mouse:
		capture_mouse()


func _notification(what: int) -> void:
	# Alt-tabbing out of a captured-mouse game and having it keep eating input
	# is a small thing that is irritating every single time.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mouse_captured:
		release_mouse()


func _cache_optional_actions() -> void:
	_has_fly = FPInput.enabled("toggle_fly")
	_has_fly_up = FPInput.enabled("fly_up")
	_has_fly_down = FPInput.enabled("fly_down")
	_has_mouse_release = FPInput.enabled("mouse_release")


func _apply_config() -> void:
	_floor_angle_rad = deg_to_rad(config.floor_max_angle_deg)
	floor_max_angle = _floor_angle_rad
	floor_snap_length = maxf(config.floor_snap_length, config.max_step_height)
	floor_stop_on_slope = true
	floor_constant_speed = config.constant_speed_on_slopes
	up_direction = Vector3.UP

	if _capsule:
		_capsule.radius = config.body_radius
		_capsule.height = config.stand_height
	if camera:
		camera.fov = config.base_fov
	if hand_rig:
		hand_rig.follow_speed = config.hand_follow_speed
	if aim_ray:
		aim_ray.target_position = Vector3(0, 0, -config.aim_distance)
		aim_ray.collision_mask = world_mask
	if awareness:
		awareness.setup(config)
	_apply_body_height(config.stand_height, true)


# ================================================================== INPUT
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		var m := event as InputEventMouseMotion
		var sign_y := -1.0 if config.invert_y else 1.0
		_yaw -= m.relative.x * config.mouse_sensitivity
		_pitch -= m.relative.y * config.mouse_sensitivity * sign_y
		_pitch = clampf(_pitch, deg_to_rad(config.pitch_min_deg), deg_to_rad(config.pitch_max_deg))
		rotation.y = _yaw
		head.rotation.x = _pitch

	if _has_mouse_release and event.is_action_pressed("mouse_release"):
		toggle_mouse_capture()

	if _has_fly and event.is_action_pressed("toggle_fly"):
		set_flying(not flying)

	if event.is_action_pressed("interact_general"):
		try_interact()


# ================================================================== PHYSICS
func _physics_process(delta: float) -> void:
	_update_aim()

	if flying:
		_process_fly(delta)
	else:
		_process_walk(delta)

	_update_camera_fx(delta)


func _process_walk(delta: float) -> void:
	var grounded := is_on_floor()

	# --- landing ---
	if grounded and not _was_grounded:
		var impact := absf(_fall_speed)
		if impact > 0.1:
			_dip = impact * config.land_dip_scale
			landed.emit(impact)
	_was_grounded = grounded
	_fall_speed = velocity.y

	# --- coyote / buffer ---
	if grounded:
		_coyote = config.coyote_time
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_buffer = config.jump_buffer
	else:
		_buffer = maxf(_buffer - delta, 0.0)

	# --- crouch ---
	_process_crouch(delta)

	# --- gravity ---
	if not grounded and not _climbing:
		var g := config.rise_gravity()
		if velocity.y < 0.0:
			g *= config.fall_gravity_multiplier
		velocity.y = maxf(velocity.y - g * delta, -config.max_fall_speed)

	# --- jump ---
	if _buffer > 0.0 and _coyote > 0.0 and not is_crouched:
		velocity.y = config.jump_velocity()
		_buffer = 0.0
		_coyote = 0.0
		grounded = false

	# --- horizontal ---
	var wish := _wish_direction()
	var speed := _target_speed()
	var accel := config.ground_accel if grounded else config.air_accel * config.air_control
	var decel := config.ground_decel if grounded else config.air_accel * config.air_control

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var target := wish * speed
	var rate := accel if wish.length_squared() > 0.0001 else decel
	flat = flat.move_toward(target, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	# --- stairs ---
	var before := global_position
	_update_step_climb(delta, grounded)
	if _climbing:
		velocity.y = 0.0

	# --- move ---
	move_and_slide()

	# --- edge snap ---
	if config.edge_snap_enabled and not _climbing and not is_on_floor() and velocity.y <= 0.0:
		_try_edge_snap()

	# --- footsteps ---
	if is_on_floor():
		var travelled := (global_position - before)
		travelled.y = 0.0
		_stride_accum += travelled.length()
		if _stride_accum >= config.stride_length:
			_stride_accum = 0.0
			_emit_footstep()

	_set_state(_resolve_state())


func _process_fly(delta: float) -> void:
	var wish := _wish_direction_3d()
	var speed := config.fly_speed
	if Input.is_action_pressed("sprint"):
		speed *= config.fly_sprint_multiplier
	velocity = velocity.move_toward(wish * speed, config.ground_accel * 2.0 * delta)
	move_and_slide()
	_set_state(State.FLY)


# ================================================================== STEP / EDGE
## Stairs, without teleporting.
##
## The old approach probed with the capsule itself and committed the whole
## transform at once. That works, but the capsule has to advance past its own
## radius in a single frame or the down-probe lands on the step's EDGE rather
## than its top -- an edge contact returns a steep normal and gets rejected. So
## the body jumps ~0.37m sideways, which you can feel.
##
## A ray has no radius. It can sample just past the riser, tell us how high the
## step's top surface is, and then the body only needs to move VERTICALLY. The
## horizontal never jumps at all -- normal movement carries you onto the tread
## once you're high enough.
##
## Worth knowing why any of this is needed: a capsule natively climbs a lip of
## r * (1 - cos(floor_max_angle)) with no code -- 12.5cm at r=0.35 and 50deg,
## which is why floor seams and modular-kit joins are invisible. Real stair
## risers are 15-20cm, just past it. Climbing 20cm natively would need a 65deg
## floor limit, and then you'd walk up cliffs.
func _update_step_climb(delta: float, grounded: bool) -> void:
	if config.max_step_height <= 0.0:
		return

	var flat := Vector3(velocity.x, 0.0, velocity.z)

	if _climbing:
		_climb_time += delta
		if _climb_time > 0.4 or not _advance_climb(delta, flat):
			_end_climb()
		else:
			# Hold full speed through the climb. Contact with the riser zeroes
			# horizontal velocity every frame, so without this you re-accelerate
			# from a standstill after each step -- roughly twice the cost of the
			# climb itself, and the real source of stair-by-stair hitching.
			var keep := _wish_direction() * _target_speed()
			velocity.x = keep.x
			velocity.z = keep.z
		return

	if not (grounded or _coyote > 0.0):
		return
	# Look ahead further than one frame, or the climb can't begin until contact
	# has already killed your speed.
	var intent := flat * maxf(delta, config.step_lookahead)
	if intent.length_squared() < 0.000001:
		return

	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, intent, hit):
		return
	# Walkable contact: the capsule will ride up on its own, don't interfere.
	if hit.get_normal().angle_to(Vector3.UP) <= _floor_angle_rad:
		return

	var top := _probe_step_top(flat.normalized())
	if is_nan(top):
		return

	_climbing = true
	_climb_target_y = top
	_climb_time = 0.0
	# Snapping would drag us straight back down onto the lower tread mid-climb.
	floor_snap_length = 0.0
	stepped_up.emit(top - global_position.y)


## Height of the walkable surface just past whatever blocked us, or NAN.
## Three rays across the body width, so a single gap or bolt head can't fool it.
func _probe_step_top(dir: Vector3) -> float:
	if dir.length_squared() < 0.0001:
		return NAN
	var space := get_world_3d().direct_space_state
	var ahead := dir * (config.body_radius + config.step_forward_margin + 0.02)
	var side := dir.cross(Vector3.UP).normalized() * (config.body_radius * 0.55)
	var best := -INF

	for lateral: float in [0.0, 1.0, -1.0]:
		var base := global_position + ahead + side * lateral
		var q := PhysicsRayQueryParameters3D.create(
			base + Vector3.UP * (config.max_step_height + 0.05),
			base - Vector3.UP * 0.05)
		q.collision_mask = world_mask
		q.exclude = [get_rid()]
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var n: Vector3 = r.normal
		if n.angle_to(Vector3.UP) > _floor_angle_rad:
			continue
		var pos: Vector3 = r.position
		best = maxf(best, pos.y)

	if best == -INF:
		return NAN
	var rise := best - global_position.y
	if rise <= 0.005 or rise > config.max_step_height:
		return NAN
	return best


func _advance_climb(delta: float, flat: Vector3) -> bool:
	# Stop pushing forward and the climb aborts rather than completing. Otherwise
	# you'd finish rising, find nothing under you, and drop -- a pop and a fall.
	# Physics stays live through the climb, so it can be interrupted; that's the
	# difference between driving the body along a path and interpolating to a
	# known endpoint.
	if flat.length() < 0.15:
		return false
	var remaining := _climb_target_y - global_position.y
	if remaining <= 0.002:
		return false
	# Climb faster when moving faster, or you get stuck against stairs at a sprint.
	var speed := config.step_climb_speed * maxf(1.0, flat.length() / maxf(config.walk_speed, 0.01))
	var rise := minf(speed * delta, remaining)
	if test_move(global_transform, Vector3.UP * rise):
		return false
	global_position.y += rise
	velocity.y = 0.0
	return true


func _end_climb() -> void:
	_climbing = false
	_climb_time = 0.0
	floor_snap_length = maxf(config.floor_snap_length, config.max_step_height)


## A sharp edge has no surface -- contact with a corner produces a normal
## pointing diagonally away from it, and the solver can't tell a 2cm lip from a
## hillside, so gravity gets projected along it and you slide off something you
## visibly landed on. This pulls you back inboard when there's floor there.
func _try_edge_snap() -> bool:
	var steep := Vector3.ZERO
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y > 0.05 and n.angle_to(Vector3.UP) > _floor_angle_rad:
			steep = n
			break
	if steep == Vector3.ZERO:
		return false

	var inward := Vector3(steep.x, 0.0, steep.z)
	if inward.length_squared() < 0.0001:
		return false
	inward = -inward.normalized() * config.body_radius

	if test_move(global_transform, inward):
		return false

	var xform := global_transform
	xform.origin += inward
	var col := KinematicCollision3D.new()
	if not test_move(xform, Vector3.DOWN * (config.max_step_height + 0.2), col):
		return false
	if col.get_normal().angle_to(Vector3.UP) > _floor_angle_rad:
		return false

	var target := xform.origin + col.get_travel()
	_absorb(global_position, target)
	global_position = target
	velocity.y = 0.0
	edge_snapped.emit()
	return true


# ================================================================== CROUCH
func _process_crouch(delta: float) -> void:
	var want := Input.is_action_pressed("crouch")
	if is_crouched and not want and _blocked_overhead():
		want = true   # can't stand up yet

	if want != is_crouched:
		is_crouched = want
		crouch_changed.emit(is_crouched)

	var target_h := config.crouch_height if is_crouched else config.stand_height
	if not is_equal_approx(_body_height, target_h):
		var h := move_toward(_body_height, target_h,
			absf(config.stand_height - config.crouch_height) * config.crouch_transition_speed * delta)
		_apply_body_height(h, false)


func _apply_body_height(h: float, immediate: bool) -> void:
	_body_height = h
	if _capsule:
		_capsule.height = maxf(h, config.body_radius * 2.0 + 0.01)
	if body_shape:
		# Capsule is centred; keep the feet planted.
		body_shape.position.y = _capsule.height * 0.5
	if head:
		head.position.y = config.eye_height(h)
	if ceiling_cast:
		ceiling_cast.position.y = _capsule.height
		ceiling_cast.target_position = Vector3(0, config.stand_height - h + 0.05, 0)
	if immediate and hand_rig:
		hand_rig.snap()


func _blocked_overhead() -> bool:
	if ceiling_cast == null:
		return false
	ceiling_cast.force_shapecast_update()
	return ceiling_cast.is_colliding()


# ================================================================== AIM
func _update_aim() -> void:
	var found: Interactable = null
	if aim_ray:
		aim_ray.force_raycast_update()
		if aim_ray.is_colliding():
			found = Interactable.find_on(aim_ray.get_collider() as Node)
	if found != aim_target:
		var prev := aim_target
		if prev and is_instance_valid(prev):
			prev.notify_focus(false, self)
		aim_target = found
		if found:
			found.notify_focus(true, self)
		aim_target_changed.emit(found, prev)


func try_interact() -> bool:
	var t := aim_target
	if t == null or not is_instance_valid(t):
		return false
	if not in_interact_range(t):
		return false
	if t.try_interact(self):
		interacted.emit(t)
		return true
	return false


## The ray says WHAT you're looking at; awareness says whether it's close enough.
## Keeping those separate is what lets you read a machine's status from 20m and
## still have to walk up to pull the lever.
func in_interact_range(t: Interactable) -> bool:
	if t.required_tier < 0:
		return true                       # any range
	if awareness == null:
		return true
	var gate: int = mini(t.required_tier, config.interact_tier)
	var tier := awareness.tier_of(t)
	return tier != -1 and tier <= gate


## Hold the camera at `from` while the body jumps to `to`, then let it catch up.
func _absorb(from: Vector3, to: Vector3) -> void:
	_smooth_offset += from - to
	_smooth_offset = _smooth_offset.limit_length(config.max_step_height + config.body_radius + 0.2)


# ================================================================== CAMERA FX
func _update_camera_fx(delta: float) -> void:
	if camera_rig == null:
		return
	var offset := Vector3.ZERO

	if config.bob_enabled and is_on_floor() and not flying:
		var flat := Vector3(velocity.x, 0.0, velocity.z).length()
		var ratio := clampf(flat / maxf(config.walk_speed, 0.01), 0.0, 2.0)
		# One full lateral cycle per two strides; vertical peaks twice per cycle,
		# i.e. once per footfall. Phase advances with distance, not time, so bob
		# stays in step with the legs at any speed.
		var per_metre := TAU / maxf(config.stride_length * 2.0, 0.01)
		_bob_phase += delta * flat * per_metre * config.bob_speed_scale
		offset.y += sin(_bob_phase * 2.0) * config.bob_amplitude * ratio
		offset.x += sin(_bob_phase) * config.bob_sway * ratio
	else:
		_bob_phase = 0.0

	if _dip > 0.0:
		offset.y -= _dip
		_dip = move_toward(_dip, 0.0, config.land_dip_recovery * delta * maxf(_dip, 0.05))

	if _smooth_offset.length_squared() > 0.000001:
		# The body has to teleport for step-up and edge snap to stay deterministic.
		# The camera doesn't: hold it where it was and glide it back. Converted into
		# Head's local space so it works on any axis, not just vertically -- the
		# forward reach of a step is what you notice when moving sideways.
		offset += head.global_transform.basis.inverse() * _smooth_offset
		_smooth_offset = _smooth_offset.lerp(Vector3.ZERO,
			1.0 - exp(-config.step_smooth_recovery * delta))
	else:
		_smooth_offset = Vector3.ZERO

	camera_rig.position = camera_rig.position.lerp(offset, 1.0 - exp(-20.0 * delta))

	if camera:
		var want_fov := config.base_fov
		if state == State.SPRINT:
			want_fov += config.sprint_fov_add
		camera.fov = lerpf(camera.fov, want_fov, 1.0 - exp(-config.fov_lerp_speed * delta))


# ================================================================== HELPERS
func _wish_direction() -> Vector3:
	var input := Input.get_vector("strafe_left", "strafe_right", "walk_forward", "walk_backward")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


func _wish_direction_3d() -> Vector3:
	var input := Input.get_vector("strafe_left", "strafe_right", "walk_forward", "walk_backward")
	var dir := camera.global_transform.basis * Vector3(input.x, 0.0, input.y)
	if _has_fly_up and Input.is_action_pressed("fly_up"):
		dir.y += 1.0
	if _has_fly_down and Input.is_action_pressed("fly_down"):
		dir.y -= 1.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


func can_sprint() -> bool:
	if is_crouched:
		return false
	if sprint_gate.is_valid():
		return bool(sprint_gate.call())
	return true


func _target_speed() -> float:
	if is_crouched:
		return config.crouch_speed
	if Input.is_action_pressed("sprint") and can_sprint():
		return config.sprint_speed
	return config.walk_speed


func _resolve_state() -> State:
	if flying:
		return State.FLY
	if not is_on_floor() and not _climbing:
		return State.AIR
	if is_crouched:
		return State.CROUCH
	var flat := Vector3(velocity.x, 0.0, velocity.z).length()
	if flat < 0.15:
		return State.IDLE
	if flat > config.walk_speed + 0.5:
		return State.SPRINT
	return State.WALK


func _set_state(s: State) -> void:
	if s == state:
		return
	var old := state
	state = s
	state_changed.emit(s, old)


func _emit_footstep() -> void:
	var collider: Node = null
	var normal := Vector3.UP
	if ground_cast:
		ground_cast.force_shapecast_update()
		if ground_cast.is_colliding():
			collider = ground_cast.get_collider(0) as Node
			normal = ground_cast.get_collision_normal(0)
	footstep.emit(collider, normal)


# ================================================================== PUBLIC API
func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true
	mouse_capture_changed.emit(true)


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false
	mouse_capture_changed.emit(false)


func toggle_mouse_capture() -> void:
	if mouse_captured:
		release_mouse()
	else:
		capture_mouse()


func set_flying(v: bool) -> void:
	flying = v
	velocity = Vector3.ZERO


func teleport(to: Vector3) -> void:
	global_position = to
	velocity = Vector3.ZERO
	_smooth_offset = Vector3.ZERO
	_dip = 0.0
	_end_climb()
	if hand_rig:
		hand_rig.snap()


## Level-three hook. "Am I sheltered" is a weather question wearing a player
## controller costume -- this exposes the probe and lets the host decide what
## shelter means (mask, distance, how many samples).
func check_overhead(distance: float = 20.0, mask: int = -1) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * _body_height
	var params := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * distance)
	params.collision_mask = mask if mask >= 0 else world_mask
	params.exclude = [get_rid()]
	return space.intersect_ray(params)


## Level-three hook for mantling: what's in front of you at chest height.
func probe_forward(distance: float = 1.0, height_ratio: float = 0.6) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * (_body_height * height_ratio)
	var fwd := -global_transform.basis.z
	var params := PhysicsRayQueryParameters3D.create(from, from + fwd * distance)
	params.collision_mask = world_mask
	params.exclude = [get_rid()]
	return space.intersect_ray(params)


## True while a step climb is in progress.
func is_step_climbing() -> bool:
	return _climbing


func get_eye_transform() -> Transform3D:
	return camera.global_transform if camera else global_transform


# ================================================================== SELF-HEAL
## Builds any missing child so the controller survives being restructured, and
## so a bare CharacterBody3D with this script attached still runs.
func _ensure_nodes() -> void:
	body_shape = null
	for c in get_children():
		if c is CollisionShape3D:
			body_shape = c as CollisionShape3D
			break
	if body_shape == null:
		body_shape = CollisionShape3D.new()
		body_shape.name = "BodyShape"
		add_child(body_shape)
	if not (body_shape.shape is CapsuleShape3D):
		body_shape.shape = CapsuleShape3D.new()
	_capsule = body_shape.shape as CapsuleShape3D

	head = get_node_or_null("Head")
	if head == null:
		head = Node3D.new()
		head.name = "Head"
		add_child(head)

	camera_rig = head.get_node_or_null("CameraRig")
	if camera_rig == null:
		camera_rig = Node3D.new()
		camera_rig.name = "CameraRig"
		head.add_child(camera_rig)

	hand_rig = head.get_node_or_null("HandRig") as FPHandRig
	if hand_rig == null:
		hand_rig = FPHandRig.new()
		hand_rig.name = "HandRig"
		head.add_child(hand_rig)

	camera = camera_rig.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera_rig.add_child(camera)
	camera.current = true

	aim_ray = camera.get_node_or_null("AimRay") as RayCast3D
	if aim_ray == null:
		aim_ray = RayCast3D.new()
		aim_ray.name = "AimRay"
		camera.add_child(aim_ray)
	aim_ray.enabled = true

	hold_point = hand_rig.get_node_or_null("HoldPoint") as Marker3D
	if hold_point == null:
		hold_point = Marker3D.new()
		hold_point.name = "HoldPoint"
		hold_point.position = Vector3(0, -0.2, -1.2)
		hand_rig.add_child(hold_point)

	ground_cast = get_node_or_null("GroundCast") as ShapeCast3D
	if ground_cast == null:
		ground_cast = ShapeCast3D.new()
		ground_cast.name = "GroundCast"
		add_child(ground_cast)
	if not (ground_cast.shape is SphereShape3D):
		ground_cast.shape = SphereShape3D.new()
	(ground_cast.shape as SphereShape3D).radius = config.body_radius * 0.9
	ground_cast.position = Vector3(0, config.body_radius, 0)
	ground_cast.target_position = Vector3(0, -(config.body_radius + 0.25), 0)
	ground_cast.collision_mask = world_mask
	ground_cast.enabled = true

	ceiling_cast = get_node_or_null("CeilingCast") as ShapeCast3D
	if ceiling_cast == null:
		ceiling_cast = ShapeCast3D.new()
		ceiling_cast.name = "CeilingCast"
		add_child(ceiling_cast)
	if not (ceiling_cast.shape is SphereShape3D):
		ceiling_cast.shape = SphereShape3D.new()
	(ceiling_cast.shape as SphereShape3D).radius = config.body_radius * 0.95
	ceiling_cast.collision_mask = world_mask
	ceiling_cast.enabled = true

	awareness = get_node_or_null("Awareness") as FPAwareness
	if awareness == null:
		awareness = FPAwareness.new()
		awareness.name = "Awareness"
		add_child(awareness)
