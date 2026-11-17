extends Node

signal player_spawned(peer_id: int, player_name: String, spawn_position: Vector3)
signal player_removed(peer_id: int)
signal player_name_changed(peer_id: int, player_name: String)
signal player_state_received(peer_id: int, pos: Vector3, yaw: float)
signal status_changed(message: String)

const DEFAULT_PORT: int = 9080
const MAX_CLIENTS: int = 64
const MAX_STATE_UPDATES_PER_SECOND: int = 30
const MAX_PLAYER_SPEED: float = 9.0
const MOVEMENT_GRACE_DISTANCE: float = 1.0
var listen_port: int = DEFAULT_PORT
var player_display_name: String = "Player"
var known_names: Dictionary = {}
var known_positions: Dictionary = {}
var last_state_packet_msec: Dictionary = {}
var last_valid_state_msec: Dictionary = {}

func _ready() -> void:
    var port_override := OS.get_environment("PORT").strip_edges()
    if not port_override.is_empty() and port_override.is_valid_int():
        listen_port = clampi(int(port_override), 1, 65535)
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

func start_server() -> void:
    var peer := WebSocketMultiplayerPeer.new()
    var error := peer.create_server(listen_port, "*")
    if error != OK:
        status_changed.emit("Server error: " + error_string(error))
        return
    multiplayer.multiplayer_peer = peer
    status_changed.emit("Server listening on port %d" % listen_port)
    known_names[1] = "City Host"
    known_positions[1] = Vector3(0, 1, 0)
    player_spawned.emit(1, "City Host", Vector3(0, 1, 0))

func connect_to_server(url: String) -> void:
    var peer := WebSocketMultiplayerPeer.new()
    var error := peer.create_client(url)
    if error != OK:
        status_changed.emit("Could not connect: " + error_string(error))
        return
    multiplayer.multiplayer_peer = peer
    status_changed.emit("Connecting...")

func _on_peer_connected(peer_id: int) -> void:
    if not multiplayer.is_server():
        return
    if known_names.size() - 1 >= MAX_CLIENTS:
        multiplayer.multiplayer_peer.disconnect_peer(peer_id, true)
        return
    var spawn := Vector3(float((peer_id % 5) * 2), 1, float((peer_id % 7) * 2))
    known_names[peer_id] = "Player %d" % peer_id
    known_positions[peer_id] = spawn
    var now_msec := Time.get_ticks_msec()
    last_state_packet_msec[peer_id] = now_msec
    last_valid_state_msec[peer_id] = now_msec
    spawn_player.rpc(peer_id, known_names[peer_id], spawn)
    for existing_id in known_names.keys():
        if int(existing_id) != peer_id:
            var existing_position: Vector3 = known_positions.get(existing_id, Vector3(0, 1, 0))
            spawn_player.rpc_id(peer_id, int(existing_id), str(known_names[existing_id]), existing_position)

func _on_peer_disconnected(peer_id: int) -> void:
    if multiplayer.is_server():
        known_names.erase(peer_id)
        known_positions.erase(peer_id)
        last_state_packet_msec.erase(peer_id)
        last_valid_state_msec.erase(peer_id)
        remove_player.rpc(peer_id)

func _on_connected_to_server() -> void:
    status_changed.emit("Connected to Tom&Jain")
    register_name.rpc_id(1, player_display_name)

func _on_connection_failed() -> void:
    multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
    status_changed.emit("Connection failed. Check the server address.")

func _on_server_disconnected() -> void:
    multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
    status_changed.emit("Server disconnected.")

@rpc("any_peer", "reliable")
func register_name(value: String) -> void:
    if not multiplayer.is_server():
        return
    var sender := multiplayer.get_remote_sender_id()
    if sender <= 1 or not known_names.has(sender):
        return
    var clean_name := value.strip_edges().substr(0, 20)
    if clean_name.is_empty():
        clean_name = "Player %d" % sender
    known_names[sender] = clean_name
    set_player_name.rpc(sender, clean_name)

@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int, player_name: String, spawn_position: Vector3) -> void:
    player_spawned.emit(peer_id, player_name, spawn_position)

@rpc("authority", "call_local", "reliable")
func set_player_name(peer_id: int, player_name: String) -> void:
    player_name_changed.emit(peer_id, player_name)

@rpc("authority", "call_local", "reliable")
func remove_player(peer_id: int) -> void:
    player_removed.emit(peer_id)

func send_player_state(pos: Vector3, yaw: float) -> void:
    if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
        return
    if multiplayer.is_server():
        _accept_player_state(1, pos, yaw)
    else:
        submit_state.rpc_id(1, pos, yaw)

@rpc("any_peer", "unreliable")
func submit_state(pos: Vector3, yaw: float) -> void:
    if not multiplayer.is_server():
        return
    var sender := multiplayer.get_remote_sender_id()
    if sender <= 1 or not known_names.has(sender):
        return
    var now_msec := Time.get_ticks_msec()
    var last_packet_msec: int = last_state_packet_msec.get(sender, 0)
    var minimum_interval_msec := int(1000.0 / MAX_STATE_UPDATES_PER_SECOND)
    if now_msec - last_packet_msec < minimum_interval_msec:
        return
    last_state_packet_msec[sender] = now_msec
    _accept_player_state(sender, pos, yaw)

func _accept_player_state(peer_id: int, pos: Vector3, yaw: float) -> void:
    if not pos.is_finite() or not is_finite(yaw):
        return
    var now_msec := Time.get_ticks_msec()
    if peer_id != 1:
        var previous_position: Vector3 = known_positions.get(peer_id, pos)
        var previous_msec: int = last_valid_state_msec.get(peer_id, now_msec)
        var elapsed_seconds := clampf(float(now_msec - previous_msec) / 1000.0, 0.0, 1.0)
        var allowed_distance := MAX_PLAYER_SPEED * elapsed_seconds + MOVEMENT_GRACE_DISTANCE
        if pos.distance_to(previous_position) > allowed_distance:
            last_valid_state_msec[peer_id] = now_msec
            return
        last_valid_state_msec[peer_id] = now_msec
    var safe_pos := Vector3(clampf(pos.x, -90.0, 90.0), clampf(pos.y, -5.0, 35.0), clampf(pos.z, -90.0, 90.0))
    var safe_yaw := wrapf(yaw, -PI, PI)
    known_positions[peer_id] = safe_pos
    relay_state.rpc(peer_id, safe_pos, safe_yaw)

@rpc("authority", "call_local", "unreliable")
func relay_state(peer_id: int, pos: Vector3, yaw: float) -> void:
    player_state_received.emit(peer_id, pos, yaw)
