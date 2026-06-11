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

const ATTACK_DAMAGE := 35.0
const ATTACK_REACH := 1.4
const ATTACK_RADIUS := 1.15
const ATTACK_COOLDOWN := 0.65
const ATTACK_STAMINA := 7.0
const ATTACK_KNOCKBACK := 7.0

# Pose des bras (depuis la T-pose, en espace global squelette) :
# bras gauche relâché le long du corps, coude légèrement plié ; bras droit en
# garde, coude très plié pour tenir le tuyau devant la poitrine.
const L_LOWER := 1.18
const L_PITCH := -0.25
const L_BEND := 0.4
const R_LOWER := 0.92
const R_PITCH := -0.45
const R_BEND := 1.2
const ARM_SWING_AMP := 0.3

var health := 100.0
var stamina := 100.0
var dead := false

var _skel: Skeleton3D
var _bone_l := -1
var _bone_r := -1
var _fore_l := -1
var _fore_r := -1
var _hand_r := -1
var _focus: Interactable
var _attack_cd := 0.0
var _swing_tween: Tween
# Offsets d'animation de frappe appliqués au bras droit (tweenés).
var _atk_pitch := 0.0
var _atk_bend := 0.0
var _sway_t := 0.0
var _bob_t := 0.0
var _cam_base_y := 0.0
var _fov_base := 75.0
var _shake := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Flashlight


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_cam_base_y = camera.position.y
	_fov_base = camera.fov
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
		elif bname.begins_with("LeftForeArm"):
			_fore_l = i
		elif bname.begins_with("RightForeArm"):
			_fore_r = i
		elif bname.begins_with("RightHand_"):
			# Le "_" exclut les phalanges (RightHandThumb1_30, etc.).
			_hand_r = i
	_attach_weapon()
	_curl_fingers()
	_update_arm_pose(0.0)


## Referme les mains : poing serré à droite (tient le tuyau), main détendue
## à gauche. Pose statique, appliquée une seule fois.
func _curl_fingers() -> void:
	for i in _skel.get_bone_count():
		var bname := _skel.get_bone_name(i)
		var right := bname.begins_with("RightHand") and not bname.begins_with("RightHand_")
		var left := bname.begins_with("LeftHand") and not bname.begins_with("LeftHand_")
		if not right and not left:
			continue
		var amount := 0.3 if bname.contains("Thumb") else (0.95 if right else 0.35)
		_pose_bone(i, Quaternion(Vector3(0, 0, 1), amount if right else -amount))


## Tuyau de plomberie attaché à l'os de la main droite : il suit le bras.
func _attach_weapon() -> void:
	if _hand_r < 0:
		return
	var att := BoneAttachment3D.new()
	_skel.add_child(att)
	att.bone_idx = _hand_r
	var pipe := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.022
	cyl.bottom_radius = 0.027
	cyl.height = 0.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.34, 0.32)
	mat.metallic = 0.85
	mat.roughness = 0.45
	cyl.material = mat
	pipe.mesh = cyl
	# Prise marteau : l'axe du tuyau suit le pouce (X local de la main),
	# décalé pour que la majeure partie dépasse au-dessus du poing.
	pipe.rotation.z = -PI / 2.0
	pipe.position = Vector3(0.2, -0.02, 0.0)
	att.add_child(pipe)


## Applique une rotation (espace global squelette) par-dessus la pose de
## repos. La compensation parent utilise le rest : pour les avant-bras, la
## flexion reste donc relative au bras déjà posé (le coude suit l'épaule).
func _pose_bone(idx: int, extra: Quaternion) -> void:
	if idx < 0:
		return
	var parent := _skel.get_bone_parent(idx)
	var parent_rot := _skel.get_bone_global_rest(parent).basis.get_rotation_quaternion()
	var rest := _skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
	_skel.set_bone_pose_rotation(idx, parent_rot.inverse() * (extra * rest))


func _arm_quat(lower: float, pitch: float) -> Quaternion:
	return Quaternion(Vector3(1, 0, 0), pitch) * Quaternion(Vector3(0, 0, 1), lower)


func _update_arm_pose(swing: float) -> void:
	if _skel == null:
		return
	# Les bras suivent légèrement le regard vertical.
	var view_pitch := head.rotation.x * 0.6
	# Bras gauche : ballant, balancement de marche complet.
	_pose_bone(_bone_l, _arm_quat(-L_LOWER, L_PITCH + view_pitch + swing))
	_pose_bone(_fore_l, Quaternion(Vector3(0, 1, 0), L_BEND))
	# Bras droit : garde arme, balancement réduit + animation de frappe.
	_pose_bone(_bone_r, _arm_quat(R_LOWER,
			R_PITCH + view_pitch - swing * 0.25 + _atk_pitch))
	_pose_bone(_fore_r, Quaternion(Vector3(0, 1, 0), R_BEND + _atk_bend))


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
	_attack_cd = maxf(_attack_cd - delta, 0.0)

	# Sensation de vitesse : le champ de vision s'élargit au sprint.
	var target_fov := _fov_base + (8.0 if sprinting else 0.0)
	camera.fov = lerpf(camera.fov, target_fov, 5.0 * delta)

	# Secousse de caméra décroissante après un coup reçu.
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 3.0, 0.0)
		camera.h_offset = randf_range(-1, 1) * _shake * 0.04
		camera.v_offset = randf_range(-1, 1) * _shake * 0.04
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

	_interact_scan()


func _try_attack() -> void:
	if _attack_cd > 0.0 or stamina < ATTACK_STAMINA:
		return
	_attack_cd = ATTACK_COOLDOWN
	stamina -= ATTACK_STAMINA
	stamina_changed.emit(stamina)
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	# Frappe animée sur le bras droit : armé au-dessus de l'épaule,
	# coup descendant bras tendu, puis retour en garde.
	_swing_tween = create_tween().set_parallel(true)
	_swing_tween.tween_property(self, "_atk_pitch", -0.7, 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(self, "_atk_bend", 0.45, 0.09)
	_swing_tween.chain().tween_property(self, "_atk_pitch", 1.15, 0.11) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.parallel().tween_property(self, "_atk_bend", -1.1, 0.11)
	_swing_tween.chain().tween_callback(_apply_hit)
	_swing_tween.chain().tween_property(self, "_atk_pitch", 0.0, 0.32) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_swing_tween.parallel().tween_property(self, "_atk_bend", 0.0, 0.32)


## Coup porté : sphère devant la caméra sur le layer monstres (4).
func _apply_hit() -> void:
	var center := camera.global_position - camera.global_transform.basis.z * ATTACK_REACH
	var shape := SphereShape3D.new()
	shape.radius = ATTACK_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = 4
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 6):
		var monster := hit.get("collider") as Monster
		if monster == null:
			continue
		var dir := monster.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else -global_transform.basis.z
		monster.take_hit(ATTACK_DAMAGE, dir * ATTACK_KNOCKBACK + Vector3(0, 1.5, 0))


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
	elif event.is_action_pressed("attack") and not dead \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_attack()


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(health + amount, 100.0)
	health_changed.emit(health)


func take_damage(amount: float) -> void:
	if dead:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health)
	damaged.emit()
	_shake = 1.0
	if health <= 0.0:
		dead = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
