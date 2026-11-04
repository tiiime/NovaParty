extends SceneTree
const Rules = preload("res://mods/uno/rules.gd")
const Cards = preload("res://mods/uno/cards.gd")
const Room = preload("res://sdk/room.gd")
const Loader = preload("res://sdk/mod_loader.gd")
var checks := 0
var failures := 0
var rules = Rules.new()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("UNO FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func fixture(hands: Array, top: int = 1) -> Dictionary:
	var state: Dictionary = rules.initial_state(42)
	state.display_seat = -1
	state.phase = "playing"
	state.round = 1
	state.discard = [top]
	state.color = Cards.info(top).color
	state.turn = 0
	for seat in range(hands.size()):
		state.hands[seat] = hands[seat].duplicate()
		state.participants.append(seat)
		state.connected[seat] = true
	for card in range(108):
		var owned := card == top
		for hand in state.hands: owned = owned or hand.has(card)
		if not owned: state.deck.append(card)
	return state
func apply_ok(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	var result: Dictionary = rules.apply(state.duplicate(true), seat, action)
	check(result.has("state"), "legal action " + str(action) + ": " + str(result.get("error", "")))
	return result.get("state", state)
func rejected(state: Dictionary, seat: int, action: Dictionary, reason: String) -> void:
	var before := JSON.stringify(state)
	var result: Dictionary = rules.apply(state, seat, action)
	check(result.get("error") == reason, "reject " + reason)
	check(JSON.stringify(state) == before, "rejection does not mutate state")
func conserved(state: Dictionary) -> bool:
	var all: Array = state.deck.duplicate()
	all.append_array(state.discard)
	for hand in state.hands: all.append_array(hand)
	all.sort()
	return all == range(108)
func run() -> void:
	var loader = Loader.new()
	var info: Dictionary = loader.inspect("res://mods/uno")
	check(not info.is_empty(), "fixed multiplayer manifest: " + loader.error)
	if info.is_empty(): quit(1); return
	var counts := {"wild": 0, "draw4": 0, "draw2": 0, "skip": 0, "reverse": 0}
	for id in range(108):
		var rank: String = Cards.info(id).rank
		if counts.has(rank): counts[rank] += 1
	check(counts == {"wild": 4, "draw4": 4, "draw2": 8, "skip": 8, "reverse": 8}, "108-card composition")
	var state := fixture([[8, 28, 100, 104], [5, 6]])
	rejected(state, 0, {"type": "play", "card": 28}, "card_not_playable")
	rejected(state, 1, {"type": "draw"}, "not_your_turn")
	rejected(state, 0, {"type": "play", "card": 8.5}, "invalid_action")
	rejected(state, 0, {"type": "play", "card": 100}, "choose_color")
	rejected(state, 0, {"type": "play", "card": 100, "color": 2.5}, "choose_color")
	rejected(state, 0, {"type": "play", "card": 8, "uno": "yes"}, "invalid_action")
	var played := apply_ok(state, 0, {"type": "play", "card": 8})
	check(played.turn == 1 and played.discard.back() == 8 and conserved(played), "same colour play")
	state = fixture([[76, 9], [5, 6]]) # Blue 1 matches red 1.
	played = apply_ok(state, 0, {"type": "play", "card": 76})
	check(played.color == 3, "same number changes active colour")
	state = fixture([[23, 5], [48, 104, 9], [105, 10]])
	state = apply_ok(state, 0, {"type": "play", "card": 23})
	state = apply_ok(state, 1, {"type": "play", "card": 48})
	state = apply_ok(state, 2, {"type": "play", "card": 105, "color": 0})
	check(state.debt == 8 and state.debt_kind == "draw4" and state.turn == 0, "+2 +2 +4 accumulates eight")
	var before_count: int = state.hands[0].size()
	state = apply_ok(state, 0, {"type": "draw"})
	check(state.hands[0].size() == before_count + 8 and state.turn == 1 and state.debt == 0 and conserved(state), "settle entire debt and skip")
	state = fixture([[104, 5], [23, 9]])
	state = apply_ok(state, 0, {"type": "play", "card": 104, "color": 0})
	rejected(state, 1, {"type": "play", "card": 23}, "card_not_playable")
	for card in [19, 21]:
		state = fixture([[card, 3], [4, 5]])
		state = apply_ok(state, 0, {"type": "play", "card": card})
		check(state.turn == 0, "two-player skip / reverse returns turn")
	state = fixture([[21, 3], [4, 5], [6, 7]])
	state = apply_ok(state, 0, {"type": "play", "card": 21})
	check(state.turn == 2 and state.direction == -1, "three-player reverse")
	state = fixture([[2, 3], [4, 5]])
	state.deck.erase(100); state.deck.append(100)
	state = apply_ok(state, 0, {"type": "draw"})
	check(state.drawn == 100 and state.turn == 0, "playable draw offers decision")
	rejected(state, 0, {"type": "play", "card": 2}, "drawn_card_only")
	rejected(state, 0, {"type": "draw"}, "already_drew")
	var passed := apply_ok(state, 0, {"type": "pass"})
	check(passed.turn == 1 and passed.hands[0].has(100), "may keep playable drawn card")
	state = apply_ok(state, 0, {"type": "play", "card": 100, "color": 2})
	check(state.color == 2 and state.turn == 1, "drawn wild chooses colour")
	state = fixture([[2, 3], [4, 5]])
	state = apply_ok(state, 0, {"type": "play", "card": 2})
	check(state.uno_target == 0, "missed UNO creates response window")
	var declared := apply_ok(state, 0, {"type": "uno"})
	rejected(declared, 1, {"type": "catch"}, "catch_unavailable")
	state = apply_ok(state, 1, {"type": "catch"})
	check(state.hands[0].size() == 3 and state.turn == 1 and state.uno_target == -1, "catch adds two without consuming catcher turn")
	state = fixture([[2, 3], [4, 5]])
	state = apply_ok(state, 0, {"type": "play", "card": 2})
	state = apply_ok(state, 1, {"type": "play", "card": 4, "uno": true})
	rejected(state, 1, {"type": "catch"}, "catch_unavailable")
	state = fixture([[23], [5]])
	state = apply_ok(state, 0, {"type": "play", "card": 23})
	check(state.phase == "finished" and state.winner == 0 and state.hands[1].size() == 3 and state.debt == 0 and conserved(state), "last penalty settles before finish")
	state = apply_ok(state, 0, {"type": "rematch"})
	check(state.phase == "finished", "single vote cannot restart")
	state = apply_ok(state, 1, {"type": "rematch"})
	check(state.phase == "playing" and state.round == 2 and state.hands[0].size() == 7 and conserved(state), "unanimous rematch redeals")
	state = fixture([[2, 3], []])
	state.discard = [10, 11, 1]
	state.deck = []
	for card in range(108):
		if not [1, 2, 3, 10, 11].has(card): state.hands[1].append(card)
	state = apply_ok(state, 0, {"type": "draw"})
	check(state.discard == [1] and conserved(state), "recycle excludes top discard and preserves all cards")
	var public_room = Room.new(info, Rules.new(), "table", "Table", 42)
	for slot in range(1, 7):
		check(public_room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "six-" + str(slot), "nickname": "Player"}).get("seat") == slot, "six player slots plus public display")
	check(public_room.command(0, request(public_room.revision, "start-six", {"type": "start"})).accepted, "public table starts six phones")
	check(public_room.state.participants.size() == 6 and public_room.snapshot(0).view.hand.is_empty() and conserved(public_room.state), "screen excluded from six-player deal")
	check(rules.describe_actions(public_room.snapshot(0).view, 0).legal_actions.is_empty(), "public screen cannot play, catch or vote")
	check(public_room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "seven", "nickname": "Player"}).type == "error", "capacity cannot grow during round")
	var mobile_room = Room.new(info, Rules.new(), "mobile-host", "Host", 42)
	check(mobile_room.command(0, request(mobile_room.revision, "mobile-mode", {"type": "table_mode", "enabled": false})).accepted, "phone host opts into playing before start")
	mobile_room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "mobile-guest", "nickname": "Guest"})
	check(mobile_room.command(0, request(mobile_room.revision, "start-two", {"type": "start"})).accepted and mobile_room.state.hands[0].size() == 7, "two phones can play without a screen")
	var locked: Dictionary = rules.initial_state(77)
	for seat in [0, 1, 2]: locked = rules.presence_changed(locked, seat, true)
	locked = apply_ok(locked, 0, {"type": "start"})
	locked.phase = "finished"
	locked.winner = 1
	locked = rules.presence_changed(locked, 3, true)
	locked = apply_ok(locked, 1, {"type": "rematch"})
	locked = apply_ok(locked, 2, {"type": "rematch"})
	check(locked.participants == [1, 2] and locked.hands[3].is_empty(), "rematch cannot enroll an inactive seat that reconnected later")
	var room = Room.new(info, Rules.new(), "uno-host", "Host", 42)
	var tokens := []
	for seat in range(1, 3):
		var welcome: Dictionary = room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "uno-" + str(seat), "nickname": "Player " + str(seat)})
		tokens.append(welcome.resume_token)
	check(room.command(0, request(room.revision, "start", {"type": "start"})).accepted, "host starts fixed three-player game")
	check(room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "late", "nickname": "Late"}).code == "game_in_progress", "new identities blocked during round")
	var old_revision: int = room.revision
	room.set_connected(2, false)
	check(room.snapshot(0).view.paused, "disconnect pauses fixed game")
	room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "player_id": "uno-2", "nickname": "Player 2", "resume_token": tokens[1]})
	check(not room.snapshot(0).view.paused, "authenticated reconnect restores player")
	check(room.command(1, request(old_revision, "stale", {"type": "draw"})).code == "stale_revision", "fixed game keeps strict revision")
	var view: Dictionary = room.snapshot(1).view
	check(not view.has("hands") and not view.has("deck") and not view.has("seed") and not view.has("shuffles"), "private view excludes opponents, deck and shuffle seed")
	var before: Dictionary = rules.describe_actions(view, 1)
	var wire_view = JSON.parse_string(JSON.stringify(view))
	check(before == rules.describe_actions(wire_view, 1), "JSON float transport keeps legal actions identical")
	var altered: Dictionary = room.state.duplicate(true)
	altered.hands[0].reverse()
	check(before == rules.describe_actions(rules.view_for(altered, 1), 1), "action description uses filtered data only")
	for count in [2, 3, 6]:
		for seed_value in range(8):
			state = rules.initial_state(seed_value)
			state.display_seat = -1
			for seat in range(count): state = rules.presence_changed(state, seat, true)
			var duplicate: Dictionary = state.duplicate(true)
			state = apply_ok(state, 0, {"type": "start"})
			duplicate = apply_ok(duplicate, 0, {"type": "start"})
			check(state == duplicate and conserved(state), "seeded deal deterministic")
			var moves := 0
			while state.phase != "finished" and moves < 5000:
				var turn: int = int(state.turn)
				var actions: Array = rules.describe_actions(rules.view_for(state, turn), turn).legal_actions
				check(not actions.is_empty(), "turn always has a legal action")
				state = apply_ok(state, turn, actions[0])
				check(conserved(state), "all 108 cards conserved throughout game")
				moves += 1
			check(state.phase == "finished" and state.hands[int(state.winner)].is_empty(), "complete deterministic match, players=" + str(count))
	print("UNO_RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func request(revision: int, id: String, action: Dictionary) -> Dictionary:
	return {"request_id": id, "expected_revision": revision, "action": action}
