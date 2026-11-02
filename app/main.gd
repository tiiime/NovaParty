extends Control
const Loader = preload("res://sdk/mod_loader.gd")
const Session = preload("res://sdk/session.gd")
const I18n = preload("res://app/i18n.gd")
const Style = preload("res://app/ui/party_theme.gd")
const UI_API = 1
const JoinCode = preload("res://sdk/join_code.gd")
var qr_scanner
var join_invite
var invite_dismissed := false
const Discovery = preload("res://sdk/discovery.gd")
const PeerMods = preload("res://sdk/peer_mods.gd")
var discovery
var join_browser
var download_dialog
var peer_transfer
var peer_target := {}
var peer_phase := "idle"
var peer_error := ""
var expected_join_session := ""
var shell_managed := false
var ui_preparing := false
var ui_ready := false
var home
var network_row: HBoxContainer
var create_button: Button
var join_button: Button
var reconnect_button: Button
var leave_button: Button
var settings_action: Button
var page_title: Label
var settings_dialog
var language_choice: OptionButton
var library
var library_help: Label
var footer: BoxContainer
var footer_nav: HBoxContainer
var footer_session: HBoxContainer
var back_button: Button
var motion_choice: CheckBox
var sound_choice: CheckBox
var ui_feedback
var page_tween: Tween
var leave_dialog: ConfirmationDialog
var status_key := "LOBBY_HELP"
var status_arguments: Array = []
var settings_opening := false
var loader = Loader.new()
var debug_service
var session
var room_generation := 0
var profile := {}
var profile_path := "user://profile.json"
var content_margin: MarginContainer
var package_dialog: FileDialog
var setup: VBoxContainer
var choices: OptionButton
var nickname: LineEdit
var address: LineEdit
var port: SpinBox
var status: Label
var roster: Label
var game_area: VBoxContainer
var game_view
var immersive_game := false
var mod_info := {}
var token := ""
var joined := false
var known_mods := {}
var roots := ["res://mods/gomoku"]

func _ready() -> void:
	if not I18n.install():
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			profile_path = "user://profile_" + argument.substr(10).sha256_text().left(12) + ".json"
	var saved = JSON.parse_string(FileAccess.get_file_as_string(profile_path)) if FileAccess.file_exists(profile_path) else null
	profile = saved if saved is Dictionary and saved.has("id") else {"id": Crypto.new().generate_random_bytes(16).hex_encode(), "nickname": ""}
	ui_feedback = preload("res://app/ui/ui_feedback.gd").new()
	set_meta("ui_feedback", ui_feedback)
	add_child(ui_feedback)
	I18n.select(str(profile.get("language", "system")))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--locale="):
			I18n.select(argument.trim_prefix("--locale="))
	var ui_theme := Theme.new()
	var ui_font := FontVariation.new()
	ui_font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	ui_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 400.0}
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 24
	ui_theme.set_color("font_color", "Label", Style.INK)
	ui_theme.set_color("font_color", "CheckBox", Style.INK)
	for state in ["font_pressed_color", "font_focus_color", "font_hover_color", "font_hover_pressed_color"]:
		ui_theme.set_color(state, "CheckBox", Style.INK)
	ui_theme.set_stylebox("panel", "PopupMenu", Style.pill(Color.WHITE, 20))
	ui_theme.set_color("font_color", "PopupMenu", Style.INK)
	ui_theme.set_color("font_color", "LineEdit", Style.INK)
	ui_theme.set_color("font_placeholder_color", "LineEdit", Color("506786"))
	ui_theme.set_stylebox("normal", "LineEdit", Style.pill(Color("f0f5ff"), 12, Color("c6d9f6"), 2))
	ui_theme.set_stylebox("focus", "LineEdit", Style.pill(Color("f0f5ff"), 12, Style.BLUE, 3))
	for key in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		ui_theme.set_color(key, "OptionButton", Style.INK)
	ui_theme.set_stylebox("normal", "OptionButton", Style.pill(Color("e6f0ff"), 12))
	ui_theme.set_stylebox("hover", "OptionButton", Style.pill(Color("dceaff"), 12))
	ui_theme.set_stylebox("focus", "OptionButton", Style.pill(Color.TRANSPARENT, 12, Style.BLUE, 3))
	ui_theme.set_stylebox("focus", "CheckBox", Style.focus_box(12))
	theme = ui_theme
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	if not shell_managed:
		get_window().close_requested.connect(func(): get_tree().quit())
		get_window().go_back_requested.connect(_go_back)
		get_window().size_changed.connect(_adapt_display)
	_adapt_display()
	var background := ColorRect.new()
	background.color = Color("eef4ff")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	home = preload("res://app/ui/party_home.gd").new()
	add_child(home)
	home.start_requested.connect(func(): _open_setup(true))
	home.join_requested.connect(func(): _open_setup(false))
	home.settings_requested.connect(_open_settings)
	home.set_reduced_motion(bool(profile.get("reduce_motion", false)))
	var margin := MarginContainer.new()
	content_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 16)
	margin.add_child(shell)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	Style.scroll_container(scroll)
	shell.add_child(scroll)
	var scroll_content := MarginContainer.new()
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.add_theme_constant_override("margin_right", 16)
	scroll_content.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(scroll_content)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	scroll_content.add_child(layout)
	page_title = _label(layout, "APP_NAME", 32)
	setup = VBoxContainer.new()
	setup.add_theme_constant_override("separation", 12)
	layout.add_child(setup)
	# Internal selection/identity adapters remain available to the session and debug API.
	# They are not user-facing form fields.
	nickname = LineEdit.new()
	nickname.text = profile.get("nickname", "")
	nickname.hide()
	add_child(nickname)
	choices = OptionButton.new()
	choices.hide()
	add_child(choices)
	library_help = _label(setup, "PICK_GAME_HELP", 21)
	library = preload("res://app/ui/game_library.gd").new()
	setup.add_child(library)
	library.selected.connect(func(index):
		choices.select(index)
		if create_button.visible:
			create_button.grab_focus()
	)
	library.add_requested.connect(_choose_package)
	library.navigation_changed.connect(_update_setup_focus)
	for root in roots:
		_add_choice(root)
	package_dialog = FileDialog.new()
	package_dialog.access = FileDialog.ACCESS_FILESYSTEM
	package_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	package_dialog.use_native_dialog = true
	package_dialog.add_filter("*.zip", tr("MOD_FILTER"), "application/zip")
	package_dialog.file_selected.connect(_install_package)
	add_child(package_dialog)
	network_row = HBoxContainer.new()
	setup.add_child(network_row)
	address = LineEdit.new()
	address.text = profile.get("last_address", "")
	address.placeholder_text = "HOST_ADDRESS"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	network_row.add_child(address)
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 27840
	network_row.add_child(port)
	footer = BoxContainer.new()
	footer.vertical = true
	footer.resized.connect(_adapt_footer, CONNECT_DEFERRED)
	footer.add_theme_constant_override("separation", 12)
	shell.add_child(footer)
	create_button = _button(footer, "LAUNCH_GAME", func(): _start(true))
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button = _button(footer, "JOIN_GAME", func(): token = ""; _start(false))
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var actions := HBoxContainer.new()
	footer_nav = actions
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 12)
	footer.add_child(actions)
	back_button = _button(actions, "BACK", _go_back, true)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var session_actions := HBoxContainer.new()
	footer_session = session_actions
	session_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_actions.add_theme_constant_override("separation", 12)
	footer.add_child(session_actions)
	reconnect_button = _button(session_actions, "RECONNECT", func():
		if joined and not token.is_empty():
			_start(false)
		else:
			_set_status("NO_RESUME")
	, true)
	leave_button = _button(session_actions, "LEAVE_ROOM", _request_leave, true)
	reconnect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_action = _button(actions, "SETTINGS", _open_settings, true)
	settings_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status = _label(layout, "LOBBY_HELP")
	roster = _label(layout, "")
	roster.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	game_area = VBoxContainer.new()
	layout.add_child(game_area)
	_build_settings()
	_build_leave_dialog()
	_build_lan_ui()
	for path in loader.installed_packages():
		var mod_root: String = loader.mount_zip(path)
		if not mod_root.is_empty():
			_add_choice(mod_root)
	_refresh_translations()
	_save_profile()
	_show_home()
	_apply_safe_area.call_deferred()
	ui_ready = true
	ui_feedback.welcome.call_deferred()
	if not shell_managed and OS.is_debug_build() and OS.has_feature("novaparty_debug"):
		debug_service = load("res://debug/service.gd").new()
		debug_service.app = self
		add_child(debug_service)

func _label(parent: Node, key: String, font_size: int = 22) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, key: String, callback: Callable, secondary: bool = false) -> Button:
	var button := Button.new()
	button.text = key
	button.set_meta("sound_cue", "launch" if key == "LAUNCH_GAME" else "back" if key in ["BACK", "CANCEL", "CLOSE"] else "confirm")
	Style.button(button, secondary)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _open_setup(as_host: bool) -> void:
	home.hide()
	content_margin.show()
	setup.show()
	network_row.visible = false
	library.visible = as_host
	join_browser.visible = not as_host
	if as_host:
		discovery.stop_browse()
	else:
		discovery.browse()
	create_button.visible = as_host
	settings_action.visible = not as_host
	join_button.visible = false
	reconnect_button.hide()
	leave_button.hide()
	page_title.text = "SETUP_TITLE" if as_host else "JOIN_TITLE"
	library_help.text = "PICK_GAME_HELP" if as_host else "JOIN_HELP"
	roster.hide()
	status.hide()
	_refresh_library()
	_set_status("LOBBY_HELP" if as_host else "JOIN_HELP")
	_adapt_footer.call_deferred()
	if as_host:
		library.focus_selected()
	else:
		join_browser.focus_default()
	_animate_page(content_margin)

func _show_home() -> void:
	if peer_transfer != null:
		_cancel_peer_join()
	if discovery != null:
		discovery.stop_browse()
	content_margin.hide()
	home.show()
	_refresh_home()
	if not ui_preparing:
		home.start_button.grab_focus()
	_animate_page(home)

func _animate_page(page: Control) -> void:
	if page_tween != null: page_tween.kill()
	home.modulate = Color.WHITE
	content_margin.modulate = Color.WHITE
	if ui_preparing or ui_feedback.reduced_motion(): return
	page.modulate.a = 0.72
	page_tween = create_tween()
	page_tween.tween_property(page, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _refresh_home() -> void:
	if home and nickname:
		home.set_nickname(nickname.text if not nickname.text.is_empty() else tr("PLAYER_DEFAULT"))

func _set_status(key: String, arguments: Array = []) -> void:
	status_key = key
	status_arguments = arguments
	status.text = tr(key) % arguments if not arguments.is_empty() else tr(key)
	status.visible = not immersive_game and key not in ["LOBBY_HELP", "JOIN_HELP", "LEFT_ROOM"]
	_send_game_status()

func _handle_notice(code: String) -> void:
	if peer_phase == "joining" and code in ["room_changed", "room_full", "incompatible", "connect_failed", "connection_lost"]:
		_clear_session()
		_open_setup(false)
		_peer_failed(code)
		return
	if is_instance_valid(game_view) and game_view.has_method("on_command_notice") and game_view.on_command_notice(code):
		return
	var messages := {"disconnected": "RECONNECT_FIRST", "connection_lost": "CONNECTION_LOST", "not_your_turn": "ERR_NOT_YOUR_TURN", "occupied": "ERR_OCCUPIED", "stale_revision": "ERR_STALE_REVISION", "game_finished": "ERR_GAME_FINISHED", "waiting_for_players": "ERR_WAITING_PLAYERS", "invalid_action": "ERR_INVALID_ACTION", "already_chosen": "ERR_ALREADY_CHOSEN", "card_not_owned": "ERR_CARD_NOT_OWNED", "game_not_finished": "ERR_GAME_NOT_FINISHED", "already_requested": "ERR_ALREADY_REQUESTED"}
	_set_status(messages.get(code, "NETWORK_ERROR"), [] if messages.has(code) else [code])

func _build_settings() -> void:
	settings_dialog = preload("res://app/ui/settings_panel.gd").new()
	settings_dialog.theme = theme
	var settings_layer := CanvasLayer.new()
	settings_layer.layer = 50
	add_child(settings_layer)
	settings_layer.add_child(settings_dialog)
	settings_dialog.visibility_changed.connect(func():
		_send_game_status()
		for button in [home.start_button, home.join_button, home.nickname_button, home.settings_button]:
			button.focus_mode = Control.FOCUS_NONE if settings_dialog.visible else Control.FOCUS_ALL
	)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	settings_dialog.add_content(body)
	_label(body, "SETTINGS", 32)
	_label(body, "LANGUAGE")
	language_choice = OptionButton.new()
	for entry in [["LANG_SYSTEM", "system"], ["简体中文", "zh_CN"], ["English", "en"]]:
		language_choice.add_item(entry[0])
		language_choice.set_item_metadata(language_choice.item_count - 1, entry[1])
	body.add_child(language_choice)
	language_choice.item_selected.connect(func(index): set_language(language_choice.get_item_metadata(index)))
	sound_choice = CheckBox.new()
	sound_choice.text = "UI_SOUNDS"
	body.add_child(sound_choice)
	sound_choice.toggled.connect(func(value):
		profile.ui_sounds = value
		ui_feedback.refresh_preferences()
		if value: ui_feedback.play("confirm")
		_save_profile()
	)
	motion_choice = CheckBox.new()
	motion_choice.text = "REDUCE_MOTION"
	body.add_child(motion_choice)
	motion_choice.toggled.connect(func(value):
		profile.reduce_motion = value
		home.set_reduced_motion(value)
		ui_feedback.refresh_preferences()
		_send_game_status()
		_save_profile()
	)
	var help := _label(body, "REDUCE_MOTION_HELP", 19)
	help.custom_minimum_size.x = 360
	body.custom_minimum_size.x = 380
	var credit := RichTextLabel.new()
	credit.bbcode_enabled = true
	credit.fit_content = true
	credit.scroll_active = false
	credit.add_theme_font_size_override("normal_font_size", 16)
	credit.add_theme_color_override("default_color", Style.INK)
	credit.text = "[url=https://heyheythere.itch.io/soft-ui-sfx-free]Soft UI SFX Free[/url] · heyheythere\n[url=https://creativecommons.org/licenses/by/4.0/]CC BY 4.0[/url]"
	credit.meta_clicked.connect(func(url): OS.shell_open(str(url)))
	body.add_child(credit)
	Style.button(settings_dialog.get_ok_button())
	settings_dialog.confirmed.connect(func():
		_save_profile()
		_refresh_home()
		if home.visible:
			home.settings_button.grab_focus()
		elif immersive_game and game_view.has_method("restore_platform_focus"):
			game_view.restore_platform_focus("settings")
		elif create_button.visible:
			library.focus_selected()
		else:
			settings_action.grab_focus()
	)

func _open_settings() -> void:
	if settings_opening:
		return
	settings_opening = true
	sound_choice.set_pressed_no_signal(bool(profile.get("ui_sounds", true)))
	motion_choice.set_pressed_no_signal(bool(profile.get("reduce_motion", false)))
	for index in range(language_choice.item_count):
		if language_choice.get_item_metadata(index) == profile.get("language", "system"):
			language_choice.select(index)
	settings_opening = false
	settings_dialog.popup_centered(Vector2i(mini(520, int(get_viewport_rect().size.x - 48)), 620))
	# Keep directional and Tab navigation inside this modal, also during a game.
	var focus_order := [language_choice, sound_choice, motion_choice, settings_dialog.get_ok_button()]
	for index in range(focus_order.size()):
		var control: Control = focus_order[index]
		control.focus_neighbor_top = control.get_path_to(focus_order[(index + focus_order.size() - 1) % focus_order.size()])
		control.focus_neighbor_bottom = control.get_path_to(focus_order[(index + 1) % focus_order.size()])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom
		control.focus_neighbor_left = control.get_path()
		control.focus_neighbor_right = control.get_path()
	language_choice.grab_focus()

func set_language(language: String) -> void:
	profile.language = language if language in ["system", "zh_CN", "en"] else "system"
	I18n.select(profile.language)
	_refresh_translations()
	_save_profile()

func _refresh_translations() -> void:
	get_window().title = tr("APP_NAME")
	if not is_instance_valid(choices):
		return
	for index in range(choices.item_count):
		var info: Dictionary = loader.inspect(choices.get_item_metadata(index))
		if not info.is_empty():
			choices.set_item_text(index, I18n.game_name(info))
	_refresh_library()
	language_choice.set_item_text(0, tr("LANG_SYSTEM"))
	_refresh_home()
	if not status_key.is_empty():
		_set_status(status_key, status_arguments)
	if is_instance_valid(session) and not session.snapshot.is_empty():
		_render_snapshot(session.snapshot)

func _build_leave_dialog() -> void:
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "EXIT_MATCH_TITLE"
	leave_dialog.dialog_text = "EXIT_MATCH_TEXT"
	leave_dialog.dialog_autowrap = true
	leave_dialog.ok_button_text = "CONFIRM_LEAVE"
	leave_dialog.cancel_button_text = "CANCEL"
	Style.button(leave_dialog.get_ok_button())
	Style.button(leave_dialog.get_cancel_button(), true)
	leave_dialog.confirmed.connect(_leave)
	leave_dialog.canceled.connect(_restore_exit_focus)
	leave_dialog.visibility_changed.connect(_send_game_status)
	add_child(leave_dialog)

func _request_leave() -> void:
	if is_instance_valid(session):
		leave_dialog.popup_centered(Vector2i(mini(580, int(get_viewport_rect().size.x - 48)), 220))

func _render_snapshot(data: Dictionary) -> void:
	token = session.resume_token
	if data.players.size() == 2:
		if data.players[1 - int(data.seat)].connected:
			_set_status("CONNECTED", [int(data.seat) + 1])
		else:
			_set_status("PEER_OFFLINE")
	game_view.render(data)
	_send_game_status()
	_update_join_invite()
	var names := []
	for player in data.players:
		names.append(player.nickname + " · " + tr("ONLINE" if player.connected else "OFFLINE"))
	roster.text = tr("ROSTER") % [" / ".join(names), int(data.revision)]

func _refresh_library() -> void:
	if not is_instance_valid(library):
		return
	var focused := get_viewport().gui_get_focus_owner()
	var focus_index: int = library.cards.find(focused) if focused is Button else -1
	var items := []
	for index in range(choices.item_count):
		var info: Dictionary = loader.inspect(choices.get_item_metadata(index))
		if info.is_empty():
			continue
		var cover_path := ""
		var cover = info.manifest.get("cover", "")
		if cover is String and not cover.is_empty() and info.manifest.files.has(cover):
			cover_path = str(info.root).path_join(cover)
		items.append({"id": info.manifest.id, "name": I18n.game_name(info), "cover_path": cover_path})
	library.populate(items, choices.selected)
	if focus_index >= 0 and focus_index < library.cards.size():
		library.cards[focus_index].grab_focus()

func _add_choice(root: String) -> void:
	var info: Dictionary = loader.inspect(root)
	if info.is_empty():
		return
	known_mods[root] = info
	for index in range(choices.item_count):
		var existing: Dictionary = loader.inspect(choices.get_item_metadata(index))
		if not existing.is_empty() and existing.manifest.id == info.manifest.id:
			choices.set_item_metadata(index, root)
			choices.set_item_text(index, I18n.game_name(info))
			_refresh_library()
			return
	choices.add_item(I18n.game_name(info))
	choices.set_item_metadata(choices.item_count - 1, root)
	_refresh_library()

func _start(as_host: bool) -> Error:
	# Keep the selected game stable for a resume attempt.
	var root: String = choices.get_item_metadata(choices.selected)
	if not as_host and not token.is_empty() and not mod_info.is_empty() and root != mod_info.root:
		_set_status("RESUME_GAME_MISMATCH")
		return ERR_INVALID_DATA
	_clear_session()
	mod_info = loader.inspect(root)
	if mod_info.is_empty():
		_set_status("NETWORK_ERROR", [loader.error])
		return ERR_INVALID_DATA
	var logic = loader.rules(mod_info)
	if logic == null:
		_set_status("NETWORK_ERROR", [loader.error])
		return ERR_INVALID_DATA
	profile.last_address = address.text.strip_edges()
	profile.nickname = nickname.text.strip_edges().left(32)
	if profile.nickname.is_empty():
		profile.nickname = tr("PLAYER_DEFAULT")
	_save_profile()
	var view_script = load(root.path_join(mod_info.manifest.view))
	game_view = view_script.new()
	game_area.add_child(game_view)
	session = Session.new()
	session.expected_remote_session = expected_join_session
	expected_join_session = ""
	room_generation += 1
	(get_parent() if shell_managed else self).add_child(session)
	game_view.command.connect(session.submit)
	_connect_game_controls(game_view)
	session.updated.connect(_render_snapshot)
	session.notice.connect(_handle_notice)
	var error: Error
	joined = not as_host
	if as_host:
		token = ""
		error = session.create(mod_info, logic, profile, int(port.value))
	else:
		error = session.join(mod_info, profile, address.text.strip_edges(), int(port.value), token)
	if as_host:
		_set_status("ROOM_CREATED", [_local_addresses()])
	else:
		_set_status("CONNECTING")
	if error == OK:
		discovery.stop_browse()
		home.hide()
		content_margin.show()
		setup.hide()
		create_button.hide()
		join_button.hide()
		settings_action.show()
		roster.show()
		reconnect_button.show()
		leave_button.show()
		page_title.text = "APP_NAME"
		_layout_game()
		if join_invite.visible:
			join_invite.done.grab_focus()
		elif game_view.has_method("focus_default"):
			game_view.focus_default()
	if error != OK:
		setup.show()
		_set_status("CONNECT_FAILED", [error_string(error)])
		_clear_session()
	return error

func _clear_session() -> void:
	invite_dismissed = false
	if join_invite != null:
		join_invite.hide()
	if session != null:
		room_generation += 1
		session.get_parent().remove_child(session)
		session.queue_free()
		session = null
	if game_view != null:
		game_area.remove_child(game_view)
		game_view.queue_free()
		game_view = null
	immersive_game = false
	page_title.show()
	footer.show()
	game_area.custom_minimum_size.y = 0

func _leave() -> void:
	_clear_session()
	setup.show()
	token = ""
	joined = false
	roster.text = ""
	_set_status("LEFT_ROOM")
	_show_home()

func _local_addresses() -> String:
	var addresses := []
	for ip in IP.get_local_addresses():
		if ip.contains(".") and not ip.contains(":") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			addresses.append(ip)
	return ", ".join(addresses) if not addresses.is_empty() else tr("NO_NETWORK")

func _save_profile() -> void:
	if ui_preparing:
		return
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(profile))

func _install_package(path: String) -> void:
	if session != null:
		_set_status("LEAVE_FIRST")
		return
	var info: Dictionary = loader.install_zip(path)
	if info.is_empty():
		_set_status("NETWORK_ERROR", [loader.error])
		return
	_add_choice(info.root)
	choices.select(choices.item_count - 1)
	_refresh_library()
	library.focus_selected()
	_set_status("INSTALLED_MOD", [I18n.game_name(info)])

func _choose_package() -> void:
	if session != null:
		_set_status("LEAVE_FIRST")
		return
	if OS.has_feature("android"):
		# Some custom ROM version strings make Godot 4.6.1's native-dialog
		# feature check return false. Invoke the Android SAF implementation directly.
		var result := DisplayServer.file_dialog_show(tr("ADD_GAME"), "", "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray(["*.zip;" + tr("MOD_FILTER") + ";application/zip"]),
			func(ok: bool, paths: PackedStringArray, _filter: int):
				if ok and not paths.is_empty():
					_install_package(paths[0])
		)
		if result != OK:
			_set_status("FILE_DIALOG_FAILED", [error_string(result)])
	else:
		package_dialog.popup_centered_ratio(0.8)

func _adapt_footer() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(footer_nav) or not is_instance_valid(footer_session):
		return
	var portrait := get_viewport_rect().size.x < 760
	footer.vertical = portrait
	var order := [create_button, join_button, footer_nav, footer_session] if portrait else [footer_nav, footer_session, create_button, join_button]
	for index in range(order.size()):
		footer.move_child(order[index], index)
	_update_setup_focus()

func _update_setup_focus() -> void:
	if not is_instance_valid(create_button) or not is_instance_valid(settings_action):
		return
	var selecting: bool = library.visible and create_button.visible and not network_row.visible
	library.set_launch_target(create_button if selecting else null)
	for button in [create_button, back_button, settings_action]:
		for direction in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			button.set_focus_neighbor(direction, NodePath(""))
		button.focus_next = NodePath("")
		button.focus_previous = NodePath("")
	if not selecting or library.cards.is_empty():
		return
	var previous: Button = library.return_focus_card()
	var portrait := get_viewport_rect().size.x < 760
	for button in [create_button, back_button]:
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(button)
	back_button.focus_neighbor_left = back_button.get_path_to(back_button)
	back_button.focus_neighbor_right = back_button.get_path_to(back_button if portrait else create_button)
	create_button.focus_neighbor_left = create_button.get_path_to(create_button if portrait else back_button)
	create_button.focus_neighbor_right = create_button.get_path_to(create_button)
	if portrait:
		create_button.focus_neighbor_bottom = create_button.get_path_to(back_button)
		back_button.focus_neighbor_top = back_button.get_path_to(create_button)
	create_button.focus_previous = create_button.get_path_to(library.cards.back())
	create_button.focus_next = create_button.get_path_to(back_button)
	back_button.focus_previous = back_button.get_path_to(create_button)
	back_button.focus_next = back_button.get_path_to(library.cards.front())

func _adapt_display() -> void:
	var window := get_window()
	var target := Vector2i(1280, 720) if window.size.x > window.size.y else Vector2i(540, 960)
	if window.content_scale_size != target:
		window.content_scale_size = target
	if is_instance_valid(content_margin):
		_apply_safe_area.call_deferred()
		_adapt_footer.call_deferred()

func _go_back() -> void:
	if qr_scanner != null and qr_scanner.active:
		qr_scanner.stop()
	elif join_invite != null and join_invite.visible:
		join_invite.hide()
		invite_dismissed = true
	elif peer_transfer != null or (download_dialog != null and download_dialog.visible):
		_cancel_peer_join()
	elif settings_dialog.visible:
		settings_dialog.close()
	elif leave_dialog.visible:
		leave_dialog.hide()
		_restore_exit_focus()
	elif is_instance_valid(game_view) and game_view.has_method("handle_platform_back") and game_view.handle_platform_back():
		pass
	elif session != null:
		_request_leave()
	elif setup.visible and create_button.visible and get_viewport().gui_get_focus_owner() == create_button:
		ui_feedback.play("back")
		library.focus_selected()
	elif not home.visible:
		ui_feedback.play("back")
		_show_home()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()

# Called only by the Debug hot-update manager. Session/rules remain alive.
func debug_replace_view(info: Dictionary) -> Dictionary:
	if not OS.is_debug_build() or not OS.has_feature("novaparty_debug"):
		return {"error": "debug_disabled"}
	if not is_instance_valid(session) or session.snapshot.is_empty():
		return {"error": "not_ready"}
	if info.manifest.id != session.info.manifest.id or info.rules_fingerprint != session.info.rules_fingerprint:
		return {"error": "rules_changed_during_game"}
	var script = load(info.root.path_join(info.manifest.view))
	if not script is GDScript or not script.can_instantiate() or not ClassDB.is_parent_class(script.get_instance_base_type(), "Control"):
		return {"error": "invalid_view_script"}
	var candidate = script.new()
	if not candidate is Control or not candidate.has_signal("command") or not candidate.has_method("render"):
		if candidate is Node:
			candidate.free()
		return {"error": "invalid_view_contract"}
	var old = game_view
	var focused := get_viewport().gui_get_focus_owner()
	var owned_focus: bool = focused != null and (focused == old or old.is_ancestor_of(focused))
	var focus_path: NodePath = old.get_path_to(focused) if owned_focus else NodePath("")
	var view_state: Dictionary = old.capture_view_state() if old.has_method("capture_view_state") else {}
	candidate.hide()
	game_area.add_child(candidate)
	candidate.render(session.snapshot.duplicate(true))
	# Connect only after prepare/render: initialization cannot submit an action.
	old.command.disconnect(session.submit)
	game_view = candidate
	candidate.command.connect(session.submit)
	_connect_game_controls(candidate)
	game_area.remove_child(old)
	old.queue_free()
	candidate.show()
	if candidate.has_method("restore_view_state"):
		candidate.restore_view_state(view_state)
	if owned_focus:
		var target = candidate.get_node_or_null(focus_path)
		if target is Control and target.focus_mode != Control.FOCUS_NONE:
			target.grab_focus()
	elif is_instance_valid(focused):
		focused.grab_focus()
	mod_info = info
	session.update_presentation(info)
	_layout_game()
	return {"replaced": true, "view_state": debug_view_state()}

func debug_view_state() -> Dictionary:
	if is_instance_valid(game_view) and game_view.has_method("capture_view_state"):
		var state: Dictionary = game_view.capture_view_state()
		state["command_connections"] = game_view.get_signal_connection_list("command").size()
		return state
	return {}

func debug_select_build(info: Dictionary) -> void:
	known_mods[info.root] = info
	for index in range(choices.item_count):
		var existing: Dictionary = loader.inspect(choices.get_item_metadata(index))
		if not existing.is_empty() and existing.manifest.id == info.manifest.id:
			choices.set_item_metadata(index, info.root)
			choices.set_item_text(index, I18n.game_name(info))
			_refresh_library()
			return
	_add_choice(info.root)

# Lifecycle mutations are authenticated and context-checked by debug/room_control.gd.
func debug_room_command(method: String, params: Dictionary) -> Dictionary:
	if not OS.is_debug_build() or not OS.has_feature("novaparty_debug"):
		return {"error": "debug_disabled"}
	if method == "room.leave":
		if not is_instance_valid(session):
			return {"error": "not_in_room"}
		_leave()
		return {"left": true, "room_generation": room_generation}
	if method == "room.reconnect":
		if not is_instance_valid(session) or session.host or not joined or token.is_empty():
			return {"error": "not_resumable"}
		if session.wire.peers.has(0):
			return {"error": "already_connected"}
		var error: Error = _start(false)
		return {"error": "start_failed"} if error != OK else {"started": true, "room_generation": room_generation, "local_session_id": session.local_session_id}
	if is_instance_valid(session):
		return {"error": "room_busy"}
	var game = params.get("game_id")
	var room_port = params.get("port", 27840)
	if not game is String or not (room_port is int or room_port is float) or room_port != int(room_port) or room_port < 1024 or room_port > 65535:
		return {"error": "invalid_room_parameters"}
	var selected := -1
	for index in range(choices.item_count):
		var info: Dictionary = loader.inspect(choices.get_item_metadata(index))
		if not info.is_empty() and info.manifest.id == game:
			selected = index
			break
	if selected < 0:
		return {"error": "unknown_game"}
	if method == "room.join":
		var host_address = params.get("address")
		if not host_address is String or not host_address.is_valid_ip_address():
			return {"error": "invalid_address"}
		address.text = host_address
	if params.has("nickname"):
		if not params.nickname is String or params.nickname.strip_edges().is_empty() or params.nickname.length() > 32:
			return {"error": "invalid_nickname"}
		nickname.text = params.nickname
	choices.select(selected)
	port.value = int(room_port)
	token = ""
	var error: Error = _start(method == "room.create")
	if error != OK:
		return {"error": "start_failed"}
	return {"started": true, "role": "host" if session.host else "guest", "room_generation": room_generation, "local_session_id": session.local_session_id}

func _apply_safe_area() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(content_margin):
		return
	var padding := safe_padding(DisplayServer.get_display_safe_area(), get_window().size, get_viewport_rect().size) if OS.get_name() == "iOS" else {"left": 24, "top": 24, "right": 24, "bottom": 24}
	if home:
		home.set_safe_insets(padding)
	for edge in padding:
		content_margin.add_theme_constant_override("margin_" + edge, padding[edge])
	_layout_game()

static func safe_padding(safe: Rect2i, native: Vector2i, logical: Vector2) -> Dictionary:
	var padding := {"left": 20, "top": 20, "right": 20, "bottom": 20}
	if native.x <= 0 or native.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return padding
	var area := safe.intersection(Rect2i(Vector2i.ZERO, native))
	padding.left += int(ceil(area.position.x * logical.x / native.x))
	padding.top += int(ceil(area.position.y * logical.y / native.y))
	padding.right += int(ceil((native.x - area.end.x) * logical.x / native.x))
	padding.bottom += int(ceil((native.y - area.end.y) * logical.y / native.y))
	return padding

# Read-only diagnostics for real-device UI validation. No settings mutation endpoint.
func debug_ui_status() -> Dictionary:
	var game_ids := []
	for index in range(choices.item_count):
		var entry: Dictionary = loader.inspect(choices.get_item_metadata(index))
		if not entry.is_empty():
			game_ids.append(entry.manifest.id)
	var points := []
	for point in home.orbit_positions(home.motion_time):
		points.append([point.x, point.y])
	var focused := get_viewport().gui_get_focus_owner()
	var focus_control := "other"
	if focused == create_button: focus_control = "launch"
	elif focused == back_button: focus_control = "back"
	elif focused == settings_action: focus_control = "settings"
	elif focused == home.start_button: focus_control = "start"
	var card_index: int = library.cards.find(focused) if focused is Button else -1
	if card_index >= 0:
		focus_control = "game:" + str(library.entries[card_index].id) if card_index < library.entries.size() else "add_game"
	return {"feedback": ui_feedback.diagnostic(), "focus_scale": [focused.scale.x, focused.scale.y] if focused != null else [], "focus_control": focus_control, "library_columns": library.columns, "game_ids": game_ids, "screen": "settings" if settings_dialog.visible else "home" if home.visible else "game" if session != null else "setup", "locale": TranslationServer.get_locale(), "reduced_motion": home.reduced_motion, "motion_time": home.motion_time, "animation_processing": home.is_processing(), "orbits": points, "title": tr("APP_NAME"), "start_label": tr("START_GAME"), "size": [size.x, size.y]}

# UI ABI 1: session, rules and the existing Mod view survive the UI shell swap.
func ui_apply_catalogs() -> void:
	I18n.install()
	I18n.select(str(profile.get("language", "system")))
	_refresh_translations()

func ui_import(old: Control) -> bool:
	ui_feedback.welcomed = true
	profile = old.profile.duplicate(true)
	profile_path = old.profile_path
	nickname.text = old.nickname.text
	address.text = old.address.text
	port.value = old.port.value
	token = old.token
	joined = old.joined
	room_generation = old.room_generation
	mod_info = old.mod_info
	for index in range(old.choices.item_count):
		var path: String = old.choices.get_item_metadata(index)
		var found := -1
		var selected_info: Dictionary = loader.inspect(path)
		for current in range(choices.item_count):
			var current_info: Dictionary = loader.inspect(choices.get_item_metadata(current))
			if choices.get_item_metadata(current) == path or (not selected_info.is_empty() and not current_info.is_empty() and selected_info.manifest.id == current_info.manifest.id):
				found = current
				choices.set_item_metadata(current, path)
				choices.set_item_text(current, I18n.game_name(selected_info))
				break
		if found < 0:
			_add_choice(path)
			found = choices.item_count - 1
		if index == old.choices.selected:
			choices.select(found)
	home.motion_time = old.home.motion_time
	home.set_reduced_motion(bool(profile.get("reduce_motion", false)))
	ui_apply_catalogs()
	if old.session != null:
		session = old.session
		session.updated.disconnect(old._render_snapshot)
		session.notice.disconnect(old._handle_notice)
		var owner_node: Node = get_parent() if shell_managed else self
		if session.get_parent() != owner_node:
			session.reparent(owner_node)
		session.updated.connect(_render_snapshot)
		session.notice.connect(_handle_notice)
		game_view = old.game_view
		if game_view != null:
			game_view.reparent(game_area)
		old.session = null
		old.game_view = null
		home.hide()
		content_margin.show()
		setup.hide()
		create_button.hide()
		join_button.hide()
		reconnect_button.show()
		leave_button.show()
		roster.show()
		if not session.snapshot.is_empty():
			_render_snapshot(session.snapshot)
	elif not old.home.visible:
		_open_setup(old.create_button.visible)
		if not old.create_button.visible and old.network_row.visible:
			_show_manual_join()
	else:
		_show_home()
	_set_status(old.status_key, old.status_arguments)
	if game_view != null:
		if old.has_method("_disconnect_game_controls"):
			old._disconnect_game_controls(game_view)
		_connect_game_controls(game_view)
	_layout_game()
	_refresh_library()
	return true

func ui_restore_focus(old_focus: Control, old: Control, path: NodePath) -> void:
	if old.settings_dialog.visible:
		_open_settings()
		if old_focus == old.motion_choice:
			motion_choice.grab_focus()
		elif old_focus == old.get("sound_choice"):
			sound_choice.grab_focus()
		elif old_focus == old.settings_dialog.get_ok_button():
			settings_dialog.get_ok_button().grab_focus()
	elif old.leave_dialog.visible and session != null:
		_request_leave()
	elif game_view != null and old_focus != null and (old_focus == game_view or game_view.is_ancestor_of(old_focus)):
		old_focus.grab_focus()
	else:
		var pairs := [[old.home.start_button, home.start_button], [old.home.join_button, home.join_button], [old.home.settings_button, home.settings_button], [old.back_button, back_button], [old.settings_action, settings_action], [old.create_button, create_button], [old.join_button, join_button], [old.address, address], [old.reconnect_button, reconnect_button], [old.leave_button, leave_button]]
		for pair in pairs:
			if old_focus == pair[0] and pair[1].is_visible_in_tree():
				pair[1].grab_focus()
				return
		var index: int = old.library.cards.find(old_focus) if old_focus is Button else -1
		if index >= 0 and index < library.cards.size() and library.is_visible_in_tree():
			library.cards[index].grab_focus()
			return
		var target = get_node_or_null(path)
		if target is Control and target.is_visible_in_tree() and target.focus_mode != Control.FOCUS_NONE:
			target.grab_focus()
		elif home.visible:
			home.start_button.grab_focus()
		elif setup.visible:
			library.focus_selected()

# Optional Mod UI extension; no dependency from a Mod on app internals.
func _connect_game_controls(view: Control) -> void:
	if view.has_method("set_session_services") and session != null:
		view.set_session_services(session)
	if view.has_signal("platform_action") and not view.is_connected("platform_action", _game_platform_action):
		view.connect("platform_action", _game_platform_action)
	_send_game_status()

func _disconnect_game_controls(view: Control) -> void:
	if view.has_signal("platform_action") and view.is_connected("platform_action", _game_platform_action):
		view.disconnect("platform_action", _game_platform_action)

func _game_platform_action(action: String) -> void:
	match action:
		"settings": _open_settings()
		"reconnect": reconnect_button.pressed.emit()
		"exit":
			if session != null and session.snapshot.get("view", {}).get("finished", false):
				_leave()
			else:
				_request_leave()

func _send_game_status() -> void:
	if not is_instance_valid(game_view) or not game_view.has_method("set_platform_state"):
		return
	var interrupted: bool = session != null and not session.host and session.connection_state in ["disconnected", "failed", "rejected"]
	var message := status.text if status_key not in ["CONNECTED", "LOBBY_HELP", "LEFT_ROOM"] else ""
	game_view.set_platform_state({"enabled": true, "connected": not interrupted, "can_reconnect": joined and interrupted, "message": message, "reduce_motion": bool(profile.get("reduce_motion", false)), "input_paused": settings_dialog.visible or leave_dialog.visible})

func _layout_game() -> void:
	immersive_game = is_instance_valid(session) and is_instance_valid(game_view) and game_view.has_method("wants_fullscreen") and game_view.wants_fullscreen()
	if immersive_game:
		page_title.hide()
		status.hide()
		roster.hide()
		footer.hide()
		var height := get_viewport_rect().size.y - content_margin.get_theme_constant("margin_top") - content_margin.get_theme_constant("margin_bottom")
		game_area.custom_minimum_size.y = maxf(520, height)
	else:
		game_area.custom_minimum_size.y = 0
	_update_join_invite()

func _restore_exit_focus() -> void:
	if is_instance_valid(game_view) and game_view.has_method("restore_platform_focus"):
		game_view.restore_platform_focus("exit")


func _build_lan_ui() -> void:
	discovery = Discovery.new()
	add_child(discovery)
	join_browser = preload("res://app/ui/join_browser.gd").new()
	setup.add_child(join_browser)
	join_browser.selected.connect(_inspect_peer)
	join_browser.refresh_requested.connect(discovery.browse)
	join_browser.manual_requested.connect(_show_manual_join)
	join_browser.scan_requested.connect(_start_scan)
	qr_scanner = preload("res://sdk/qr_scanner.gd").new()
	add_child(qr_scanner)
	qr_scanner.scanned.connect(_join_scanned_code)
	qr_scanner.failed.connect(func(code): _set_status("CAMERA_PERMISSION_DENIED" if code == "camera_permission_denied" else "CAMERA_UNAVAILABLE"))
	var invite_layer := CanvasLayer.new()
	invite_layer.layer = 25
	add_child(invite_layer)
	join_invite = preload("res://app/ui/join_invite.gd").new()
	join_invite.theme = theme
	invite_layer.add_child(join_invite)
	join_invite.hide()
	join_invite.dismissed.connect(func():
		invite_dismissed = true
		if game_view != null and game_view.has_method("focus_default"):
			game_view.focus_default()
	)
	discovery.changed.connect(func(rooms): join_browser.populate(rooms))
	discovery.unavailable.connect(func(_code): join_browser.message.text = "DISCOVERY_UNAVAILABLE")
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	download_dialog = preload("res://app/ui/mod_download.gd").new()
	download_dialog.theme = theme
	layer.add_child(download_dialog)
	download_dialog.confirmed.connect(func():
		if peer_transfer != null:
			peer_phase = "downloading"
			peer_transfer.confirm_download()
	)
	download_dialog.canceled.connect(_cancel_peer_join)

func _show_manual_join() -> void:
	library_help.text = "MANUAL_JOIN_HELP"
	join_browser.hide()
	discovery.stop_browse()
	library.show()
	network_row.show()
	join_button.show()
	address.grab_focus()

func _inspect_peer(target: Dictionary) -> void:
	if session != null:
		return
	_cancel_peer_join()
	peer_target = target.duplicate(true)
	peer_error = ""
	peer_phase = "inspecting"
	peer_transfer = PeerMods.new()
	add_child(peer_transfer)
	peer_transfer.catalog_received.connect(_peer_catalog)
	peer_transfer.progress.connect(download_dialog.update_progress)
	peer_transfer.completed.connect(_peer_downloaded)
	peer_transfer.failed.connect(_peer_failed)
	_set_status("CHECKING_GAME")
	var error: Error = peer_transfer.inspect_remote(str(target.address), int(target.port), str(target.get("session_id", "")))
	if error != OK:
		_peer_failed("connect_failed")

func _peer_catalog(metadata: Dictionary) -> void:
	if metadata.get("kind", "game") != "game":
		_peer_failed("not_a_game")
		return
	for index in range(choices.item_count):
		var path: String = choices.get_item_metadata(index)
		known_mods[path] = loader.inspect(path)
	for info in known_mods.values():
		if not info.is_empty() and info.manifest.id == metadata.game_id and info.rules_fingerprint == metadata.rules_fingerprint:
			_join_peer(info, metadata)
			return
	peer_phase = "confirmation"
	var display_name: String = str(metadata.name)
	var localized = metadata.get("localized_names", {})
	if localized is Dictionary:
		display_name = str(localized.get("zh" if TranslationServer.get_locale().begins_with("zh") else "en", display_name))
	download_dialog.ask(tr("DOWNLOAD_GAME_DETAILS") % [display_name, metadata.version, metadata.source_name, str(peer_target.address), "%.1f" % (float(metadata.size) / 1024.0)])
	_set_status("DOWNLOAD_CONFIRMATION")

func _peer_downloaded(path: String, metadata: Dictionary) -> void:
	peer_phase = "validating"
	_set_status("VALIDATING_GAME")
	var info: Dictionary = loader.install_peer_zip(path, metadata)
	if info.is_empty():
		_peer_failed(loader.error)
		return
	_join_peer(info, metadata)

func _join_peer(info: Dictionary, metadata: Dictionary) -> void:
	known_mods[info.root] = info
	var selected := -1
	for index in range(choices.item_count):
		var existing: Dictionary = loader.inspect(choices.get_item_metadata(index))
		if not existing.is_empty() and existing.manifest.id == info.manifest.id:
			selected = index
			choices.set_item_metadata(index, info.root)
			choices.set_item_text(index, I18n.game_name(info))
			break
	if selected < 0:
		_add_choice(info.root)
		selected = choices.item_count - 1
	choices.select(selected)
	address.text = peer_target.address
	port.value = int(peer_target.port)
	token = ""
	expected_join_session = metadata.session_id
	peer_phase = "joining"
	download_dialog.hide()
	if peer_transfer != null:
		peer_transfer.cancel()
		peer_transfer.queue_free()
		peer_transfer = null
	_start(false)

func _peer_failed(code: String) -> void:
	peer_error = code
	_cancel_peer_join()
	peer_phase = "failed"
	_set_status("PEER_JOIN_FAILED")

func _cancel_peer_join() -> void:
	if peer_transfer != null:
		peer_transfer.cancel()
		peer_transfer.queue_free()
		peer_transfer = null
	if download_dialog != null:
		download_dialog.hide()
	peer_phase = "idle"
	_set_status("JOIN_HELP")
	if join_browser != null and join_browser.is_visible_in_tree():
		join_browser.focus_default()

func debug_lan_command(method: String, params: Dictionary) -> Dictionary:
	if method == "qr.image" and session != null:
		var texture: Texture2D = session.get_join_qr()
		return {"data": Marshalls.raw_to_base64(texture.get_image().save_png_to_buffer()) if texture != null else ""}
	if method == "qr.decode_image" and params.get("data") is String and params.data.length() <= 4000000:
		return {"value": JoinCode.decode_png(Marshalls.base64_to_raw(params.data))}
	if method == "qr.status":
		return {"active": qr_scanner.active, "camera_opened": qr_scanner.camera_opened, "invite": session.get_join_info() if session != null else {}, "visible": join_invite.visible, "mod_qr": game_view.capture_view_state().get("qr_visible", false) if game_view != null and game_view.has_method("capture_view_state") else false}
	if method == "qr.scan":
		_start_scan()
		return {"scanning": qr_scanner.active}
	if method == "qr.stop":
		qr_scanner.stop()
		return {"stopped": true}
	if method == "qr.join" and params.get("value") is String:
		_join_scanned_code(params.value)
		return {"phase": peer_phase}
	if method == "lan.status":
		return {"rooms": discovery.list_rooms(), "backend": discovery.backend, "discovery_error": discovery.last_error, "phase": peer_phase, "last_error": peer_error, "confirmation": download_dialog.visible and not download_dialog.working, "received": peer_transfer.received if peer_transfer != null else 0}
	if method == "lan.search":
		_open_setup(false)
		return {"searching": true}
	if method == "lan.inspect":
		if not params.get("address") is String or not params.address.is_valid_ip_address() or not (params.get("port") is int or params.get("port") is float) or params.port != int(params.port) or params.port < 1024 or params.port > 65535:
			return {"error": "invalid_address"}
		_inspect_peer(params)
		return {"inspecting": true}
	if method == "lan.confirm_download" and peer_phase == "confirmation":
		download_dialog.confirm.pressed.emit()
		return {"downloading": true}
	if method == "lan.cancel":
		_cancel_peer_join()
		return {"canceled": true}
	return {"error": "invalid_state"}

func _exit_tree() -> void:
	if peer_transfer != null:
		peer_transfer.cancel()

func _start_scan() -> void:
	if session == null:
		_cancel_peer_join()
		qr_scanner.start(tr("SCAN_TO_JOIN"), tr("CANCEL"))

func _join_scanned_code(value: String) -> void:
	var invite := JoinCode.decode(value)
	if invite.is_empty():
		_set_status("INVALID_JOIN_QR")
		return
	_inspect_peer(invite)

func _update_join_invite() -> void:
	if join_invite == null or session == null:
		return
	var controlled: bool = game_view != null and game_view.has_method("controls_join_qr") and game_view.controls_join_qr()
	var show_code: bool = session.host and session.snapshot.get("players", []).size() == 1 and not controlled and not invite_dismissed
	if not show_code:
		var was_visible: bool = join_invite.visible
		join_invite.hide()
		if was_visible and game_view != null and game_view.has_method("focus_default"):
			game_view.focus_default()
		return
	var texture: Texture2D = session.get_join_qr()
	join_invite.visible = texture != null
	join_invite.image.texture = texture
	var side := minf(400, minf(get_viewport_rect().size.x - 48, get_viewport_rect().size.y - 180))
	join_invite.size = Vector2(side, side + 120)
	join_invite.position = (get_viewport_rect().size - join_invite.size) / 2
