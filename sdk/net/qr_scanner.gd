extends Node
signal scanned(value: String)
signal failed(code: String)
signal canceled
var android
var apple
var active := false
var camera_opened := false
var permission_pending := false
var scan_title := ""
var close_label := ""
func _ready() -> void:
	if OS.has_feature("android") and Engine.has_singleton("JavaClassWrapper") and Engine.has_singleton("AndroidRuntime"):
		var klass = Engine.get_singleton("JavaClassWrapper").wrap("org.novaparty.sdk.JoinQRCode")
		if klass != null:
			android = klass.JoinQRCode(Engine.get_singleton("AndroidRuntime").getActivity())
	elif ClassDB.class_exists("NovaBonjour"):
		apple = ClassDB.instantiate("NovaBonjour")
	if not get_tree().on_request_permissions_result.is_connected(_permission_result):
		get_tree().on_request_permissions_result.connect(_permission_result)
func start(title: String, close_text: String) -> void:
	if active:
		return
	active = true
	camera_opened = false
	scan_title = title
	close_label = close_text
	if android != null:
		if not android.cameraAvailable():
			active = false
			camera_opened = false
			failed.emit("camera_unavailable")
			return
		if not OS.get_granted_permissions().has("android.permission.CAMERA"):
			permission_pending = true
			if not OS.request_permission("android.permission.CAMERA"):
				return
			permission_pending = false
		android.start(title, close_text)
	elif apple != null and OS.has_feature("ios"):
		_process_events(apple.call("exchange", JSON.stringify({"op": "qr_scan", "title": title, "close": close_text})))
	else:
		active = false
		failed.emit("camera_unavailable")
func _permission_result(permission: String, granted: bool) -> void:
	if permission == "android.permission.CAMERA" and permission_pending:
		permission_pending = false
		active = false
		if granted:
			start(scan_title, close_label)
		else:
			failed.emit("camera_permission_denied")
func stop() -> void:
	active = false
	camera_opened = false
	permission_pending = false
	if android != null:
		android.close()
	if apple != null:
		apple.call("exchange", "{\"op\":\"qr_stop\"}")
func _process(_delta: float) -> void:
	if not active or permission_pending:
		return
	if android != null:
		_process_events(str(android.poll()))
	elif apple != null:
		_process_events(apple.call("exchange", "{}"))
func _process_events(json: String) -> void:
	var events = JSON.parse_string(json)
	if not events is Array:
		return
	for event in events:
		if event.get("type") == "qr_opened":
			camera_opened = true
		elif event.get("type") == "qr_result":
			active = false
			camera_opened = false
			scanned.emit(str(event.get("value", "")))
		elif event.get("type") == "qr_error":
			active = false
			camera_opened = false
			failed.emit(str(event.get("code", "camera_unavailable")))
		elif event.get("type") == "qr_canceled":
			active = false
			camera_opened = false
			canceled.emit()
func _exit_tree() -> void:
	stop()
	if apple != null:
		apple.free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and active and not permission_pending:
		stop()
		canceled.emit()
