extends CharacterBody3D

@export var move_speed: float = 6.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.0045

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var camera_pivot: Node3D
var remote_target_position: Vector3
var remote_target_yaw: float = 0.0
var display_name: String = "Player"
var is_local_player := false
var name_tag: Label3D
var visual_root: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var animation_clock := 0.0

func _ready() -> void:
    camera_pivot = $CameraPivot
    $CameraPivot/SpringArm3D/Camera3D.current = is_local_player
    $Body.visible = false
    _build_character()
    name_tag = Label3D.new()
    name_tag.text = display_name
    name_tag.position = Vector3(0, 2.35, 0)
    name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(name_tag)
    remote_target_position = global_position

func _unhandled_input(event: InputEvent) -> void:
    if not is_local_player:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
        Network.interact()
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
    if not is_local_player:
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
        camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.15, 0.85)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
    if is_local_player:
        _move_local(delta)
        Network.send_player_state(global_position, rotation.y)
    else:
        global_position = global_position.lerp(remote_target_position, min(delta * 12.0, 1.0))
        rotation.y = lerp_angle(rotation.y, remote_target_yaw, min(delta * 12.0, 1.0))

func _move_local(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity
    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    if direction.length() > 0.001:
        velocity.x = direction.x * move_speed
        velocity.z = direction.z * move_speed
    else:
        velocity.x = move_toward(velocity.x, 0.0, move_speed * 5.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, move_speed * 5.0 * delta)
    move_and_slide()

func _process(delta: float) -> void:
    if not is_instance_valid(visual_root):
        return
    animation_clock += delta
    var horizontal_speed := Vector2(velocity.x, velocity.z).length()
    var stride := sin(animation_clock * (10.0 if horizontal_speed > 3.5 else 7.0)) if horizontal_speed > 0.15 else 0.0
    if not is_on_floor():
        left_arm.rotation.x = -0.48
        right_arm.rotation.x = -0.48
        left_leg.rotation.x = 0.32
        right_leg.rotation.x = -0.32
    else:
        left_arm.rotation.x = stride * 0.72
        right_arm.rotation.x = -stride * 0.72
        left_leg.rotation.x = -stride * 0.8
        right_leg.rotation.x = stride * 0.8
    visual_root.position.y = 0.035 * absf(stride) if horizontal_speed > 0.15 and is_on_floor() else 0.0
    if horizontal_speed < 0.15 and is_on_floor():
        visual_root.position.y += sin(animation_clock * 2.0) * 0.018

func _build_character() -> void:
    visual_root = Node3D.new()
    visual_root.name = "AnimatedCharacter"
    add_child(visual_root)

    var skin := _material(Color(0.77, 0.52, 0.36))
    var shirt := _material(Color(0.12, 0.52, 0.64) if is_local_player else Color(0.66, 0.35, 0.72))
    var pants := _material(Color(0.13, 0.16, 0.23))
    var hair := _material(Color(0.12, 0.075, 0.055))
    var shoes := _material(Color(0.08, 0.085, 0.10))
    var eye_white := _material(Color(0.96, 0.93, 0.84))
    var eye_dark := _material(Color(0.055, 0.04, 0.035))

    _add_capsule(visual_root, "Jacket", Vector3(0, 1.12, 0), 0.92, 0.36, shirt)
    _add_capsule(visual_root, "Head", Vector3(0, 1.82, 0), 0.50, 0.235, skin)
    _add_sphere(visual_root, "Hair", Vector3(0, 2.0, -0.015), 0.245, hair)
    _add_sphere(visual_root, "Nose", Vector3(0, 1.82, -0.225), 0.052, skin)
    _add_sphere(visual_root, "LeftEye", Vector3(-0.085, 1.85, -0.21), 0.043, eye_white)
    _add_sphere(visual_root, "RightEye", Vector3(0.085, 1.85, -0.21), 0.043, eye_white)
    _add_sphere(visual_root, "LeftPupil", Vector3(-0.085, 1.85, -0.247), 0.019, eye_dark)
    _add_sphere(visual_root, "RightPupil", Vector3(0.085, 1.85, -0.247), 0.019, eye_dark)
    _add_box(visual_root, "Belt", Vector3(0, 0.68, 0), Vector3(0.58, 0.12, 0.38), shoes)

    left_arm = _add_limb(visual_root, "LeftArm", Vector3(-0.4, 1.42, 0), 0.72, 0.14, skin)
    right_arm = _add_limb(visual_root, "RightArm", Vector3(0.4, 1.42, 0), 0.72, 0.14, skin)
    left_leg = _add_limb(visual_root, "LeftLeg", Vector3(-0.18, 0.66, 0), 0.86, 0.17, pants)
    right_leg = _add_limb(visual_root, "RightLeg", Vector3(0.18, 0.66, 0), 0.86, 0.17, pants)
    _add_box(left_leg, "LeftShoe", Vector3(0, -0.43, -0.07), Vector3(0.27, 0.16, 0.42), shoes)
    _add_box(right_leg, "RightShoe", Vector3(0, -0.43, -0.07), Vector3(0.27, 0.16, 0.42), shoes)

func _material(color: Color) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_color = color
    result.roughness = 0.72
    return result

func _add_capsule(parent: Node3D, label: String, pos: Vector3, height: float, radius: float, material: Material) -> MeshInstance3D:
    var mesh_node := MeshInstance3D.new()
    mesh_node.name = label
    var mesh := CapsuleMesh.new()
    mesh.height = height
    mesh.radius = radius
    mesh_node.mesh = mesh
    mesh_node.material_override = material
    mesh_node.position = pos
    parent.add_child(mesh_node)
    return mesh_node

func _add_sphere(parent: Node3D, label: String, pos: Vector3, radius: float, material: Material) -> MeshInstance3D:
    var mesh_node := MeshInstance3D.new()
    mesh_node.name = label
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh_node.mesh = mesh
    mesh_node.material_override = material
    mesh_node.position = pos
    parent.add_child(mesh_node)
    return mesh_node

func _add_box(parent: Node3D, label: String, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
    var mesh_node := MeshInstance3D.new()
    mesh_node.name = label
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_node.mesh = mesh
    mesh_node.material_override = material
    mesh_node.position = pos
    parent.add_child(mesh_node)
    return mesh_node

func _add_limb(parent: Node3D, label: String, pos: Vector3, height: float, radius: float, material: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = label
    pivot.position = pos
    parent.add_child(pivot)
    _add_capsule(pivot, label + "Mesh", Vector3(0, -height * 0.32, 0), height, radius, material)
    return pivot

func set_remote_state(pos: Vector3, yaw: float) -> void:
    if not is_local_player:
        remote_target_position = pos
        remote_target_yaw = yaw

func update_display_name(value: String) -> void:
    display_name = value
    if is_instance_valid(name_tag):
        name_tag.text = display_name

