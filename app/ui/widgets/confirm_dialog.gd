extends "res://app/ui/widgets/sheet.gd"
# Two-choice sheet. The safe choice is focused first; back/escape always cancels.
signal canceled
var heading: Label
var message: Label
var ok_button: Button
var cancel_button: Button

func _ready() -> void:
	super._ready()
	done.hide()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	add_content(body)
	heading = Style.label(Label.new(), T.FONT_SIZE_TITLE, T.FONT_WEIGHT_TITLE)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(heading)
	message = Style.label(Label.new(), T.FONT_SIZE_BODY, T.FONT_WEIGHT_BODY, T.MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(message)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	panel.get_child(0).add_child(footer)
	cancel_button = Button.new()
	cancel_button.set_meta("sound_cue", "back")
	Style.button(cancel_button, "secondary")
	ok_button = Button.new()
	Style.button(ok_button, "danger")
	for button in [cancel_button, ok_button]:
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(button)
	cancel_button.pressed.connect(close)
	ok_button.pressed.connect(func(): hide(); confirmed.emit())
	for pair in [[cancel_button, ok_button], [ok_button, cancel_button]]:
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			pair[0].set_focus_neighbor(side, pair[0].get_path_to(pair[1]))
		for side in [SIDE_TOP, SIDE_BOTTOM]:
			pair[0].set_focus_neighbor(side, pair[0].get_path())
		pair[0].focus_next = pair[0].get_path_to(pair[1])
		pair[0].focus_previous = pair[0].get_path_to(pair[1])

func setup(title_key: String, text_key: String, ok_key: String, cancel_key: String, kind: String = "danger") -> void:
	heading.text = title_key
	message.text = text_key
	ok_button.text = ok_key
	cancel_button.text = cancel_key
	Style.button(ok_button, kind)

func get_cancel_button() -> Button:
	return cancel_button

func get_ok_button() -> Button:
	return ok_button

func popup_centered(target: Vector2i) -> void:
	super.popup_centered(target)
	cancel_button.grab_focus()

func close() -> void:
	hide()
	canceled.emit()
