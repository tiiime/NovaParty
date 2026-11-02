extends RefCounted
const SIZE = 15

func initial_state(_seed_value: int) -> Dictionary:
	var board := []
	board.resize(SIZE * SIZE)
	board.fill(-1)
	return {"board": board, "turn": 0, "winner": -1, "finished": false, "moves": 0, "round": 1, "rematch_votes": [false, false], "last_move": -1, "winning_line": []}

func apply(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	if seat not in [0, 1]:
		return {"error": "invalid_action"}
	if action.get("type") == "rematch":
		if action.has("round") and action.round != state.round:
			return {"error": "stale_revision"}
		if not state.finished:
			return {"error": "game_not_finished"}
		if state.rematch_votes[seat]:
			return {"error": "already_requested"}
		state.rematch_votes[seat] = true
		if state.rematch_votes[0] and state.rematch_votes[1]:
			var fresh := initial_state(0)
			fresh.round = int(state.round) + 1
			return {"state": fresh}
		return {"state": state}
	if state.finished:
		return {"error": "game_finished"}
	if seat != state.turn:
		return {"error": "not_your_turn"}
	var x = action.get("x")
	var y = action.get("y")
	if action.get("type") != "place" or not _coordinate(x) or not _coordinate(y):
		return {"error": "invalid_action"}
	x = int(x)
	y = int(y)
	if state.board[y * SIZE + x] != -1:
		return {"error": "occupied"}
	state.board[y * SIZE + x] = seat
	state.moves += 1
	state.last_move = y * SIZE + x
	for direction in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var count := 1
		var line := [y * SIZE + x]
		for sign_value in [-1, 1]:
			var point: Vector2i = Vector2i(x, y) + direction * sign_value
			while point.x >= 0 and point.x < SIZE and point.y >= 0 and point.y < SIZE and state.board[point.y * SIZE + point.x] == seat:
				line.append(point.y * SIZE + point.x)
				count += 1
				point += direction * sign_value
		if count >= 5:
			state.winning_line = line
			state.winner = seat
			state.finished = true
	if state.moves == SIZE * SIZE:
		state.finished = true
	state.turn = 1 - seat
	return {"state": state}

func view_for(state: Dictionary, _seat: int) -> Dictionary:
	return state.duplicate(true)

func _coordinate(value) -> bool:
	return (value is int or value is float) and value == int(value) and value >= 0 and value < SIZE

# Only the local player's filtered view is provided to this optional SDK hook.
func describe_actions(view: Dictionary, seat: int) -> Dictionary:
	var legal := []
	if view.finished and not view.get("rematch_votes", [false, false])[seat]:
		legal.append({"type": "rematch", "round": int(view.get("round", 1))})
	if not view.finished and view.turn == seat:
		for y in range(SIZE):
			for x in range(SIZE):
				if view.board[y * SIZE + x] == -1:
					legal.append({"type": "place", "x": x, "y": y})
	return {"schema": {"oneOf": [{"type": "object", "required": ["type"], "properties": {"type": {"const": "rematch"}, "round": {"type": "integer", "minimum": 1}}, "additionalProperties": false}, {"type": "object", "required": ["type", "x", "y"], "properties": {"type": {"const": "place"}, "x": {"type": "integer", "minimum": 0, "maximum": 14}, "y": {"type": "integer", "minimum": 0, "maximum": 14}}, "additionalProperties": false}]}, "legal_actions": legal}

# Optional SDK clock hook: deterministic seat and round, never a wall-clock read.
func clock_context(state: Dictionary) -> Dictionary:
	return {"seat": -1 if state.finished else int(state.turn), "round": int(state.get("round", 1))}
