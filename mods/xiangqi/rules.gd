extends RefCounted
# Signed pieces: red is positive (seat 0), black is negative (seat 1).
const W = 9
const H = 10
const GENERAL = 1
const ADVISOR = 2
const ELEPHANT = 3
const HORSE = 4
const ROOK = 5
const CANNON = 6
const SOLDIER = 7
const UNDO_LIMIT = 128

func initial_state(_seed: int) -> Dictionary:
	var board := []
	board.resize(W * H)
	board.fill(0)
	var home := [ROOK, HORSE, ELEPHANT, ADVISOR, GENERAL, ADVISOR, ELEPHANT, HORSE, ROOK]
	for x in range(W):
		board[x] = -home[x]
		board[81 + x] = home[x]
	for x in [1, 7]:
		board[18 + x] = -CANNON
		board[63 + x] = CANNON
	for x in [0, 2, 4, 6, 8]:
		board[27 + x] = -SOLDIER
		board[54 + x] = SOLDIER
	return {"board": board, "turn": 0, "phase": "play", "winner": -1, "reason": "", "last": [-1, -1], "round": 1, "votes": [false, false], "history": [], "undo_by": -1, "undo_result": ""}

func _side(seat: int) -> int: return 1 if seat == 0 else -1

func _point(value) -> bool:
	return (value is int or value is float) and value >= 0 and value < W * H and value == int(value)

func _can_undo(state: Dictionary) -> bool:
	return (state.phase == "play" or state.reason == "general_captured") and not state.votes[0] and not state.votes[1] and not state.history.is_empty()

func _undo(state: Dictionary, seat: int, kind: String) -> Dictionary:
	var requester := int(state.undo_by)
	if kind == "request_undo":
		if requester >= 0: return {"error": "undo_pending"}
		if not _can_undo(state): return {"error": "undo_unavailable"}
		if seat != 1 - int(state.turn): return {"error": "not_last_mover"}
		state.undo_by = seat
		state.undo_result = ""
	else:
		if requester < 0: return {"error": "undo_unavailable"}
		if kind == "cancel_undo":
			if seat != requester: return {"error": "not_undo_requester"}
			state.undo_result = "undo_cancelled"
		else:
			if seat == requester: return {"error": "undo_needs_opponent"}
			state.undo_result = "undo_declined"
			if kind == "accept_undo":
				var move: Array = state.history.pop_back()
				var src := int(move[0])
				var dst := int(move[1])
				state.board[src] = state.board[dst]
				state.board[dst] = move[2]
				state.last = move[3]
				state.turn = requester
				state.phase = "play"
				state.winner = -1
				state.reason = ""
				state.undo_result = "undo_accepted"
		state.undo_by = -1
	return {"state": state}

func apply(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	if seat not in [0, 1]: return {"error": "invalid_action"}
	var kind = action.get("type")
	if kind in ["request_undo", "accept_undo", "decline_undo", "cancel_undo"]: return _undo(state, seat, kind)
	if int(state.undo_by) >= 0: return {"error": "undo_pending"}
	if kind == "rematch" and state.phase == "finished":
		if state.votes[seat]: return {"error": "already_requested"}
		state.votes[seat] = true
		if state.votes[0] and state.votes[1]:
			var round_number := int(state.round) + 1
			state = initial_state(0)
			state.round = round_number
		return {"state": state}
	if state.phase != "play": return {"error": "game_finished"}
	if kind == "resign":
		_finish(state, 1 - seat, "resigned")
		return {"state": state}
	if int(state.turn) != seat: return {"error": "not_your_turn"}
	if kind != "move" or not _point(action.get("from")) or not _point(action.get("to")): return {"error": "invalid_action"}
	var src := int(action.from)
	var dst := int(action.to)
	var board: Array = state.board
	var side := _side(seat)
	if src == dst or int(board[src]) * side <= 0 or int(board[dst]) * side > 0: return {"error": "illegal_move"}
	var captured := int(board[dst])
	state.history.append([src, dst, captured, state.last])
	if state.history.size() > UNDO_LIMIT: state.history.pop_front()
	board[dst] = board[src]
	board[src] = 0
	state.last = [src, dst]
	state.turn = 1 - seat
	state.undo_result = ""
	if absi(captured) == GENERAL: _finish(state, seat, "general_captured")
	return {"state": state}

func _finish(state: Dictionary, winner: int, reason: String) -> void:
	state.phase = "finished"
	state.winner = winner
	state.reason = reason
	state.undo_result = ""

func view_for(state: Dictionary, _seat: int) -> Dictionary:
	var view := {}
	for key in ["board", "turn", "phase", "winner", "reason", "last", "round", "votes", "undo_by", "undo_result"]:
		view[key] = state[key]
	view["can_undo"] = _can_undo(state)
	return view.duplicate(true)

func describe_actions(view: Dictionary, seat: int) -> Dictionary:
	var actions := []
	var requester := int(view.undo_by)
	if seat in [0, 1]:
		if requester >= 0:
			if seat == requester: actions.append({"type": "cancel_undo"})
			else: actions.append_array([{"type": "accept_undo"}, {"type": "decline_undo"}])
		else:
			if view.can_undo and seat == 1 - int(view.turn): actions.append({"type": "request_undo"})
			if view.phase == "play":
				actions.append({"type": "resign"})
				if int(view.turn) == seat:
					var side := _side(seat)
					var destinations := []
					for dst in range(W * H):
						if int(view.board[dst]) * side <= 0: destinations.append(dst)
					for src in range(W * H):
						if int(view.board[src]) * side > 0:
							for dst in destinations: actions.append({"type": "move", "from": src, "to": dst})
			elif not view.votes[seat]: actions.append({"type": "rematch"})
	return {"schema": {"type": "object", "required": ["type"], "properties": {"type": {"enum": ["move", "resign", "rematch", "request_undo", "accept_undo", "decline_undo", "cancel_undo"]}, "from": {"type": "integer", "minimum": 0, "maximum": 89}, "to": {"type": "integer", "minimum": 0, "maximum": 89}}}, "legal_actions": actions}
