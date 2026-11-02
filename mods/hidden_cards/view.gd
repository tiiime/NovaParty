extends VBoxContainer
signal command(action: Dictionary)

func render(snapshot: Dictionary) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var owned_focus := focused != null and is_ancestor_of(focused)
	var focused_card = focused.get_meta("card", -1) if owned_focus else -1
	var restore_focus := focused == null or owned_focus
	var candidates := []
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var state: Dictionary = snapshot.view
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = _t("CARDS_STATUS") % [mini(int(state.round) + 1, 3), str(state.scores), _t("YES") if state.submitted[1 - int(snapshot.seat)] else _t("NO")]
	add_child(label)
	var row := HBoxContainer.new()
	row.name = "Cards"
	add_child(row)
	for card in state.hand:
		var button := Button.new()
		button.name = "Card_" + str(int(card))
		button.text = _card(int(card))
		button.set_meta("card", card)
		button.custom_minimum_size = Vector2(100, 100)
		button.disabled = state.finished or state.chosen != -1 or snapshot.players.size() < 2
		button.pressed.connect(func(): call_deferred("_submit_card", card))
		row.add_child(button)
		if not button.disabled:
			candidates.append(button)
	if restore_focus and not candidates.is_empty():
		var target: Button = candidates[0]
		for candidate in candidates:
			if candidate.get_meta("card") == focused_card:
				target = candidate
		target.grab_focus()
	for cards in state.history:
		var history := Label.new()
		history.text = _t("REVEAL") % [_card(int(cards[0])), _card(int(cards[1]))]
		add_child(history)
	if state.finished:
		var done := Label.new()
		done.text = _t("GAME_OVER")
		add_child(done)

func _card(card: int) -> String:
	return ["♠", "♥", "♣", "♦"][card / 13] + ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"][card % 13]

# Wait until the button input callback has returned before snapshots rebuild it.
func _submit_card(card) -> void:
	command.emit({"type": "choose", "card": card})

func capture_view_state() -> Dictionary:
	var focused := get_viewport().gui_get_focus_owner()
	return {"focused_card": focused.get_meta("card", -1) if focused != null and is_ancestor_of(focused) else -1}

func restore_view_state(state: Dictionary) -> void:
	for row in get_children():
		for child in row.get_children():
			if child is Button and not child.disabled and child.get_meta("card", -1) == state.get("focused_card", -1):
				child.grab_focus()

# Catalogs travel with the Mod, including when loaded by an older SDK 1 client.
var localized_text := {}

func _t(key: String) -> String:
	if localized_text.is_empty():
		var root: String = get_script().resource_path.get_base_dir()
		for language in ["en", "zh"]:
			var data = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("locale-" + language + ".json")))
			localized_text[language] = data if data is Dictionary else {}
	var locale := TranslationServer.get_locale().get_slice("_", 0)
	var messages: Dictionary = localized_text.get(locale, localized_text.en)
	return str(messages.get(key, localized_text.en.get(key, key)))
