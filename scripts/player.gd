class_name PlayerController
extends CharacterBody3D

## Contrôleur FPS : ZQSD (touches physiques, compatible AZERTY), saut, sprint
## avec stamina, lampe torche. Le corps hazmat complet est attaché au joueur,
## tête masquée (scale du bone) ; les bras sont posés et balancés
## procéduralement car le modèle n'a aucune animation.

signal health_changed(value: float)
signal stamina_changed(value: float)
signal damaged
signal died
signal focus_changed(prompt: String)

const WALK_SPEED := 3.6
const SPRINT_SPEED := 6.4
const JUMP_VELOCITY := 4.4
const ACCEL := 10.0
const MOUSE_SENS := 0.0022
const STAMINA_DRAIN := 16.0
const STAMINA_REGEN := 11.0
const INTERACT_DIST := 2.6

# Pose des bras : abaissés depuis la T-pose puis ramenés vers l'avant.
const ARM_LOWER := 1.05
const ARM_PITCH := -0.7
const ARM_SWING_AMP := 0.35

var health := 100.0
var stamina := 100.0
var dead := false

var _skel: Skeleton3D
var _bone_l := -1
var _bone_r := -1
var _focus: Interactable
var _sway_t := 0.0
var _bob_t := 0.0
var _cam_base_y := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Flashlight


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_cam_base_y = camera.position.y
	_build_body_model()


func _build_body_model() -> void:
	var model: Node3D = load("res://assets/character/escape_the_backrooms_hazmat.glb").instantiate()
	add_child(model)
	# Les modèles glTF font face à +Z ; la caméra regarde vers -Z.
	model.rotation.y = PI
	model.position = Vector3(0, 0, 0.12)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	_skel = skels[0]
	for i in _skel.get_bone_count():
		var bname := _skel.get_bone_name(i)
		if bname.begins_with("Head") and not bname.begins_with("HeadTop"):
			# Tête réduite à néant pour ne pas obstruer la caméra.
			_skel.set_bone_pose_scale(i, Vector3(0.01, 0.01, 0.01))
		elif bname.begins_with("LeftArm"):
			_bone_l = i
		elif bname.begins_with("RightArm"):
			_bone_r = i
	_update_arm_pose(0.0)


func _pose_arm(idx: int, lower: float, pitch: float) -> void:
	if idx < 0:
		return
	var parent := _skel.get_bone_parent(idx)
	var parent_rot := _skel.get_bone_global_rest(parent).basis.get_rotation_quaternion()
	var rest := _skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
	var q := Quaternion(Vector3(1, 0, 0), pitch) * Quaternion(Vector3(0, 0, 1), lower) * rest
	_skel.set_bone_pose_rotation(idx, parent_rot.inverse() * q)


func _update_arm_pose(swing: float) -> void:
	if _skel == null:
		return
	# Les bras suivent légèrement le regard vertical.
	var view_pitch := head.rotation.x * 0.6
	_pose_arm(_bone_l, -ARM_LOWER, ARM_PITCH + view_pitch + swing)
	_pose_arm(_bone_r, ARM_LOWER, ARM_PITCH + view_pitch - swing)


func _physics_process(delta: float) -> void:
	if dead:
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var moving := dir.length_squared() > 0.01

	var sprinting := moving and Input.is_action_pressed("sprint") and stamina > 0.0
	if sprinting:
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
	else:
		stamina = minf(stamina + STAMINA_REGEN * delta, 100.0)
	stamina_changed.emit(stamina)

	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	velocity.x = lerpf(velocity.x, dir.x * speed, ACCEL * delta)
	velocity.z = lerpf(velocity.z, dir.z * speed, ACCEL * delta)
	move_and_slide()

	# Head bob + balancement des bras proportionnels à la vitesse.
	var planar := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar > 0.5:
		_bob_t += delta * planar * 1.6
		_sway_t += delta * planar * 1.5
		camera.position.y = _cam_base_y + sin(_bob_t) * 0.04
		camera.rotation.z = sin(_bob_t * 0.5) * 0.012
	else:
		camera.position.y = lerpf(camera.position.y, _cam_base_y, 6.0 * delta)
		camera.rotation.z = lerpf(camera.rotation.z, 0.0, 6.0 * delta)
	var swing_amp := ARM_SWING_AMP * clampf(planar / SPRINT_SPEED, 0.0, 1.0)
	_update_arm_pose(sin(_sway_t) * swing_amp)
	_interact_scan()


## Raycast du regard vers les Interactable (layer 8). Le layer monde (1) est
## inclus pour que les murs bloquent la visée à travers les cloisons.
func _interact_scan() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * INTERACT_DIST
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8)
	query.collide_with_areas = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var hit: Node = result.get("collider")
	var target := hit as Interactable
	if target != _focus:
		_focus = target
		focus_changed.emit(_focus.prompt if _focus != null else "")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENS, -1.45, 1.45)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("flashlight") and not dead:
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("interact") and not dead:
		if _focus != null and is_instance_valid(_focus):
			_focus.interact(self)


func take_damage(amount: float) -> void:
	if dead:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health)
	damaged.emit()
	if health <= 0.0:
		dead = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
