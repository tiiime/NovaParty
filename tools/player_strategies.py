"""Local player policies. Input is only the controlled seat's filtered snapshot."""
DIRECTIONS = ((1, 0), (0, 1), (1, 1), (1, -1))


def ready(snapshot):
    return (snapshot.get('in_room') and snapshot.get('connected', True)
            and len(snapshot.get('players', [])) == 2
            and all(p.get('connected') for p in snapshot['players'])
            and not snapshot.get('view', {}).get('finished', False))


def gomoku(snapshot):
    if not ready(snapshot):
        return None
    view, seat = snapshot['view'], int(snapshot['seat'])
    if snapshot.get('game_id') != 'gomoku' or view.get('turn') != seat:
        return None
    board = list(view['board'])
    if len(board) != 225:
        raise ValueError('invalid_gomoku_board')
    occupied = [i for i, value in enumerate(board) if value != -1]
    if not occupied:
        return {'type': 'place', 'x': 7, 'y': 7}
    candidates = set()
    for index in occupied:
        x, y = index % 15, index // 15
        for yy in range(max(0, y - 2), min(15, y + 3)):
            for xx in range(max(0, x - 2), min(15, x + 3)):
                if board[yy * 15 + xx] == -1:
                    candidates.add((xx, yy))
    if not candidates:
        return None
    scored = []
    for x, y in sorted(candidates):
        own = _score(board, x, y, seat)
        opponent = _score(board, x, y, 1 - seat)
        scored.append((x, y, own, opponent))
    wins = [item for item in scored if item[2] >= 1_000_000_000]
    blocks = [item for item in scored if item[3] >= 1_000_000_000]
    choices = wins or blocks or scored
    def priority(item):
        x, y, own, opponent = item
        value = own if wins else own + 1.1 * opponent
        return value, -abs(x - 7) - abs(y - 7), -y, -x
    x, y, _, _ = max(choices, key=priority)
    return {'type': 'place', 'x': x, 'y': y}


def _score(board, x, y, seat):
    index = y * 15 + x
    board[index] = seat
    total, open_threes = 0, 0
    winning_holes = set()
    try:
        for dx, dy in DIRECTIONS:
            line, coordinates = '', []
            for distance in range(-4, 5):
                xx, yy = x + dx * distance, y + dy * distance
                coordinates.append((xx, yy))
                value = board[yy * 15 + xx] if 0 <= xx < 15 and 0 <= yy < 15 else 2
                line += 'X' if value == seat else '.' if value == -1 else '#'
            left, right = 3, 5
            while left >= 0 and line[left] == 'X':
                left -= 1
            while right < 9 and line[right] == 'X':
                right += 1
            count = right - left - 1
            ends = int(left >= 0 and line[left] == '.') + int(right < 9 and line[right] == '.')
            if count >= 5:
                return 1_000_000_000
            for start in range(5):
                window = line[start:start + 5]
                if window.count('X') == 4 and window.count('.') == 1:
                    winning_holes.add(coordinates[start + window.index('.')])
            is_three = False
            for pattern in ('.XXX.', '.XX.X.', '.X.XX.'):
                for start in range(10 - len(pattern)):
                    if start <= 4 < start + len(pattern) and line[start:start + len(pattern)] == pattern:
                        is_three = True
            if is_three:
                open_threes += 1
                total += 60_000
            elif count == 3 and ends:
                total += 1_200
            elif count == 2:
                total += 600 if ends == 2 else 50 if ends else 0
            elif count == 1:
                total += 10 * ends
        if len(winning_holes) >= 2:
            return 20_000_000 + total
        if winning_holes:
            total += 250_000
        if open_threes >= 2:
            total += 2_000_000
        return total
    finally:
        board[index] = -1


def first_legal(snapshot, actions):
    """Generic adapter: decisions are restricted to SDK-provided legal actions."""
    return actions[0] if ready(snapshot) and actions else None
