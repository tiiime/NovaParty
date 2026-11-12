extends Node
# Transport only: bounded newline-delimited UTF-8 JSON over TCP or a Bluetooth LE byte stream.
# Bluetooth peers use the address form "ble:<device key>"; see sdk/bluetooth.gd.
const Bluetooth = preload("res://sdk/net/bluetooth.gd")
const BLE_PREFIX = "ble:"
var bluetooth
signal message(peer: int, data: Dictionary)
signal lost(peer: int)
signal opened(peer: int)
const MAX_FRAME = 65536
const MAX_QUEUE = 262144
var server := TCPServer.new()
var peers := {}
var next_peer := 1

func listen(port: int, bind_address: String = "*") -> Error:
	return server.listen(port, bind_address)

# Accept Bluetooth guests next to TCP ones. Returns false when the platform has no radio bridge.
func listen_bluetooth(session_id: String) -> bool:
	if bluetooth == null:
		bluetooth = Bluetooth.shared(get_tree())
	if not bluetooth.incoming.is_connected(_accept):
		bluetooth.incoming.connect(_accept)
	return bluetooth.host(session_id)

func _accept(stream) -> void:
	if peers.size() >= 16:
		stream.disconnect_from_host()
		return
	peers[next_peer] = {"stream": stream, "input": PackedByteArray(), "output": PackedByteArray(), "ready": false, "since": Time.get_ticks_msec()}
	next_peer += 1

func connect_to(address: String, port: int) -> Error:
	if address.begins_with(BLE_PREFIX):
		if bluetooth == null:
			bluetooth = Bluetooth.shared(get_tree())
		var link = bluetooth.connect_peer(address.substr(BLE_PREFIX.length()))
		if link == null:
			return ERR_UNAVAILABLE
		peers[0] = {"stream": link, "input": PackedByteArray(), "output": PackedByteArray(), "ready": false, "since": Time.get_ticks_msec()}
		return OK
	var stream := StreamPeerTCP.new()
	var result := stream.connect_to_host(address, port)
	if result == OK:
		peers[0] = {"stream": stream, "input": PackedByteArray(), "output": PackedByteArray(), "ready": false, "since": Time.get_ticks_msec()}
	return result

func send(peer: int, data: Dictionary) -> void:
	if not peers.has(peer):
		return
	var bytes := (JSON.stringify(data) + "\n").to_utf8_buffer()
	if bytes.size() > MAX_FRAME or peers[peer].output.size() + bytes.size() > MAX_QUEUE:
		drop(peer)
		return
	peers[peer].output.append_array(bytes)

func drop(peer: int) -> void:
	if peers.has(peer):
		peers[peer].stream.disconnect_from_host()
		peers.erase(peer)
		lost.emit(peer)

func _process(_delta: float) -> void:
	while server.is_connection_available():
		var stream := server.take_connection()
		if peers.size() >= 16:
			stream.disconnect_from_host()
			continue
		peers[next_peer] = {"stream": stream, "input": PackedByteArray(), "output": PackedByteArray(), "ready": false, "since": Time.get_ticks_msec()}
		next_peer += 1
	for id in peers.keys():
		if not peers.has(id):
			continue
		var p: Dictionary = peers[id]
		p.stream.poll()
		var status: int = p.stream.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			drop(id)
			continue
		if status != StreamPeerTCP.STATUS_CONNECTED:
			if Time.get_ticks_msec() - int(p.since) > (Bluetooth.CONNECT_TIMEOUT_MS if p.stream is Bluetooth.Stream else 10000):
				drop(id)
			continue
		if not p.ready:
			p.ready = true
			p.stream.set_no_delay(true)
			opened.emit(id)
		if not peers.has(id):
			continue
		if not p.output.is_empty():
			var sent: Array = p.stream.put_partial_data(p.output)
			if sent[0] != OK:
				drop(id)
				continue
			p.output = p.output.slice(sent[1])
		var count: int = p.stream.get_available_bytes()
		if count > MAX_QUEUE:
			drop(id)
			continue
		if count > 0:
			var read: Array = p.stream.get_data(count)
			if read[0] != OK:
				drop(id)
				continue
			p.input.append_array(read[1])
		var frames := 0
		while peers.has(id) and frames < 64:
			var end: int = p.input.find(10)
			if end == -1:
				break
			if end > MAX_FRAME:
				drop(id)
				break
			var parsed = JSON.parse_string(p.input.slice(0, end).get_string_from_utf8())
			p.input = p.input.slice(end + 1)
			if not parsed is Dictionary:
				drop(id)
				break
			message.emit(id, parsed)
			frames += 1
		if peers.has(id) and p.input.size() > MAX_FRAME:
			drop(id)

func _exit_tree() -> void:
	server.stop()
	if is_instance_valid(bluetooth) and bluetooth.incoming.is_connected(_accept):
		bluetooth.incoming.disconnect(_accept)
		bluetooth.stop_host()
	for p in peers.values():
		p.stream.disconnect_from_host()
