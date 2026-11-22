extends Node
# NovaParty Link over Bluetooth LE (GATT). One shared node per process owns the native radio bridge.
#
# The host is a GATT peripheral, each guest a central. Both directions carry the very same
# newline-delimited JSON frames as the TCP transport, cut into ATT-sized chunks, so Session,
# Room and Mod sharing are transport-agnostic. See docs/bluetooth.md for the wire contract.
signal devices_changed(devices: Array)
signal incoming(stream)
signal state_changed(state: String)
signal host_state_changed(state: String)
signal host_status_changed(status: String)
const SERVICE_UUID = "6E6F7661-7061-7274-7900-000000000001"
const RX_UUID = "6E6F7661-7061-7274-7900-000000000002" # central -> host, write with response
const TX_UUID = "6E6F7661-7061-7274-7900-000000000003" # host -> central, notify
const NAME_PREFIX = "NP"
const WINDOW = 4096 # unacknowledged bytes handed to the radio per link
const CONNECT_TIMEOUT_MS = 12000
const DEVICE_TTL_MS = 8000
const NODE_NAME = "NovaPartyBluetooth"

# Byte stream with the StreamPeerTCP subset that wire.gd uses.
class Stream extends RefCounted:
	var owner_ref: WeakRef
	var link := ""
	var key := ""
	var status := StreamPeerTCP.STATUS_CONNECTING
	var input := PackedByteArray()
	var outstanding := 0
	func poll() -> void: pass
	func get_status() -> int: return status
	func set_no_delay(_enabled: bool) -> void: pass
	func get_available_bytes() -> int: return input.size()
	func get_data(count: int) -> Array:
		var bytes := input.slice(0, count)
		input = input.slice(count)
		return [OK, bytes]
	func put_partial_data(bytes: PackedByteArray) -> Array:
		var owner = owner_ref.get_ref()
		if status != StreamPeerTCP.STATUS_CONNECTED or owner == null:
			return [ERR_CONNECTION_ERROR, 0]
		var count := mini(bytes.size(), WINDOW - outstanding)
		if count <= 0:
			return [OK, 0]
		outstanding += count
		owner._command({"op": "ble_send", "link": link, "data": Marshalls.raw_to_base64(bytes.slice(0, count))})
		return [OK, count]
	func disconnect_from_host() -> void:
		var owner = owner_ref.get_ref()
		if status != StreamPeerTCP.STATUS_NONE and owner != null:
			owner._close(self)
		status = StreamPeerTCP.STATUS_NONE

var backend # Object with exchange(String) -> String; null when the platform has no bridge
var backend_name := "unavailable"
var state := "unknown"
var android_host_state := ""
var last_error := ""
var hosting := false
var advertising := false
var host_status := ""
var scanning := false
var devices := {}
var streams := {}
var pending := {} # device key -> Stream waiting for ble_open
var scan_users := 0
var next_idle_poll := 0

static var _shared: Node

static func shared(tree: SceneTree) -> Node:
	if not is_instance_valid(_shared):
		_shared = load("res://sdk/net/bluetooth.gd").new()
		_shared.name = NODE_NAME
		tree.root.add_child.call_deferred(_shared)
		_shared._attach_platform()
	return _shared

func _attach_platform() -> void:
	if backend != null:
		return
	if OS.has_feature("android") and Engine.has_singleton("JavaClassWrapper") and Engine.has_singleton("AndroidRuntime"):
		var klass = Engine.get_singleton("JavaClassWrapper").wrap("org.novaparty.sdk.BleLink")
		if klass != null:
			backend = klass.BleLink(Engine.get_singleton("AndroidRuntime").getActivity())
			backend_name = "android_ble"
	elif ClassDB.class_exists("NovaBonjour") and OS.get_name() in ["macOS", "iOS"]:
		backend = ClassDB.instantiate("NovaBonjour")
		backend_name = "apple_corebluetooth"
	if backend != null:
		_command({"op": "ble_state"})

# Tests and tools may inject a loopback bridge.
func use_backend(value, label: String = "custom") -> void:
	backend = value
	backend_name = label
	state = "unknown"
	_command({"op": "ble_state"})

func available() -> bool:
	return backend != null and state not in ["unsupported", "unauthorized"]

func host_state() -> String:
	return android_host_state if not android_host_state.is_empty() else state

func request_access(for_host: bool = false) -> void:
	_command({"op": "ble_permissions", "host": for_host})

func host(session_id: String, locked: bool = false) -> bool:
	if backend == null or (backend_name in ["android_ble", "apple_corebluetooth"] and host_state() != "on"):
		return false
	hosting = true
	advertising = true
	host_status = "starting"
	_command({"op": "ble_host", "name": NAME_PREFIX + session_id.left(6) + ("L" if locked else "")})
	return true

func set_advertising(enabled: bool) -> void:
	if hosting and advertising != enabled:
		advertising = enabled
		host_status = "starting" if enabled else ""
		_command({"op": "ble_advertise", "enabled": enabled})

func stop_host() -> void:
	if hosting:
		hosting = false
		advertising = false
		host_status = ""
		_command({"op": "ble_host_stop"})

func scan() -> void:
	scan_users += 1
	if backend != null and not scanning:
		scanning = true
		devices.clear()
		_command({"op": "ble_scan"})

func stop_scan() -> void:
	scan_users = maxi(0, scan_users - 1)
	if scanning and scan_users == 0:
		scanning = false
		_command({"op": "ble_scan_stop"})
		devices.clear()

func list_devices() -> Array:
	var list := devices.values()
	list.sort_custom(func(a, b): return int(a.rssi) > int(b.rssi))
	return list

func connect_peer(key: String) -> Stream:
	# The native radio identifies a central link by peripheral key, not by Session.
	# A concurrent dial to the same target cannot safely replace a live stream.
	if backend == null or state == "unsupported" or key.is_empty() or key.length() > 64 or pending.has(key) or streams.has("c:" + key):
		return null
	var stream := Stream.new()
	stream.owner_ref = weakref(self)
	stream.key = key
	pending[key] = stream
	_command({"op": "ble_connect", "key": key})
	return stream

func _close(stream: Stream) -> void:
	if not stream.link.is_empty():
		if streams.get(stream.link) == stream:
			streams.erase(stream.link)
			_command({"op": "ble_close", "link": stream.link})
	elif pending.get(stream.key) == stream:
		pending.erase(stream.key)
		_command({"op": "ble_close", "link": "c:" + stream.key})

func _command(command: Dictionary) -> void:
	if backend == null:
		return
	var events = JSON.parse_string(str(backend.call("exchange", JSON.stringify(command))))
	if events is Array:
		for event in events:
			if event is Dictionary:
				_event(event)

func _process(_delta: float) -> void:
	if backend == null or state == "unsupported":
		return
	if not (hosting or scanning or not streams.is_empty() or not pending.is_empty()):
		var now := Time.get_ticks_msec()
		if now < next_idle_poll: return
		next_idle_poll = now + 250
	_command({})
	if scanning:
		var now := Time.get_ticks_msec()
		var expired := false
		for key in devices.keys():
			if now - int(devices[key].seen) > DEVICE_TTL_MS:
				devices.erase(key)
				expired = true
		if expired:
			devices_changed.emit(list_devices())

func _event(event: Dictionary) -> void:
	var link := str(event.get("link", ""))
	match event.get("type"):
		"ble_state":
			var value := str(event.get("state", "unknown"))
			if value != "on": scanning = false
			if value != state:
				state = value
				if backend_name != "android_ble":
					if state != "on": _clear_host_state()
					host_state_changed.emit(state)
				state_changed.emit(state)
		"ble_host_state":
			var previous := host_state()
			android_host_state = str(event.get("state", "unknown"))
			if android_host_state != previous:
				if android_host_state != "on": _clear_host_state()
				host_state_changed.emit(android_host_state)
		"ble_advertising":
			if hosting and advertising:
				host_status = "ready"
				host_status_changed.emit(host_status)
		"ble_error":
			last_error = str(event.get("code", "bluetooth_failed"))
			if hosting and (last_error.begins_with("advertise_failed") or last_error == "gatt_server_unavailable"):
				host_status = "failed"
				host_status_changed.emit(host_status)
			# Native permission refusals are followed by a state update; don't let a
			# scan refusal tear down an authorized host.
		"ble_found":
			var key := str(event.get("key", ""))
			var label := str(event.get("name", ""))
			if not scanning or key.is_empty() or key.length() > 64 or not label.begins_with(NAME_PREFIX) or devices.size() >= 32 and not devices.has(key):
				return
			var code := label.substr(NAME_PREFIX.length(), 6).to_lower()
			if code.length() != 6 or not code.is_valid_hex_number(false): code = ""
			var locked := label.substr(NAME_PREFIX.length() + 6) == "L" and not code.is_empty()
			if code.is_empty() and devices.has(key):
				code = devices[key].code
				locked = devices[key].get("password_required", false)
			var changed: bool = not devices.has(key) or devices[key].code != code or devices[key].get("password_required", false) != locked
			devices[key] = {"key": key, "code": code, "password_required": locked, "rssi": int(event.get("rssi", -100)), "seen": Time.get_ticks_msec()}
			if changed:
				devices_changed.emit(list_devices())
		"ble_open":
			if link.begins_with("c:") and pending.has(link.substr(2)):
				var stream: Stream = pending[link.substr(2)]
				pending.erase(link.substr(2))
				stream.link = link
				stream.status = StreamPeerTCP.STATUS_CONNECTED
				streams[link] = stream
			elif link.begins_with("p:") and hosting and not streams.has(link) and streams.size() < 16:
				var stream := Stream.new()
				stream.owner_ref = weakref(self)
				stream.link = link
				stream.status = StreamPeerTCP.STATUS_CONNECTED
				streams[link] = stream
				incoming.emit(stream)
			else:
				_command({"op": "ble_close", "link": link})
		"ble_data":
			var data = event.get("data")
			if streams.has(link) and data is String and data.length() <= 4096:
				streams[link].input.append_array(Marshalls.base64_to_raw(data))
		"ble_sent":
			if streams.has(link):
				streams[link].outstanding = maxi(0, streams[link].outstanding - int(event.get("bytes", 0)))
		"ble_closed":
			if streams.has(link):
				streams[link].status = StreamPeerTCP.STATUS_ERROR
				streams.erase(link)
			elif link.begins_with("c:") and pending.has(link.substr(2)):
				pending[link.substr(2)].status = StreamPeerTCP.STATUS_ERROR
				pending.erase(link.substr(2))

func _clear_host_state() -> void:
	hosting = false
	advertising = false
	host_status = ""

func diagnostic() -> Dictionary:
	return {"backend": backend_name, "state": state, "hosting": hosting, "advertising": advertising, "host_status": host_status, "host_state": host_state(), "scanning": scanning, "devices": list_devices(), "links": streams.keys(), "last_error": last_error}

func _exit_tree() -> void:
	if backend != null:
		_command({"op": "ble_shutdown"})
		if backend_name == "apple_corebluetooth":
			backend.free()
		backend = null
