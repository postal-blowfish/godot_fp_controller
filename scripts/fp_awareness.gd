class_name FPAwareness
extends Area3D

## One Area3D sized to the largest tier, tracking whatever is inside it, with
## tier resolved per-node by squared distance on a timer.
##
## Deliberately not three nested Areas: that would mean three sets of enter/exit
## bookkeeping per object and the radii baked into the scene rather than the
## config. Here the tier count is whatever length `awareness_tiers` happens to be,
## so one project can have three and another can have one, from the same node.

signal tier_changed(interactable: Interactable, new_tier: int, old_tier: int)

var config: FPPlayerConfig
var _tracked: Dictionary = {}   # Interactable -> tier int
var _accum: float = 0.0
var _shape: SphereShape3D


func setup(cfg: FPPlayerConfig) -> void:
	config = cfg
	monitoring = true
	monitorable = false

	var owner_shape: CollisionShape3D = null
	for c in get_children():
		if c is CollisionShape3D:
			owner_shape = c
			break
	if owner_shape == null:
		owner_shape = CollisionShape3D.new()
		owner_shape.name = "AwarenessShape"
		add_child(owner_shape)

	_shape = SphereShape3D.new()
	_shape.radius = config.max_awareness_radius()
	owner_shape.shape = _shape

	if not body_entered.is_connected(_on_entered):
		body_entered.connect(_on_entered)
		body_exited.connect(_on_exited)
		area_entered.connect(_on_entered)
		area_exited.connect(_on_exited)


func _physics_process(delta: float) -> void:
	if config == null:
		return
	var interval := 1.0 / maxf(config.awareness_tick_hz, 1.0)
	_accum += delta
	if _accum < interval:
		return
	_accum = 0.0
	_tick()


func _tick() -> void:
	var origin := global_position
	var stale: Array[Interactable] = []
	for it: Interactable in _tracked.keys():
		if not is_instance_valid(it):
			stale.append(it)
			continue
		var subject := it.get_subject() as Node3D
		if subject == null:
			stale.append(it)
			continue
		var d := origin.distance_to(subject.global_position)
		var new_tier := config.tier_for_distance(d)
		var old_tier: int = _tracked[it]
		if new_tier != old_tier:
			_tracked[it] = new_tier
			it.set_tier(new_tier)
			tier_changed.emit(it, new_tier, old_tier)
	for dead in stale:
		_tracked.erase(dead)


func _on_entered(node: Node) -> void:
	var it := Interactable.find_on(node)
	if it == null or _tracked.has(it):
		return
	_tracked[it] = -1


func _on_exited(node: Node) -> void:
	var it := Interactable.find_on(node)
	if it == null or not _tracked.has(it):
		return
	var old: int = _tracked[it]
	_tracked.erase(it)
	if old != -1:
		it.set_tier(-1)
		tier_changed.emit(it, -1, old)


## Everything currently at or inside `tier`.
func get_at_tier(tier: int) -> Array[Interactable]:
	var out: Array[Interactable] = []
	for it: Interactable in _tracked.keys():
		var t: int = _tracked[it]
		if t != -1 and t <= tier:
			out.append(it)
	return out


## Everything currently inside the outermost tier, with its tier.
func get_tracked() -> Dictionary:
	return _tracked.duplicate()


func tier_of(it: Interactable) -> int:
	if not _tracked.has(it):
		return -1
	return int(_tracked[it])
