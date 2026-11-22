extends SceneTree
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL UI: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1920, 1080)
	var main = load("res://app/main.tscn").instantiate()
	main.profile_path = "user://ui-test-" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(main)
	await process_frame
	await process_frame
	check(root.content_scale_size == Vector2i(1280, 720), "landscape scale")
	check(main.theme.default_font.has_char("棋".unicode_at(0)), "bundled font contains Chinese glyphs")
	var portrait: Dictionary = main.safe_padding(Rect2i(0, 177, 1170, 2253), Vector2i(1170, 2532), Vector2(390, 844))
	check(portrait.top == 79 and portrait.bottom == 54 and portrait.left == 20, "portrait avoids notch and home indicator")
	var landscape: Dictionary = main.safe_padding(Rect2i(177, 0, 2178, 1068), Vector2i(2532, 1170), Vector2(844, 390))
	check(landscape.left == 79 and landscape.right == 79 and landscape.bottom == 54, "rotated safe area avoids both side cutouts")
	check(not quit_on_go_back, "Android back must not auto-quit")
	check(main.home.visible and not main.content_margin.visible, "real startup opens party home")
	check(root.gui_get_focus_owner() == main.home.start_button, "home focuses the primary action")
	check(main.home.header.size.y < 82 and main.home.start_button.get_global_rect().end.y <= root.get_visible_rect().size.y, "landscape brand and badge leave room for the primary action")
	main.set_language("en")
	check(TranslationServer.translate("APP_NAME") == "NovaParty", "English title installed")
	check(TranslationServer.translate("START_GAME") == "Choose a game", "English home selection label")
	check(main.choices.get_item_text(0) == "Gomoku", "game picker updates language without changing IDs")
	main.set_language("zh_CN")
	check(TranslationServer.translate("APP_NAME") == "星星大作战", "Chinese title installed")
	check(TranslationServer.translate("START_GAME") == "选择游戏", "Chinese home selection label")
	main.join_invite.set_bluetooth(true, "BLUETOOTH_HOST_READY", false, "e0726a")
	check(main.join_invite.bluetooth_room_code.visible and main.join_invite.bluetooth_room_code.text == "蓝牙房间号：E0726A", "host shows the same uppercase code as the Bluetooth list")
	main.join_invite.set_bluetooth(true, "BLUETOOTH_HOST_FAILED")
	check(not main.join_invite.bluetooth_room_code.visible, "stale code is hidden after advertisement failure")
	main.join_invite.set_bluetooth(false)
	var orbit_a: Array = main.home.orbit_positions(0)
	var orbit_b: Array = main.home.orbit_positions(1)
	check(orbit_a[0].distance_to(orbit_b[0]) > 1, "stars orbit over time")
	main.home.set_reduced_motion(true)
	var frozen: float = main.home.motion_time
	main.home._process(1.5)
	check(main.home.motion_time == frozen, "reduce motion freezes animation time")
	main.home.set_reduced_motion(false)
	main._open_settings()
	await process_frame
	await process_frame
	check(main.settings_dialog.panel.size.y < root.get_visible_rect().size.y, "settings panel stays within viewport")
	check(main.settings_dialog.scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER and not main.settings_dialog.scroll.get_v_scroll_bar().visible, "settings scroll without a visible scrollbar")
	check(main.home.start_button.focus_mode == Control.FOCUS_NONE, "modal settings isolates home focus")
	main.motion_choice.button_pressed = true
	check(main.home.reduced_motion and main.profile.reduce_motion, "settings motion preference takes effect")
	var saved_profile = JSON.parse_string(FileAccess.get_file_as_string(main.profile_path))
	check(saved_profile.reduce_motion, "motion preference is persisted")
	main.settings_dialog.close()
	check(root.gui_get_focus_owner() == main.home.settings_button, "closing settings restores its entry focus")
	main.home.set_reduced_motion(false)
	main._open_setup(true)
	check(main.roots == ["res://mods/gomoku"], "only Gomoku is bundled by default")
	# Other games enter the library explicitly as external test fixtures.
	main._add_choice("res://mods/hidden_cards")
	main._add_choice("res://mods/jump_rope")
	check(not main.home.is_processing(), "hidden home stops decorative processing")
	await process_frame
	await process_frame
	check(main.library.cards.size() == main.choices.item_count + 1, "last library tile adds a game")
	check(main.library.cards[-1].tooltip_text == TranslationServer.translate("ADD_GAME"), "add tile is labelled and localized")
	check(not main.nickname.visible and not main.choices.visible, "nickname and old dropdown are absent from setup")
	check(main.library.columns == 3, "TV uses a wide cover grid")
	main.library.cards[1].pressed.emit()
	check(main.choices.selected == 1 and main.library.selection == 1, "cover selection drives actual launch selection")
	check(root.gui_get_focus_owner() == main.create_button, "selected card moves focus to launch")
	check(not main.settings_action.visible, "selection footer omits settings")
	check(main.library.cards[1].button_pressed and main.library.cards[1].get_meta("detail").text == main.tr("GAME_PICKED_SHORT"), "selected game has explicit visual and semantic feedback")
	check(main.create_button.text == "LAUNCH_GAME", "launch action avoids room terminology")
	check(main.back_button.global_position.y > main.library.global_position.y, "back follows game grid in fixed footer")
	check(main.library._cover({"id": "unknown"}) != null, "unknown games receive a default cover")
	root.size = Vector2i(540, 960)
	await process_frame
	await process_frame
	await process_frame
	check(main.library.columns == 2, "phone uses two cover columns")
	var scroller: ScrollContainer = main.library.get_parent().get_parent().get_parent().get_parent()
	check(scroller.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER and scroller.follow_focus, "shared pages hide the scrollbar and still follow focus")
	check(main.footer.get_global_rect().end.y <= root.get_visible_rect().size.y, "phone footer remains inside safe viewport")
	check(main.back_button.get_global_rect().end.x <= root.get_visible_rect().size.x, "phone back action fits horizontally")
	main._open_settings()
	await process_frame
	main.settings_dialog.close()
	check(root.gui_get_focus_owner() == main.library.cards[1], "closing a restored settings panel returns to selected card")
	root.size = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	main.session = Node.new()
	main.add_child(main.session)
	main.setup.hide()
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	root.go_back_requested.emit()
	await process_frame
	check(main.session != null and main.leave_dialog.visible, "back does not silently abandon a live game")
	main.leave_dialog.confirmed.emit()
	check(main.session == null and main.home.visible, "confirmed leave returns to party home")
	check(root.gui_get_focus_owner() == main.home.start_button, "leave restores primary action focus")
	root.size = Vector2i(540, 960)
	await process_frame
	await process_frame
	check(root.content_scale_size == Vector2i(540, 960), "portrait scale")
	check(main.home.header.size.y < 82 and main.home.join_button.get_global_rect().end.y < main.home.nickname_button.global_position.y, "portrait join stays above the quick-access dock")
	await verify_join_routes(main)
	if root.gui_get_focus_owner():
		root.gui_get_focus_owner().release_focus()
	var view = load("res://mods/hidden_cards/view.gd").new()
	root.add_child(view)
	var rules = load("res://mods/hidden_cards/rules.gd").new()
	var snapshot := {"seat": 0, "players": [{}, {}], "view": rules.view_for(rules.initial_state(42), 0)}
	main.set_language("en")
	view.render(snapshot)
	check(view.get_child(0).text.begins_with("Hidden Cards"), "game instructions localize from filtered state")
	var focused := root.gui_get_focus_owner()
	check(focused != null and view.is_ancestor_of(focused), "cards get initial focus")
	var buttons = view.get_child(1).get_children()
	buttons[1].grab_focus()
	var selected = buttons[1].get_meta("card")
	view.render(snapshot)
	focused = root.gui_get_focus_owner()
	check(focused != null and focused.get_meta("card", -1) == selected, "snapshot preserves selected card focus")
	view.queue_free()
	DirAccess.remove_absolute(main.profile_path)
	main.queue_free()
	await process_frame
	await create_timer(0.06).timeout
	print("UI_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func verify_join_routes(main: Control) -> void:
	main._open_setup(false)
	check(main.flow.page == main.Page.NEARBY and main.discovery.browsing and not main.discovery.bluetooth_only, "join starts with LAN discovery")
	main._search_nearby(true)
	check(main.discovery.bluetooth_only and main.join_browser.bluetooth.text == "WIFI_SEARCH", "Bluetooth search has a dedicated list and a way back to LAN")
	main.join_browser.bluetooth.pressed.emit()
	check(not main.discovery.bluetooth_only and main.join_browser.bluetooth.text == "BLUETOOTH_SEARCH", "transport action returns to LAN search")
	var room := {"key": "fixture", "name": "Test game", "version": "1", "source_name": "Friend", "address": "127.0.0.1", "port": 27840}
	main.join_browser.populate([room])
	var room_button: Button = main.join_browser.room_buttons.fixture
	room_button.grab_focus()
	main.join_browser.populate([room.merged({"version": "2"}, true)])
	check(main.join_browser.room_buttons.fixture == room_button and root.gui_get_focus_owner() == room_button, "discovery refresh retains room and focus by key")
	main._show_manual_join()
	check(not main.discovery.browsing and main.network_row.visible and not main.library.visible, "manual join is a dedicated form with no guessed game")
	main.address.text = "not an address"
	main._submit_manual_join()
	check(main.manual_error.visible and root.gui_get_focus_owner() == main.address and main.peer_transfer == null, "invalid host focuses the field without connecting")
	var server := TCPServer.new()
	check(server.listen(0, "127.0.0.1") == OK, "fixture holds an unresponsive connection")
	main.address.text = "127.0.0.1:" + str(server.get_local_port())
	main._submit_manual_join()
	check(main.peer_phase == "inspecting" and main.pending_cancel.visible and main.join_button.disabled, "manual catalog check is cancelable and single-submit")
	var transfer = main.peer_transfer
	main._submit_manual_join()
	check(main.peer_transfer == transfer and main.address.text == "127.0.0.1" and int(main.port.value) == server.get_local_port(), "pasted endpoint is retained; duplicate tap is ignored")
	main._go_back()
	check(main.flow.page == main.Page.MANUAL and main.peer_transfer == null and not main.join_button.disabled, "first back cancels work, not the form")
	main._go_back()
	check(main.flow.page == main.Page.NEARBY and main.discovery.browsing, "second back returns to nearby discovery")
	main._go_back()
	check(main.home.visible and not main.discovery.browsing, "back from nearby stops discovery and returns home")
	server.stop()
	await process_frame
