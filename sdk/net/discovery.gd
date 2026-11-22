extends Node
signal changed(rooms: Array)
signal unavailable(code: String)
var apple
var android
var rooms := {}
var browsing := false
var own_session := ""
var backend := "unavailable"
var last_error := ""
const Bluetooth = preload("res://sdk/net/bluetooth.gd")
var bluetooth
var bluetooth_scanning := false
var bluetooth_only := false

func _ready() -> void:
	if OS.has_feature("android"):
		android = load("res://sdk/net/discovery_android.gd").new()
		add_child(android)
		android.event.connect(_event)
		backend = "android_nsd"
	elif ClassDB.class_exists("NovaBonjour"):
		apple = ClassDB.instantiate("NovaBonjour")
		backend = "apple_bonjour"

func browse(use_bluetooth: bool = false) -> void:
	if browsing:
		stop_browse()
	browsing = true
	bluetooth_only = use_bluetooth
	rooms.clear()
	changed.emit([])
	if bluetooth_only:
		_browse_bluetooth()
	elif apple != null:
		_exchange({"op": "browse"})
	elif android != null:
		android.browse()
	else:
		unavailable.emit("native_discovery_unavailable")

func _browse_bluetooth() -> void:
	if bluetooth == null:
		bluetooth = Bluetooth.shared(get_tree())
	if not bluetooth.devices_changed.is_connected(_bluetooth_devices_changed):
		bluetooth.devices_changed.connect(_bluetooth_devices_changed)
	if bluetooth.state != "on":
		unavailable.emit("bluetooth_unavailable")
		return
	bluetooth_scanning = true
	bluetooth.scan()
	if not bluetooth.scanning:
		_stop_bluetooth()
		unavailable.emit("bluetooth_unavailable")

func _bluetooth_devices_changed(_devices: Array) -> void:
	if browsing and bluetooth_only: changed.emit(list_rooms())

func _stop_bluetooth() -> void:
	if bluetooth_scanning:
		bluetooth_scanning = false
		bluetooth.stop_scan()

func stop_browse() -> void:
	browsing = false
	if bluetooth_only:
		_stop_bluetooth()
	elif apple != null:
		_exchange({"op": "stop_browse"})
	elif android != null:
		android.stop_browse()
	rooms.clear()

func advertise(port: int, session_id: String, info: Dictionary, nickname: String) -> void:
	own_session = session_id
	var txt := {"v": "1", "sid": session_id, "game": info.manifest.id, "name": str(info.manifest.name).left(32), "ver": info.manifest.version, "host": nickname.left(32)}
	if apple != null:
		_exchange({"op": "advertise", "port": port, "txt": txt})
	elif android != null:
		android.advertise(port, txt)

func stop_advertise() -> void:
	own_session = ""
	if apple != null:
		_exchange({"op": "stop_advertise"})
	if android != null:
		android.stop_advertise()

func _exchange(command: Dictionary) -> void:
	var events = JSON.parse_string(apple.call("exchange", JSON.stringify(command)))
	if events is Array:
		for value in events:
			if value is Dictionary:
				_event(value)

func _process(_delta: float) -> void:
	if apple != null:
		_exchange({})

func _event(value: Dictionary) -> void:
	if value.get("type") == "error":
		last_error = str(value.get("code", "discovery_failed"))
		unavailable.emit(last_error)
	elif value.get("type") == "removed":
		if rooms.has(value.get("key")):
			rooms.erase(value.key)
			changed.emit(list_rooms())
	elif value.get("type") == "found" and browsing and not bluetooth_only:
		var txt = value.get("txt", {})
		if not txt is Dictionary or txt.get("v") != "1" or not txt.get("sid") is String or txt.sid == own_session or not txt.get("game") is String or not txt.game.is_valid_identifier():
			return
		if not value.get("address") is String or not value.address.is_valid_ip_address() or int(value.get("port", 0)) < 1024 or int(value.get("port", 0)) > 65535 or rooms.size() >= 64:
			return
		rooms[str(value.key)] = {"key": str(value.key), "session_id": str(txt.sid).left(128), "game_id": txt.game, "name": str(txt.get("name", txt.game)).left(64), "version": str(txt.get("ver", "")).left(32), "source_name": str(txt.get("host", "")).left(32), "address": value.address, "port": int(value.port)}
		changed.emit(list_rooms())

func list_rooms() -> Array:
	if bluetooth_only:
		var nearby := []
		if bluetooth_scanning:
			for device in bluetooth.list_devices():
				nearby.append({"key": "ble:" + device.key, "transport": "ble", "session_id": "", "code": device.code, "game_id": "", "name": "", "version": "", "source_name": "", "address": "ble:" + device.key, "port": 0, "rssi": device.rssi})
		return nearby
	var unique := {}
	for room in rooms.values():
		if not unique.has(room.session_id) or str(unique[room.session_id].address).begins_with("127."):
			unique[room.session_id] = room
	var list := unique.values()
	list.sort_custom(func(a, b): return (a.name + a.key) < (b.name + b.key))
	return list

func _exit_tree() -> void:
	_stop_bluetooth()
	if apple != null:
		apple.free()
