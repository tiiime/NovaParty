extends RefCounted
# Pure Dou Dizhu card logic shared by rules and view. No state, no randomness.
#
# Card ids 0..53. 0..51: rank = id / 4 (0 = "3" … 11 = "A", 12 = "2"), suit = id % 4.
# 52 = small joker (rank 13), 53 = big joker (rank 14).
const RANK_NAMES = ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2", "小王", "大王"]
const SUITS = ["♠", "♥", "♣", "♦"]
const HIGHEST_CHAIN_RANK = 11 # Straights, pair chains and airplanes stop at A.
const TYPES = ["single", "pair", "triple", "triple_single", "triple_pair", "straight", "pair_chain", "plane", "plane_single", "plane_pair", "four_two", "four_pairs", "bomb", "rocket"]

static func rank(card: int) -> int:
	return 13 if card == 52 else 14 if card == 53 else card / 4

static func suit(card: int) -> int:
	return -1 if card >= 52 else card % 4

static func label(card: int) -> String:
	return RANK_NAMES[rank(card)]

static func integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and value == floor(float(value))

# Array.has/find are type-sensitive; protocol JSON numbers arrive as floats.
static func index_number(values: Array, number: int) -> int:
	for i in range(values.size()):
		if values[i] == number: return i
	return -1

static func contains_number(values: Array, number: int) -> bool:
	return index_number(values, number) >= 0

static func sort_hand(cards: Array) -> Array:
	var result: Array = cards.map(func(c): return int(c))
	result.sort_custom(func(a, b): return rank(a) > rank(b) or (rank(a) == rank(b) and a > b))
	return result

static func _counts(cards: Array) -> Dictionary:
	var counts := {}
	for card in cards:
		var r := rank(int(card))
		counts[r] = int(counts.get(r, 0)) + 1
	return counts

static func _consecutive(ranks: Array) -> bool:
	if ranks.is_empty() or int(ranks.back()) > HIGHEST_CHAIN_RANK: return false
	for i in range(1, ranks.size()):
		if int(ranks[i]) != int(ranks[i - 1]) + 1: return false
	return true

# Returns {"type", "main", "length"} for a legal combination, or {} when the cards form none.
# "main" is the comparison rank (highest rank of the run for chains); "length" is the chain length.
static func classify(cards: Array) -> Dictionary:
	var n := cards.size()
	if n == 0: return {}
	var counts := _counts(cards)
	var ranks: Array = counts.keys()
	ranks.sort()
	if n == 1: return {"type": "single", "main": ranks[0], "length": 1}
	if n == 2:
		if counts.size() == 1: return {"type": "pair", "main": ranks[0], "length": 1}
		if counts.has(13) and counts.has(14): return {"type": "rocket", "main": 14, "length": 1}
		return {}
	var shape: Array = counts.values()
	shape.sort()
	if counts.size() == 1:
		if n == 3: return {"type": "triple", "main": ranks[0], "length": 1}
		if n == 4: return {"type": "bomb", "main": ranks[0], "length": 1}
	if n == 4 and shape == [1, 3]: return {"type": "triple_single", "main": _rank_with(counts, 3), "length": 1}
	if n == 5 and shape == [2, 3]: return {"type": "triple_pair", "main": _rank_with(counts, 3), "length": 1}
	if n >= 5 and shape.count(1) == n and _consecutive(ranks):
		return {"type": "straight", "main": ranks.back(), "length": n}
	if n >= 6 and n % 2 == 0 and shape.count(2) == counts.size() and counts.size() >= 3 and _consecutive(ranks):
		return {"type": "pair_chain", "main": ranks.back(), "length": counts.size()}
	if n == 6 and shape.has(4): return {"type": "four_two", "main": _rank_with(counts, 4), "length": 1}
	if n == 8 and shape == [2, 2, 4]: return {"type": "four_pairs", "main": _rank_with(counts, 4), "length": 1}
	return _airplane(counts, n)

static func _rank_with(counts: Dictionary, amount: int) -> int:
	for r in counts:
		if int(counts[r]) == amount: return int(r)
	return -1

# Airplanes: k >= 2 consecutive triples, optionally with k single kickers or k pair kickers.
# The highest valid run wins, so e.g. 333 444 555 666 can read as a 3-run with kickers.
static func _airplane(counts: Dictionary, n: int) -> Dictionary:
	var triples: Array = []
	for r in counts:
		if int(counts[r]) >= 3 and int(r) <= HIGHEST_CHAIN_RANK: triples.append(int(r))
	triples.sort()
	for k in range(mini(triples.size(), n / 3), 1, -1):
		for start in range(triples.size() - k, -1, -1):
			var run: Array = triples.slice(start, start + k)
			if not _consecutive(run): continue
			var rest := counts.duplicate()
			for r in run: rest[r] = int(rest[r]) - 3
			var remaining := n - 3 * k
			if remaining == 0: return {"type": "plane", "main": run.back(), "length": k}
			if remaining == k:
				# Kickers may not include both jokers (that would hide a rocket).
				if not (int(rest.get(13, 0)) > 0 and int(rest.get(14, 0)) > 0):
					return {"type": "plane_single", "main": run.back(), "length": k}
			if remaining == 2 * k:
				var pairs := 0
				var even := true
				for r in rest:
					if int(rest[r]) % 2 != 0: even = false
					pairs += int(rest[r]) / 2
				if even and pairs == k and not rest.has(13) and not rest.has(14):
					return {"type": "plane_pair", "main": run.back(), "length": k}
	return {}

# True when `play` may follow `lead` (an empty lead means a free lead).
static func beats(play: Dictionary, lead: Dictionary) -> bool:
	if play.is_empty(): return false
	if lead.is_empty(): return true
	if play.type == "rocket": return true
	if lead.type == "rocket": return false
	if play.type == "bomb" and lead.type != "bomb": return true
	return play.type == lead.type and int(play.length) == int(lead.length) and int(play.main) > int(lead.main)

# Suggested plays for the hint button and Debug legal actions, weakest first.
# Covers every type for free leads and following; kickers use the lowest spare cards.
static func hints(hand: Array, lead: Dictionary, limit: int = 24) -> Array:
	var by_rank := {}
	for card in sort_hand(hand):
		var r := rank(card)
		if not by_rank.has(r): by_rank[r] = []
		by_rank[r].push_front(card)
	var ranks: Array = by_rank.keys()
	ranks.sort()
	var result: Array = []
	var seen := {}
	var add := func(cards: Array) -> void:
		var combo := classify(cards)
		var key := str(sort_hand(cards))
		if not combo.is_empty() and beats(combo, lead) and not seen.has(key):
			seen[key] = true
			result.append(sort_hand(cards))
	var kinds: Array = ["single", "pair", "triple", "triple_single", "triple_pair", "straight", "pair_chain", "plane"] if lead.is_empty() else [lead.type]
	for kind in kinds:
		match kind:
			"single", "pair", "triple":
				var need: int = {"single": 1, "pair": 2, "triple": 3}[kind]
				# Prefer cards that do not break a larger group.
				for exact in [true, false]:
					for r in ranks:
						var size: int = by_rank[r].size()
						if (size == need) == exact and size >= need: add.call(by_rank[r].slice(0, need))
			"triple_single", "triple_pair":
				var kick: int = 1 if kind == "triple_single" else 2
				for r in ranks:
					if by_rank[r].size() < 3: continue
					for k in ranks:
						if k != r and by_rank[k].size() >= kick:
							add.call(by_rank[r].slice(0, 3) + by_rank[k].slice(0, kick))
							break
			"straight", "pair_chain", "plane":
				var width: int = {"straight": 1, "pair_chain": 2, "plane": 3}[kind]
				var lengths: Array = [int(lead.length)] if not lead.is_empty() else ([5] if kind == "straight" else [3] if kind == "pair_chain" else [2])
				for length in lengths:
					for start in range(0, HIGHEST_CHAIN_RANK - length + 2):
						var cards: Array = []
						for r in range(start, start + length):
							if not by_rank.has(r) or by_rank[r].size() < width:
								cards = []
								break
							cards += by_rank[r].slice(0, width)
						if not cards.is_empty(): add.call(cards)
			"plane_single", "plane_pair":
				var kick_size: int = 1 if kind == "plane_single" else 2
				var length: int = int(lead.length)
				for start in range(0, HIGHEST_CHAIN_RANK - length + 2):
					var body: Array = []
					for r in range(start, start + length):
						if not by_rank.has(r) or by_rank[r].size() < 3:
							body = []
							break
						body += by_rank[r].slice(0, 3)
					if body.is_empty(): continue
					var kickers: Array = []
					for r in ranks:
						if kickers.size() >= length * kick_size: break
						if r >= start and r < start + length: continue
						if by_rank[r].size() >= kick_size and (kick_size == 2 or r < 13 or not kickers.any(func(c): return rank(c) >= 13)):
							kickers += by_rank[r].slice(0, kick_size)
					if kickers.size() == length * kick_size: add.call(body + kickers)
			"four_two", "four_pairs":
				var kick_size: int = 1 if kind == "four_two" else 2
				for r in ranks:
					if by_rank[r].size() != 4: continue
					var kickers: Array = []
					for k in ranks:
						if k == r or kickers.size() >= 2 * kick_size: continue
						if by_rank[k].size() >= kick_size: kickers += by_rank[k].slice(0, kick_size)
					if kickers.size() == 2 * kick_size: add.call(by_rank[r] + kickers.slice(0, 2 * kick_size))
	# Bombs and the rocket always answer a lead (and are listed last on a free lead).
	for r in ranks:
		if by_rank[r].size() == 4: add.call(by_rank[r])
	if by_rank.has(13) and by_rank.has(14): add.call([52, 53])
	return result.slice(0, limit)
