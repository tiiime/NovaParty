extends "res://app/ui/widgets/sheet.gd"
signal canceled
var title: Label
var detail: Label
var amount: Label
var bar: ProgressBar
var confirm: Button
var cancel: Button
var working := false

func _ready() -> void:
	super._ready()
	done.hide()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	add_content(body)
	title = Style.label(Label.new(), T.FONT_SIZE_TITLE, T.FONT_WEIGHT_TITLE)
	title.text = "DOWNLOAD_GAME_TITLE"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(title)
	detail = Style.label(Label.new(), T.FONT_SIZE_META, T.FONT_WEIGHT_BODY, T.MUTED)
	detail.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)
	amount = Style.label(Label.new(), T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL)
	amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.add_child(amount)
	bar = ProgressBar.new()
	Style.progress(bar)
	body.add_child(bar)
	var footer: VBoxContainer = panel.get_child(0)
	confirm = Button.new()
	confirm.text = "DOWNLOAD_AND_JOIN"
	confirm.set_meta("haptic", "confirm")
	Style.button(confirm, "primary")
	footer.add_child(confirm)
	confirm.pressed.connect(func():
		if working: return
		working = true
		confirm.hide()
		amount.show()
		bar.show()
		cancel.grab_focus()
		confirmed.emit()
	)
	cancel = Button.new()
	cancel.text = "CANCEL"
	cancel.set_meta("sound_cue", "back")
	Style.button(cancel, "secondary", T.BUTTON_HEIGHT_SMALL)
	footer.add_child(cancel)
	cancel.pressed.connect(close)

func ask(text: String) -> void:
	working = false
	detail.text = text
	confirm.show()
	bar.hide()
	amount.hide()
	update_progress(0, 1)
	popup_centered(Vector2i(558, 560))
	cancel.grab_focus()

func update_progress(received: int, total: int) -> void:
	bar.value = 100.0 * received / maxi(total, 1)
	amount.text = tr("DOWNLOADING_PERCENT") % int(bar.value)

func close() -> void:
	hide()
	canceled.emit()
