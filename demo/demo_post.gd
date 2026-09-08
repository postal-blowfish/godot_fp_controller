extends Interactable

## Marker post used to exercise awareness tiers at range.

func default_action(who: Node) -> void:
	print("[demo] %s used by %s" % [get_subject().name, who.name])
	interacted.emit(who)
