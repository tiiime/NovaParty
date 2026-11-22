extends RefCounted
# 9×9, positional superko, no suicide, area scoring, white komi 7.5.
const N = 9
const POINTS = N * N
const KOMI = 7.5
const MAX_PLAYS = 512

func initial_state(_seed: int) -> Dictionary:
	var board := []
	board.resize(POINTS)
	board.fill(0)
	return {"board": board, "turn": 0, "phase": "play", "winner": -1, "reason": "", "last": [-1, -1], "round": 1, "votes": [false, false], "history": {_key(board): true}, "captures": [0, 0], "passes": 0, "plays": 0, "dead": [], "confirmed": [false, false], "scores": []}

func _key(board: Array) -> String:
	var bytes := PackedByteArray()
	for piece in board: bytes.append(int(piece) + 1)
	return Marshalls.raw_to_base64(bytes)

func _neighbors(index: int) -> Array[int]:
	var result: Array[int] = []
	if index % N > 0: result.append(index - 1)
	if index % N < N - 1: result.append(index + 1)
	if index >= N: result.append(index - N)
	if index < POINTS - N: result.append(index + N)
	return result

func _group(board: Array, start: int) -> Dictionary:
	var side := int(board[start])
	var cells := [start]
	var seen := {start: true}
	var edges := {}
	var cursor := 0
	while cursor < cells.size():
		for p in _neighbors(cells[cursor]):
			var value := int(board[p])
			if value == side:
				if not seen.has(p):
					seen[p] = true
					cells.append(p)
			else: edges[p] = value
		cursor += 1
	return {"cells": cells, "edges": edges}

func _has_liberty(group: Dictionary) -> bool:
	return 0 in group.edges.values()

func _play(board: Array, index: int, side: int, history: Dictionary) -> Dictionary:
	if int(board[index]) != 0: return {"error": "occupied"}
	var next := board.duplicate()
	next[index] = side
	var captured := 0
	for neighbor in _neighbors(index):
		if int(next[neighbor]) != -side: continue
		var opponent := _group(next, neighbor)
		if not _has_liberty(opponent):
			for cell in opponent.cells: next[cell] = 0
			captured += opponent.cells.size()
	if not _has_liberty(_group(next, index)): return {"error": "suicide"}
	var key := _key(next)
	if history.has(key): return {"error": "ko"}
	return {"board": next, "key": key, "captured": captured}

func _point(value) -> bool:
	return (value is int or value is float) and value >= 0 and value < POINTS and value == int(value)

func _area(state: Dictionary) -> Array:
	var board: Array = state.board.duplicate()
	for index in state.dead: board[int(index)] = 0
	var scores := [0.0, KOMI]
	var visited := {}
	for index in range(POINTS):
		var side := int(board[index])
		if side != 0:
			scores[0 if side > 0 else 1] += 1
		elif not visited.has(index):
			var group := _group(board, index)
			for cell in group.cells: visited[cell] = true
			var sides: Array = group.edges.values()
			if 1 in sides and not -1 in sides: scores[0] += group.cells.size()
			elif -1 in sides and not 1 in sides: scores[1] += group.cells.size()
	return scores

func apply(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	if seat not in [0, 1]: return {"error": "invalid_action"}
	var kind = action.get("type")
	if state.phase == "finished":
		if kind != "rematch": return {"error": "game_finished"}
		if state.votes[seat]: return {"error": "already_requested"}
		state.votes[seat] = true
		if state.votes[0] and state.votes[1]:
			var round_number := int(state.round) + 1
			state = initial_state(0)
			state.round = round_number
		return {"state": state}
	if kind == "resign":
		state.phase = "finished"
		state.reason = "resigned"
		state.winner = 1 - seat
		return {"state": state}
	if state.phase == "score": return _score(state, seat, action)
	if int(state.turn) != seat: return {"error": "not_your_turn"}
	if kind == "pass":
		state.turn = 1 - seat
		state.passes = int(state.passes) + 1
		if int(state.passes) == 2: state.phase = "score"
		return {"state": state}
	if kind != "move" or not _point(action.get("to")): return {"error": "invalid_action"}
	var index := int(action.to)
	var result := _play(state.board, index, 1 if seat == 0 else -1, state.history)
	if result.has("error"): return result
	state.board = result.board
	state.history[result.key] = true
	state.plays = int(state.plays) + 1
	state.captures[seat] = int(state.captures[seat]) + int(result.captured)
	state.passes = 0
	state.turn = 1 - seat
	state.last = [-1, index]
	if int(state.plays) >= MAX_PLAYS: state.phase = "score"
	return {"state": state}

func _score(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	match action.get("type"):
		"mark":
			if not _point(action.get("to")) or int(state.board[int(action.to)]) == 0: return {"error": "invalid_action"}
			var cells: Array = _group(state.board, int(action.to)).cells
			var marked := {}
			for index in state.dead: marked[int(index)] = true
			var remove: bool = marked.has(cells[0])
			for index in cells:
				if remove: marked.erase(index)
				else: marked[index] = true
			state.dead = marked.keys()
			state.dead.sort()
			state.confirmed = [false, false]
		"confirm_score":
			if state.confirmed[seat]: return {"error": "already_requested"}
			state.confirmed[seat] = true
			if state.confirmed[0] and state.confirmed[1]:
				state.scores = _area(state)
				state.winner = 0 if state.scores[0] > state.scores[1] else 1
				state.phase = "finished"
				state.reason = "scored"
		"resume":
			if int(state.plays) >= MAX_PLAYS: return {"error": "move_limit"}
			state.phase = "play"
			state.passes = 0
			state.dead = []
			state.confirmed = [false, false]
		_: return {"error": "invalid_action"}
	return {"state": state}

func view_for(state: Dictionary, seat: int) -> Dictionary:
	var view := state.duplicate(true)
	view.erase("history")
	var legal := []
	var blocked := {}
	if state.phase == "play" and seat in [0, 1] and int(state.turn) == seat:
		for index in range(POINTS):
			var result := _play(state.board, index, 1 if seat == 0 else -1, state.history)
			if result.has("error"):
				blocked[str(index)] = result.error
			else: legal.append({"type": "move", "to": index})
	if state.phase == "score":
		view.scores = _area(state)
		for index in range(POINTS):
			if int(state.board[index]) != 0: legal.append({"type": "mark", "to": index})
	view.legal = legal
	view.blocked = blocked
	return view

func describe_actions(view: Dictionary, seat: int) -> Dictionary:
	var actions: Array = view.get("legal", []).duplicate(true)
	if seat in [0, 1]:
		if view.phase == "finished":
			if not view.votes[seat]: actions.append({"type": "rematch"})
		else:
			actions.append({"type": "resign"})
			if view.phase == "play" and int(view.turn) == seat: actions.append({"type": "pass"})
			if view.phase == "score":
				if not view.confirmed[seat]: actions.append({"type": "confirm_score"})
				if int(view.plays) < MAX_PLAYS: actions.append({"type": "resume"})
	return {"schema": {"type": "object", "required": ["type"], "properties": {"type": {"enum": ["move", "pass", "mark", "confirm_score", "resume", "resign", "rematch"]}, "to": {"type": "integer", "minimum": 0, "maximum": 80}}}, "legal_actions": actions}
