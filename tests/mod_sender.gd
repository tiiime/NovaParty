extends SceneTree
const Loader = preload("res://sdk/mod_loader.gd")
const Sender = preload("res://sdk/mod_sender.gd")
const Receiver = preload("res://sdk/peer_mods.gd")
var completed := false
var failed := false
var sender
var receiver
var installed := ""
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var loader := Loader.new()
	var info := loader.inspect("res://mods/hidden_cards")
	sender = Sender.new()
	receiver = Receiver.new()
	root.add_child(sender)
	root.add_child(receiver)
	var listen_error = sender.listen(info, "SDK Sender", 29649, "127.0.0.1")
	if listen_error != OK: printerr("listen failed"); quit(1); return
	receiver.catalog_received.connect(func(metadata):
		assert(metadata.kind == "mod")
		assert(receiver.received == 0)
		receiver.confirm_download()
	)
	receiver.failed.connect(func(code): failed = true; printerr(code))
	receiver.completed.connect(func(path, metadata):
		var result := loader.install_peer_zip(path, metadata)
		assert(not result.is_empty() and result.rules_fingerprint == info.rules_fingerprint)
		installed = "user://mods/" + str(metadata.sha256) + ".zip"
		completed = true
	)
	var inspect_error = receiver.inspect_remote("127.0.0.1", 29649)
	if inspect_error != OK: printerr("inspect failed"); quit(1); return
	for i in range(500):
		if completed or failed: break
		await create_timer(0.01).timeout
	if not completed or failed: printerr("transfer failed"); quit(1); return
	sender.queue_free()
	receiver.queue_free()
	await process_frame
	if not installed.is_empty(): DirAccess.remove_absolute(installed)
	print("MOD_SENDER_OK standalone SDK transfer, explicit consent, verified installation without a game session")
	quit()
