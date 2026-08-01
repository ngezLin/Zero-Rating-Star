extends Node

signal player_list_updated
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal game_started
signal public_ip_fetched(ip: String)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

var local_player_name: String = "Player"
var local_player_ready: bool = false
var host_ip_address: String = "127.0.0.1"
var public_ip_address: String = ""
var upnp_active: bool = false

# Dictionary of players: { peer_id: { "id": int, "name": String, "ready": bool } }
var players: Dictionary = {}

var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var http_request: HTTPRequest

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_ip_request_completed)
	fetch_public_ip()

func fetch_public_ip() -> void:
	if http_request:
		http_request.request("https://api.ipify.org")

func _on_ip_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var fetched_ip = body.get_string_from_utf8().strip_edges()
		if fetched_ip != "":
			public_ip_address = fetched_ip
			if host_ip_address == "127.0.0.1" or host_ip_address == "":
				host_ip_address = public_ip_address
			public_ip_fetched.emit(public_ip_address)

# --- 6-Digit Lobby Code Encoder & Decoder ---

func get_lobby_code() -> String:
	var ip = public_ip_address if public_ip_address != "" else host_ip_address
	return encode_ip_to_lobby_code(ip)

func encode_ip_to_lobby_code(ip_str: String) -> String:
	if ip_str == "" or ip_str == "127.0.0.1":
		return "LOCAL6"
	var parts = ip_str.split(".")
	if parts.size() != 4:
		return ip_str
	
	var octet1 = parts[0].to_int() & 0xFF
	var octet2 = parts[1].to_int() & 0xFF
	var octet3 = parts[2].to_int() & 0xFF
	var octet4 = parts[3].to_int() & 0xFF
	
	var packed: int = (octet1 << 24) | (octet2 << 16) | (octet3 << 8) | octet4
	var obfuscated: int = (packed ^ 0x3E7A91C5) & 0xFFFFFFFF
	
	const CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var code = ""
	var val = obfuscated
	for i in range(6):
		var rem = val % 36
		code = CHARS[rem] + code
		val = val / 36
	return code

func decode_lobby_code_to_ip(code_str: String) -> String:
	var clean = code_str.strip_edges().to_upper()
	if clean == "LOCAL6" or clean == "LOCAL" or clean == "127.0.0.1":
		return "127.0.0.1"
		
	# Strip optional "ZSR-" prefix if user typed it
	if clean.begins_with("ZSR-"):
		clean = clean.substr(4)
		
	const CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	if clean.length() == 6:
		var val: int = 0
		var valid = true
		for i in range(6):
			var ch = clean[i]
			var idx = CHARS.find(ch)
			if idx == -1:
				valid = false
				break
			val = val * 36 + idx
			
		if valid:
			var original = (val ^ 0x3E7A91C5) & 0xFFFFFFFF
			var octet1 = (original >> 24) & 0xFF
			var octet2 = (original >> 16) & 0xFF
			var octet3 = (original >> 8) & 0xFF
			var octet4 = original & 0xFF
			return "%d.%d.%d.%d" % [octet1, octet2, octet3, octet4]
			
	# If already a standard IP address or hostname, return as is
	return code_str

func host_game(port: int = DEFAULT_PORT, p_name: String = "Host") -> Error:
	local_player_name = p_name if p_name.strip_edges() != "" else "Host"
	enet_peer = ENetMultiplayerPeer.new()
	var err = enet_peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to create ENet server: %d" % err)
		return err

	multiplayer.multiplayer_peer = enet_peer
	players.clear()
	_register_local_player(1)
	
	# Attempt automatic UPnP port forwarding
	_setup_upnp(port)
	
	player_list_updated.emit()
	return OK

func _setup_upnp(port: int) -> void:
	var thread = Thread.new()
	thread.start(_upnp_thread_func.bind(port))

func _upnp_thread_func(port: int) -> void:
	var upnp = UPNP.new()
	var err = upnp.discover()
	if err == UPNP.UPNP_RESULT_SUCCESS:
		if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
			var map_udp = upnp.add_port_mapping(port, port, "ZeroStarRating_UDP", "UDP")
			var map_tcp = upnp.add_port_mapping(port, port, "ZeroStarRating_TCP", "TCP")
			if map_udp == UPNP.UPNP_RESULT_SUCCESS:
				upnp_active = true
				var ext_ip = upnp.query_external_address()
				if ext_ip != "":
					public_ip_address = ext_ip
					host_ip_address = ext_ip

func join_game(ip_or_code: String = "127.0.0.1", port: int = DEFAULT_PORT, p_name: String = "Player") -> Error:
	local_player_name = p_name if p_name.strip_edges() != "" else "Player"
	var raw_input = ip_or_code.strip_edges()
	host_ip_address = decode_lobby_code_to_ip(raw_input)
	
	enet_peer = ENetMultiplayerPeer.new()
	var err = enet_peer.create_client(host_ip_address, port)
	if err != OK:
		push_error("Failed to create ENet client: %d" % err)
		return err

	multiplayer.multiplayer_peer = enet_peer
	players.clear()
	return OK

func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	player_list_updated.emit()

func _register_local_player(id: int) -> void:
	players[id] = {
		"id": id,
		"name": local_player_name,
		"ready": (id == 1)
	}

func toggle_ready() -> void:
	local_player_ready = !local_player_ready
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id]["ready"] = local_player_ready
	
	if multiplayer.is_server():
		_broadcast_players()
	else:
		rpc_id(1, "request_ready_change", my_id, local_player_ready)

func start_game() -> void:
	if multiplayer.is_server():
		rpc("sync_start_game")

# --- RPCs & Callbacks ---

func _on_peer_connected(_id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		if multiplayer.is_server():
			_broadcast_players()
		else:
			player_list_updated.emit()

func _on_connected_to_server() -> void:
	var my_id = multiplayer.get_unique_id()
	_register_local_player(my_id)
	rpc_id(1, "register_player_server", my_id, local_player_name)
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()

@rpc("any_peer", "call_remote", "reliable")
func register_player_server(id: int, p_name: String) -> void:
	if multiplayer.is_server():
		players[id] = {
			"id": id,
			"name": p_name,
			"ready": false
		}
		_broadcast_players()

@rpc("any_peer", "call_remote", "reliable")
func request_ready_change(id: int, is_ready: bool) -> void:
	if multiplayer.is_server() and players.has(id):
		players[id]["ready"] = is_ready
		_broadcast_players()

func _broadcast_players() -> void:
	if multiplayer.is_server():
		rpc("sync_player_list", players)
		player_list_updated.emit()

@rpc("authority", "call_local", "reliable")
func sync_player_list(updated_players: Dictionary) -> void:
	players = updated_players
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		local_player_ready = players[my_id]["ready"]
	player_list_updated.emit()

@rpc("authority", "call_local", "reliable")
func sync_start_game() -> void:
	game_started.emit()
