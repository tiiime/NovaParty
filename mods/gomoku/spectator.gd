extends VBoxContainer
const Board = preload("board.gd")
var board: Control
var heading: Label
var status: Label
var texts := {}

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	heading = _label(28)
	status = _label(21)
	var art := AspectRatioContainer.new()
	art.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(art)
	board = Board.new()
	board.custom_minimum_size = Vector2(184, 184)
	art.add_child(board)
	board.focus_mode = FOCUS_NONE
	board.mouse_filter = MOUSE_FILTER_IGNORE
	var path: String = get_script().resource_path.get_base_dir()
	var config = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("theme.json")))
	if config is Dictionary and config.get("board_color") is String:
		board.board_color = Color.from_string(config.board_color, board.board_color)
	for locale in ["en", "zh"]:
		texts[locale] = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("locale-" + locale + ".json")))

func render(snapshot: Dictionary) -> void:
	var view: Dictionary = snapshot.view
	var players: Array = snapshot.players
	heading.text = _t("GOMOKU") + "  ·  " + _t("SPECTATOR_LABEL")
	if view.finished:
		status.text = _t("WINNER_NAME") % players[int(view.winner)].nickname if view.winner >= 0 else _t("DRAW")
	elif players.size() < 2:
		status.text = _t("SPECTATOR_WAIT") % players.size()
	elif not players[0].connected or not players[1].connected:
		status.text = _t("PAUSED_DISCONNECTED")
	else:
		status.text = _t("SPECTATOR_TURN") % players[int(view.turn)].nickname
	board.cells = view.board
	board.last_move = int(view.last_move)
	board.winning_line = view.winning_line
	board.queue_redraw()

func _label(extent: int) -> Label:
	var label := Label.new()
	label.auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", extent)
	add_child(label)
	return label

func _t(key: String) -> String:
	return str(texts.zh.get(key, key) if TranslationServer.get_locale().begins_with("zh") else texts.en.get(key, key))
