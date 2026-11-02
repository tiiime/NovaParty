extends Node
# Standalone A→B Mod delivery. No room or game rules need to be instantiated.
const Wire = preload("wire.gd")
const Sharing = preload("mod_sharing.gd")
var wire
var sharing = Sharing.new()
var info := {}
var offer_context := {}
var touched := {}
func _ready() -> void:
	wire = Wire.new()
	add_child(wire)
	wire.opened.connect(func(peer): touched[peer] = Time.get_ticks_msec())
	wire.lost.connect(func(peer): touched.erase(peer))
	wire.message.connect(_message)
func listen(mod_info: Dictionary, source_name: String, port: int, bind_address: String = "*") -> Error:
	info = mod_info
	offer_context = {"game_session_id": Crypto.new().generate_random_bytes(16).hex_encode(), "players": [{"nickname": source_name.left(32)}]}
	return wire.listen(port, bind_address)
func _message(peer: int, value: Dictionary) -> void:
	touched[peer] = Time.get_ticks_msec()
	if not sharing.handle(peer, value, wire, offer_context, info, false):
		wire.drop(peer)
func _process(_delta: float) -> void:
	for peer in touched.keys():
		if Time.get_ticks_msec() - int(touched[peer]) > 10000:
			wire.drop(peer)
