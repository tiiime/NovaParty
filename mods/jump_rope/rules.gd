extends RefCounted
const CAPACITY = 5 # One display plus up to four controllers.

func initial_state(_seed_value: int) -> Dictionary:
	var slots := []
	for seat in range(CAPACITY):
		slots.append({"role": "none", "count": 0, "generation": 1 if seat == 0 else 0})
	return {"slots": slots}

func presence_changed(state: Dictionary, seat: int, _connected: bool) -> Dictionary:
	state.slots[seat] = {"role": "none", "count": 0, "generation": int(state.slots[seat].generation) + 1}
	return state

func apply(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	if seat < 0 or seat >= CAPACITY:
		return {"error": "invalid_action"}
	var slot: Dictionary = state.slots[seat]
	if action.get("generation") != slot.generation:
		return {"error": "stale_generation"}
	match action.get("type"):
		"role":
			var role = action.get("role")
			if role not in ["display", "controller", "none"]:
				return {"error": "invalid_action"}
			if role == "controller" and slot.role != role:
				var active := 0
				for other in state.slots:
					if other.role == "controller":
						active += 1
				if active >= 4:
					return {"error": "controllers_full"}
			if slot.role != role:
				slot.role = role
				slot.count = 0
				slot.generation += 1
		"jump":
			var count = action.get("count")
			if slot.role != "controller" or not (count is int or count is float) or count != int(count) or count < slot.count or count > slot.count + 16 or count > 1000000:
				return {"error": "invalid_action"}
			# Absolute counters make retries and simultaneous controllers independent.
			slot.count = int(count)
		_:
			return {"error": "invalid_action"}
	return {"state": state}

func view_for(state: Dictionary, _seat: int) -> Dictionary:
	return state.duplicate(true)

func describe_actions(view: Dictionary, seat: int) -> Dictionary:
	return {"schema": {"type": "object", "required": ["type", "generation"], "properties": {"type": {"enum": ["role", "jump"]}, "generation": {"const": view.slots[seat].generation}, "role": {"enum": ["display", "controller", "none"]}, "count": {"type": "integer", "minimum": 0}}}, "legal_actions": []}
