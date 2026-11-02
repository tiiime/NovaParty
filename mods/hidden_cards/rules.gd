extends RefCounted
# Test game: three simultaneous high-card rounds, not a standard poker variant.
func initial_state(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var deck := range(52)
	for i in range(51, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = deck[i]
		deck[i] = deck[j]
		deck[j] = swap
	return {"deck": deck.slice(6), "hands": [deck.slice(0, 3), deck.slice(3, 6)], "chosen": [-1, -1], "round": 0, "history": [], "scores": [0, 0], "finished": false}

func apply(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	if state.finished:
		return {"error": "game_finished"}
	var card = action.get("card")
	if action.get("type") != "choose" or not (card is int or card is float) or card != int(card):
		return {"error": "invalid_action"}
	card = int(card)
	if state.chosen[seat] != -1:
		return {"error": "already_chosen"}
	if not state.hands[seat].has(card):
		return {"error": "card_not_owned"}
	state.chosen[seat] = card
	if state.chosen[0] != -1 and state.chosen[1] != -1:
		var a: int = int(state.chosen[0]) % 13
		var b: int = int(state.chosen[1]) % 13
		if a != b:
			state.scores[0 if a > b else 1] += 1
		state.history.append(state.chosen.duplicate())
		for player in range(2):
			state.hands[player].erase(state.chosen[player])
		state.chosen = [-1, -1]
		state.round += 1
		state.finished = state.round == 3
	return {"state": state}

func view_for(state: Dictionary, seat: int) -> Dictionary:
	return {"hand": state.hands[seat].duplicate(), "chosen": state.chosen[seat], "submitted": [state.chosen[0] != -1, state.chosen[1] != -1], "counts": [state.hands[0].size(), state.hands[1].size()], "round": state.round, "history": state.history.duplicate(true), "scores": state.scores.duplicate(), "finished": state.finished}

func describe_actions(view: Dictionary, _seat: int) -> Dictionary:
	var legal := []
	if not view.finished and view.chosen == -1:
		for card in view.hand:
			legal.append({"type": "choose", "card": card})
	return {"schema": {"type": "object", "required": ["type", "card"], "properties": {"type": {"const": "choose"}, "card": {"type": "integer", "enum": view.hand.duplicate()}}, "additionalProperties": false}, "legal_actions": legal}
