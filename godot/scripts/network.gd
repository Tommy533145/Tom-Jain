extends Node

signal room_joined(room_code: String, player_id: String)
signal state_received(state: Dictionary)
signal status_changed(message: String)
signal server_error(message: String)

var socket := WebSocketPeer.new()
var player_display_name := "Player"
var player_id := ""
var room_code := ""
var account_key := ""
var pending_action := ""
var pending_room := ""
var connected_once := false
var last_move_sent := 0.0
const MOVE_SEND_INTERVAL := 1.0 / 15.0

func _ready() -> void:
    var config := ConfigFile.new()
    if config.load("user://profile.cfg") == OK:
        account_key = str(config.get_value("profile", "account_key", ""))
    if account_key.length() < 20:
        account_key = Crypto.new().generate_random_bytes(24).hex_encode()
        config.set_value("profile", "account_key", account_key)
        config.save("user://profile.cfg")

func _process(_delta: float) -> void:
    socket.poll()
    var ready := socket.get_ready_state()
    if ready == WebSocketPeer.STATE_OPEN:
        if not connected_once:
            connected_once = true
            _send({
                "type": pending_action,
                "room": pending_room,
                "name": player_display_name,
                "account": account_key,
            })
        while socket.get_available_packet_count() > 0:
            var packet := socket.get_packet().get_string_from_utf8()
            var parsed = JSON.parse_string(packet)
            if typeof(parsed) != TYPE_DICTIONARY:
                continue
            _handle_message(parsed)
    elif ready == WebSocketPeer.STATE_CLOSED and connected_once:
        connected_once = false
        status_changed.emit("Disconnected from the city.")

func connect_to_city(url: String, action: String, room: String, display_name: String) -> void:
    if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
        socket.close()
        socket = WebSocketPeer.new()
    player_display_name = display_name.strip_edges().substr(0, 20)
    if player_display_name.is_empty():
        player_display_name = "Player"
    pending_action = action
    pending_room = room.strip_edges().to_upper()
    room_code = ""
    player_id = ""
    connected_once = false
    var error := socket.connect_to_url(url.strip_edges())
    if error != OK:
        status_changed.emit("Could not connect: " + error_string(error))
        return
    status_changed.emit("Connecting to your city…")

func disconnect_from_city() -> void:
    if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        socket.close()
    connected_once = false

func send_move(city_x: float, city_z: float, yaw: float) -> void:
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    var now := Time.get_ticks_msec() / 1000.0
    if now - last_move_sent < MOVE_SEND_INTERVAL:
        return
    last_move_sent = now
    _send({"type": "move", "x": city_x, "y": city_z, "yaw": yaw})

func send_action(action: String, value: String = "") -> void:
    var payload := {"type": action}
    if not value.is_empty():
        if action == "work":
            payload["job"] = value
        elif action in ["buy", "enter"]:
            payload["home"] = value
        elif action == "decorate":
            payload["item"] = value
    _send(payload)

func _send(payload: Dictionary) -> void:
    if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        socket.send_text(JSON.stringify(payload))

func _handle_message(message: Dictionary) -> void:
    match str(message.get("type", "")):
        "welcome":
            room_code = str(message.get("room", ""))
            player_id = str(message.get("player", ""))
            room_joined.emit(room_code, player_id)
            status_changed.emit("Connected to city " + room_code)
        "state":
            state_received.emit(message)
            if message.has("notice") and typeof(message["notice"]) == TYPE_DICTIONARY:
                status_changed.emit(str(message["notice"].get("text", "")))
        "error":
            server_error.emit(str(message.get("message", "The server rejected that action.")))
