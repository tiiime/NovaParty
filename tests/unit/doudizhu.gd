extends SceneTree
# Dou Dizhu rules: every combination type, comparisons, bidding, scoring, privacy and
# hundreds of complete bot games driven only by the hint generator.
const Rules = preload("res://mods/doudizhu/rules.gd")
const Cards = preload("res://mods/doudizhu/cards.gd")
const Room = preload("res://sdk/session/room.gd")
const Loader = preload("res://sdk/mods/mod_loader.gd")
var checks := 0
var failures := 0
var rules = Rules.new()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("DOUDIZHU FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

# Cards by rank name, picking unused suits: c(["3","3","4"]).
func c(names: Array) -> Array:
	var used := {}
	var result := []
	for name in names:
		var r: int = Cards.RANK_NAMES.find(name) if name not in ["S", "B"] else (13 if name == "S" else 14)
		if r >= 13:
			result.append(52 if r == 13 else 53)
			continue
		var n: int = used.get(r, 0)
		used[r] = n + 1
		result.append(r * 4 + n)
	return result

func kind(names: Array) -> String:
	return str(Cards.classify(c(names)).get("type", "invalid"))

func combo(names: Array) -> Dictionary:
	return Cards.classify(c(names))

func lobby() -> Dictionary:
	var state: Dictionary = rules.initial_state(7)
	for seat in range(3):
		state = rules.presence_changed(state, seat, true)
	return state

func ok(state: Dictionary, seat: int, action: Dictionary) -> Dictionary:
	var result: Dictionary = rules.apply(state.duplicate(true), seat, action)
	check(result.has("state"), "legal %s by %d: %s" % [str(action), seat, result.get("error", "")])
	return result.get("state", state)

func rejected(state: Dictionary, seat: int, action: Dictionary, reason: String) -> void:
	var before := JSON.stringify(state)
	var result: Dictionary = rules.apply(state, seat, action)
	check(result.get("error") == reason, "reject %s with %s (got %s)" % [str(action), reason, str(result.get("error"))])
	check(JSON.stringify(state) == before, "rejection leaves state untouched")

func _full(all: Array) -> bool:
	var sorted := all.map(func(x): return int(x))
	sorted.sort()
	return sorted == range(54)

func run() -> void:
	combinations()
	comparisons()
	hints()
	bidding_and_play()
	scoring()
	bots()
	await room_privacy()
	print("DOUDIZHU_RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func combinations() -> void:
	check(kind(["3"]) == "single", "single")
	check(kind(["S"]) == "single", "joker single")
	check(kind(["5", "5"]) == "pair", "pair")
	check(kind(["S", "B"]) == "rocket", "rocket")
	check(kind(["5", "6"]) == "invalid", "two different singles")
	check(kind(["7", "7", "7"]) == "triple", "triple")
	check(kind(["7", "7", "7", "3"]) == "triple_single", "triple with single")
	check(kind(["7", "7", "7", "B"]) == "triple_single", "triple with joker single")
	check(kind(["7", "7", "7", "3", "3"]) == "triple_pair", "triple with pair")
	check(kind(["7", "7", "7", "7"]) == "bomb", "bomb")
	check(kind(["3", "4", "5", "6", "7"]) == "straight", "five straight")
	check(combo(["10", "J", "Q", "K", "A"]).main == Cards.RANK_NAMES.find("A"), "straight to A")
	check(kind(["J", "Q", "K", "A", "2"]) == "invalid", "straight cannot include 2")
	check(kind(["3", "4", "5", "6"]) == "invalid", "four cards are not a straight")
	check(kind(["3", "4", "5", "6", "8"]) == "invalid", "gapped straight")
	check(combo(["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]).length == 12, "longest straight")
	check(kind(["3", "3", "4", "4", "5", "5"]) == "pair_chain", "three pair chain")
	check(kind(["3", "3", "4", "4"]) == "invalid", "two pairs are not a chain")
	check(kind(["K", "K", "A", "A", "2", "2"]) == "invalid", "pair chain cannot include 2")
	check(kind(["3", "3", "3", "4", "4", "4"]) == "plane", "plane")
	check(kind(["3", "3", "3", "4", "4", "4", "8", "9"]) == "plane_single", "plane with singles")
	check(kind(["3", "3", "3", "4", "4", "4", "8", "8", "9", "9"]) == "plane_pair", "plane with pairs")
	check(kind(["3", "3", "3", "4", "4", "4", "S", "B"]) == "invalid", "rocket cannot be plane kickers")
	check(kind(["3", "3", "3", "5", "5", "5"]) == "invalid", "non-consecutive triples")
	check(kind(["A", "A", "A", "2", "2", "2"]) == "invalid", "plane cannot include 2")
	var tricky := combo(["3", "3", "3", "4", "4", "4", "5", "5", "5", "6", "6", "6"])
	check(tricky.type == "plane" and tricky.length == 4, "four triples read as a plane of four")
	var kicked := combo(["3", "3", "3", "4", "4", "4", "5", "5", "5", "9", "9", "9"])
	check(kicked.type == "plane_single" and kicked.length == 3 and kicked.main == 2, "triple used as three single kickers")
	check(kind(["8", "8", "8", "8", "3", "5"]) == "four_two", "four with two singles")
	check(kind(["8", "8", "8", "8", "3", "3"]) == "four_two", "four with a pair as two singles")
	check(kind(["8", "8", "8", "8", "3", "3", "5", "5"]) == "four_pairs", "four with two pairs")
	check(kind(["8", "8", "8", "8", "3", "5", "6"]) == "invalid", "four with three kickers")
	check(Cards.classify([]).is_empty(), "empty play")

func comparisons() -> void:
	check(Cards.beats(combo(["4"]), combo(["3"])), "higher single")
	check(not Cards.beats(combo(["3"]), combo(["3"])), "equal single does not beat")
	check(Cards.beats(combo(["2"]), combo(["A"])), "2 beats A")
	check(Cards.beats(combo(["B"]), combo(["S"])), "big joker beats small")
	check(not Cards.beats(combo(["5", "5"]), combo(["4"])), "pair cannot follow single")
	check(Cards.beats(combo(["3", "3", "3", "3"]), combo(["2", "2"])), "bomb beats pair")
	check(Cards.beats(combo(["4", "4", "4", "4"]), combo(["3", "3", "3", "3"])), "higher bomb")
	check(not Cards.beats(combo(["A", "A", "A", "A"]), combo(["S", "B"])), "bomb loses to rocket")
	check(Cards.beats(combo(["S", "B"]), combo(["2", "2", "2", "2"])), "rocket beats bomb")
	check(not Cards.beats(combo(["4", "5", "6", "7", "8", "9"]), combo(["3", "4", "5", "6", "7"])), "straight lengths must match")
	check(Cards.beats(combo(["4", "5", "6", "7", "8"]), combo(["3", "4", "5", "6", "7"])), "higher straight")
	check(Cards.beats(combo(["9", "9", "9", "3"]), combo(["8", "8", "8", "A"])), "triple kicker ignored")
	check(Cards.beats(combo(["4", "4", "4", "5", "5", "5", "6", "7"]), combo(["3", "3", "3", "4", "4", "4", "A", "2"])), "plane compares body")
	check(Cards.beats(combo(["3"]), {}), "anything leads freely")

func hints() -> void:
	var hand := c(["3", "4", "4", "5", "6", "7", "8", "9", "9", "9", "9", "S", "B"])
	var follow: Array = Cards.hints(hand, combo(["6"]))
	check(not follow.is_empty() and Cards.rank(follow[0][0]) == Cards.RANK_NAMES.find("7"), "weakest single that beats, without breaking groups")
	check(follow.any(func(h): return Cards.classify(h).type == "bomb") and follow.back().size() == 2, "bomb and rocket listed after normal answers")
	var straight: Array = Cards.hints(hand, combo(["3", "4", "5", "6", "7"]))
	check(straight.any(func(h): return Cards.classify(h).type == "straight" and Cards.classify(h).main == Cards.RANK_NAMES.find("8")), "straight answer found")
	check(Cards.hints(c(["3", "5"]), combo(["4", "4"])).is_empty(), "nothing beats: empty hint list")
	var plane: Array = Cards.hints(c(["5", "5", "5", "6", "6", "6", "3", "K"]), combo(["3", "3", "3", "4", "4", "4", "8", "9"]))
	check(plane.size() == 1 and Cards.classify(plane[0]).type == "plane_single", "plane with kickers answer")
	for lead_names in [["3"], ["3", "3"], ["3", "3", "3", "4"], ["3", "4", "5", "6", "7"]]:
		for h in Cards.hints(hand, combo(lead_names)):
			check(Cards.beats(Cards.classify(h), combo(lead_names)), "every hint beats " + str(lead_names))

func dealt(seed_value: int = 7) -> Dictionary:
	var state := lobby()
	state.seed = seed_value
	return rules.start_round(state).state

func bidding_and_play() -> void:
	var state := lobby()
	rejected(state, 1, {"type": "start"}, "host_only")
	var short: Dictionary = rules.initial_state(1)
	short = rules.presence_changed(short, 0, true)
	short = rules.presence_changed(short, 1, true)
	check(rules.start_round(short).error == "round_not_ready", "two players cannot start")
	check(rules.can_join(short) and not rules.can_join(state), "three players fill the table")
	state = rules.start_round(state).state
	check(state.phase == "bidding" and state.participants == [0, 1, 2], "all three seats are dealt in")
	for seat in range(3): check(state.hands[seat].size() == 17, "17 cards each")
	check(state.bottom.size() == 3 and _full(state.hands[0] + state.hands[1] + state.hands[2] + state.bottom), "54 unique cards dealt")
	check(state.turn == 0, "first round starts with first player")
	rejected(state, 1, {"type": "bid", "amount": 1}, "not_your_turn")
	rejected(state, 0, {"type": "play", "cards": [0]}, "invalid_action")
	rejected(state, 0, {"type": "bid", "amount": 4}, "invalid_action")
	state = ok(state, 0, {"type": "bid", "amount": 2})
	rejected(state, 1, {"type": "bid", "amount": 1}, "bid_too_low")
	rejected(state, 1, {"type": "bid", "amount": 2}, "bid_too_low")
	state = ok(state, 1, {"type": "bid", "amount": 0})
	state = ok(state, 2, {"type": "bid", "amount": 0})
	check(state.phase == "playing" and state.landlord == 0 and state.bid == 2 and state.hands[0].size() == 20, "highest bidder becomes landlord with bottom cards")
	check(state.turn == 0, "landlord leads")
	rejected(state, 0, {"type": "pass"}, "must_lead")
	var foreign: int = state.hands[1][0]
	rejected(state, 0, {"type": "play", "cards": [foreign]}, "card_not_owned")
	var mine: Array = Cards.sort_hand(state.hands[0])
	rejected(state, 0, {"type": "play", "cards": [mine[0], mine[0]]}, "invalid_action")
	var low: int = mine.back()
	state = ok(state, 0, {"type": "play", "cards": [low]})
	check(state.lead.type == "single" and state.table["0"] == [low], "lead recorded on the table")
	state = ok(state, 1, {"type": "pass"})
	state = ok(state, 2, {"type": "pass"})
	check(state.turn == 0 and state.lead.is_empty() and state.table.is_empty(), "two passes return a free lead")
	# Instant 3 ends bidding.
	var quick := dealt(11)
	var first: int = quick.turn
	quick = ok(quick, first, {"type": "bid", "amount": 3})
	check(quick.phase == "playing" and quick.landlord == first, "bid of 3 wins immediately")
	# All pass: redeal, same round number, different hands.
	var none := dealt(13)
	var before: Array = none.hands[1].duplicate()
	for _i in range(3): none = ok(none, none.turn, {"type": "bid", "amount": 0})
	check(none.phase == "bidding" and none.round == 1 and none.hands[1] != before and none.last.type == "redeal", "nobody bids: reshuffle and redeal")
	# Pause when a player drops.
	var dropped := dealt(17)
	dropped = rules.presence_changed(dropped, 2, false)
	rejected(dropped, dropped.turn, {"type": "bid", "amount": 1}, "players_disconnected")
	check(rules.view_for(dropped, 1).paused, "view reports pause")

func fixture(hands: Dictionary, landlord: int, bid: int = 1) -> Dictionary:
	var state := dealt(3)
	for seat in hands: state.hands[int(seat)] = c(hands[seat])
	state.phase = "playing"
	state.landlord = landlord
	state.bid = bid
	state.turn = landlord
	for seat in range(3): state.plays[str(seat)] = 0
	return state

func scoring() -> void:
	# Landlord spring: farmers never play.
	var state := fixture({0: ["3", "3", "3", "4"], 1: ["5", "6"], 2: ["7", "8"]}, 0, 2)
	state = ok(state, 0, {"type": "play", "cards": c(["3", "3", "3", "4"])})
	check(state.phase == "finished" and state.winner == 0 and state.result.landlord_won and state.result.spring, "landlord spring")
	check(state.multiplier == 2 and state.result.deltas == {"0": 8, "1": -4, "2": -4}, "spring doubles: bid 2 x2, landlord gets double")
	var total := 0
	for seat in state.scores: total += int(state.scores[seat])
	check(total == 0, "scores are zero-sum")
	# Bomb doubles; farmer wins; landlord played twice so no anti-spring.
	state = fixture({0: ["3", "4", "K"], 1: ["9", "9", "9", "9", "5"], 2: ["6", "7"]}, 0, 1)
	state = ok(state, 0, {"type": "play", "cards": c(["3"])})
	state = ok(state, 1, {"type": "play", "cards": c(["9", "9", "9", "9"])})
	check(state.multiplier == 2 and state.bombs == 1, "bomb doubles the multiplier")
	state = ok(state, 2, {"type": "pass"})
	state = ok(state, 0, {"type": "pass"})
	check(state.turn == 1 and state.lead.is_empty(), "bomb wins the trick")
	state = ok(state, 1, {"type": "play", "cards": c(["5"])})
	check(state.phase == "finished" and not state.result.landlord_won and state.result.spring and state.result.deltas == {"0": -8, "1": 4, "2": 4}, "landlord played once: anti-spring doubles again")
	# Rocket.
	state = fixture({0: ["S", "B", "3"], 1: ["4"], 2: ["5"]}, 0, 3)
	state = ok(state, 0, {"type": "play", "cards": c(["S", "B"])})
	check(state.multiplier == 2, "rocket doubles")
	check(state.turn == 1, "rocket passes the turn on")
	rejected(state, 1, {"type": "play", "cards": c(["4"])}, "does_not_beat")
	# Rematch keeps cumulative scores and rotates the first bidder.
	state = fixture({0: ["3"], 1: ["5"], 2: ["7"]}, 0, 1)
	state = ok(state, 0, {"type": "play", "cards": c(["3"])})
	check(not rules.view_for_spectator(state).has("revealed") and rules.view_for(state, 0).revealed[1].size() == 1, "only participants review remaining cards")
	var scores: Dictionary = state.scores.duplicate()
	for seat in range(3): state = ok(state, seat, {"type": "rematch"})
	check(state.phase == "bidding" and state.round == 2 and state.scores == scores and state.turn == 1, "rematch keeps scores, rotates first bidder")

func bots() -> void:
	var games := 0
	var springs := 0
	var bombs := 0
	var types := {}
	for seed_value in range(1, 301):
		var state := dealt(seed_value)
		var steps := 0
		while state.phase != "finished" and steps < 400:
			steps += 1
			var seat: int = state.turn
			var view: Dictionary = rules.view_for(state, seat)
			var legal: Array = rules.describe_actions(view, seat).legal_actions
			check(not legal.is_empty(), "a legal action always exists")
			if legal.is_empty(): break
			# Rotate through suggestions so every combination family appears across games.
			var action: Dictionary = legal[(seed_value * 7 + steps) % legal.size()]
			# Mix in passes so tricks resolve in different ways.
			if state.phase == "playing" and legal.back().type == "pass" and (seed_value + steps) % 3 == 0: action = legal.back()
			var result: Dictionary = rules.apply(state.duplicate(true), seat, action)
			check(result.has("state"), "bot action accepted: %s %s" % [str(action), result.get("error", "")])
			if not result.has("state"): break
			state = result.state
			if action.type == "play": types[Cards.classify(action.cards).type] = true
			var held := 0
			for s in range(3): held += state.hands[s].size()
			if state.phase == "bidding": check(held == 51, "bidding keeps 51 cards in hands")
		check(state.phase == "finished", "game %d finishes" % seed_value)
		games += 1
		var total := 0
		for seat in state.scores: total += int(state.scores[seat])
		check(total == 0, "zero-sum result")
		if state.result.spring: springs += 1
		bombs += int(state.bombs)
		check(state.hands[int(state.winner)].is_empty(), "winner emptied their hand")
		for seat in range(3):
			var other: Dictionary = rules.view_for(state, seat)
			check(other.revealed[int(state.winner)].is_empty() and other.finished, "finished view reveals the rest")
	check(types.size() >= 6, "bots exercised many combination types: " + str(types.keys()))
	print("DOUDIZHU_BOTS games=%d springs=%d bombs=%d types=%s" % [games, springs, bombs, ",".join(types.keys())])

func room_privacy() -> void:
	var loader = Loader.new()
	var info: Dictionary = loader.inspect("res://mods/doudizhu")
	check(not info.is_empty(), "manifest loads: " + loader.error)
	if info.is_empty(): return
	var room = Room.new(info, loader.rules(info), "host", "Host", 99, {}, {"role": "spectator"})
	for i in range(3):
		var reply: Dictionary = room.hello({"protocol": 2, "rules_fingerprint": info.rules_fingerprint, "fingerprint": info.fingerprint, "player_id": "p%d" % i, "nickname": "P%d" % i, "capabilities": []})
		check(reply.type == "welcome", "player %d seated" % i)
	check(not room.rules.can_join(room.state), "table closes at three players")
	check(room.host_start_round().is_empty(), "seatless host starts")
	var public: Dictionary = room.spectator_snapshot().view
	check(not public.has("hand") and not public.has("revealed") and public.bottom.is_empty(), "public display sees no hand and no bottom before bidding ends")
	var text := JSON.stringify(room.snapshot(1))
	for seat in [0, 2]:
		for card in room.state.hands[seat]:
			check(not room.snapshot(1).view.hand.has(card), "seat 1 never receives seat %d's cards" % seat)
	check(not text.contains("\"hands\"") and not text.contains("\"seed\""), "snapshot omits internal hands and seed")
	check(room.snapshot(1).view.hand.size() == 17, "player sees own 17 cards")
