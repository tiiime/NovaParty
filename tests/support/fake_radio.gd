extends RefCounted
# In-process stand-in for the native Bluetooth bridge. Radios created on the same `air`
# dictionary see each other. It follows docs/bluetooth.md: 20-byte chunks, one acknowledged
# chunk per poll, base64 payloads, "p:"/"c:" link names.
const MTU_PAYLOAD = 20
var air: Dictionary
var id := ""
var events := []
var host_name := ""
var advertising := false
var scanning := false
var links := {} # link -> {"radio": peer radio, "remote": peer link, "queue": PackedByteArray}
var powered := true

func _init(shared_air: Dictionary, radio_id: String) -> void:
	air = shared_air
	id = radio_id
	air[id] = self

func exchange(text: String) -> String:
	var command = JSON.parse_string(text)
	if command is Dictionary:
		_handle(command)
	_pump()
	var output := JSON.stringify(events)
	events = []
	return output

func _handle(command: Dictionary) -> void:
	match command.get("op", ""):
		"ble_state": events.append({"type": "ble_state", "state": "on" if powered else "off"})
		"ble_host":
			host_name = str(command.name)
			advertising = true
		"ble_advertise": advertising = bool(command.enabled)
		"ble_host_stop":
			advertising = false
			host_name = ""
			for link in links.keys():
				if link.begins_with("p:"): _close(link, true)
		"ble_scan": scanning = true
		"ble_scan_stop": scanning = false
		"ble_connect":
			var target = air.get(str(command.key))
			var link := "c:" + str(command.key)
			if target == null or target.host_name.is_empty() or not target.powered:
				events.append({"type": "ble_closed", "link": link, "code": "connect_failed"})
				return
			links[link] = {"radio": target, "remote": "p:" + id, "queue": PackedByteArray()}
			target.links["p:" + id] = {"radio": self, "remote": link, "queue": PackedByteArray()}
			events.append({"type": "ble_open", "link": link})
			target.events.append({"type": "ble_open", "link": "p:" + id})
		"ble_send":
			if links.has(command.link):
				links[command.link].queue.append_array(Marshalls.base64_to_raw(command.data))
		"ble_close": _close(str(command.link), true)
		"ble_shutdown":
			for link in links.keys(): _close(link, true)

func _close(link: String, notify_remote: bool) -> void:
	if not links.has(link):
		return
	var entry: Dictionary = links[link]
	links.erase(link)
	if notify_remote and entry.radio.links.has(entry.remote):
		entry.radio.links.erase(entry.remote)
		entry.radio.events.append({"type": "ble_closed", "link": entry.remote, "code": "remote_closed"})

# Power loss: both ends observe a closed link, as with a real supervision timeout.
func drop_all() -> void:
	for link in links.keys():
		events.append({"type": "ble_closed", "link": link, "code": "link_lost"})
		_close(link, true)

func _pump() -> void:
	if scanning:
		for other in air.values():
			if other != self and other.advertising and other.powered:
				events.append({"type": "ble_found", "key": other.id, "name": other.host_name, "rssi": -50})
	for link in links.keys():
		var entry: Dictionary = links[link]
		if entry.queue.is_empty():
			continue
		var chunk: PackedByteArray = entry.queue.slice(0, MTU_PAYLOAD * 8)
		entry.queue = entry.queue.slice(chunk.size())
		var offset := 0
		while offset < chunk.size():
			entry.radio.events.append({"type": "ble_data", "link": entry.remote, "data": Marshalls.raw_to_base64(chunk.slice(offset, offset + MTU_PAYLOAD))})
			offset += MTU_PAYLOAD
		events.append({"type": "ble_sent", "link": link, "bytes": chunk.size()})
