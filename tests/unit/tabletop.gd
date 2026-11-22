extends SceneTree
const X = preload("res://mods/xiangqi/rules.gd")
const G = preload("res://mods/go/rules.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func xmove(x, state: Dictionary, from: int, to: int) -> Dictionary:
	return x.apply(state, int(state.turn), {"type": "move", "from": from, "to": to})

func undo(x, state: Dictionary, seat: int, type: String) -> String:
	return str(x.apply(state, seat, {"type": type}).get("error", ""))

func xiangqi() -> void:
	var x = X.new()
	var initial: Dictionary = x.initial_state(0)
	var initial_board: Array = initial.board.duplicate()
	check(initial.board.count(0) == 58, "standard 32 pieces")
	var view: Dictionary = x.view_for(initial, 0)
	var description: Dictionary = x.describe_actions(view, 0)
	check(description.legal_actions.size() == 16 * 74 + 1, "all free moves are available to Debug on turn")
	check(JSON.stringify(description).to_utf8_buffer().size() < 65536, "debug action list fits wire budget")
	check(not view.has("history") and not view.has("legal") and not view.can_undo, "compact view with private undo history")
	check(undo(x, initial, 0, "request_undo") == "undo_unavailable", "cannot request undo before first move")
	check(xmove(x, initial, 81, 81).get("error") == "illegal_move", "no no-op moves")
	check(xmove(x, initial, 81, 82).get("error") == "illegal_move", "cannot cover a friendly piece")
	check(xmove(x, initial, 27, 34).get("error") == "illegal_move", "cannot move opponent piece")
	check(xmove(x, initial, 42, 34).get("error") == "illegal_move", "cannot move an empty point")
	check(x.apply(initial, 1, {"type": "move", "from": 27, "to": 36}).get("error") == "not_your_turn", "turn enforcement")
	check(x.apply(initial, 0, {"type": "move", "from": 54, "to": 45.5}).get("error") == "invalid_action", "reject fractional point")
	check(xmove(x, initial, 85, 2).has("state") and initial.board[2] == X.GENERAL, "general can leave palace and capture across board")
	check(xmove(x, initial, 27, 30).has("state") and initial.board[30] == -X.SOLDIER, "pawn can move sideways on home bank")
	var before: Array = initial.board.duplicate()
	check(undo(x, initial, 0, "request_undo") == "not_last_mover", "only last mover can request")
	check(undo(x, initial, 1, "request_undo").is_empty() and initial.board == before and initial.undo_by == 1, "request doesn't change board")
	check(undo(x, initial, 1, "accept_undo") == "undo_needs_opponent", "requester cannot approve their own undo")
	check(undo(x, initial, 0, "cancel_undo") == "not_undo_requester", "opponent cannot cancel the request")
	check(xmove(x, initial, 81, 45).get("error") == "undo_pending", "moves blocked until consent or dismissal")
	check(undo(x, initial, 0, "decline_undo").is_empty() and initial.board == before and initial.undo_by == -1, "decline does not change board")
	check(undo(x, initial, 1, "request_undo").is_empty() and undo(x, initial, 1, "cancel_undo").is_empty() and initial.board == before, "withdraw request without changing position")
	check(undo(x, initial, 1, "request_undo").is_empty() and undo(x, initial, 0, "accept_undo").is_empty(), "opponent can approve most recent move")
	check(initial.board[27] == -X.SOLDIER and initial.board[30] == 0 and initial.turn == 1 and initial.last == [85, 2], "undo restores previous move marker and turn")
	check(undo(x, initial, 0, "request_undo").is_empty() and undo(x, initial, 1, "accept_undo").is_empty() and initial.board == initial_board and initial.last == [-1, -1], "next approved undo restores captured piece and initial board")
	check(xmove(x, initial, 81, 4).has("state") and initial.winner == 0 and initial.reason == "general_captured", "captured general ends free play")
	check(undo(x, initial, 0, "request_undo").is_empty() and undo(x, initial, 1, "accept_undo").is_empty() and initial.phase == "play" and initial.winner == -1 and initial.board == initial_board, "approval can undo final capture before rematch")
	x.apply(initial, 1, {"type": "resign"})
	check(undo(x, initial, 0, "request_undo") == "undo_unavailable", "cannot undo a resignation")
	check(x.apply(initial, 1, {"type": "rematch"}).state.phase == "finished", "one rematch vote keeps result")
	check(x.apply(initial, 0, {"type": "rematch"}).state.round == 2, "both rematch votes reset")

func gmove(go, state: Dictionary, at: int) -> Dictionary:
	return go.apply(state, int(state.turn), {"type": "move", "to": at})

func go_game() -> void:
	var go = G.new()
	var state: Dictionary = go.initial_state(0)
	check(go.view_for(state, 0).legal.size() == 81 and not go.view_for(state, 0).has("history"), "81 opening choices and hidden history")
	check(gmove(go, state, 0).has("state"), "first stone")
	check(gmove(go, state, 0).error == "occupied", "reject occupied point")
	var capture: Dictionary = go.initial_state(0)
	capture.board[0] = -1
	capture.board[1] = -1
	capture.board[2] = 1
	capture.board[9] = 1
	check(gmove(go, capture, 10).state.captures == [2, 0] and capture.board[0] == 0 and capture.board[1] == 0, "capture connected group")
	var suicide: Dictionary = go.initial_state(0)
	suicide.board[1] = -1
	suicide.board[9] = -1
	check(gmove(go, suicide, 0).error == "suicide", "reject suicide")
	check(go.view_for(suicide, 0).blocked["0"] == "suicide", "local rejection reason")
	var ko: Dictionary = go.initial_state(0)
	for index in [1, 9, 19]: ko.board[index] = 1
	for index in [10, 2, 12, 20]: ko.board[index] = -1
	ko.history = {go._key(ko.board): true}
	check(gmove(go, ko, 11).has("state") and ko.board[10] == 0, "take ko")
	check(gmove(go, ko, 10).error == "ko", "reject immediate recapture")
	var scored: Dictionary = go.initial_state(0)
	scored.board[0] = 1
	scored.board[1] = 1
	scored.board[80] = -1
	go.apply(scored, 0, {"type": "pass"})
	go.apply(scored, 1, {"type": "pass"})
	check(scored.phase == "score" and go.view_for(scored, 0).scores == [2.0, 8.5], "two passes and neutral area")
	go.apply(scored, 1, {"type": "confirm_score"})
	go.apply(scored, 0, {"type": "mark", "to": 1})
	check(scored.dead == [0, 1] and scored.confirmed == [false, false], "mark group cancels old confirmation")
	check(go.view_for(scored, 0).scores == [0.0, 88.5], "dead stones removed before area score")
	go.apply(scored, 1, {"type": "resume"})
	check(scored.phase == "play" and scored.dead.is_empty() and scored.board[0] == 1 and scored.turn == 0, "resume restores unchanged board and turn")
	go.apply(scored, 0, {"type": "pass"})
	go.apply(scored, 1, {"type": "pass"})
	go.apply(scored, 1, {"type": "confirm_score"})
	check(scored.phase == "score", "one confirmation cannot finish")
	go.apply(scored, 0, {"type": "confirm_score"})
	check(scored.phase == "finished" and scored.winner == 1 and scored.scores == [2.0, 8.5], "dual confirmation is authoritative")

func run() -> void:
	xiangqi()
	go_game()
	print("TABLETOP_RULES checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
