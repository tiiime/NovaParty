extends RefCounted
# Proof of room access; this does not encrypt or authenticate the game transport.
const MAX_LENGTH := 64

static func key(password: String) -> PackedByteArray:
	return ("novaparty-room-password-v1\n" + password).sha256_buffer() if not password.is_empty() else PackedByteArray()

static func proof(secret: PackedByteArray, nonce: String, session_id: String, identity: String, role: String) -> PackedByteArray:
	var context := JSON.stringify(["novaparty-room-proof-v1", nonce, session_id, identity, role])
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, secret, context.to_utf8_buffer())
