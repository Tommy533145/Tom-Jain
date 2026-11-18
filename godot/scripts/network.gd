extends Node

signal player_spawned(player_id: String, player_name: String, spawn_position: Vector3)
signal player_removed(player_id: String)
signal player_name_changed(player_id: String, player_name: String)
signal player_state_received(player_id: String, pos: Vector3, yaw: float)
signal status_changed(message: String)
signal room_state_received(state: Dictionary)

const CITY_WIDTH := 1600.0
const CITY_HEIGHT := 1100.0

var socket: WebSocketPeer
var request: Dictionary = {}
var request_sent := false
var player_display_name := "Player"
var player_id := ""
var room_code := ""
var known_players: Dictionary = {}
var room_state: Dictionary = {}
var account_key := ""
var local_position := Vector3.ZERO
var local_inside := ""

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("user://two_keys.cfg") == OK:
		account_key = str(config.get_value("account", "key", ""))
	if account_key.length() < 20:
		account_key = Crypto.new().generate_random_bytes(24).hex_encode()
	config.set_value("account", "key", account_key)
	config.save("user://two_keys.cfg")

func _process(_delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not request_sent:
		var error := socket.send_text(JSON.stringify(request))
		if error != OK:
			status_changed.emit("Could not start the city connection.")
			return
		request_sent = true
	elif state == WebSocketPeer.STATE_CLOSED:
		if not player_id.is_empty():
			status_changed.emit("Connection lost. Reload the game to reconnect.")
			_clear_players()
		player_id = ""
		return
	while socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0:
		var packet := socket.get_packet().get_string_from_utf8()
		var message: Variant = JSON.parse_string(packet)
		if message is Dictionary:
			_handle_message(message)

func default_server_url() -> String:
	if OS.has_feature("web"):
		var location: String = JavaScriptBridge.eval("window.location.protocol + '//' + window.location.host")
		if location.begins_with("https://"):
			return "wss://" + location.trim_prefix("https://") + "/ws"
		return "ws://" + location.trim_prefix("http://") + "/ws"
	return "ws://127.0.0.1:8001/ws"

func connect_to_server(url: String, player_name: String, code: String = "") -> void:
	var clean_url := url.strip_edges()
	if clean_url.is_empty():
		clean_url = default_server_url()
	player_display_name = player_name.strip_edges().substr(0, 20)
	if player_display_name.is_empty():
		player_display_name = "Player"
	room_code = code.strip_edges().to_upper()
	request = {
		"type": "join" if not room_code.is_empty() else "create",
		"name": player_display_name,
		"account": account_key,
	}
	if not room_code.is_empty():
		request["room"] = room_code
	request_sent = false
	player_id = ""
	_clear_players()
	socket = WebSocketPeer.new()
	var error := socket.connect_to_url(clean_url)
	if error != OK:
		status_changed.emit("Could not connect: " + error_string(error))
		socket = null
		return
	status_changed.emit("Connecting to the city...")

func send_player_state(pos: Vector3, yaw: float) -> void:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN or player_id.is_empty():
		return
	local_position = pos
	var message := {
		"type": "move",
		"x": (pos.x + 90.0) / 180.0 * CITY_WIDTH,
		"y": (pos.z + 90.0) / 180.0 * CITY_HEIGHT,
		"yaw": yaw,
	}
	socket.send_text(JSON.stringify(message))

func interact() -> void:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN or player_id.is_empty():
		return
	if not local_inside.is_empty():
		_send_message({"type": "exit"})
		return
	var nearest_distance := INF
	var nearest_kind := ""
	var nearest_id := ""
	for job in room_state.get("jobs", []):
		var point := _server_position_to_world(float(job.get("x", 0)), float(job.get("y", 0)))
		var distance := Vector2(local_position.x, local_position.z).distance_to(Vector2(point.x, point.z))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_kind = "work"
			nearest_id = str(job.get("id", ""))
	for home in room_state.get("properties", []):
		var point := _server_position_to_world(float(home.get("x", 0)), float(home.get("y", 0)))
		var distance := Vector2(local_position.x, local_position.z).distance_to(Vector2(point.x, point.z))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_kind = "home"
			nearest_id = str(home.get("id", ""))
	if nearest_kind == "work" and nearest_distance <= 7.0:
		_send_message({"type": "work", "job": nearest_id})
	elif nearest_kind == "home" and nearest_distance <= 9.0:
		if room_state.get("homes", {}).has(nearest_id):
			_send_message({"type": "enter", "home": nearest_id})
		else:
			_send_message({"type": "buy", "home": nearest_id})

func _send_message(message: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))

func _handle_message(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"welcome":
			player_id = str(message.get("player", ""))
			room_code = str(message.get("room", ""))
			status_changed.emit("Connected | Room " + room_code)
		"state":
			room_state = message
			var present: Dictionary = {}
			for player in message.get("players", []):
				if not player is Dictionary:
					continue
				var remote_id := str(player.get("id", ""))
				if remote_id.is_empty():
					continue
				present[remote_id] = true
				if remote_id == player_id:
					local_inside = str(player.get("inside", ""))
				var name := str(player.get("name", "Player"))
				var world_position := _server_position_to_world(float(player.get("x", 800.0)), float(player.get("y", 550.0)))
				var yaw := float(player.get("yaw", 0.0))
				if not known_players.has(remote_id):
					known_players[remote_id] = name
					player_spawned.emit(remote_id, name, world_position)
				elif str(known_players[remote_id]) != name:
					known_players[remote_id] = name
					player_name_changed.emit(remote_id, name)
				player_state_received.emit(remote_id, world_position, yaw)
			for existing_id in known_players.keys():
				if not present.has(existing_id):
					known_players.erase(existing_id)
					player_removed.emit(str(existing_id))
			room_state_received.emit(room_state)
		"error":
			status_changed.emit(str(message.get("message", "The server rejected the request.")))

func _server_position_to_world(x: float, y: float) -> Vector3:
	return Vector3(x / CITY_WIDTH * 180.0 - 90.0, 1.0, y / CITY_HEIGHT * 180.0 - 90.0)

func _clear_players() -> void:
	for existing_id in known_players.keys():
		player_removed.emit(str(existing_id))
	known_players.clear()

