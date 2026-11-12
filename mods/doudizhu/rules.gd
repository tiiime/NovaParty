extends RefCounted
# Dou Dizhu, three players. The host runs this; every client receives only view_for(seat).
#
# Phases: lobby -> bidding -> playing -> finished (-> bidding on unanimous rematch).
# Bidding: each player in turn bids 1-3 above the current bid or passes; 3 ends bidding.
# If everyone passes the hand is redealt. The landlord takes the 3 bottom cards and leads.
# Score per round = bid x 2^(bombs + rockets) x spring; landlord wins/loses double.
const Cards = preload("cards.gd")
const CAPACITY = 4 # Optional public display at seat 0 plus three players.
const PLAYERS = 3

func initial_state(seed_value: int) -> Dictionary:
	return {"seed": seed_value, "shuffles": 0, "phase": "lobby", "display_seat": 0, "connected": [false, false, false, false],
		"participants": [], "hands": [[], [], [], []], "bottom": [], "turn": -1, "bidder": -1, "bid": 0, "bids": {}, "bid_turns": 0,
		"landlord": -1, "lead": {}, "lead_seat": -1, "lead_cards": [], "table": {}, "plays": {}, "multiplier": 1, "bombs": 0,
		"winner": -1, "result": {}, "scores": {}, "round": 0, "votes": [], "last": {}}

func can_join(state: Dictionary) -> bool:
	return state.phase == "lobby" and _player_count(state) < PLAYERS

func _player_count(state: Dictionary) -> int:
	return state.connected.count(true) - (1 if state.display_seat == 0 and state.connected[0] else 0)

func presence_changed(state: Dictionary, seat: int, connected: bool) -> Dictionary:
	if seat >= 0 and seat < CAPACITY: state.connected[seat] = connected
	return state

func _paused(state: Dictionary) -> bool:
	for seat in state.participants:
		if not state.connected[int(seat)]: return true
	return false

func _key(seat: int) -> String:
	return str(seat)

func _next(state: Dictionary, seat: int) -> int:
	var index: int = Cards.index_number(state.participants, seat)
	return int(state.participants[(index + 1) % state.participants.size()])

func _deal(state: Dictionary) -> void:
	# Rematches keep the same three players; only a new lobby can enroll players.
	if state.phase == "lobby":
		state.participants = []
		for seat in range(CAPACITY):
			if state.connected[seat] and seat != state.display_seat: state.participants.append(seat)
		for seat in state.participants: state.scores[_key(int(seat))] = 0
		state.round = 0
	var deck: Array = range(54)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(state.seed) + int(state.shuffles) * 104729
	state.shuffles += 1
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var item = deck[i]
		deck[i] = deck[j]
		deck[j] = item
	state.hands = [[], [], [], []]
	for i in range(51):
		state.hands[int(state.participants[i % 3])].append(deck[i])
	state.bottom = deck.slice(51)
	state.round += 1
	state.phase = "bidding"
	# The first bidder rotates every round.
	state.turn = int(state.participants[(int(state.round) - 1) % 3])
	state.bidder = state.turn
	state.bid = 0
	state.bids = {}
	state.bid_turns = 0
	state.landlord = -1
	state.lead = {}
	state.lead_seat = -1
	state.lead_cards = []
	state.table = {}
	state.plays = {}
	state.multiplier = 1
	state.bombs = 0
	state.winner = -1
	state.result = {}
	state.votes = []
	state.last = {"type": "deal", "seat": -1}

func _become_landlord(state: Dictionary, seat: int) -> void:
	state.landlord = seat
	state.hands[seat] += state.bottom
	state.phase = "playing"
	state.turn = seat
	state.lead = {}
	state.lead_seat = -1
	state.lead_cards = []
	state.table = {}
	for player in state.participants: state.plays[_key(int(player))] = 0
	state.last = {"type": "landlord", "seat": seat, "bid": state.bid}

func _finish(state: Dictionary, winner: int) -> void:
	state.phase = "finished"
	state.winner = winner
	var landlord_won := winner == int(state.landlord)
	var spring := false
	if landlord_won:
		spring = true
		for seat in state.participants:
			if int(seat) != int(state.landlord) and int(state.plays.get(_key(int(seat)), 0)) > 0: spring = false
	else:
		spring = int(state.plays.get(_key(int(state.landlord)), 0)) <= 1
	if spring: state.multiplier = int(state.multiplier) * 2
	var unit := int(state.bid) * int(state.multiplier)
	var deltas := {}
	for seat in state.participants:
		var farmer := int(seat) != int(state.landlord)
		var amount := unit * (1 if farmer else 2)
		var gain := amount if (farmer != landlord_won) else -amount
		deltas[_key(int(seat))] = gain
		state.scores[_key(int(seat))] = int(state.scores.get(_key(int(seat)), 0)) + gain
	state.result = {"landlord_won": landlord_won, "spring": spring, "bid": state.bid, "multiplier": state.multiplier, "bombs": state.bombs, "deltas": deltas}

func apply(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	if not Cards.integer(seat, 0, CAPACITY - 1) or not state.connected[seat]:
		return {"error": "player_offline"}
	var kind = action.get("type")
	if kind == "table_mode":
		if state.phase != "lobby" or seat != 0: return {"error": "host_only"}
		if not action.get("enabled") is bool: return {"error": "invalid_action"}
		if not action.enabled and state.connected.count(true) > PLAYERS: return {"error": "too_many_players"}
		state.display_seat = 0 if action.enabled else -1
		return {"state": state}
	if kind == "start":
		if state.phase != "lobby" or seat != 0: return {"error": "host_only"}
		if _player_count(state) != PLAYERS: return {"error": "need_three_players"}
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
	if seat != int(state.turn): return {"error": "not_your_turn"}
	if state.phase == "bidding":
		if kind != "bid": return {"error": "invalid_action"}
		var amount = action.get("amount")
		if not Cards.integer(amount, 0, 3): return {"error": "invalid_action"}
		if int(amount) != 0 and int(amount) <= int(state.bid): return {"error": "bid_too_low"}
		state.bids[_key(seat)] = int(amount)
		state.bid_turns += 1
		state.last = {"type": "bid", "seat": seat, "amount": int(amount)}
		if int(amount) > 0:
			state.bid = int(amount)
			state.bidder = seat
		if int(amount) == 3:
			_become_landlord(state, seat)
		elif int(state.bid_turns) >= PLAYERS:
			if int(state.bid) > 0:
				_become_landlord(state, int(state.bidder))
			else:
				# Nobody bid: redeal with a fresh shuffle; the same round number is kept.
				state.round -= 1
				_deal(state)
				state.last = {"type": "redeal", "seat": -1}
		else:
			state.turn = _next(state, seat)
		return {"state": state}
	# Playing.
	var free_lead: bool = state.lead.is_empty() or int(state.lead_seat) == seat
	if kind == "pass":
		if free_lead: return {"error": "must_lead"}
		state.table[_key(seat)] = "pass"
		state.last = {"type": "pass", "seat": seat}
		state.turn = _next(state, seat)
		if int(state.turn) == int(state.lead_seat):
			# Everyone passed: the trick goes back to its leader for a free lead.
			state.lead = {}
			state.table = {}
		return {"state": state}
	if kind != "play": return {"error": "invalid_action"}
	var raw = action.get("cards")
	if not raw is Array or raw.is_empty() or raw.size() > 20: return {"error": "invalid_action"}
	var cards: Array = []
	for value in raw:
		if not Cards.integer(value, 0, 53) or Cards.contains_number(cards, int(value)): return {"error": "invalid_action"}
		if not Cards.contains_number(state.hands[seat], int(value)): return {"error": "card_not_owned"}
		cards.append(int(value))
	var combo := Cards.classify(cards)
	if combo.is_empty(): return {"error": "invalid_combination"}
	if not free_lead and not Cards.beats(combo, state.lead): return {"error": "does_not_beat"}
	for card in cards: state.hands[seat].remove_at(Cards.index_number(state.hands[seat], card))
	if free_lead: state.table = {}
	if combo.type in ["bomb", "rocket"]:
		state.bombs += 1
		state.multiplier = int(state.multiplier) * 2
	state.lead = combo
	state.lead_seat = seat
	state.lead_cards = Cards.sort_hand(cards)
	state.table[_key(seat)] = Cards.sort_hand(cards)
	state.plays[_key(seat)] = int(state.plays.get(_key(seat), 0)) + 1
	state.last = {"type": "play", "seat": seat, "combo": combo.type}
	if state.hands[seat].is_empty():
		_finish(state, seat)
	else:
		state.turn = _next(state, seat)
	return {"state": state}

func view_for(state: Dictionary, seat: int) -> Dictionary:
	var counts := []
	for hand in state.hands: counts.append(hand.size())
	var finished: bool = state.phase == "finished"
	var hands_shown := []
	for i in range(CAPACITY):
		# Remaining hands are revealed to everyone only once the round is over.
		hands_shown.append(Cards.sort_hand(state.hands[i]) if finished else [])
	return {"phase": state.phase, "participants": state.participants.duplicate(), "connected": state.connected.duplicate(),
		"display_seat": state.display_seat, "hand": [] if seat == int(state.display_seat) or not Cards.contains_number(state.participants, seat) else Cards.sort_hand(state.hands[seat]),
		"counts": counts, "bottom": state.bottom.duplicate() if int(state.landlord) >= 0 else [], "turn": state.turn,
		"bid": state.bid, "bids": state.bids.duplicate(), "landlord": state.landlord, "lead": state.lead.duplicate(),
		"lead_seat": state.lead_seat, "lead_cards": state.lead_cards.duplicate(), "table": state.table.duplicate(true),
		"multiplier": state.multiplier, "bombs": state.bombs, "paused": _paused(state), "winner": state.winner,
		"result": state.result.duplicate(true), "scores": state.scores.duplicate(), "round": state.round,
		"votes": state.votes.duplicate(), "last": state.last.duplicate(true), "revealed": hands_shown,
		"finished": finished}

func describe_actions(view: Dictionary, seat: int) -> Dictionary:
	var legal := []
	if view.phase == "lobby":
		if seat == 0:
			var players: int = view.connected.count(true) - (1 if view.display_seat == 0 and view.connected[0] else 0)
			if players == PLAYERS: legal.append({"type": "start"})
			if view.display_seat != 0 or view.connected.count(true) <= PLAYERS: legal.append({"type": "table_mode", "enabled": view.display_seat != 0})
	elif not view.paused and Cards.contains_number(view.participants, seat):
		if view.phase == "finished":
			if not Cards.contains_number(view.votes, seat): legal.append({"type": "rematch"})
		elif int(view.turn) == seat:
			if view.phase == "bidding":
				legal.append({"type": "bid", "amount": 0})
				for amount in range(int(view.bid) + 1, 4): legal.append({"type": "bid", "amount": amount})
			else:
				var free_lead: bool = view.lead.is_empty() or int(view.lead_seat) == seat
				for cards in Cards.hints(view.hand, {} if free_lead else view.lead):
					legal.append({"type": "play", "cards": cards})
				if not free_lead: legal.append({"type": "pass"})
	return {"schema": {"type": "object", "required": ["type"], "properties": {"type": {"enum": ["start", "table_mode", "bid", "play", "pass", "rematch"]}, "amount": {"type": "integer", "minimum": 0, "maximum": 3}, "cards": {"type": "array", "items": {"type": "integer", "minimum": 0, "maximum": 53}, "minItems": 1, "maxItems": 20, "uniqueItems": true}, "enabled": {"type": "boolean"}}, "additionalProperties": false},
		"legal_actions": legal, "note": "play lists suggested combinations; any legal combination that beats the lead is accepted"}
