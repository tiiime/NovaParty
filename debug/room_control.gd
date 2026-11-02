extends RefCounted
var app: Object
var receipts := {}
var order := []

# Lifecycle IDs are separate from move IDs. Generation guards remain after cache eviction.
func handle(method: String, params: Dictionary, context: Dictionary) -> Dictionary:
	var id = params.get("request_id")
	if not id is String or id.is_empty() or id.length() > 128:
		return {"error": "invalid_request_id"}
	var payload := JSON.stringify({"method": method, "params": params}, "", true)
	if receipts.has(id):
		return receipts[id].result.duplicate(true) if receipts[id].payload == payload else {"error": "request_id_reused"}
	var generation = params.get("room_generation")
	var result: Dictionary
	if params.get("app_instance_id") != context.app_instance_id or not (generation is int or generation is float) or generation != int(generation) or generation != context.room_generation:
		result = {"error": "stale_room_context"}
	elif method in ["room.leave", "room.reconnect"] and (context.local_session_id.is_empty() or params.get("local_session_id") != context.local_session_id):
		result = {"error": "stale_room_context"}
	elif not app.has_method("debug_room_command"):
		result = {"error": "unsupported_app"}
	else:
		result = app.debug_room_command(method, params)
	receipts[id] = {"payload": payload, "result": result.duplicate(true)}
	order.append(id)
	if order.size() > 128:
		receipts.erase(order.pop_front())
	return result
