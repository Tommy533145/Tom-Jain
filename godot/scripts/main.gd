extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var players_root: Node3D
var menu_layer: CanvasLayer
var status_label: Label
var name_input: LineEdit
var address_input: LineEdit
var room_input: LineEdit
var join_button: Button
var hud_layer: CanvasLayer
var room_label: Label

func _ready() -> void:
    _create_world()
    _create_interaction_markers()
    _create_menu()
    Network.player_spawned.connect(_spawn_player)
    Network.player_removed.connect(_remove_player)
    Network.player_name_changed.connect(_rename_player)
    Network.player_state_received.connect(_apply_player_state)
    Network.status_changed.connect(_update_status)
    Network.room_state_received.connect(_update_room_state)

func _create_world() -> void:
    var world_env := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_SKY
    environment.sky = Sky.new()
    environment.sky.sky_material = ProceduralSkyMaterial.new()
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.68, 0.72, 0.78)
    environment.ambient_light_energy = 0.7
    world_env.environment = environment
    add_child(world_env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -32, 0)
    sun.shadow_enabled = true
    add_child(sun)

    _make_box("Ground", Vector3(0, -0.25, 0), Vector3(180, 0.5, 180), Color(0.19, 0.28, 0.22))
    _make_box("MainRoad", Vector3(0, 0.02, 0), Vector3(18, 0.06, 180), Color(0.09, 0.10, 0.12))
    _make_box("CrossRoad", Vector3(0, 0.03, 0), Vector3(180, 0.06, 14), Color(0.09, 0.10, 0.12))
    for x in [-8.0, 8.0]:
        _make_box("Sidewalk", Vector3(x, 0.12, 0), Vector3(2, 0.22, 180), Color(0.42, 0.43, 0.42))
    for z in [-7.0, 7.0]:
        _make_box("Sidewalk", Vector3(0, 0.12, z), Vector3(180, 0.22, 2), Color(0.42, 0.43, 0.42))

    var rng := RandomNumberGenerator.new()
    rng.seed = 7219
    var palette: Array[Color] = [Color(0.62,0.66,0.70), Color(0.76,0.69,0.57), Color(0.42,0.52,0.60), Color(0.72,0.73,0.68)]
    for ix in range(-3, 4):
        for iz in range(-3, 4):
            if abs(ix) <= 1 or abs(iz) <= 1:
                continue
            var height := rng.randf_range(7.0, 20.0)
            var width := rng.randf_range(9.0, 13.0)
            var depth := rng.randf_range(9.0, 13.0)
            var center := Vector3(ix * 23.0, height * 0.5, iz * 23.0)
            _make_box("Building", center, Vector3(width, height, depth), palette[rng.randi_range(0, palette.size() - 1)])
            _make_box("Roof", center + Vector3(0, height * 0.5 + 0.15, 0), Vector3(width + 0.3, 0.3, depth + 0.3), Color(0.18,0.20,0.22))
    _make_box("Plaza", Vector3(0, 0.10, 22), Vector3(30, 0.2, 18), Color(0.55,0.57,0.53))
    _make_box("Fountain", Vector3(0, 0.65, 22), Vector3(4, 1.1, 4), Color(0.25,0.48,0.60))

func _make_box(label: String, pos: Vector3, size: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.name = label
    body.position = pos
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.82
    mesh.material_override = material
    body.add_child(mesh)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    add_child(body)

func _create_interaction_markers() -> void:
    var jobs := [
        ["Cafe shift", 250.0, 305.0, Color(0.28, 0.9, 0.5)],
        ["Courier desk", 1320.0, 305.0, Color(0.28, 0.9, 0.5)],
        ["Community garden", 280.0, 670.0, Color(0.28, 0.9, 0.5)],
        ["Street music", 1300.0, 670.0, Color(0.28, 0.9, 0.5)],
    ]
    for job in jobs:
        _make_marker(str(job[0]), _city_to_world(float(job[1]), float(job[2])), job[3])
    var homes := [
        ["Canal Loft  |  80 coins", 715.0, 245.0],
        ["Garden Cottage  |  120 coins", 1110.0, 245.0],
        ["Brick Townhouse  |  160 coins", 715.0, 850.0],
        ["Skyline Flat  |  220 coins", 1110.0, 850.0],
    ]
    for home in homes:
        _make_marker(str(home[0]), _city_to_world(float(home[1]), float(home[2])), Color(0.98, 0.72, 0.22))

func _city_to_world(x: float, y: float) -> Vector3:
    return Vector3(x / 1600.0 * 180.0 - 90.0, 1.4, y / 1100.0 * 180.0 - 90.0)

func _make_marker(label: String, pos: Vector3, color: Color) -> void:
    var beacon := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 1.0
    sphere.height = 2.0
    beacon.mesh = sphere
    beacon.position = pos
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color * 0.65
    beacon.material_override = material
    add_child(beacon)
    var sign := Label3D.new()
    sign.text = label + "  |  E"
    sign.position = pos + Vector3(0, 2.0, 0)
    sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sign.font_size = 36
    sign.modulate = color
    add_child(sign)

func _create_menu() -> void:
    menu_layer = CanvasLayer.new()
    add_child(menu_layer)
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_CENTER)
    panel.position = Vector2(-230, -165)
    panel.size = Vector2(460, 330)
    menu_layer.add_child(panel)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 12)
    panel.add_child(layout)

    var heading := Label.new()
    heading.text = "TOM&JAIN  |  CITY ONLINE"
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 25)
    layout.add_child(heading)

    var tagline := Label.new()
    tagline.text = "Meet players. Explore the city. Build your story."
    tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    layout.add_child(tagline)

    name_input = LineEdit.new()
    name_input.placeholder_text = "Player name"
    name_input.text = "Player"
    layout.add_child(name_input)

    address_input = LineEdit.new()
    address_input.placeholder_text = "Server URL"
    address_input.text = Network.default_server_url()
    layout.add_child(address_input)

    var create_button := Button.new()
    create_button.text = "CREATE A CITY"
    create_button.pressed.connect(_create_city)
    layout.add_child(create_button)

    room_input = LineEdit.new()
    room_input.placeholder_text = "Partner's 8-character room code"
    layout.add_child(room_input)

    join_button = Button.new()
    join_button.text = "JOIN PARTNER'S CITY"
    join_button.pressed.connect(_join_city)
    layout.add_child(join_button)

    status_label = Label.new()
    status_label.text = "Not connected"
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    layout.add_child(status_label)

    hud_layer = CanvasLayer.new()
    hud_layer.visible = false
    add_child(hud_layer)
    room_label = Label.new()
    room_label.position = Vector2(20, 18)
    room_label.add_theme_font_size_override("font_size", 20)
    hud_layer.add_child(room_label)
    var controls := Label.new()
    controls.text = "WASD move  |  Mouse look  |  Space jump  |  E work/buy/enter  |  Esc release mouse"
    controls.position = Vector2(20, 50)
    hud_layer.add_child(controls)

func _create_city() -> void:
    join_button.disabled = true
    Network.connect_to_server(address_input.text, name_input.text)

func _join_city() -> void:
    join_button.disabled = true
    Network.connect_to_server(address_input.text, name_input.text, room_input.text)

func _update_status(message: String) -> void:
    status_label.text = message
    if message.begins_with("Connected | Room "):
        menu_layer.visible = false
        hud_layer.visible = true
        room_label.text = "TOM&JAIN CITY  |  ROOM " + Network.room_code + "  |  SHARE THIS CODE"
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    else:
        join_button.disabled = false

func _spawn_player(peer_id: String, player_name: String, spawn_position: Vector3) -> void:
    if players_root == null:
        players_root = Node3D.new()
        players_root.name = "Players"
        add_child(players_root)
    if players_root.has_node(peer_id):
        return
    var player := PLAYER_SCENE.instantiate()
    player.name = peer_id
    player.is_local_player = peer_id == Network.player_id
    player.display_name = player_name
    player.position = spawn_position
    players_root.add_child(player)

func _remove_player(peer_id: String) -> void:
    if players_root == null:
        return
    var player := players_root.get_node_or_null(peer_id)
    if player:
        player.queue_free()

func _apply_player_state(peer_id: String, pos: Vector3, yaw: float) -> void:
    if players_root == null:
        return
    var player := players_root.get_node_or_null(peer_id)
    if player:
        player.set_remote_state(pos, yaw)

func _rename_player(peer_id: String, player_name: String) -> void:
    if players_root == null:
        return
    var player = players_root.get_node_or_null(peer_id)
    if player:
        player.update_display_name(player_name)

func _update_room_state(state: Dictionary) -> void:
    for player in state.get("players", []):
        if str(player.get("id", "")) == Network.player_id:
            var coins := int(player.get("coins", 0))
            var inside := str(player.get("inside", ""))
            var location := "  |  Inside " + inside if not inside.is_empty() else ""
            room_label.text = "ROOM " + Network.room_code + "  |  " + str(coins) + " COINS" + location + "  |  SHARE THE CODE"

