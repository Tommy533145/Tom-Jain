extends CharacterBody3D

@export var move_speed: float = 6.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.0025

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var camera_pivot: Node3D
var remote_target_position: Vector3
var remote_target_yaw: float = 0.0
var display_name: String = "Player"

func _ready() -> void:
    camera_pivot = $CameraPivot
    $CameraPivot/SpringArm3D/Camera3D.current = is_multiplayer_authority()
    var name_tag := Label3D.new()
    name_tag.text = display_name
    name_tag.position = Vector3(0, 2.1, 0)
    name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(name_tag)
    remote_target_position = global_position
    if is_multiplayer_authority():
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if not is_multiplayer_authority():
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
        camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.0, 0.65)
    elif event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
    if is_multiplayer_authority():
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

func set_remote_state(pos: Vector3, yaw: float) -> void:
    if not is_multiplayer_authority():
        remote_target_position = pos
        remote_target_yaw = yaw
