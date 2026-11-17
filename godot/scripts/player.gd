extends CharacterBody3D

@export var move_speed: float = 10.0
@export var mouse_sensitivity: float = 0.0025

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var camera_pivot: Node3D
var display_name := "Player"
var name_tag: Label3D
var is_local_player := false
var remote_target_position := Vector3.ZERO
var remote_target_yaw := 0.0
var send_accumulator := 0.0

func _ready() -> void:
    camera_pivot = $CameraPivot
    $CameraPivot/SpringArm3D/Camera3D.current = is_local_player
    name_tag = Label3D.new()
    name_tag.text = display_name
    name_tag.position = Vector3(0, 2.1, 0)
    name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    name_tag.modulate = Color(0.96, 0.94, 0.83)
    add_child(name_tag)
    remote_target_position = global_position
    if is_local_player:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if not is_local_player:
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
        camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -0.95, 0.4)
    elif event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
    if is_local_player:
        _move_local(delta)
        send_accumulator += delta
        if send_accumulator >= 1.0 / 15.0:
            send_accumulator = 0.0
            Network.send_move(global_position.x * 10.0, global_position.z * 10.0, rotation.y)
    else:
        global_position = global_position.lerp(remote_target_position, min(delta * 10.0, 1.0))
        rotation.y = lerp_angle(rotation.y, remote_target_yaw, min(delta * 10.0, 1.0))

func _move_local(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    if direction.length() > 0.001:
        velocity.x = direction.x * move_speed
        velocity.z = direction.z * move_speed
    else:
        velocity.x = move_toward(velocity.x, 0.0, move_speed * 5.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, move_speed * 5.0 * delta)
    move_and_slide()

func set_remote_state(pos: Vector3, yaw: float) -> void:
    if is_local_player:
        return
    remote_target_position = pos
    remote_target_yaw = yaw

func update_display_name(value: String) -> void:
    display_name = value
    if is_instance_valid(name_tag):
        name_tag.text = display_name
