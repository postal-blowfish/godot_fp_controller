extends Interactable

## The whole contract, demonstrated. Extend Interactable, fill in default_action.
## Everything else -- prompt text, range gating, focus signals -- is inherited.

var opened: bool = false


func default_action(who: Node) -> void:
	opened = not opened
	prompt = "Close crate" if opened else "Open crate"
	print("[demo] crate %s by %s" % ["opened" if opened else "closed", who.name])
	interacted.emit(who)
