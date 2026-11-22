extends Control
const Loader = preload("res://sdk/mods/mod_loader.gd")
const Session = preload("res://sdk/session/session.gd")
const I18n = preload("res://app/i18n.gd")
const Style = preload("res://app/ui/theme/party_theme.gd")
const T = Style.T
const Icons = preload("res://app/ui/theme/party_icons.gd")
const PartyFlow = preload("res://app/ui/screens/party_flow.gd")
const Page = PartyFlow.Page
var flow := PartyFlow.new()
const SwitchRow = preload("res://app/ui/widgets/switch_row.gd")
const UI_API = 2
const SAFE_PAGE_GUTTER := 22
const UserProfile = preload("res://sdk/session/user_profile.gd")
var user_panel
const JoinCode = preload("res://sdk/net/join_code.gd")
var qr_scanner
var join_invite
var invite_dismissed := false
const Discovery = preload("res://sdk/net/discovery.gd")
const Bluetooth = preload("res://sdk/net/bluetooth.gd")
const PeerMods = preload("res://sdk/mods/peer_mods.gd")
var discovery
var join_browser
var download_dialog
var peer_transfer
var peer_target := {}
var peer_phase := "idle"
var peer_error := ""
var expected_join_session := ""
var room_access: Control

# A narrow, local presentation service for observers. Never hand them the Session
# node, its socket, or the authoritative rules state.
class SpectatorServices extends RefCounted:
	var _session: WeakRef

	func _init(session: Node):
		_session = weakref(session)

	func get_join_info(address_override: String = "") -> Dictionary:
		var current = _session.get_ref()
		return current.get_join_info(address_override) if current != null and current.host else {}

	func get_join_qr(address_override: String = "") -> Texture2D:
		var current = _session.get_ref()
		return current.get_join_qr(address_override) if current != null and current.host else null

	func get_player_profile(player_seat: int) -> Dictionary:
		var current = _session.get_ref()
		return current.get_player_profile(player_seat) if current != null else {}

	func get_avatar_texture(public_profile: Dictionary) -> Texture2D:
		return UserProfile.texture(public_profile)
var join_offer := {}
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
var page_eyebrow: Label
var connecting_copy: Label
var manual_form: PanelContainer
var manual_error: Label
var launch_selection: Label
var invite_button: Button
var pending_cancel: Button
var settings_focus: Control
var settings_invite: Button
var leave_focus: Control
var modal_focus_modes := {}
var settings_dialog
var language_choice: OptionButton
var library
var library_help: Label
var footer: BoxContainer
var footer_nav: HBoxContainer
var footer_session: HBoxContainer
var back_button: Button
var motion_choice: Button
var sound_choice: Button
var haptic_choice: Button
var ui_feedback
var page_tween: Tween
var leave_dialog
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
var immersive_surface: ColorRect
var immersive_area: MarginContainer
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
	# Schema 2: names saved by older builds' fallbacks ("Player", or "Android" from a broken
	# device-name lookup) are defaults, not choices; clear them so the device name applies.
	if int(profile.get("profile_schema", 0)) < 2 and profile.get("nickname", "") in ["玩家", "Player", "Android"]:
		profile.nickname = ""
	profile.profile_schema = 2
	var appearance := UserProfile.local_public(profile)
	profile.avatar = appearance.avatar.duplicate(true)
	profile.theme_color = appearance.theme_color
	ui_feedback = preload("res://app/ui/theme/ui_feedback.gd").new()
	set_meta("ui_feedback", ui_feedback)
	add_child(ui_feedback)
	I18n.select(str(profile.get("language", "system")))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--locale="):
			I18n.select(argument.trim_prefix("--locale="))
	theme = Style.build_theme()
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	if not shell_managed:
		get_window().close_requested.connect(func(): get_tree().quit())
		get_window().go_back_requested.connect(_go_back)
		get_window().size_changed.connect(_adapt_display)
	_adapt_display()
	var background := ColorRect.new()
	background.color = T.PAGE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	home = preload("res://app/ui/screens/party_home.gd").new()
	add_child(home)
	home.start_requested.connect(func(): _open_setup(true))
	home.join_requested.connect(func(): _open_setup(false))
	home.settings_requested.connect(_open_settings)
	home.user_requested.connect(_open_user_profile)
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
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	shell.add_child(heading)
	page_eyebrow = _label(heading, "APP_NAME", T.FONT_SIZE_META, T.FONT_WEIGHT_TITLE, T.SKY_LIP)
	page_title = _label(heading, "APP_NAME", 38, T.FONT_WEIGHT_TITLE)
	var scroll := preload("res://app/ui/widgets/focus_scroll.gd").new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	var scroll_content := scroll.padding()
	scroll.add_child(scroll_content)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	scroll_content.add_child(layout)
	status = _label(layout, "LOBBY_HELP", T.FONT_SIZE_BODY, T.FONT_WEIGHT_LABEL)
	status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	connecting_copy = _label(layout, "JOIN_WAIT_HELP", T.FONT_SIZE_BODY, T.FONT_WEIGHT_BODY, T.MUTED)
	pending_cancel = _button(layout, "CANCEL", _cancel_peer_join, "secondary")
	pending_cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	setup = VBoxContainer.new()
	setup.add_theme_constant_override("separation", 12)
	layout.add_child(setup)
	# Internal selection/identity adapters remain available to the session and debug API.
	# They are not user-facing form fields.
	nickname = LineEdit.new()
	nickname.text = UserProfile.local_public(profile).display_name
	nickname.hide()
	add_child(nickname)
	choices = OptionButton.new()
	choices.hide()
	add_child(choices)
	library_help = _label(setup, "PICK_GAME_HELP", T.FONT_SIZE_BODY, T.FONT_WEIGHT_BODY, T.MUTED)
	library = preload("res://app/ui/screens/game_library.gd").new()
	setup.add_child(library)
	library.selected.connect(func(index):
		choices.select(index)
		_update_launch_summary()
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
	manual_form = PanelContainer.new()
	manual_form.add_theme_stylebox_override("panel", Style.sheet())
	setup.add_child(manual_form)
	network_row = HBoxContainer.new()
	network_row.add_theme_constant_override("separation", 12)
	manual_form.add_child(network_row)
	var host_field := VBoxContainer.new()
	host_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	network_row.add_child(host_field)
	_label(host_field, "HOST_LABEL", T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL)
	address = LineEdit.new()
	address.text = profile.get("last_address", "")
	address.placeholder_text = "192.168.1.24"
	address.accessibility_name = tr("HOST_LABEL")
	address.custom_minimum_size.y = T.HIT_MIN
	address.text_submitted.connect(func(_value): _submit_manual_join())
	address.text_changed.connect(func(_value): manual_error.hide())
	host_field.add_child(address)
	var port_field := VBoxContainer.new()
	network_row.add_child(port_field)
	_label(port_field, "PORT", T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL)
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 27840
	port.custom_minimum_size = Vector2(128, T.HIT_MIN)
	port.get_line_edit().accessibility_name = tr("PORT")
	port_field.add_child(port)
	manual_error = _label(setup, "INVALID_HOST", T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL, T.DANGER)
	manual_error.add_theme_stylebox_override("normal", Style.banner("danger"))
	manual_error.hide()
	footer = BoxContainer.new()
	footer.vertical = true
	footer.resized.connect(_adapt_footer, CONNECT_DEFERRED)
	footer.add_theme_constant_override("separation", 12)
	shell.add_child(footer)
	launch_selection = _label(shell, "", T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL, T.MUTED)
	launch_selection.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	shell.move_child(launch_selection, footer.get_index())
	create_button = _button(footer, "LAUNCH_GAME", _launch_game)
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button = _button(footer, "JOIN_GAME", _submit_manual_join, "primary")
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var actions := HBoxContainer.new()
	footer_nav = actions
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 12)
	footer.add_child(actions)
	back_button = _button(actions, "BACK", _go_back, true)
	back_button.icon = Icons.get_icon("back", T.SKY)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var session_actions := HBoxContainer.new()
	footer_session = session_actions
	session_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_actions.add_theme_constant_override("separation", 12)
	footer.add_child(session_actions)
	reconnect_button = _button(session_actions, "RECONNECT", _reconnect, true)
	invite_button = _button(session_actions, "OPEN_INVITE", _open_invite, true)
	leave_button = _button(session_actions, "LEAVE_ROOM", _request_leave, "danger")
	reconnect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_action = _button(actions, "SETTINGS", _open_settings, true)
	settings_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster = _label(layout, "", T.FONT_SIZE_META, T.FONT_WEIGHT_LABEL, T.MUTED)
	roster.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	game_area = VBoxContainer.new()
	layout.add_child(game_area)
	immersive_surface = ColorRect.new()
	immersive_surface.color = T.PAGE
	immersive_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	immersive_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(immersive_surface)
	immersive_area = MarginContainer.new()
	immersive_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	immersive_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	immersive_surface.add_child(immersive_area)
	immersive_surface.hide()
	_build_settings()
	_build_user_profile()
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

func _label(parent: Node, key: String, font_size: int = T.FONT_SIZE_BODY, weight: int = T.FONT_WEIGHT_BODY, color: Color = T.INK) -> Label:
	var label := Label.new()
	label.text = key
	Style.label(label, font_size, weight, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, key: String, callback: Callable, kind = "primary") -> Button:
	var button := Button.new()
	button.text = key
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.set_meta("sound_cue", "launch" if key == "LAUNCH_GAME" else "back" if key in ["BACK", "CANCEL", "CLOSE"] else "confirm")
	button.set_meta("haptic", "confirm" if key in ["LAUNCH_GAME", "JOIN_GAME"] else "tap")
	Style.button(button, kind)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _open_setup(as_host: bool) -> void:
	if is_instance_valid(session): return
	_reset_peer_join()
	_navigate(Page.LIBRARY if as_host else Page.NEARBY)
	_set_status("LOBBY_HELP" if as_host else "JOIN_HELP")

func _show_home() -> void:
	_reset_peer_join()
	_navigate(Page.HOME)

func _navigate(next: PartyFlow.Page, take_focus: bool = true) -> void:
	var previous := flow.page
	flow.open(next)
	if next == Page.NEARBY and previous != Page.NEARBY:
		_search_nearby(false)
	elif next != Page.NEARBY:
		join_browser.stop_search()
		if discovery.browsing: discovery.stop_browse()
	_render_page(take_focus)
	if previous != next:
		_animate_page(home if next == Page.HOME else content_margin)

func _render_page(take_focus: bool = false) -> void:
	var page := flow.page
	var is_home := page == Page.HOME
	var choosing := page == Page.LIBRARY
	var nearby := page == Page.NEARBY
	var manual := page == Page.MANUAL
	var connecting := page == Page.CONNECTING
	var match_page := page == Page.MATCH
	home.visible = is_home
	content_margin.visible = not is_home and not (match_page and immersive_game)
	immersive_surface.visible = match_page and immersive_game
	setup.visible = choosing or nearby or manual
	library.visible = choosing
	join_browser.visible = nearby
	manual_form.visible = manual
	network_row.visible = manual
	launch_selection.visible = choosing and choices.selected >= 0
	_update_launch_summary()
	library_help.visible = choosing or nearby or manual
	library_help.text = "PICK_GAME_HELP" if choosing else "MANUAL_JOIN_HELP" if manual else "JOIN_HELP"
	page_title.text = "SETUP_TITLE" if choosing else "MANUAL_JOIN" if manual else "JOIN_TITLE" if nearby or connecting else "APP_NAME"
	if match_page and not mod_info.is_empty(): page_title.text = I18n.game_name(mod_info)
	page_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if match_page else Node.AUTO_TRANSLATE_MODE_INHERIT
	page_eyebrow.text = "STEP_HOST" if choosing else "STEP_JOIN" if nearby or manual or connecting else "APP_NAME"
	var show_heading := not (match_page and immersive_game)
	page_title.visible = show_heading
	page_title.get_parent().visible = show_heading
	create_button.visible = choosing
	create_button.disabled = choices.item_count == 0
	join_button.visible = manual
	join_button.disabled = peer_phase == "inspecting"
	if not manual: manual_error.hide()
	connecting_copy.visible = connecting
	pending_cancel.visible = peer_phase == "inspecting" and (nearby or manual)
	join_browser.set_busy(peer_phase == "inspecting")
	back_button.visible = not match_page
	back_button.text = "CANCEL" if connecting else "BACK"
	settings_action.visible = match_page and not immersive_game
	roster.visible = match_page and not immersive_game
	game_area.visible = match_page
	footer_session.visible = match_page and not immersive_game
	footer_nav.visible = not match_page or not immersive_game
	leave_button.visible = match_page
	invite_button.visible = match_page and is_instance_valid(session) and session.get("host") == true
	reconnect_button.visible = match_page and _can_reconnect()
	footer.visible = not (match_page and immersive_game)
	status.visible = _status_visible()
	_update_setup_focus()
	if not take_focus or ui_preparing or (_top_modal() != null and not join_invite.visible): return
	match page:
		Page.HOME: _refresh_home(); home.start_button.grab_focus()
		Page.LIBRARY: library.focus_selected()
		Page.NEARBY: join_browser.focus_default()
		Page.MANUAL: address.grab_focus()
		Page.CONNECTING: back_button.grab_focus()
		Page.MATCH:
			if join_invite.visible: join_invite.done.grab_focus()
			elif is_instance_valid(game_view) and game_view.has_method("focus_default"): game_view.focus_default()
			if get_viewport().gui_get_focus_owner() == null and leave_button.is_visible_in_tree():
				(invite_button if invite_button.is_visible_in_tree() else leave_button).grab_focus()

func _status_visible() -> bool:
	return not immersive_game and flow.page != Page.HOME and status_key not in ["LOBBY_HELP", "JOIN_HELP", "LEFT_ROOM"]

func _search_nearby(use_bluetooth: bool = false) -> void:
	join_browser.begin_search(use_bluetooth)
	discovery.browse(use_bluetooth)

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
		home.set_user_profile(UserProfile.local_public(profile))

func _set_status(key: String, arguments: Array = []) -> void:
	status_key = key
	status_arguments = arguments
	status.text = tr(key) % arguments if not arguments.is_empty() else tr(key)
	status.visible = _status_visible()
	var tone := "success" if key in ["CONNECTED", "SPECTATING", "INSTALLED_MOD"] else "wait" if key in ["CONNECTING", "CONNECTING_BLUETOOTH", "RECONNECTING", "CHECKING_GAME", "VALIDATING_GAME", "DOWNLOAD_CONFIRMATION", "ROOM_CREATED", "PEER_OFFLINE"] else "danger"
	status.add_theme_stylebox_override("normal", Style.banner(tone))
	status.add_theme_color_override("font_color", T.SUCCESS if tone == "success" else T.DANGER if tone == "danger" else T.INK)
	_send_game_status()

func _handle_notice(code: String) -> void:
	if flow.page == Page.CONNECTING:
		_finish_failed_join.call_deferred(session, code)
		return
	if code == "connection_lost" and is_instance_valid(session) and session.connection_state == "failed":
		return # Keep the more specific reconnect-timeout message.
	var is_transport_error: bool = is_instance_valid(session) and code == session.connection_error and session.connection_state in ["failed", "disconnected", "rejected"]
	if not is_transport_error and is_instance_valid(game_view) and game_view.has_method("on_command_notice") and game_view.on_command_notice(code):
		return
	ui_feedback.haptic("warn")
	var messages := {"disconnected": "RECONNECT_FIRST", "connection_lost": "CONNECTION_LOST", "not_your_turn": "ERR_NOT_YOUR_TURN", "occupied": "ERR_OCCUPIED", "stale_revision": "ERR_STALE_REVISION", "game_finished": "ERR_GAME_FINISHED", "waiting_for_players": "ERR_WAITING_PLAYERS", "invalid_action": "ERR_INVALID_ACTION", "already_chosen": "ERR_ALREADY_CHOSEN", "card_not_owned": "ERR_CARD_NOT_OWNED", "game_not_finished": "ERR_GAME_NOT_FINISHED", "already_requested": "ERR_ALREADY_REQUESTED"}
	if messages.has(code):
		_set_status(messages[code])
	elif is_instance_valid(session) and session.connection_state == "rejected":
		_set_status(_join_error_key(code, true))
	else:
		_set_status("NETWORK_ERROR", [code])

func _finish_failed_join(failed_session: Node, code: String) -> void:
	if not is_instance_valid(failed_session) or failed_session != session or flow.page != Page.CONNECTING: return
	_clear_session()
	joined = false
	token = ""
	if code in ["password_required", "wrong_password"] and not join_offer.is_empty():
		_navigate(flow.join_origin, false)
		join_offer.password_required = true
		_prompt_join(join_offer, tr(_join_error_key(code)))
	else:
		_peer_failed(code)

func _connection_changed(state: String, code: String) -> void:
	if flow.page == Page.CONNECTING:
		if state in ["failed", "disconnected", "rejected"]:
			_finish_failed_join.call_deferred(session, code)
		return
	if flow.page != Page.MATCH: return
	match state:
		"reconnecting", "connecting", "handshaking": _set_status("RECONNECTING")
		"failed": _set_status("RECONNECT_TIMEOUT")
		"disconnected": _set_status("CONNECTION_LOST")
		"rejected": _set_status(_join_error_key(code, true))
	_render_page()
	_send_game_status()

func _can_reconnect() -> bool:
	return is_instance_valid(session) and joined and not token.is_empty() and session.get("connection_state") in ["failed", "disconnected"]

func _reconnect() -> void:
	if _can_reconnect() and session.has_method("reconnect_now"):
		session.reconnect_now()
	elif _can_reconnect():
		_start(false)

func _submit_manual_join() -> void:
	if flow.page != Page.MANUAL or peer_phase == "inspecting": return
	var host := address.text.strip_edges()
	var endpoint_port := int(port.value)
	if not host.is_valid_ip_address() and host.contains(":"):
		var separator := host.rfind(":")
		var candidate := host.left(separator).trim_prefix("[").trim_suffix("]")
		var suffix := host.substr(separator + 1)
		if candidate.is_valid_ip_address() and suffix.is_valid_int() and int(suffix) >= 1024 and int(suffix) <= 65535:
			host = candidate
			endpoint_port = int(suffix)
	if not host.is_valid_ip_address():
		manual_error.show()
		address.grab_focus()
		return
	manual_error.hide()
	address.text = host
	port.value = endpoint_port
	_inspect_peer({"address": host, "port": endpoint_port})

func _build_settings() -> void:
	settings_dialog = preload("res://app/ui/widgets/sheet.gd").new()
	settings_dialog.theme = theme
	var settings_layer := CanvasLayer.new()
	settings_layer.layer = 50
	add_child(settings_layer)
	settings_layer.add_child(settings_dialog)
	settings_dialog.visibility_changed.connect(_modal_changed)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	settings_dialog.add_content(body)
	_label(body, "PROFILE_LOCAL", T.FONT_SIZE_META, T.FONT_WEIGHT_TITLE, T.SKY_LIP)
	_label(body, "SETTINGS", T.FONT_SIZE_TITLE, T.FONT_WEIGHT_TITLE)
	_label(body, "SETTINGS_HELP", T.FONT_SIZE_META, T.FONT_WEIGHT_BODY, T.MUTED)
	# Immersive Mods with their own waiting screen may not expose an invite action.
	settings_invite = _button(body, "OPEN_BLUETOOTH_INVITE", func():
		settings_dialog.close()
		_open_invite()
	, "secondary")
	settings_invite.icon = Icons.get_icon("bluetooth", T.SKY)
	settings_invite.hide()
	_label(body, "LANGUAGE", T.FONT_SIZE_META, T.FONT_WEIGHT_TITLE, T.MUTED)
	language_choice = OptionButton.new()
	for entry in [["LANG_SYSTEM", "system"], ["简体中文", "zh_CN"], ["English", "en"]]:
		language_choice.add_item(entry[0])
		language_choice.set_item_metadata(language_choice.item_count - 1, entry[1])
	language_choice.custom_minimum_size.y = T.ROW_HEIGHT
	body.add_child(language_choice)
	language_choice.item_selected.connect(func(index): set_language(language_choice.get_item_metadata(index)))
	_label(body, "FEEDBACK", T.FONT_SIZE_META, T.FONT_WEIGHT_TITLE, T.MUTED)
	sound_choice = SwitchRow.new()
	sound_choice.text = "UI_SOUNDS"
	body.add_child(sound_choice)
	sound_choice.toggled.connect(func(value):
		profile.ui_sounds = value
		ui_feedback.refresh_preferences()
		if value: ui_feedback.play("confirm")
		_save_profile()
	)
	haptic_choice = SwitchRow.new()
	haptic_choice.text = "HAPTICS"
	body.add_child(haptic_choice)
	haptic_choice.toggled.connect(func(value):
		profile.haptics = value
		if value: ui_feedback.haptic("confirm")
		_save_profile()
	)
	motion_choice = SwitchRow.new()
	motion_choice.text = "REDUCE_MOTION"
	body.add_child(motion_choice)
	motion_choice.toggled.connect(func(value):
		profile.reduce_motion = value
		home.set_reduced_motion(value)
		ui_feedback.refresh_preferences()
		_send_game_status()
		_save_profile()
	)
	var help := _label(body, "REDUCE_MOTION_HELP", T.FONT_SIZE_META, T.FONT_WEIGHT_BODY, T.MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var credit := RichTextLabel.new()
	credit.bbcode_enabled = true
	credit.fit_content = true
	credit.scroll_active = false
	credit.add_theme_font_size_override("normal_font_size", 16)
	credit.add_theme_color_override("default_color", T.MUTED)
	credit.text = "[url=https://heyheythere.itch.io/soft-ui-sfx-free]Soft UI SFX Free[/url] · heyheythere\n[url=https://creativecommons.org/licenses/by/4.0/]CC BY 4.0[/url]"
	credit.meta_clicked.connect(func(url): OS.shell_open(str(url)))
	body.add_child(credit)
	settings_dialog.confirmed.connect(func():
		_save_profile()
		_refresh_home()
		if home.visible:
			home.settings_button.grab_focus()
		elif create_button.is_visible_in_tree():
			library.focus_selected()
		elif immersive_game and game_view.has_method("restore_platform_focus"):
			game_view.restore_platform_focus("settings")
		elif is_instance_valid(settings_focus) and settings_focus.is_visible_in_tree():
			settings_focus.grab_focus()
		else:
			_render_page(true)
	)

func _open_settings() -> void:
	if settings_opening:
		return
	settings_opening = true
	settings_focus = get_viewport().gui_get_focus_owner()
	sound_choice.set_pressed_no_signal(bool(profile.get("ui_sounds", true)))
	motion_choice.set_pressed_no_signal(bool(profile.get("reduce_motion", false)))
	haptic_choice.set_pressed_no_signal(bool(profile.get("haptics", true)))
	for row in [sound_choice, haptic_choice, motion_choice]: row.queue_redraw()
	for index in range(language_choice.item_count):
		if language_choice.get_item_metadata(index) == profile.get("language", "system"):
			language_choice.select(index)
	settings_opening = false
	settings_invite.visible = _has_bluetooth_invite()
	settings_dialog.popup_centered(Vector2i(mini(540, int(get_viewport_rect().size.x - 32)), 720))
	# Keep directional and Tab navigation inside this modal, also during a game.
	var focus_order := [language_choice, sound_choice, haptic_choice, motion_choice, settings_dialog.get_ok_button()]
	if settings_invite.visible: focus_order.push_front(settings_invite)
	for index in range(focus_order.size()):
		var control: Control = focus_order[index]
		control.focus_neighbor_top = control.get_path_to(focus_order[(index + focus_order.size() - 1) % focus_order.size()])
		control.focus_neighbor_bottom = control.get_path_to(focus_order[(index + 1) % focus_order.size()])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom
		control.focus_neighbor_left = control.get_path()
		control.focus_neighbor_right = control.get_path()
	(focus_order[0] as Control).grab_focus()

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
	address.accessibility_name = tr("HOST_LABEL")
	port.get_line_edit().accessibility_name = tr("PORT")
	join_browser.populate(join_browser.items)
	_refresh_home()
	if not status_key.is_empty():
		_set_status(status_key, status_arguments)
	if is_instance_valid(session) and not session.snapshot.is_empty():
		_render_snapshot(session.snapshot)
		if not mod_info.is_empty(): page_title.text = I18n.game_name(mod_info)

func _build_leave_dialog() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 55
	add_child(layer)
	leave_dialog = preload("res://app/ui/widgets/confirm_dialog.gd").new()
	leave_dialog.theme = theme
	layer.add_child(leave_dialog)
	leave_dialog.setup("EXIT_MATCH_TITLE", "EXIT_MATCH_TEXT", "CONFIRM_LEAVE", "CANCEL")
	leave_dialog.confirmed.connect(_leave)
	leave_dialog.canceled.connect(_restore_exit_focus)
	leave_dialog.visibility_changed.connect(_modal_changed)

func _request_leave() -> void:
	if is_instance_valid(session) and not leave_dialog.visible:
		leave_focus = get_viewport().gui_get_focus_owner()
		leave_dialog.setup("EXIT_MATCH_TITLE", "EXIT_HOST_TEXT" if session.get("host") == true else "EXIT_GUEST_TEXT", "CONFIRM_LEAVE", "CANCEL")
		leave_dialog.popup_centered(Vector2i(580, 328))

func _render_snapshot(data: Dictionary) -> void:
	# A confirmed snapshot ends the join transaction. Later transport loss must
	# preserve the seat/token for reconnect instead of clearing the session.
	if peer_phase == "joining":
		peer_phase = "joined"
		peer_error = ""
		join_offer.clear()
	token = session.resume_token
	var entering := flow.page != Page.MATCH
	if entering: flow.open(Page.MATCH)
	var names := PackedStringArray()
	var offline := false
	for player in data.players:
		offline = offline or not player.connected
		names.append(player.nickname + " · " + tr("ONLINE" if player.connected else "OFFLINE"))
	roster.text = "   /   ".join(names)
	if session.connection_state in ["connected", "hosting"]:
		if data.get("role") == "spectator":
			var watch_status := "PEER_OFFLINE" if offline and mod_info.manifest.get("session_mode", "") != "drop_in" else "SPECTATING"
			if status_key != watch_status: _set_status(watch_status)
		elif session.host and data.players.size() == 1:
			_set_status("ROOM_CREATED", [_local_addresses()])
		elif offline and mod_info.manifest.get("session_mode", "") != "drop_in":
			_set_status("PEER_OFFLINE")
		elif entering or status_key in ["PEER_OFFLINE", "RECONNECTING", "RECONNECT_TIMEOUT", "CONNECTION_LOST", "ROOM_CREATED"]:
			_set_status("CONNECTED", [int(data.seat) + 1])
	game_view.render(data)
	if _top_modal() != null: _suspend_focus(game_view)
	if entering:
		_navigate(Page.MATCH, false)
		_layout_game()
		_render_page(true)
	else:
		_send_game_status()
		_update_join_invite()

func _update_launch_summary() -> void:
	if is_instance_valid(launch_selection) and choices.selected >= 0:
		launch_selection.text = tr("LAUNCH_SELECTION") % choices.get_item_text(choices.selected)

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
		items.append({"id": info.manifest.id, "name": I18n.game_name(info), "cover_path": cover_path, "players": info.manifest.get("players", {})})
	library.populate(items, choices.selected)
	_update_launch_summary()
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

func _supports_room_access() -> bool:
	var script: Script = Session
	return script.get_script_method_list().any(func(method): return method.name == "supports_room_access")

func _launch_game() -> void:
	if choices.selected < 0: return
	if not _supports_room_access():
		_start(true, 27840)
		return
	var info := loader.inspect(choices.get_item_metadata(choices.selected))
	if not info.is_empty(): room_access.create_prompt(info.manifest.has("spectators"))

func _start(as_host: bool, local_port: int = -1, options: Dictionary = {}) -> Error:
	# Keep the selected game stable for a resume attempt.
	if choices.selected < 0 or choices.selected >= choices.item_count: return ERR_INVALID_DATA
	var root: String = mod_info.root if not as_host and not token.is_empty() and not mod_info.is_empty() else choices.get_item_metadata(choices.selected)
	_clear_session()
	mod_info = loader.inspect(root)
	if mod_info.is_empty():
		_set_status("NETWORK_ERROR", [loader.error])
		return ERR_INVALID_DATA
	var logic = null
	if as_host:
		logic = loader.rules(mod_info)
		if logic == null:
			_set_status("NETWORK_ERROR", [loader.error])
			return ERR_INVALID_DATA
	if not as_host and not address.text.begins_with("ble:"):
		profile.last_address = address.text.strip_edges()
	# The editor owns nickname; empty means follow the current device name.
	if nickname.text != UserProfile.local_public(profile).display_name:
		profile.nickname = UserProfile.clean_name(nickname.text, "")
	var connection_profile := profile.duplicate(true)
	connection_profile.nickname = UserProfile.local_public(profile).display_name
	_save_profile()
	var spectating: bool = options.get("role", "player") == "spectator"
	if spectating and not mod_info.manifest.has("spectators"):
		_set_status("JOIN_SPECTATORS_UNSUPPORTED")
		return ERR_UNAVAILABLE
	var view_entry: String = mod_info.manifest.spectators.view if spectating else mod_info.manifest.view
	var view_script = load(root.path_join(view_entry))
	if not view_script is Script or not view_script.can_instantiate() or not ClassDB.is_parent_class(view_script.get_instance_base_type(), "Control"):
		_set_status("GAME_VIEW_FAILED")
		return ERR_INVALID_DATA
	game_view = view_script.new()
	if (not spectating and not game_view.has_signal("command")) or not game_view.has_method("render"):
		game_view.free()
		game_view = null
		_set_status("GAME_VIEW_FAILED")
		return ERR_INVALID_DATA
	game_area.add_child(game_view)
	session = Session.new()
	session.expected_remote_session = expected_join_session
	expected_join_session = ""
	room_generation += 1
	(get_parent() if shell_managed else self).add_child(session)
	if not spectating: game_view.command.connect(session.submit)
	_connect_game_controls(game_view, spectating)
	session.updated.connect(_render_snapshot)
	session.notice.connect(_handle_notice)
	session.status_changed.connect(_connection_changed)
	var error: Error
	joined = not as_host
	if as_host:
		token = ""
		var listen_port := local_port if local_port > 0 else int(port.value)
		error = session.create(mod_info, logic, connection_profile, listen_port) if options.is_empty() else session.create(mod_info, logic, connection_profile, listen_port, options)
		if error != OK:
			_clear_session()
			_navigate(Page.LIBRARY)
			_set_status("HOST_FAILED", [listen_port])
	else:
		_navigate(Page.CONNECTING)
		_set_status("CONNECTING_BLUETOOTH" if address.text.begins_with("ble:") else "CONNECTING")
		error = session.join(mod_info, connection_profile, address.text.strip_edges(), int(port.value), token) if options.is_empty() else session.join(mod_info, connection_profile, address.text.strip_edges(), int(port.value), token, options)
		if error != OK: _finish_failed_join(session, "connect_failed")
	return error

func _clear_session() -> void:
	invite_dismissed = false
	if join_invite != null:
		join_invite.hide()
	if session != null:
		room_generation += 1
		var previous: Node = session
		session = null
		if previous.has_method("close"): previous.close()
		previous.get_parent().remove_child(previous)
		previous.queue_free()
	if game_view != null:
		game_view.get_parent().remove_child(game_view)
		game_view.queue_free()
		game_view = null
	immersive_game = false
	game_area.custom_minimum_size.y = 0

func _leave() -> void:
	leave_dialog.hide()
	_clear_session()
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

func _save_profile() -> bool:
	if ui_preparing: return true
	var temporary := profile_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(profile))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	return DirAccess.rename_absolute(temporary, profile_path) == OK

func _install_package(path: String) -> void:
	if session != null:
		_set_status("LEAVE_FIRST")
		return
	var info: Dictionary = loader.install_zip(path)
	if info.is_empty():
		_set_status("NETWORK_ERROR", [loader.error])
		return
	_add_choice(info.root)
	for index in range(choices.item_count):
		if choices.get_item_metadata(index) == info.root:
			choices.select(index)
			break
	_refresh_library()
	library.focus_selected()
	_set_status("INSTALLED_MOD", [I18n.game_name(info)])
	ui_feedback.haptic("confirm")

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
	if is_instance_valid(room_access) and room_access.visible:
		room_access.close()
	elif qr_scanner != null and qr_scanner.active:
		qr_scanner.stop()
		_render_page(true)
	elif download_dialog.visible or peer_transfer != null or flow.page == Page.CONNECTING:
		_cancel_peer_join()
	elif leave_dialog.visible:
		leave_dialog.close()
	elif user_panel.visible:
		user_panel.close()
	elif settings_dialog.visible:
		settings_dialog.close()
	elif join_invite.visible:
		join_invite.close()
	elif is_instance_valid(game_view) and game_view.has_method("handle_platform_back") and game_view.handle_platform_back():
		pass
	elif session != null:
		_request_leave()
	elif flow.page == Page.LIBRARY and get_viewport().gui_get_focus_owner() == create_button:
		ui_feedback.play("back")
		library.focus_selected()
	elif flow.page != Page.HOME:
		ui_feedback.play("back")
		_navigate(flow.back_target())
		_set_status("JOIN_HELP" if flow.is_join() else "LOBBY_HELP")

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
	var spectating: bool = session.snapshot.get("role") == "spectator"
	var entry: String = info.manifest.spectators.view if spectating else info.manifest.view
	var script = load(info.root.path_join(entry))
	if not script is GDScript or not script.can_instantiate() or not ClassDB.is_parent_class(script.get_instance_base_type(), "Control"):
		return {"error": "invalid_view_script"}
	var candidate = script.new()
	if not candidate is Control or (not spectating and not candidate.has_signal("command")) or not candidate.has_method("render"):
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
	if not spectating: old.command.disconnect(session.submit)
	game_view = candidate
	if not spectating: candidate.command.connect(session.submit)
	_connect_game_controls(candidate, spectating)
	old.get_parent().remove_child(old)
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
		state["command_connections"] = game_view.get_signal_connection_list("command").size() if game_view.has_signal("command") else 0
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
	if method == "room.start_round":
		if not is_instance_valid(session) or not session.host or not session.has_method("start_round"):
			return {"error": "host_only"}
		if _top_modal() != null or not session.start_round(): return {"error": "round_not_ready"}
		return {"started": true}
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
		if not session.has_method("reconnect_now"):
			var error := _start(false)
			if error != OK: return {"error": "start_failed"}
		elif not session.reconnect_now():
			return {"error": "not_resumable"}
		return {"started": true, "room_generation": room_generation, "local_session_id": session.local_session_id}
	if is_instance_valid(session):
		return {"error": "room_busy"}
	var game = params.get("game_id")
	var room_port = params.get("port", 27840)
	var role = params.get("role", "player")
	if not role is String or role not in ["player", "spectator"] or (role == "spectator" and not _supports_room_access()):
		return {"error": "invalid_role"}
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
	var options := {"role": role} if role == "spectator" else {}
	var error: Error = _start(method == "room.create", -1, options)
	if error != OK:
		return {"error": "start_failed"}
	return {"started": true, "role": "host" if session.host else "guest", "room_generation": room_generation, "local_session_id": session.local_session_id}

func _apply_safe_area() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(content_margin):
		return
	var padding := {"left": T.PAGE_MARGIN, "top": T.PAGE_MARGIN, "right": T.PAGE_MARGIN, "bottom": T.PAGE_MARGIN}
	var immersive_padding := {"left": 8, "top": 8, "right": 8, "bottom": 8}
	if OS.get_name() in ["iOS", "Android"]:
		var safe := DisplayServer.get_display_safe_area()
		var window_rect := Rect2i(get_window().position, get_window().size)
		var overlap := safe.intersection(window_rect)
		if overlap.has_area():
			padding = safe_padding(Rect2i(overlap.position - window_rect.position, overlap.size), get_window().size, get_viewport_rect().size)
			for edge in padding: immersive_padding[edge] += padding[edge] - SAFE_PAGE_GUTTER
	if home:
		home.set_safe_insets(padding)
	for edge in padding:
		content_margin.add_theme_constant_override("margin_" + edge, padding[edge])
		if is_instance_valid(immersive_area):
			immersive_area.add_theme_constant_override("margin_" + edge, immersive_padding[edge])
	_layout_game()

static func safe_padding(safe: Rect2i, native: Vector2i, logical: Vector2) -> Dictionary:
	var padding := {"left": SAFE_PAGE_GUTTER, "top": SAFE_PAGE_GUTTER, "right": SAFE_PAGE_GUTTER, "bottom": SAFE_PAGE_GUTTER}
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
	return {"route": Page.keys()[flow.page].to_lower(), "status": status_key, "bluetooth_join_visible": join_browser.bluetooth.visible, "bluetooth_host_visible": join_invite.visible and join_invite.bluetooth_button.visible, "feedback": ui_feedback.diagnostic(), "focus_scale": [focused.scale.x, focused.scale.y] if focused != null else [], "focus_control": focus_control, "library_columns": library.columns, "game_ids": game_ids, "screen": "user" if user_panel != null and user_panel.visible else "settings" if settings_dialog.visible else "home" if home.visible else "game" if session != null else "setup", "locale": TranslationServer.get_locale(), "reduced_motion": home.reduced_motion, "motion_time": home.motion_time, "animation_processing": home.is_processing(), "orbits": points, "user_profile": UserProfile.local_public(profile), "title": tr("APP_NAME"), "start_label": tr("START_GAME"), "size": [size.x, size.y]}

# UI ABI 2: session, rules and the existing Mod view survive the UI shell swap.
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
	var old_flow = old.get("flow")
	if old_flow != null:
		flow.join_origin = old_flow.join_origin
	if old.session != null:
		session = old.session
		session.updated.disconnect(old._render_snapshot)
		session.notice.disconnect(old._handle_notice)
		if old.has_method("_connection_changed"):
			var old_handler := Callable(old, "_connection_changed")
			if session.status_changed.is_connected(old_handler): session.status_changed.disconnect(old_handler)
		var owner_node: Node = get_parent() if shell_managed else self
		if session.get_parent() != owner_node:
			session.reparent(owner_node)
		session.updated.connect(_render_snapshot)
		session.notice.connect(_handle_notice)
		session.status_changed.connect(_connection_changed)
		invite_dismissed = old.invite_dismissed
		peer_phase = old.peer_phase if old.peer_phase in ["joining", "joined"] else "idle"
		game_view = old.game_view
		if game_view != null:
			game_view.reparent(game_area)
		old.session = null
		old.game_view = null
		_navigate(Page.CONNECTING if session.snapshot.is_empty() else Page.MATCH, false)
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
		_connect_game_controls(game_view, session.snapshot.get("role") == "spectator" or (_supports_room_access() and session.role == "spectator"))
	_layout_game()
	_refresh_library()
	return true

func ui_restore_focus(old_focus: Control, old: Control, path: NodePath) -> void:
	if old.get("user_panel") != null and old.user_panel.visible:
		_open_user_profile()
		user_panel.draft = old.user_panel.draft.duplicate(true)
		user_panel.name_input.text = str(user_panel.draft.get("nickname", ""))
		user_panel._refresh()
	elif old.settings_dialog.visible:
		_open_settings()
		if old_focus == old.motion_choice:
			motion_choice.grab_focus()
		elif old_focus == old.get("sound_choice"):
			sound_choice.grab_focus()
		elif old_focus == old.get("haptic_choice"):
			haptic_choice.grab_focus()
		elif old_focus == old.get("language_choice"):
			language_choice.grab_focus()
		elif old_focus == old.get("settings_invite") and settings_invite.visible:
			settings_invite.grab_focus()
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
		else:
			_render_page(true)

# Optional Mod UI extension; no dependency from a Mod on app internals.
func _connect_game_controls(view: Control, spectating: bool = false) -> void:
	if view.has_method("set_session_services") and session != null:
		if spectating: view.set_session_services(SpectatorServices.new(session))
		else: view.set_session_services(session)
	if view.has_signal("platform_action") and not view.is_connected("platform_action", _game_platform_action):
		view.connect("platform_action", _game_platform_action)
	_send_game_status()

func _disconnect_game_controls(view: Control) -> void:
	if view.has_signal("platform_action") and view.is_connected("platform_action", _game_platform_action):
		view.disconnect("platform_action", _game_platform_action)

func _game_platform_action(action: String) -> void:
	if action.begins_with("haptic:"):
		ui_feedback.haptic(action.trim_prefix("haptic:"))
		return
	match action:
		"settings": _open_settings()
		"reconnect": _reconnect()
		"invite": _open_invite()
		"start_round":
			if flow.page == Page.MATCH and _top_modal() == null and is_instance_valid(session) and session.has_method("start_round"):
				session.start_round()
		"exit":
			if session != null and (session.snapshot.get("view", {}).get("finished", false) or session.snapshot.get("view", {}).get("phase") == "finished"):
				_leave()
			else:
				_request_leave()

func _send_game_status() -> void:
	if not is_instance_valid(game_view) or not game_view.has_method("set_platform_state"):
		return
	var ready_to_play: bool = session != null and (session.host or (session.connection_state == "connected" and not session.snapshot.is_empty())) and flow.page == Page.MATCH
	var modal_open := _top_modal() != null
	var message := status.text if status_key not in ["CONNECTED", "LOBBY_HELP", "LEFT_ROOM", "ROOM_CREATED"] else ""
	var state := {"enabled": true, "connected": ready_to_play, "can_reconnect": _can_reconnect(), "can_invite": ready_to_play and session.host and (not session.get_join_info().is_empty() or _has_bluetooth_invite()), "message": message, "reduce_motion": bool(profile.get("reduce_motion", false)), "input_paused": modal_open}
	if ready_to_play and session.has_method("can_start_round"):
		state.can_start = session.can_start_round()
	if session != null and session.has_method("start_round"):
		state.host = session.host
		state.password_required = session.host and session.room != null and session.room.password_required()
	if game_view.get_meta("novaparty_platform_state", {}) == state: return
	game_view.set_meta("novaparty_platform_state", state.duplicate(true))
	game_view.set_platform_state(state)
	if modal_open: _suspend_focus(game_view)

func _layout_game() -> void:
	var previous_focus := get_viewport().gui_get_focus_owner()
	immersive_game = is_instance_valid(session) and is_instance_valid(game_view) and game_view.has_method("wants_fullscreen") and game_view.wants_fullscreen()
	if immersive_game:
		immersive_surface.color = game_view.fullscreen_background() if game_view.has_method("fullscreen_background") else T.PAGE
	if is_instance_valid(game_view):
		var target: Control = immersive_area if immersive_game else game_area
		if game_view.get_parent() != target: game_view.reparent(target, false)
	_render_page()
	_update_join_invite()
	_send_game_status()
	if _top_modal() == null and is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
		if previous_focus.focus_mode != Control.FOCUS_NONE: previous_focus.grab_focus()

func _restore_exit_focus() -> void:
	if is_instance_valid(leave_focus) and leave_focus.is_visible_in_tree():
		leave_focus.grab_focus()
	elif is_instance_valid(game_view) and game_view.has_method("restore_platform_focus"):
		game_view.restore_platform_focus("exit")
	else:
		_render_page(true)


func _build_lan_ui() -> void:
	discovery = Discovery.new()
	add_child(discovery)
	join_browser = preload("res://app/ui/screens/join_browser.gd").new()
	setup.add_child(join_browser)
	join_browser.selected.connect(_inspect_peer)
	join_browser.refresh_requested.connect(func(): _search_nearby(join_browser.bluetooth_mode))
	join_browser.manual_requested.connect(_show_manual_join)
	join_browser.scan_requested.connect(_start_scan)
	join_browser.bluetooth_requested.connect(_request_bluetooth)
	var radio = Bluetooth.shared(get_tree())
	join_browser.set_bluetooth_available(radio.backend != null and radio.state != "unsupported")
	radio.state_changed.connect(_bluetooth_state_changed)
	radio.host_state_changed.connect(_bluetooth_host_state_changed)
	radio.host_status_changed.connect(_bluetooth_host_status)
	qr_scanner = preload("res://sdk/net/qr_scanner.gd").new()
	add_child(qr_scanner)
	qr_scanner.scanned.connect(_join_scanned_code)
	qr_scanner.failed.connect(func(code):
		_set_status("CAMERA_PERMISSION_DENIED" if code == "camera_permission_denied" else "CAMERA_UNAVAILABLE")
		_render_page(true)
	)
	var invite_layer := CanvasLayer.new()
	invite_layer.layer = 25
	add_child(invite_layer)
	join_invite = preload("res://app/ui/dialogs/join_invite.gd").new()
	join_invite.theme = theme
	invite_layer.add_child(join_invite)
	join_invite.hide()
	join_invite.bluetooth_requested.connect(_request_bluetooth_host)
	join_invite.confirmed.connect(func():
		invite_dismissed = true
		if game_view != null and game_view.has_method("restore_platform_focus"):
			game_view.restore_platform_focus("invite")
		elif is_instance_valid(game_view) and game_view.has_method("focus_default") and session != null and session.snapshot.get("players", []).size() > 1:
			game_view.focus_default()
		elif invite_button.is_visible_in_tree(): invite_button.grab_focus()
	)
	join_invite.visibility_changed.connect(_modal_changed)
	discovery.changed.connect(join_browser.populate)
	discovery.unavailable.connect(func(_code): join_browser.unavailable())
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	download_dialog = preload("res://app/ui/dialogs/mod_download.gd").new()
	download_dialog.theme = theme
	layer.add_child(download_dialog)
	download_dialog.confirmed.connect(func():
		if peer_transfer != null:
			peer_phase = "downloading"
			peer_transfer.confirm_download()
	)
	download_dialog.canceled.connect(_cancel_peer_join)
	download_dialog.visibility_changed.connect(_modal_changed)
	room_access = preload("res://app/ui/dialogs/room_access.gd").new()
	room_access.theme = theme
	layer.add_child(room_access)
	room_access.visibility_changed.connect(_modal_changed)
	room_access.chosen.connect(func(role: String, password: String):
		if room_access.creating:
			_start(true, 27840, {"role": role, "password": password})
		else:
			_continue_peer_join(join_offer, role, password)
	)
	room_access.confirmed.connect(func():
		if room_access.creating: create_button.grab_focus()
		else: _cancel_peer_join()
	)

func _show_manual_join() -> void:
	if session != null or peer_transfer != null: return
	_navigate(Page.MANUAL)
	_set_status("JOIN_HELP")

func _inspect_peer(target: Dictionary) -> void:
	if session != null or peer_transfer != null: return
	if not flow.is_join(): _navigate(Page.NEARBY, false)
	peer_target = target.duplicate(true)
	peer_error = ""
	peer_phase = "inspecting"
	peer_transfer = PeerMods.new()
	add_child(peer_transfer)
	peer_transfer.catalog_received.connect(_peer_catalog)
	peer_transfer.progress.connect(download_dialog.update_progress)
	peer_transfer.completed.connect(_peer_downloaded)
	peer_transfer.failed.connect(_peer_failed)
	_set_status("CONNECTING_BLUETOOTH" if str(target.address).begins_with("ble:") else "CHECKING_GAME")
	_render_page()
	pending_cancel.grab_focus()
	var error: Error = peer_transfer.inspect_remote(str(target.address), int(target.port), str(target.get("session_id", "")))
	if error != OK:
		_peer_failed("connect_failed")

func _peer_catalog(metadata: Dictionary) -> void:
	if metadata.get("kind", "game") != "game":
		_peer_failed("not_a_game")
		return
	join_offer = metadata.duplicate(true)
	if not _supports_room_access():
		if metadata.get("password_required", false) or metadata.get("player_slots", 1) <= 0: _peer_failed("incompatible")
		else: _continue_peer_join(join_offer)
		return
	var can_play: bool = metadata.get("player_slots", 1) > 0
	var can_watch: bool = metadata.get("spectator_slots", 0) > 0
	if not can_play and not can_watch:
		_peer_failed(str(metadata.get("player_unavailable", "room_full")))
	elif (can_watch or metadata.get("password_required", false)) and not _find_peer_mod(metadata).is_empty():
		_prompt_join(join_offer)
	else:
		_continue_peer_join(join_offer)

func _prompt_join(metadata: Dictionary, error: String = "") -> void:
	peer_phase = "role"
	_render_page()
	var localized = metadata.get("localized_names", {})
	var label: String = metadata.name
	if localized is Dictionary: label = str(localized.get("zh" if TranslationServer.get_locale().begins_with("zh") else "en", label))
	room_access.join_prompt(metadata.get("player_slots", 1) > 0, metadata.get("spectator_slots", 0) > 0, metadata.get("password_required", false), label, error)

func _find_peer_mod(metadata: Dictionary) -> Dictionary:
	for index in range(choices.item_count):
		var path: String = choices.get_item_metadata(index)
		known_mods[path] = loader.inspect(path)
	for info in known_mods.values():
		if not info.is_empty() and info.manifest.id == metadata.game_id and info.rules_fingerprint == metadata.rules_fingerprint:
			return info
	return {}

func _continue_peer_join(metadata: Dictionary, role: String = "player", password: String = "") -> void:
	var info := _find_peer_mod(metadata)
	if not info.is_empty():
		_join_peer(info, metadata, role, password)
		return
	# A failed password attempt may have closed the previous catalog connection.
	if peer_transfer == null:
		_inspect_peer(peer_target)
		return
	peer_phase = "confirmation"
	_render_page()
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
	known_mods[info.root] = info
	if _supports_room_access() and metadata.has("player_slots"):
		# The offer may have changed during a package download. Refresh the live
		# room before presenting available roles (especially on a slow BLE link).
		var target := peer_target.duplicate(true)
		target.session_id = metadata.session_id
		_reset_peer_join()
		_inspect_peer(target)
	else:
		_join_peer(info, metadata)

func _join_peer(info: Dictionary, metadata: Dictionary, role: String = "player", password: String = "") -> void:
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
	var options := {"role": role, "password": password} if role == "spectator" or not password.is_empty() else {}
	if peer_transfer != null:
		peer_transfer.cancel()
		peer_transfer.queue_free()
		peer_transfer = null
	download_dialog.hide()
	room_access.hide()
	expected_join_session = metadata.session_id
	peer_phase = "joining"
	var error := _start(false, -1, options)
	if error != OK and peer_phase == "joining": _peer_failed("incompatible")

func _join_error_key(code: String, resuming: bool = false) -> String:
	match code:
		"room_full": return "JOIN_ROOM_FULL"
		"password_required": return "ROOM_PASSWORD_REQUIRED"
		"wrong_password": return "ROOM_WRONG_PASSWORD"
		"spectators_full": return "JOIN_SPECTATORS_FULL"
		"spectators_unsupported": return "JOIN_SPECTATORS_UNSUPPORTED"
		"role_locked": return "JOIN_ROLE_LOCKED"
		"game_in_progress": return "JOIN_IN_PROGRESS"
		"room_changed", "invalid_resume_token", "session_replaced": return "JOIN_ROOM_ENDED" if resuming else "JOIN_ROOM_CHANGED"
		"incompatible", "not_a_game": return "JOIN_INCOMPATIBLE"
		"download_storage_failed": return "JOIN_STORAGE_FAILED"
		"package_hash_mismatch", "invalid_chunk": return "JOIN_PACKAGE_FAILED"
		"transfer_timeout", "handshake_timeout": return "JOIN_TIMEOUT"
		_: return "PEER_JOIN_FAILED"

func _peer_failed(code: String) -> void:
	_reset_peer_join()
	peer_phase = "failed"
	peer_error = code
	_navigate(flow.join_origin)
	_set_status(_join_error_key(code))

func _reset_peer_join() -> void:
	if peer_transfer != null:
		peer_transfer.cancel()
		peer_transfer.queue_free()
		peer_transfer = null
	if download_dialog != null: download_dialog.hide()
	if room_access != null: room_access.hide()
	join_offer.clear()
	peer_phase = "idle"
	peer_error = ""
	expected_join_session = ""

func _cancel_peer_join() -> void:
	if flow.page == Page.CONNECTING:
		_clear_session()
		joined = false
		token = ""
	_reset_peer_join()
	if flow.page == Page.CONNECTING or flow.is_join():
		_navigate(flow.join_origin)
		_set_status("JOIN_HELP")

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
	if method == "ble.status":
		return Bluetooth.shared(get_tree()).diagnostic()
	if method == "ble.request_access":
		var radio = Bluetooth.shared(get_tree())
		if radio.backend == null or radio.state == "unsupported": return {"requested": false}
		radio.request_access()
		return {"requested": true}
	if method == "lan.status":
		return {"rooms": discovery.list_rooms(), "backend": discovery.backend, "discovery_error": discovery.last_error, "phase": peer_phase, "last_error": peer_error, "confirmation": download_dialog.visible and not download_dialog.working, "role_prompt": room_access.visible and not room_access.creating, "received": peer_transfer.received if peer_transfer != null else 0}
	if method == "lan.search":
		var was_nearby := flow.page == Page.NEARBY
		if session == null: _open_setup(false)
		# Diagnostics may select Bluetooth without tapping or requesting access.
		var use_bluetooth: bool = params.get("transport", "") == "ble"
		if use_bluetooth or was_nearby or session != null: _search_nearby(use_bluetooth)
		return {"searching": true}
	if method == "lan.inspect":
		if params.get("address") is String and params.address.begins_with("ble:") and params.address.length() <= 68:
			_inspect_peer({"address": params.address, "port": 0})
			return {"inspecting": true}
		if not params.get("address") is String or not params.address.is_valid_ip_address() or not (params.get("port") is int or params.get("port") is float) or params.port != int(params.port) or params.port < 1024 or params.port > 65535:
			return {"error": "invalid_address"}
		_inspect_peer(params)
		return {"inspecting": true}
	if method == "lan.confirm_download" and peer_phase == "confirmation":
		download_dialog.confirm.pressed.emit()
		return {"downloading": true}
	if method == "lan.choose_role" and peer_phase == "role" and room_access.visible and not join_offer.get("password_required", false):
		var role = params.get("role")
		if role == "player" and join_offer.get("player_slots", 1) > 0:
			_continue_peer_join(join_offer, "player")
			return {"joining": true}
		if role == "spectator" and join_offer.get("spectator_slots", 0) > 0:
			_continue_peer_join(join_offer, "spectator")
			return {"joining": true}
	if method == "lan.cancel":
		_cancel_peer_join()
		return {"canceled": true}
	return {"error": "invalid_state"}

func _exit_tree() -> void:
	if peer_transfer != null:
		peer_transfer.cancel()

# Both iOS and Android should prompt for Bluetooth only after an explicit tap.
func _request_bluetooth() -> void:
	if join_browser.bluetooth_mode:
		_set_status("JOIN_HELP")
		_search_nearby(false)
		return
	var radio = Bluetooth.shared(get_tree())
	if radio.state == "on":
		_set_status("JOIN_HELP")
		_search_nearby(true)
	elif _can_request_bluetooth(radio.state):
		_set_status("BLUETOOTH_PERMISSION")
		radio.request_access()
	else:
		_set_status("BLUETOOTH_UNAVAILABLE")

func _can_request_bluetooth(state: String) -> bool:
	return state == "unknown" or (state == "unauthorized" and OS.get_name() == "Android")

func _bluetooth_state_changed(state: String) -> void:
	if not is_inside_tree(): return  # UI hot swap may have already detached this shell.
	join_browser.set_bluetooth_available(Bluetooth.shared(get_tree()).backend != null and state != "unsupported")
	if not join_browser.is_visible_in_tree(): return
	if state == "on" and (status_key == "BLUETOOTH_PERMISSION" or join_browser.bluetooth_mode):
		_set_status("JOIN_HELP")
		_search_nearby(true)
	elif state in ["unauthorized", "off", "unsupported"] and (status_key == "BLUETOOTH_PERMISSION" or join_browser.bluetooth_mode):
		_set_status("BLUETOOTH_UNAVAILABLE")
		if join_browser.bluetooth_mode: _search_nearby(true)

func _bluetooth_host_state_changed(state: String) -> void:
	if not is_instance_valid(join_invite) or not join_invite.visible: return
	var message: String = join_invite.bluetooth_status.text
	if state == "on" and message == "BLUETOOTH_HOST_PERMISSION":
		_request_bluetooth_host()
	elif state in ["unauthorized", "off", "unsupported"]:
		join_invite.set_bluetooth(_has_bluetooth_invite(), "BLUETOOTH_UNAVAILABLE")
	elif state == "on" and message == "BLUETOOTH_UNAVAILABLE":
		join_invite.set_bluetooth(_has_bluetooth_invite())

func _has_bluetooth_invite() -> bool:
	var radio = Bluetooth.shared(get_tree())
	return OS.get_name() in ["Android", "iOS"] and radio.backend != null and radio.host_state() != "unsupported" and is_instance_valid(session) and (session.accepts_new_connections() if session.has_method("accepts_new_connections") else session.accepts_new_players())

func _request_bluetooth_host() -> void:
	if not _has_bluetooth_invite() or not join_invite.visible: return
	var radio = Bluetooth.shared(get_tree())
	var state: String = radio.host_state()
	if state == "on":
		var enabled: bool = session.enable_bluetooth_hosting()
		_bluetooth_host_status(radio.host_status if enabled else "failed")
	elif _can_request_bluetooth(state):
		join_invite.set_bluetooth(true, "BLUETOOTH_HOST_PERMISSION")
		radio.request_access(true)
	else:
		join_invite.set_bluetooth(true, "BLUETOOTH_UNAVAILABLE")

func _bluetooth_host_status(value: String) -> void:
	if join_invite == null or not join_invite.visible or not _has_bluetooth_invite(): return
	var keys := {"starting": "BLUETOOTH_HOST_STARTING", "ready": "BLUETOOTH_HOST_READY", "failed": "BLUETOOTH_HOST_FAILED"}
	var code := str(session.snapshot.get("game_session_id", "")).left(6) if value == "ready" else ""
	join_invite.set_bluetooth(true, keys.get(value, ""), value not in ["starting", "ready"], code)

func _start_scan() -> void:
	if session == null:
		if not flow.is_join(): _navigate(Page.NEARBY)
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
	var waiting: bool = session.host and not mod_info.manifest.get("host_start", false) and session.snapshot.get("players", []).size() < 2
	if join_invite.visible and not waiting and not invite_dismissed:
		join_invite.close()
	elif waiting and not controlled and not invite_dismissed and not join_invite.visible:
		_open_invite(false)

func _open_invite(manual: bool = true) -> void:
	if not is_instance_valid(session) or not session.host or join_invite.visible: return
	var info: Dictionary = session.get_join_info()
	var has_bluetooth := _has_bluetooth_invite()
	if info.is_empty() and not has_bluetooth: return
	if manual: invite_dismissed = true
	join_invite.set_bluetooth(has_bluetooth)
	join_invite.present(session.get_join_qr() if not info.is_empty() else null, info, session.room != null and session.room.has_method("password_required") and session.room.password_required())
	if has_bluetooth and session.bluetooth_hosting:
		_bluetooth_host_status(Bluetooth.shared(get_tree()).host_status)

func _top_modal() -> Control:
	for modal in [room_access, download_dialog, leave_dialog, user_panel, settings_dialog, join_invite]:
		if is_instance_valid(modal) and modal.visible: return modal
	return null

func _modal_changed() -> void:
	var top := _top_modal()
	for control in modal_focus_modes:
		if is_instance_valid(control): control.focus_mode = modal_focus_modes[control]
	modal_focus_modes.clear()
	if top != null:
		for branch in [home, content_margin, immersive_surface, join_invite, user_panel, settings_dialog, leave_dialog, download_dialog, room_access]:
			if is_instance_valid(branch) and branch != top: _suspend_focus(branch)
	_send_game_status()

func _suspend_focus(node: Node) -> void:
	if node is Control and node.focus_mode != Control.FOCUS_NONE:
		modal_focus_modes[node] = node.focus_mode
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_suspend_focus(child)

func _build_user_profile() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 52
	add_child(layer)
	user_panel = preload("res://app/ui/dialogs/user_panel.gd").new()
	user_panel.theme = theme
	layer.add_child(user_panel)
	user_panel.saved.connect(_save_user_profile)
	user_panel.confirmed.connect(func():
		if home.visible: home.nickname_button.grab_focus()
	)
	user_panel.visibility_changed.connect(_modal_changed)

func _open_user_profile() -> void:
	user_panel.edit(profile)

func _save_user_profile(value: Dictionary) -> void:
	var previous := profile.duplicate(true)
	var public := UserProfile.local_public(value)
	profile.nickname = UserProfile.clean_name(value.get("nickname", ""), "")
	profile.avatar = public.avatar.duplicate(true)
	profile.theme_color = public.theme_color
	if not _save_profile():
		profile = previous
		user_panel.error_label.show()
		return
	nickname.text = public.display_name
	if session != null: session.update_user_profile(profile)
	_refresh_home()
	ui_feedback.play("confirm")
	user_panel.close()
