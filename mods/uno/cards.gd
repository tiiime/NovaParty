extends RefCounted
const CAPACITY = 7 # Public display plus up to six players.
const COLORS = ["red", "yellow", "green", "blue"]
static func integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and value == floor(float(value))

static func info(card: int) -> Dictionary:
	if card >= 100:
		return {"color": -1, "rank": "wild" if card < 104 else "draw4", "points": 50}
	var local := card % 25
	var rank: String
	if local == 0:
		rank = "0"
	elif local <= 18:
		rank = str((local - 1) % 9 + 1)
	else:
		rank = "skip" if local <= 20 else "reverse" if local <= 22 else "draw2"
	return {"color": card / 25, "rank": rank, "points": int(rank) if rank.is_valid_int() else 20}

static func matches(card: int, view: Dictionary) -> bool:
	var data := info(card)
	if int(view.debt) > 0:
		return data.rank == "draw4" or (view.debt_kind == "draw2" and data.rank == "draw2")
	if data.color == -1:
		return true
	return data.color == int(view.color) or data.rank == info(int(view.top)).rank

# Array.has/find are type-sensitive; protocol JSON numbers arrive as floats.
static func index_number(values: Array, number: int) -> int:
	for i in range(values.size()):
		if values[i] == number: return i
	return -1

static func contains_number(values: Array, number: int) -> bool:
	return index_number(values, number) >= 0
