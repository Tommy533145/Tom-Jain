extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const UNIT_SCALE: float = 0.1
const CITY_BLOCKS: Array[Rect2] = [
    Rect2(55, 65, 270, 135), Rect2(430, 65, 225, 135), Rect2(790, 65, 300, 135), Rect2(1160, 65, 370, 135),
    Rect2(55, 345, 270, 255), Rect2(430, 345, 225, 255), Rect2(790, 345, 300, 255), Rect2(1160, 345, 370, 255),
    Rect2(55, 735, 270, 295), Rect2(430, 735, 225, 295), Rect2(790, 735, 300, 295), Rect2(1160, 735, 370, 295),
]
const BLOCK_COLORS: Array[Color] = [
    Color("#c7b99c"), Color("#bd8e75"), Color("#b8c7b1"), Color("#c6b890"),
    Color("#9fb6a0"), Color("#d2b894"), Color("#b49683"), Color("#a8beb1"),
    Color("#c8a986"), Color("#a3b9aa"), Color("#c2ad8d"), Color("#b7bea7"),
]
const JOBS: Array[Dictionary] = [
    {"id":"cafe","name":"Cafe shift","x":250.0,"y":305.0,"reward":15},
    {"id":"courier","name":"Courier desk","x":1320.0,"y":305.0,"reward":20},
    {"id":"garden","name":"Community garden","x":280.0,"y":670.0,"reward":15},
    {"id":"music","name":"Street music","x":1300.0,"y":670.0,"reward":20},
]
const HOMES: Array[Dictionary] = [
    {"id":"loft","name":"Canal Loft","x":715.0,"y":245.0,"cost":80},
    {"id":"cottage","name":"Garden Cottage","x":1110.0,"y":245.0,"cost":120},
    {"id":"townhouse","name":"Brick Townhouse","x":715.0,"y":850.0,"cost":160},
    {"id":"penthouse","name":"Skyline Flat","x":1110.0,"y":850.0,"cost":220},
]
const FURNITURE: Array[Dictionary] = [
    {"id":"sofa","name":"Cozy sofa","cost":45},
    {"id":"table","name":"Coffee table","cost":30},
    {"id":"plant","name":"Leafy plant","cost":20},
    {"id":"lamp","name":"Reading lamp","cost":25},
    {"id":"art","name":"Framed city art","cost":35},
    {"id":"bed","name":"Big shared bed","cost":70},
]

var city_root: Node3D
var interior_root: Node3D
var players_root: Node3D
var player_nodes: Dictionary = {}
var local_player: CharacterBody3D
var local_id := ""
var current_room := ""
var homes_owned: Dictionary = {}
var decor_by_home: Dictionary = {}
var player_states: Array = []
var furniture_catalog: Array = FURNITURE
var local_inside := ""
var nearby: Dictionary = {}
var toast_timer := 0.0

var lobby_layer: CanvasLayer
var hud_layer: CanvasLayer
var name_input: LineEdit
var url_input: LineEdit
var room_input: LineEdit
var lobby_status: Label
var room_label: Label
var coin_label: Label
var status_label: Label
var action_label: Label
var copy_button: Button

func _ready() -> void:
    _build_environment()
    _build_city()
    _build_interior()
    _build_ui()
    Network.room_joined.connect(_on_room_joined)
    Network.state_received.connect(_on_state_received)
    Network.status_changed.connect(_on_status_changed)
    Network.server_error.connect(_on_server_error)
    if OS.get_cmdline_user_args().has("--server"):
        lobby_layer.visible = false
        status_label.text = "Server is running. Connect with a Godot client."

func _process(delta: float) -> void:
    toast_timer = maxf(toast_timer - delta, 0.0)
    if local_player and current_room != "":
        _update_interaction_prompt()
    elif is_instance_valid(action_label):
        action_label.text = ""
    if toast_timer <= 0.0 and status_label.text.begins_with("✓"):
        status_label.text = ""

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("interact") and hud_layer.visible:
        _interact()
        get_viewport().set_input_as_handled()

func _build_environment() -> void:
    var world_env := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_SKY
    environment.sky = Sky.new()
    environment.sky.sky_material = ProceduralSkyMaterial.new()
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#d7dfd5")
    environment.ambient_light_energy = 0.8
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world_env.environment = environment
    add_child(world_env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -32, 0)
    sun.light_energy = 1.1
    sun.shadow_enabled = true
    add_child(sun)

func _build_city() -> void:
    city_root = Node3D.new()
    city_root.name = "City"
    add_child(city_root)
    players_root = Node3D.new()
    players_root.name = "Players"
    city_root.add_child(players_root)

    _make_box(city_root, "Ground", Vector3(80, -0.35, 55), Vector3(160, 0.7, 110), Color("#819678"))
    _make_box(city_root, "North Road", Vector3(80, 0.01, 30.5), Vector3(160, 0.08, 7.2), Color("#343a39"))
    _make_box(city_root, "South Road", Vector3(80, 0.01, 66.5), Vector3(160, 0.08, 6.4), Color("#343a39"))
    _make_box(city_root, "West Avenue", Vector3(37.5, 0.015, 55), Vector3(7, 0.09, 110), Color("#3a403e"))
    _make_box(city_root, "Market Avenue", Vector3(72, 0.015, 55), Vector3(7.5, 0.09, 110), Color("#3a403e"))
    _make_box(city_root, "East Avenue", Vector3(112, 0.015, 55), Vector3(7, 0.09, 110), Color("#3a403e"))
    for x in [0.0, 160.0]:
        _make_box(city_root, "Sidewalk", Vector3(x, 0.08, 55), Vector3(1.4, 0.22, 110), Color("#b6b5a7"))
    for z in [27.3, 33.7, 63.3, 69.7]:
        _make_box(city_root, "Curb", Vector3(80, 0.08, z), Vector3(160, 0.18, 0.28), Color("#b8b6a8"))
    for x in range(3, 160, 12):
        _make_box(city_root, "Road marking", Vector3(float(x), 0.07, 30.5), Vector3(4.2, 0.025, 0.12), Color("#e5cf8e"))
        _make_box(city_root, "Road marking", Vector3(float(x), 0.07, 66.5), Vector3(4.2, 0.025, 0.12), Color("#e5cf8e"))

    var rng := RandomNumberGenerator.new()
    rng.seed = 7219
    for index in range(CITY_BLOCKS.size()):
        var block := CITY_BLOCKS[index]
        var height := rng.randf_range(7.0, 17.0)
        _make_building(block, height, BLOCK_COLORS[index], index)

    _make_box(city_root, "Pocket Park", Vector3(68.2, 0.06, 50), Vector3(5.5, 0.18, 10), Color("#a4be91"))
    _make_tree(city_root, Vector3(67.5, 0, 48))
    _make_tree(city_root, Vector3(69.5, 0, 52))
    _make_fountain(city_root, Vector3(80, 0, 55))

    for job in JOBS:
        _make_marker(city_root, Vector3(float(job["x"]) * UNIT_SCALE, 0, float(job["y"]) * UNIT_SCALE), str(job["name"]), Color("#72ba83"))
    for home in HOMES:
        _make_home_marker(city_root, home)

func _make_building(block: Rect2, height: float, color: Color, index: int) -> void:
    var center := Vector3((block.position.x + block.size.x * 0.5) * UNIT_SCALE, height * 0.5, (block.position.y + block.size.y * 0.5) * UNIT_SCALE)
    var size := Vector3(block.size.x * UNIT_SCALE, height, block.size.y * UNIT_SCALE)
    _make_box(city_root, "Building %d" % index, center, size, color)
    _make_box(city_root, "Roof %d" % index, Vector3(center.x, height + 0.1, center.z), Vector3(size.x + 0.3, 0.2, size.z + 0.3), Color("#464b49"))
    var cols := maxi(2, int(block.size.x / 55.0))
    var rows := maxi(2, int(height / 3.4))
    for col in range(cols):
        for row in range(rows):
            var wx := center.x - size.x * 0.5 + 1.3 + float(col) * maxf((size.x - 2.2) / float(cols), 0.65)
            var wy := 2.0 + float(row) * maxf(height / float(rows + 1), 1.6)
            _make_visual_box(city_root, "Window", Vector3(wx, wy, center.z - size.z * 0.5 - 0.015), Vector3(0.9, 1.2, 0.04), Color("#c5d3c2"))
            _make_visual_box(city_root, "Window", Vector3(wx, wy, center.z + size.z * 0.5 + 0.015), Vector3(0.9, 1.2, 0.04), Color("#c5d3c2"))

func _make_tree(parent: Node3D, pos: Vector3) -> void:
    _make_visual_box(parent, "Tree trunk", pos + Vector3(0, 0.8, 0), Vector3(0.35, 1.6, 0.35), Color("#765d45"))
    var crown := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = 1.15
    mesh.height = 2.3
    crown.mesh = mesh
    crown.position = pos + Vector3(0, 2.35, 0)
    crown.material_override = _material(Color("#628965"))
    parent.add_child(crown)

func _make_fountain(parent: Node3D, pos: Vector3) -> void:
    _make_visual_box(parent, "Fountain base", pos + Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 2.4), Color("#849f9c"))
    _make_visual_box(parent, "Fountain water", pos + Vector3(0, 0.83, 0), Vector3(1.8, 0.08, 1.8), Color("#71a9b1"))

func _make_home_marker(parent: Node3D, home: Dictionary) -> void:
    var pos := Vector3(float(home["x"]) * UNIT_SCALE, 0, float(home["y"]) * UNIT_SCALE)
    var house_color := Color("#c8a77b")
    _make_box(parent, "Home " + str(home["id"]), pos + Vector3(0, 1.15, -1.5), Vector3(3.0, 2.3, 2.6), house_color)
    _make_visual_box(parent, "Home roof", pos + Vector3(0, 2.55, -1.5), Vector3(3.3, 0.35, 2.9), Color("#665247"))
    _make_visual_box(parent, "Home door", pos + Vector3(0, 0.8, -0.16), Vector3(0.7, 1.6, 0.08), Color("#654632"))
    _make_marker(parent, pos, str(home["name"]), Color("#e3bc64"))

func _make_marker(parent: Node3D, pos: Vector3, text: String, color: Color) -> void:
    _make_visual_box(parent, text + " marker base", pos + Vector3(0, 0.65, 0), Vector3(0.62, 1.3, 0.62), color)
    var label := Label3D.new()
    label.text = text
    label.position = pos + Vector3(0, 2.0, 0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 32
    label.outline_size = 7
    label.modulate = Color("#f5f0dc")
    parent.add_child(label)

func _build_interior() -> void:
    interior_root = Node3D.new()
    interior_root.name = "Shared Home Interior"
    interior_root.visible = false
    add_child(interior_root)
    _make_box(interior_root, "Apartment floor", Vector3(80, -0.2, 55), Vector3(40, 0.4, 32), Color("#c7b99d"))
    _make_box(interior_root, "Back wall", Vector3(80, 2.0, 39), Vector3(40, 4.0, 0.35), Color("#e0d6c2"))
    _make_box(interior_root, "Left wall", Vector3(60, 2.0, 55), Vector3(0.35, 4.0, 32), Color("#d6c8ad"))
    _make_box(interior_root, "Right wall", Vector3(100, 2.0, 55), Vector3(0.35, 4.0, 32), Color("#d6c8ad"))
    _make_box(interior_root, "Window", Vector3(80, 2.6, 39.25), Vector3(8.0, 2.0, 0.12), Color("#8cb2b0"))
    _make_box(interior_root, "Décor stand", Vector3(94, 0.65, 65), Vector3(2.0, 1.3, 1.5), Color("#d5ad62"))

func _build_ui() -> void:
    lobby_layer = CanvasLayer.new()
    add_child(lobby_layer)
    var backdrop := ColorRect.new()
    backdrop.color = Color(0.06, 0.10, 0.09, 0.84)
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    lobby_layer.add_child(backdrop)
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_CENTER)
    panel.position = Vector2(-260, -245)
    panel.size = Vector2(520, 490)
    lobby_layer.add_child(panel)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 12)
    panel.add_child(layout)

    var title := Label.new()
    title.text = "TWO KEYS, ONE CITY"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 30)
    layout.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "A little open world for two."
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    layout.add_child(subtitle)

    name_input = LineEdit.new()
    name_input.placeholder_text = "Your name"
    name_input.text = "Player"
    layout.add_child(name_input)
    url_input = LineEdit.new()
    url_input.placeholder_text = "Python server WebSocket URL"
    url_input.text = "ws://127.0.0.1:8000/ws"
    layout.add_child(url_input)
    room_input = LineEdit.new()
    room_input.placeholder_text = "Partner's 8-character room code"
    room_input.max_length = 8
    room_input.text_submitted.connect(func(_value: String): _connect_to_city("join"))
    layout.add_child(room_input)

    var create_button := Button.new()
    create_button.text = "CREATE OUR CITY"
    create_button.pressed.connect(func(): _connect_to_city("create"))
    layout.add_child(create_button)
    var join_button := Button.new()
    join_button.text = "JOIN WITH CODE"
    join_button.pressed.connect(func(): _connect_to_city("join"))
    layout.add_child(join_button)

    lobby_status = Label.new()
    lobby_status.text = "Host the Python server, then share your room code."
    lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    layout.add_child(lobby_status)

    hud_layer = CanvasLayer.new()
    hud_layer.visible = false
    add_child(hud_layer)
    var top_panel := PanelContainer.new()
    top_panel.position = Vector2(18, 18)
    top_panel.custom_minimum_size = Vector2(330, 92)
    hud_layer.add_child(top_panel)
    var top_layout := VBoxContainer.new()
    top_panel.add_child(top_layout)
    room_label = Label.new()
    top_layout.add_child(room_label)
    coin_label = Label.new()
    top_layout.add_child(coin_label)
    status_label = Label.new()
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    top_layout.add_child(status_label)
    action_label = Label.new()
    action_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    action_label.position = Vector2(-240, -85)
    action_label.size = Vector2(480, 55)
    action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    action_label.add_theme_font_size_override("font_size", 20)
    hud_layer.add_child(action_label)

func _connect_to_city(action: String) -> void:
    lobby_status.text = "Connecting…"
    Network.connect_to_city(url_input.text, action, room_input.text, name_input.text)

func _on_room_joined(code: String, _player_id: String) -> void:
    current_room = code
    room_input.text = code
    room_label.text = "CITY  " + code
    lobby_layer.visible = false
    hud_layer.visible = true
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_state_received(state: Dictionary) -> void:
    homes_owned = state.get("homes", {})
    decor_by_home = state.get("decor", {})
    furniture_catalog = state.get("furniture", FURNITURE)
    player_states = state.get("players", [])
    var present: Dictionary = {}
    for player_state in player_states:
        var id := str(player_state.get("id", ""))
        if id.is_empty():
            continue
        present[id] = true
        if not player_nodes.has(id):
            _spawn_player(id, str(player_state.get("name", "Player")), player_state)
        var node: CharacterBody3D = player_nodes[id]
        node.update_display_name(str(player_state.get("name", "Player")))
        var city_position := Vector3(float(player_state.get("x", 800.0)) * UNIT_SCALE, 0.0, float(player_state.get("y", 305.0)) * UNIT_SCALE)
        var yaw := float(player_state.get("yaw", 0.0))
        if id == local_id:
            local_inside = str(player_state.get("inside", "") or "")
            if local_inside.is_empty():
                if local_player == null:
                    local_player = node
                if local_player.global_position.distance_to(city_position) > 4.0:
                    local_player.global_position = city_position
            else:
                if local_player == null:
                    local_player = node
                if local_player.global_position.distance_to(city_position) > 4.0:
                    local_player.global_position = city_position
            coin_label.text = "✦  %d coins" % int(player_state.get("coins", 0))
        else:
            node.set_remote_state(city_position, yaw)
        node.visible = _should_show_player(player_state, id)
    for id in player_nodes.keys().duplicate():
        if not present.has(id):
            player_nodes[id].queue_free()
            player_nodes.erase(id)
            if id == local_id:
                local_player = null
    city_root.visible = local_inside.is_empty()
    interior_root.visible = not local_inside.is_empty()
    _refresh_interior_decor()

func _spawn_player(id: String, player_name: String, player_state: Dictionary) -> void:
    var player := PLAYER_SCENE.instantiate() as CharacterBody3D
    player.name = id
    player.display_name = player_name
    player.is_local_player = id == local_id
    var pos := Vector3(float(player_state.get("x", 770.0)) * UNIT_SCALE, 0.0, float(player_state.get("y", 305.0)) * UNIT_SCALE)
    player.position = pos
    players_root.add_child(player)
    player_nodes[id] = player
    if id == local_id:
        local_player = player

func _should_show_player(player_state: Dictionary, id: String) -> bool:
    var their_inside := str(player_state.get("inside", "") or "")
    if local_inside.is_empty():
        return their_inside.is_empty()
    return id == local_id or their_inside == local_inside

func _refresh_interior_decor() -> void:
    if interior_root == null:
        return
    for child in interior_root.get_children():
        if str(child.name).begins_with("Purchased "):
            child.queue_free()
    if local_inside.is_empty():
        return
    var items: Array = decor_by_home.get(local_inside, [])
    for item in items:
        match str(item):
            "sofa":
                _make_box(interior_root, "Purchased sofa", Vector3(71, 0.55, 48), Vector3(4.0, 1.1, 1.4), Color("#718f7a"))
            "table":
                _make_box(interior_root, "Purchased table", Vector3(80, 0.38, 55), Vector3(2.1, 0.75, 1.4), Color("#9a6b48"))
            "plant":
                _make_tree(interior_root, Vector3(64, 0, 63))
            "lamp":
                _make_box(interior_root, "Purchased lamp", Vector3(94, 1.1, 48), Vector3(0.35, 2.2, 0.35), Color("#e3bc64"))
            "art":
                _make_box(interior_root, "Purchased art", Vector3(87, 2.4, 39.5), Vector3(2.5, 1.6, 0.12), Color("#8cb6a3"))
            "bed":
                _make_box(interior_root, "Purchased bed", Vector3(89, 0.35, 61), Vector3(4.0, 0.7, 2.8), Color("#b8796d"))

func _interact() -> void:
    if local_player == null:
        return
    if not local_inside.is_empty():
        if _distance_to_map_point(940.0, 650.0) <= 82.0:
            var owned_items: Array = decor_by_home.get(local_inside, [])
            for item in furniture_catalog:
                var item_id := str(item.get("id", ""))
                if not owned_items.has(item_id):
                    Network.send_action("decorate", item_id)
                    return
            _show_notice("You have collected every décor item for this home.")
        else:
            Network.send_action("exit")
        return

    var job := _nearest(JOBS)
    if not job.is_empty() and _distance_to_map_point(float(job["x"]), float(job["y"])) <= 62.0:
        Network.send_action("work", str(job["id"]))
        return
    var home := _nearest(HOMES)
    if home.is_empty() or _distance_to_map_point(float(home["x"]), float(home["y"])) > 86.0:
        _show_notice("Explore the city and look for a green job sign or gold home marker.")
        return
    var home_id := str(home["id"])
    if homes_owned.has(home_id):
        Network.send_action("enter", home_id)
    else:
        Network.send_action("buy", home_id)

func _nearest(items: Array) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    var pos := local_player.global_position
    for item in items:
        var distance := _distance_to_map_point(float(item["x"]), float(item["y"]))
        if distance < best_distance:
            best_distance = distance
            best = item
    return best

func _distance_to_map_point(map_x: float, map_y: float) -> float:
    var pos := local_player.global_position
    return Vector2(pos.x * 10.0 - map_x, pos.z * 10.0 - map_y).length()

func _update_interaction_prompt() -> void:
    if local_player == null:
        return
    if not local_inside.is_empty():
        var owned: Array = decor_by_home.get(local_inside, [])
        var next_item: Dictionary = {}
        for item in furniture_catalog:
            if not owned.has(str(item.get("id", ""))):
                next_item = item
                break
        if _distance_to_map_point(940.0, 650.0) <= 82.0:
            action_label.text = "E  ·  Add %s  ·  %d coins" % [str(next_item.get("name", "Décor complete")), int(next_item.get("cost", 0))]
        else:
            action_label.text = "E  ·  Step back outside"
        return
    var job := _nearest(JOBS)
    if not job.is_empty() and _distance_to_map_point(float(job["x"]), float(job["y"])) <= 62.0:
        action_label.text = "E  ·  %s  ·  Earn %d coins" % [str(job["name"]), int(job["reward"])]
        return
    var home := _nearest(HOMES)
    if not home.is_empty() and _distance_to_map_point(float(home["x"]), float(home["y"])) <= 86.0:
        var home_id := str(home["id"])
        if homes_owned.has(home_id):
            action_label.text = "E  ·  Enter %s" % str(home["name"])
        else:
            action_label.text = "E  ·  Buy %s  ·  %d coins" % [str(home["name"]), int(home["cost"])]
        return
    action_label.text = ""

func _on_status_changed(message: String) -> void:
    lobby_status.text = message
    if hud_layer.visible:
        status_label.text = message

func _on_server_error(message: String) -> void:
    if lobby_layer.visible:
        lobby_status.text = message
    else:
        _show_notice(message)

func _show_notice(message: String) -> void:
    status_label.text = "✓ " + message
    toast_timer = 3.0

func _make_box(parent: Node3D, label: String, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = label
    body.position = pos
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.material_override = _material(color)
    body.add_child(mesh)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    parent.add_child(body)
    return body

func _make_visual_box(parent: Node3D, label: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    mesh.name = label
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.position = pos
    mesh.material_override = _material(color)
    parent.add_child(mesh)
    return mesh

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.82
    return material
