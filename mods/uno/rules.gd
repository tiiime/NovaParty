extends RefCounted
const Cards = preload("cards.gd")

func initial_state(seed_value: int) -> Dictionary:
	var hands := []
	for _i in range(Cards.CAPACITY): hands.append([])
	return {"seed": seed_value, "shuffles": 0, "phase": "lobby", "display_seat": 0, "connected": [false, false, false, false, false, false, false], "participants": [], "hands": hands, "deck": [], "discard": [], "turn": -1, "direction": 1, "color": 0, "debt": 0, "debt_kind": "", "drawn": -1, "uno_target": -1, "winner": -1, "score": 0, "round": 0, "votes": [], "last": {}}

func can_join(state: Dictionary) -> bool:
	return state.phase == "lobby" and _player_count(state) < 6

func _player_count(state: Dictionary) -> int:
	return state.connected.count(true) - (1 if state.display_seat == 0 and state.connected[0] else 0)

func presence_changed(state: Dictionary, seat: int, connected: bool) -> Dictionary:
	state.connected[seat] = connected
	return state

func _paused(state: Dictionary) -> bool:
	for seat in state.participants:
		if not state.connected[int(seat)]: return true
	return false

func _shuffle(state: Dictionary, values: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(state.seed) + int(state.shuffles) * 104729
	state.shuffles += 1
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var item = values[i]
		values[i] = values[j]
		values[j] = item

func _deal(state: Dictionary) -> void:
	# Rematches preserve the round membership, even if an inactive lobby seat
	# reconnects after the first deal. Only a new lobby can enroll players.
	if state.phase == "lobby":
		state.participants = []
		for seat in range(Cards.CAPACITY):
			if state.connected[seat] and seat != state.display_seat: state.participants.append(seat)
	for seat in range(Cards.CAPACITY):
		state.hands[seat] = []
	state.deck = range(108)
	_shuffle(state, state.deck)
	for _card in range(7):
		for seat in state.participants: state.hands[int(seat)].append(state.deck.pop_back())
	# Explicit party rule: start with a number card, avoiding an initial penalty.
	for i in range(state.deck.size() - 1, -1, -1):
		if Cards.info(int(state.deck[i])).rank.is_valid_int():
			state.discard = [state.deck[i]]
			state.deck.remove_at(i)
			break
	state.phase = "playing"
	state.turn = state.participants[1]
	state.direction = 1
	state.color = Cards.info(int(state.discard.back())).color
	state.debt = 0
	state.debt_kind = ""
	state.drawn = -1
	state.uno_target = -1
	state.winner = -1
	state.score = 0
	state.votes = []
	state.round += 1
	state.last = {"type": "start", "seat": 0}

func _next(state: Dictionary, seat: int, steps: int = 1) -> int:
	var index: int = Cards.index_number(state.participants, seat)
	return int(state.participants[posmod(index + steps * int(state.direction), state.participants.size())])

func _draw(state: Dictionary, seat: int, count: int) -> Array:
	var cards := []
	for _i in range(count):
		if state.deck.is_empty():
			if state.discard.size() <= 1: break
			var top = state.discard.pop_back()
			state.deck = state.discard.duplicate()
			state.discard = [top]
			_shuffle(state, state.deck)
		var card = state.deck.pop_back()
		state.hands[seat].append(card)
		cards.append(card)
	return cards

func _advance(state: Dictionary, steps: int = 1) -> void:
	state.turn = _next(state, int(state.turn), steps)
	state.drawn = -1

func _finish(state: Dictionary, winner: int) -> void:
	# Ending on a penalty card settles that debt before scoring; no post-win stacking.
	if int(state.debt) > 0:
		_draw(state, _next(state, winner), int(state.debt))
	state.debt = 0
	state.debt_kind = ""
	state.phase = "finished"
	state.winner = winner
	state.uno_target = -1
	state.drawn = -1
	state.score = 0
	for seat in state.participants:
		for card in state.hands[int(seat)]: state.score += int(Cards.info(int(card)).points)

func apply(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	if not Cards.integer(seat, 0, Cards.CAPACITY - 1) or not state.connected[seat]:
		return {"error": "player_offline"}
	var kind = action.get("type")
	if kind == "table_mode":
		if state.phase != "lobby" or seat != 0: return {"error": "host_only"}
		if not action.get("enabled") is bool: return {"error": "invalid_action"}
		if not action.enabled and state.connected.count(true) > 6: return {"error": "too_many_players"}
		state.display_seat = 0 if action.enabled else -1
		return {"state": state}
	if kind == "start":
		if state.phase != "lobby" or seat != 0: return {"error": "host_only"}
		if _player_count(state) < 2: return {"error": "waiting_for_players"}
		if _player_count(state) > 6: return {"error": "too_many_players"}
		_deal(state)
		return {"state": state}
	if state.phase == "lobby": return {"error": "not_started"}
	if not Cards.contains_number(state.participants, seat): return {"error": "not_a_player"}
	if _paused(state): return {"error": "players_disconnected"}
	if kind == "rematch":
		if state.phase != "finished": return {"error": "game_not_finished"}
		if Cards.contains_number(state.votes, seat): return {"error": "already_requested"}
		state.votes.append(seat)
		if state.votes.size() == state.participants.size(): _deal(state)
		return {"state": state}
	if state.phase == "finished": return {"error": "game_finished"}
	if kind == "uno":
		if state.uno_target != seat: return {"error": "uno_unavailable"}
		state.uno_target = -1
		state.last = {"type": "uno", "seat": seat}
		return {"state": state}
	if kind == "catch":
		if int(state.uno_target) < 0 or state.uno_target == seat: return {"error": "catch_unavailable"}
		var offender: int = int(state.uno_target)
		var amount := _draw(state, offender, 2).size()
		state.uno_target = -1
		state.last = {"type": "catch", "seat": offender, "amount": amount}
		return {"state": state}
	if seat != state.turn: return {"error": "not_your_turn"}
	if kind == "draw":
		if state.drawn != -1: return {"error": "already_drew"}
		state.uno_target = -1
		var penalty := int(state.debt)
		var picked := _draw(state, seat, penalty if penalty > 0 else 1)
		state.last = {"type": "draw", "seat": seat, "amount": picked.size()}
		if penalty > 0:
			state.debt = 0
			state.debt_kind = ""
			_advance(state)
		elif picked.is_empty() or not Cards.matches(int(picked[0]), _table(state)):
			_advance(state)
		else:
			state.drawn = picked[0]
		return {"state": state}
	if kind == "pass":
		if state.drawn == -1: return {"error": "draw_before_pass"}
		state.uno_target = -1
		_advance(state)
		return {"state": state}
	if kind != "play": return {"error": "invalid_action"}
	var value = action.get("card")
	if not Cards.integer(value, 0, 107): return {"error": "invalid_action"}
	var card := int(value)
	if not Cards.contains_number(state.hands[seat], card): return {"error": "card_not_owned"}
	if state.drawn != -1 and state.drawn != card: return {"error": "drawn_card_only"}
	if not Cards.matches(card, _table(state)): return {"error": "card_not_playable"}
	var info := Cards.info(card)
	if info.color == -1 and not Cards.integer(action.get("color"), 0, 3): return {"error": "choose_color"}
	if action.has("uno") and not action.uno is bool: return {"error": "invalid_action"}
	state.uno_target = -1
	state.hands[seat].remove_at(Cards.index_number(state.hands[seat], card))
	state.discard.append(card)
	state.color = int(action.color) if info.color == -1 else info.color
	state.drawn = -1
	state.last = {"type": "play", "seat": seat, "card": card}
	if info.rank in ["draw2", "draw4"]:
		state.debt += 2 if info.rank == "draw2" else 4
		state.debt_kind = info.rank
	if state.hands[seat].is_empty():
		_finish(state, seat)
		return {"state": state}
	if state.hands[seat].size() == 1 and not action.get("uno", false): state.uno_target = seat
	if info.rank == "reverse": state.direction = -int(state.direction)
	_advance(state, 2 if info.rank == "skip" or (info.rank == "reverse" and state.participants.size() == 2) else 1)
	return {"state": state}

func _table(state: Dictionary) -> Dictionary:
	return {"top": state.discard.back(), "color": state.color, "debt": state.debt, "debt_kind": state.debt_kind}

func view_for(state: Dictionary, seat: int) -> Dictionary:
	var counts := []
	for hand in state.hands: counts.append(hand.size())
	var top: int = -1 if state.discard.is_empty() else int(state.discard.back())
	return {"deck_count": state.deck.size(), "phase": state.phase, "participants": state.participants.duplicate(), "connected": state.connected.duplicate(), "display_seat": state.display_seat, "hand": [] if seat == state.display_seat else state.hands[seat].duplicate(), "counts": counts, "top": top, "color": state.color, "direction": state.direction, "turn": state.turn, "debt": state.debt, "debt_kind": state.debt_kind, "drawn": state.drawn if state.turn == seat else -1, "uno_target": state.uno_target, "paused": _paused(state), "winner": state.winner, "score": state.score, "round": state.round, "votes": state.votes.duplicate(), "last": state.last.duplicate(true)}

func describe_actions(view: Dictionary, seat: int) -> Dictionary:
	var legal := []
	if view.phase == "lobby":
		if seat == 0:
			var players: int = view.connected.count(true) - (1 if view.display_seat == 0 and view.connected[0] else 0)
			if players >= 2: legal.append({"type": "start"})
			if view.display_seat != 0 or view.connected.count(true) <= 6: legal.append({"type": "table_mode", "enabled": view.display_seat != 0})
	elif not view.paused and Cards.contains_number(view.participants, seat):
		if view.phase == "finished":
			if not Cards.contains_number(view.votes, seat): legal.append({"type": "rematch"})
		else:
			if view.uno_target == seat: legal.append({"type": "uno"})
			elif int(view.uno_target) >= 0: legal.append({"type": "catch"})
			if view.turn == seat:
				for card in view.hand:
					if (view.drawn == -1 or card == view.drawn) and Cards.matches(int(card), view):
						for color in (range(4) if Cards.info(int(card)).color == -1 else [-1]):
							var action := {"type": "play", "card": card, "uno": true}
							if color != -1: action.color = color
							legal.append(action)
				legal.append({"type": "draw"} if view.drawn == -1 else {"type": "pass"})
	return {"schema": {"type": "object", "required": ["type"], "properties": {"type": {"enum": ["start", "table_mode", "play", "draw", "pass", "uno", "catch", "rematch"]}, "card": {"type": "integer", "minimum": 0, "maximum": 107}, "color": {"type": "integer", "minimum": 0, "maximum": 3}, "uno": {"type": "boolean"}, "enabled": {"type": "boolean"}}, "additionalProperties": false}, "legal_actions": legal}
