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

func _ready() -> void:
	if OS.has_feature("android"):
		android = load("res://sdk/net/discovery_android.gd").new()
		add_child(android)
		android.event.connect(_event)
		backend = "android_nsd"
	elif ClassDB.class_exists("NovaBonjour"):
		apple = ClassDB.instantiate("NovaBonjour")
		backend = "apple_bonjour"

func browse() -> void:
	if browsing:
		stop_browse()
	browsing = true
	rooms.clear()
	changed.emit([])
	if apple != null:
		_exchange({"op": "browse"})
	elif android != null:
		android.browse()
	_browse_bluetooth()
	if apple == null and android == null and not bluetooth_scanning:
		unavailable.emit("native_discovery_unavailable")

# Bluetooth results join the same list; their address is "ble:<device key>".
func _browse_bluetooth() -> void:
	if bluetooth == null:
		bluetooth = Bluetooth.shared(get_tree())
		bluetooth.devices_changed.connect(func(_devices): if browsing: changed.emit(list_rooms()))
	# A normal Wi-Fi search must not instantiate CoreBluetooth and request permission.
	if bluetooth.state == "on" and not bluetooth_scanning:
		bluetooth_scanning = true
		bluetooth.scan()

func _stop_bluetooth() -> void:
	if bluetooth_scanning:
		bluetooth_scanning = false
		bluetooth.stop_scan()

func stop_browse() -> void:
	browsing = false
	if apple != null:
		_exchange({"op": "stop_browse"})
	if android != null:
		android.stop_browse()
	_stop_bluetooth()
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
	elif value.get("type") == "found" and browsing:
		var txt = value.get("txt", {})
		if not txt is Dictionary or txt.get("v") != "1" or not txt.get("sid") is String or txt.sid == own_session or not txt.get("game") is String or not txt.game.is_valid_identifier():
			return
		if not value.get("address") is String or not value.address.is_valid_ip_address() or int(value.get("port", 0)) < 1024 or int(value.get("port", 0)) > 65535 or rooms.size() >= 64:
			return
		rooms[str(value.key)] = {"key": str(value.key), "session_id": str(txt.sid).left(128), "game_id": txt.game, "name": str(txt.get("name", txt.game)).left(64), "version": str(txt.get("ver", "")).left(32), "source_name": str(txt.get("host", "")).left(32), "address": value.address, "port": int(value.port)}
		changed.emit(list_rooms())

func list_rooms() -> Array:
	var unique := {}
	for room in rooms.values():
		if not unique.has(room.session_id) or str(unique[room.session_id].address).begins_with("127."):
			unique[room.session_id] = room
	var list := unique.values()
	list.sort_custom(func(a, b): return (a.name + a.key) < (b.name + b.key))
	if bluetooth_scanning:
		for device in bluetooth.list_devices():
			# A host already listed through the local network is not repeated as a Bluetooth row.
			var listed := false
			if not str(device.code).is_empty():
				for room in list:
					if str(room.session_id).begins_with(device.code): listed = true
			if not listed:
				list.append({"key": "ble:" + device.key, "transport": "ble", "session_id": "", "code": device.code, "game_id": "", "name": "", "version": "", "source_name": "", "address": "ble:" + device.key, "port": 0, "rssi": device.rssi})
	return list

func _exit_tree() -> void:
	_stop_bluetooth()
	if apple != null:
		apple.free()
