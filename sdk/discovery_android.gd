extends Node
signal event(value: Dictionary)
var bridge
func _ready() -> void:
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"):
		return
	var wrapper = Engine.get_singleton("JavaClassWrapper")
	var klass = wrapper.wrap("org.novaparty.sdk.LanDiscovery")
	if klass != null:
		bridge = klass.LanDiscovery(Engine.get_singleton("AndroidRuntime").getApplicationContext())
func browse() -> void:
	if bridge != null:
		bridge.browse()
	else:
		event.emit({"type": "error", "code": "native_discovery_unavailable"})
func stop_browse() -> void:
	if bridge != null:
		bridge.stopBrowse()
func advertise(port: int, txt: Dictionary) -> void:
	if bridge != null:
		bridge.advertise(port, JSON.stringify(txt))
func stop_advertise() -> void:
	if bridge != null:
		bridge.stopAdvertise()
func _process(_delta: float) -> void:
	if bridge != null:
		var events = JSON.parse_string(str(bridge.poll()))
		if events is Array:
			for value in events:
				if value is Dictionary:
					event.emit(value)
func _exit_tree() -> void:
	if bridge != null:
		bridge.close()
