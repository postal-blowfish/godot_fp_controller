extends CanvasLayer

## Demo-only diagnostic overlay. Not part of the package, but it copies into a
## host project cleanly if you want it during integration -- delete the demo
## folder and nothing under scripts/ breaks.

@export var player_path: NodePath = ^"../Player"

var player: FPPlayer
var _label: Label
var _events: Array[String] = []
var _steps: int = 0
var _snaps: int = 0
var _footsteps: int = 0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)

	player = get_node_or_null(player_path) as FPPlayer
	if player == null:
		_label.text = "DebugHUD: no FPPlayer at %s" % player_path
		set_process(false)
		return

	player.stepped_up.connect(_on_stepped_up)
	player.edge_snapped.connect(_on_edge_snapped)
	player.landed.connect(_on_landed)
	player.crouch_changed.connect(_on_crouch)
	player.footstep.connect(_on_footstep)
	player.interacted.connect(_on_interacted)
	player.aim_target_changed.connect(_on_aim_changed)
	if player.awareness:
		player.awareness.tier_changed.connect(_on_tier_changed)


func _on_stepped_up(height: float) -> void:
	_steps += 1
	_push("step up %.2fm" % height)


func _on_edge_snapped() -> void:
	_snaps += 1
	_push("EDGE SNAP")


func _on_landed(impact: float) -> void:
	_push("landed %.1f m/s" % impact)


func _on_crouch(crouched: bool) -> void:
	_push("crouch %s" % ("on" if crouched else "off"))


func _on_footstep(_collider: Node, _normal: Vector3) -> void:
	_footsteps += 1


func _on_interacted(target: Interactable) -> void:
	_push("used \"%s\"" % target.prompt)


func _on_aim_changed(target: Interactable, _previous: Interactable) -> void:
	if target != null:
		_push("aim -> %s" % target.get_subject().name)


func _on_tier_changed(it: Interactable, new_tier: int, old_tier: int) -> void:
	_push("%s tier %s -> %s" % [it.get_subject().name, _tier(old_tier), _tier(new_tier)])


func _push(msg: String) -> void:
	_events.push_front(msg)
	while _events.size() > 7:
		_events.pop_back()


func _tier(t: int) -> String:
	return "out" if t < 0 else str(t)


func _yn(v: bool) -> String:
	return "yes" if v else "no"


func _process(_delta: float) -> void:
	var flat := Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	var lines: Array[String] = []

	lines.append("state %s   speed %.2f m/s   fov %.1f" % [
		FPPlayer.State.keys()[player.state], flat, player.camera.fov])
	lines.append("floor %s   climbing %s   crouch %s   fly %s   mouse %s" % [
		_yn(player.is_on_floor()), _yn(player.is_step_climbing()),
		_yn(player.is_crouched), _yn(player.flying), _yn(player.mouse_captured)])
	lines.append("steps %d   edge snaps %d   footsteps %d" % [_steps, _snaps, _footsteps])
	lines.append("")

	var aim := player.aim_target
	if aim != null:
		lines.append("AIM  %s  \"%s\"  tier %s  %s" % [
			aim.get_subject().name, aim.prompt,
			_tier(player.awareness.tier_of(aim)),
			"IN RANGE - press E" if player.in_interact_range(aim) else "too far"])
	else:
		lines.append("AIM  -")
	lines.append("")

	lines.append("AWARENESS  tier radii %s" % str(player.config.awareness_tiers))
	var tracked := player.awareness.get_tracked()
	if tracked.is_empty():
		lines.append("   (nothing tracked)")
	else:
		var rows: Array[String] = []
		for it: Interactable in tracked.keys():
			var subj := it.get_subject() as Node3D
			if subj == null:
				continue
			rows.append("   %-8s %5.1fm   tier %s" % [
				subj.name,
				player.global_position.distance_to(subj.global_position),
				_tier(int(tracked[it]))])
		rows.sort()
		lines.append_array(rows)
	lines.append("")

	lines.append("EVENTS")
	for e in _events:
		lines.append("   " + e)

	_label.text = "\n".join(lines)
