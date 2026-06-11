class_name Monster
extends CharacterBody3D

## Monstre générique : charge n'importe quel GLB, le normalise à une hauteur
## cible (les modèles ont des échelles très variées), puis poursuit le joueur
## via le navmesh (repli en ligne droite si pas de chemin).
##
## Chaque type a une personnalité (cfg.behavior) :
## - "rusher"   : charge à vue, frappe puis fuit quelques secondes.
## - "stalker"  : rôde en cercle à distance, ne charge que si le joueur ne le
##                regarde plus depuis un moment ou s'il est affaibli.
## - "brute"    : lent, massif, entend le sprint de très loin, recul réduit.
## - "smiler"   : rapide dans l'ombre, se FIGE quand le joueur le regarde ou
##                l'éclaire à la lampe.
## - "ambusher" : dormant et immobile (vous fixe), burst rapide à courte
##                portée puis se rendort s'il vous perd.

const DESPAWN_RANGE := 70.0

var cfg := {}
var player: PlayerController
var health := 90.0

var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _walk_anim := ""
var _model: Node3D
var _skel: Skeleton3D
var _bone_hips := -1
var _bone_l_arm := -1
var _bone_r_arm := -1
var _bone_l_fore := -1
var _bone_r_fore := -1
var _bone_l_leg := -1
var _bone_r_leg := -1
var _bone_l_foot := -1
var _bone_r_foot := -1
var _generic_left_bones: Array[int] = []
var _generic_right_bones: Array[int] = []
var _generic_leg_bones: Array[int] = []
var _left_parts: Array[Node3D] = []
var _right_parts: Array[Node3D] = []
var _leg_parts: Array[Node3D] = []
var _part_rest_rot := {}
var _base_model_pos := Vector3.ZERO
var _base_model_rot := Vector3.ZERO
var _motion_phase := 0.0
var _motion_blend := 0.0
var _dying := false
var _stagger := 0.0
var _speed := 4.0
var _behavior := "rusher"
var _damage := 18.0
var _atk_cooldown := 1.3
var _stagger_mult := 1.0
var _state := ""
var _state_t := 0.0
var _unseen_t := 0.0
var _commit := false
var _frozen := false
var _orbit_sign := 1.0
var _floats := false
var _hover := 1.3
var _attack_range := 1.7
var _attack_cd := 0.0
var _repath := 0.0
var _wander_dir := Vector3.ZERO
var _wander_t := 0.0
var _bob_phase := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	collision_layer = 4
	# Pas de collision physique avec le joueur : la dépénétration des capsules
	# le propulserait à travers les murs. Les dégâts sont gérés par distance.
	collision_mask = 1 | 4
	_speed = cfg.get("speed", 4.0) * randf_range(0.9, 1.1)
	_floats = cfg.get("floats", false)
	_hover = cfg.get("hover", 1.3)
	health = cfg.get("hp", 90.0)
	_behavior = cfg.get("behavior", "rusher")
	_damage = cfg.get("damage", 18.0)
	_atk_cooldown = cfg.get("atk_cd", 1.3)
	_stagger_mult = cfg.get("stagger_mult", 1.0)
	_orbit_sign = 1.0 if randf() < 0.5 else -1.0
	if _behavior == "ambusher":
		_state = "dormant"
	_bob_phase = randf() * TAU

	var model: Node3D = load(cfg["model"]).instantiate()
	_model = model
	add_child(model)
	var aabb := combined_aabb(model)
	var target_h: float = cfg.get("height", 2.0)
	var s := target_h / maxf(aabb.size.y, 0.01)
	if aabb.size.x * s > 3.0:
		s = 3.0 / aabb.size.x
	model.scale = Vector3.ONE * s
	# Pieds du modèle posés sur l'origine du body.
	var center := aabb.get_center() * s
	model.position = Vector3(-center.x, -aabb.position.y * s, -center.z)
	_setup_motion_rig()

	var cap := CapsuleShape3D.new()
	cap.radius = clampf(aabb.size.x * s * 0.25, 0.3, 0.6)
	cap.height = maxf(aabb.size.y * s, cap.radius * 2.1)
	var col := CollisionShape3D.new()
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)
	_attack_range = maxf(2.2, cap.radius + 1.4)

	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.8
	_agent.target_desired_distance = 1.0
	_agent.radius = cap.radius
	_agent.height = cap.height
	add_child(_agent)

	var anims := find_children("*", "AnimationPlayer", true, false)
	if not anims.is_empty():
		_anim = anims[0]
		var list := _anim.get_animation_list()
		if list.size() > 0:
			_walk_anim = list[0]
			_anim.get_animation(_walk_anim).loop_mode = Animation.LOOP_LINEAR
			_anim.play(_walk_anim)


## Coup reçu : dégâts, recul et bref étourdissement ; mort en dessous de 0.
func take_hit(damage: float, knockback: Vector3) -> void:
	if _dying:
		return
	health -= damage
	_stagger = 0.45 * _stagger_mult
	velocity += knockback * _stagger_mult
	if _behavior == "ambusher":
		# Réveillé de force par le coup.
		_state = "burst"
		_state_t = 6.0
	if health <= 0.0:
		_die()


func _die() -> void:
	_dying = true
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	if _anim != null:
		_anim.stop()
	# Effondrement : le modèle s'affaisse dans le sol puis disparaît.
	var tween := create_tween()
	tween.set_parallel(true)
	if _model != null:
		tween.tween_property(_model, "scale", _model.scale * Vector3(1.1, 0.04, 1.1), 0.55) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_interval(0.25)
	tween.chain().tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_state_t = maxf(_state_t - delta, 0.0)
	if _stagger > 0.0:
		# Sonné : subit le recul avec friction, sans poursuivre.
		_stagger -= delta
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		if not _floats and not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		_update_visual_motion(delta)
		return
	var hunting := player != null and is_instance_valid(player) and not player.dead
	var dist := INF
	if hunting:
		dist = global_position.distance_to(player.global_position)
		if dist > DESPAWN_RANGE:
			queue_free()
			return

	var dir := Vector3.ZERO
	var speed := _speed * 0.45
	var face_player := false
	_frozen = false
	if hunting:
		match _behavior:
			"rusher":
				if _state == "flee":
					dir = global_position - player.global_position
					speed = _speed
					if _state_t <= 0.0:
						_state = ""
				elif dist <= 26.0 and (dist < 8.0 or _sees_player()):
					dir = _nav_dir_to(player.global_position, delta)
					speed = _speed
					face_player = true
				else:
					dir = _wander(delta)
			"stalker":
				if dist <= 32.0 and _sees_player():
					face_player = true
					_unseen_t = 0.0 if _player_watching() else _unseen_t + delta
					if not _commit and _state_t <= 0.0 \
							and (_unseen_t > 1.5 or player.health <= 40.0):
						_commit = true
					if _commit:
						dir = _nav_dir_to(player.global_position, delta)
						speed = _speed
					else:
						# Rôde sur un anneau ~11 m autour du joueur.
						var to_p := player.global_position - global_position
						to_p.y = 0.0
						var tangent := to_p.cross(Vector3.UP).normalized() * _orbit_sign
						var radial := to_p.normalized() \
								* clampf((dist - 11.0) * 0.4, -1.0, 1.0)
						dir = tangent + radial
						speed = _speed * 0.55
				else:
					_commit = false
					_unseen_t = 0.0
					dir = _wander(delta)
			"brute":
				var planar := Vector2(player.velocity.x, player.velocity.z).length()
				var hearing := 34.0 if planar > 5.0 else 20.0
				if dist <= hearing or _sees_player():
					dir = _nav_dir_to(player.global_position, delta)
					speed = _speed
					face_player = true
				else:
					dir = _wander(delta)
			"smiler":
				if dist <= 30.0 and _sees_player():
					face_player = true
					if _player_watching() or _in_flashlight():
						_frozen = true
					else:
						dir = _nav_dir_to(player.global_position, delta)
						speed = _speed * 1.25
				else:
					dir = _wander(delta)
			"ambusher":
				if _state == "burst":
					dir = _nav_dir_to(player.global_position, delta)
					speed = _speed * 1.3
					face_player = true
					if _state_t <= 0.0 or dist > 22.0:
						_state = "dormant"
				elif dist <= 9.0 and _sees_player():
					_state = "burst"
					_state_t = 6.0
				elif dist <= 20.0 and _sees_player():
					face_player = true  # Immobile, il vous fixe.
	else:
		dir = _wander(delta)

	# Attaque : à portée, pas figé, et le comportement l'autorise.
	if hunting and dist <= _attack_range and not _frozen:
		if face_player:
			# Reste à distance d'attaque au lieu de fusionner avec la caméra.
			dir = Vector3.ZERO
		if _attack_cd <= 0.0 and _attack_allowed():
			_attack_cd = _atk_cooldown
			player.take_damage(_damage)
			if _behavior == "rusher":
				_state = "flee"
				_state_t = 2.4
			elif _behavior == "stalker":
				_commit = false
				_unseen_t = 0.0
				_state_t = 4.0  # Répit avant la prochaine charge.

	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	if _floats:
		var target_y := global_position.y
		if face_player:
			target_y = player.global_position.y + _hover
		velocity.y = clampf((target_y - global_position.y) * 2.0, -2.0, 2.0) \
				+ sin(Time.get_ticks_msec() / 1000.0 * 2.0 + _bob_phase) * 0.35
	elif not is_on_floor():
		velocity.y -= _gravity * delta

	move_and_slide()

	# Les modèles glTF font face à +Z.
	var face := dir
	if face_player:
		face = player.global_position - global_position
	if Vector2(face.x, face.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), 8.0 * delta)
	_update_visual_motion(delta)


func _attack_allowed() -> bool:
	match _behavior:
		"stalker":
			return _commit
		"ambusher":
			return _state == "burst"
		_:
			return true


## Chemin navmesh vers la cible (ligne droite si pas encore bakée).
func _nav_dir_to(target: Vector3, delta: float) -> Vector3:
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.35
		_agent.target_position = target
	var dir := _agent.get_next_path_position() - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = target - global_position
		dir.y = 0.0
	return dir


func _eye() -> Vector3:
	return global_position + Vector3(0, 1.4, 0)


## Ligne de vue dégagée (aucun mur) entre le monstre et la caméra du joueur.
func _sees_player() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
			_eye(), player.camera.global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Le joueur a le monstre à l'écran (cône large) et sans obstacle.
func _player_watching() -> bool:
	var to_me := (_eye() - player.camera.global_position).normalized()
	var fwd := -player.camera.global_transform.basis.z
	return to_me.dot(fwd) > 0.55 and _sees_player()


## Le faisceau de la lampe torche éclaire le monstre.
func _in_flashlight() -> bool:
	if not player.flashlight.visible:
		return false
	var to_me := _eye() - player.flashlight.global_position
	if to_me.length() > 16.0:
		return false
	var fwd := -player.flashlight.global_transform.basis.z
	return to_me.normalized().dot(fwd) > 0.9 and _sees_player()


func _wander(delta: float) -> Vector3:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(2.0, 5.0)
		if randf() < 0.3:
			_wander_dir = Vector3.ZERO
		else:
			var a := randf() * TAU
			_wander_dir = Vector3(cos(a), 0.0, sin(a))
	return _wander_dir


func _setup_motion_rig() -> void:
	if _model == null:
		return
	_base_model_pos = _model.position
	_base_model_rot = _model.rotation
	_motion_phase = randf() * TAU

	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skel = skels[0]
		_find_motion_bones()

	for node: Node in _model.find_children("*", "Node3D", true, false):
		var part := node as Node3D
		if part == null or part is Skeleton3D:
			continue
		_register_motion_part(part)


func _find_motion_bones() -> void:
	if _skel == null:
		return
	for i in _skel.get_bone_count():
		var n := _skel.get_bone_name(i).to_lower()
		if _bone_hips < 0 and (n.contains("hips") or n.contains("pelvis")):
			_bone_hips = i
		elif _bone_l_arm < 0 and n.contains("leftarm") and not n.contains("fore") \
				and not n.contains("hand"):
			_bone_l_arm = i
		elif _bone_r_arm < 0 and n.contains("rightarm") and not n.contains("fore") \
				and not n.contains("hand"):
			_bone_r_arm = i
		elif _bone_l_fore < 0 and n.contains("leftforearm"):
			_bone_l_fore = i
		elif _bone_r_fore < 0 and n.contains("rightforearm"):
			_bone_r_fore = i
		elif _bone_l_leg < 0 and (n.contains("leftupleg") or n.contains("leftthigh")):
			_bone_l_leg = i
		elif _bone_r_leg < 0 and (n.contains("rightupleg") or n.contains("rightthigh")):
			_bone_r_leg = i
		elif _bone_l_foot < 0 and n.contains("leftfoot"):
			_bone_l_foot = i
		elif _bone_r_foot < 0 and n.contains("rightfoot"):
			_bone_r_foot = i
	if _bone_l_arm < 0 and _bone_r_arm < 0 and _bone_l_leg < 0 and _bone_r_leg < 0:
		_infer_motion_bones_from_rest()


func _infer_motion_bones_from_rest() -> void:
	var poses := []
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for i in _skel.get_bone_count():
		var p := _skel.get_bone_global_rest(i).origin
		poses.append({"idx": i, "pos": p})
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var width := maxf(max_x - min_x, 0.01)
	var height := maxf(max_y - min_y, 0.01)
	var center_x := (min_x + max_x) * 0.5
	for entry in poses:
		var idx: int = entry["idx"]
		if _skel.get_bone_parent(idx) < 0:
			continue
		var p: Vector3 = entry["pos"]
		var side := p.x - center_x
		if absf(side) < width * 0.12:
			continue
		var y_norm := (p.y - min_y) / height
		if y_norm > 0.38:
			if side < 0.0:
				_generic_left_bones.append(idx)
			else:
				_generic_right_bones.append(idx)
		elif y_norm > 0.08:
			_generic_leg_bones.append(idx)


func _register_motion_part(part: Node3D) -> void:
	var n := part.name.to_lower()
	var direct_name := not n.contains("_")
	if n.begins_with("leftarm") and direct_name:
		_left_parts.append(part)
	elif n.begins_with("rightarm") and direct_name:
		_right_parts.append(part)
	elif n.begins_with("legs") and direct_name:
		_leg_parts.append(part)
	elif n.begins_with("leftfinger") and direct_name:
		_left_parts.append(part)
	elif n.begins_with("rightfinger") and direct_name:
		_right_parts.append(part)
	if _left_parts.has(part) or _right_parts.has(part) or _leg_parts.has(part):
		_part_rest_rot[part] = part.rotation


func _update_visual_motion(delta: float) -> void:
	if _model == null:
		return
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var moving := planar_speed > 0.18 and not _frozen and not _dying
	var speed_ratio := clampf(planar_speed / maxf(_speed, 0.01), 0.0, 1.6)
	var target_blend := 1.0 if moving else 0.0
	_motion_blend = move_toward(_motion_blend, target_blend, delta * (6.0 if moving else 4.0))
	_motion_phase += delta * lerpf(4.0, 8.2, clampf(speed_ratio, 0.0, 1.0)) \
			* maxf(_motion_blend, 0.18)

	if _anim != null and _walk_anim != "":
		if not _anim.is_playing():
			_anim.play(_walk_anim)
		_anim.speed_scale = lerpf(0.0, 1.35, clampf(speed_ratio, 0.0, 1.0)) \
				* _motion_blend

	var stride := sin(_motion_phase)
	var opposite := sin(_motion_phase + PI)
	var bounce := absf(sin(_motion_phase * 2.0))
	var idle := sin(Time.get_ticks_msec() / 1000.0 * 1.4 + _bob_phase)
	var body_amount := maxf(_motion_blend, 0.18)
	var float_mul := 0.35 if _floats else 1.0
	_model.position = _base_model_pos + Vector3(0.0,
			(bounce * 0.045 * _motion_blend + idle * 0.012 * (1.0 - _motion_blend)) \
					* float_mul,
			0.0)
	_model.rotation = _base_model_rot + Vector3(
			stride * 0.035 * _motion_blend,
			0.0,
			opposite * 0.045 * body_amount)

	if _anim == null:
		_apply_bone_motion(stride, opposite, speed_ratio)
	_apply_part_motion(stride, opposite, speed_ratio)


func _apply_bone_motion(stride: float, opposite: float, speed_ratio: float) -> void:
	if _skel == null:
		return
	var blend := _motion_blend
	var arm_amp := lerpf(0.25, 0.75, clampf(speed_ratio, 0.0, 1.0)) * blend
	var leg_amp := lerpf(0.18, 0.55, clampf(speed_ratio, 0.0, 1.0)) * blend
	var bend := (0.18 + absf(stride) * 0.18) * blend
	_pose_bone(_bone_l_arm, Quaternion(Vector3(1, 0, 0), stride * arm_amp))
	_pose_bone(_bone_r_arm, Quaternion(Vector3(1, 0, 0), opposite * arm_amp))
	_pose_bone(_bone_l_fore, Quaternion(Vector3(1, 0, 0), bend))
	_pose_bone(_bone_r_fore, Quaternion(Vector3(1, 0, 0), bend))
	_pose_bone(_bone_l_leg, Quaternion(Vector3(1, 0, 0), opposite * leg_amp))
	_pose_bone(_bone_r_leg, Quaternion(Vector3(1, 0, 0), stride * leg_amp))
	_pose_bone(_bone_l_foot, Quaternion(Vector3(1, 0, 0), -stride * 0.22 * blend))
	_pose_bone(_bone_r_foot, Quaternion(Vector3(1, 0, 0), -opposite * 0.22 * blend))
	_pose_bone(_bone_hips, Quaternion(Vector3(0, 0, 1), opposite * 0.08 * blend))
	for idx in _generic_left_bones:
		_pose_bone(idx, Quaternion(Vector3(1, 0, 0), stride * arm_amp * 0.45))
	for idx in _generic_right_bones:
		_pose_bone(idx, Quaternion(Vector3(1, 0, 0), opposite * arm_amp * 0.45))
	for idx in _generic_leg_bones:
		_pose_bone(idx, Quaternion(Vector3(1, 0, 0), sin(_motion_phase * 2.0) * leg_amp * 0.25))


func _pose_bone(idx: int, extra: Quaternion) -> void:
	if idx < 0 or _skel == null:
		return
	var parent := _skel.get_bone_parent(idx)
	var parent_rot := Quaternion(0.0, 0.0, 0.0, 1.0)
	if parent >= 0:
		parent_rot = _skel.get_bone_global_rest(parent).basis.get_rotation_quaternion()
	var rest := _skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
	_skel.set_bone_pose_rotation(idx, parent_rot.inverse() * (extra * rest))


func _apply_part_motion(stride: float, opposite: float, speed_ratio: float) -> void:
	var amp := lerpf(0.22, 0.75, clampf(speed_ratio, 0.0, 1.0)) * _motion_blend
	for part in _left_parts:
		var rest: Vector3 = _part_rest_rot.get(part, part.rotation)
		part.rotation = rest + Vector3(stride * amp, 0.0, opposite * 0.18 * _motion_blend)
	for part in _right_parts:
		var rest: Vector3 = _part_rest_rot.get(part, part.rotation)
		part.rotation = rest + Vector3(opposite * amp, 0.0, stride * 0.18 * _motion_blend)
	for part in _leg_parts:
		var rest: Vector3 = _part_rest_rot.get(part, part.rotation)
		part.rotation = rest + Vector3(stride * amp * 0.45, 0.0,
				sin(_motion_phase * 2.0) * 0.18 * _motion_blend)


static func combined_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var xform := Transform3D.IDENTITY
			var p: Node = n
			while p != null and p != root:
				if p is Node3D:
					xform = p.transform * xform
				p = p.get_parent()
			var aabb: AABB = xform * n.mesh.get_aabb()
			if first:
				result = aabb
				first = false
			else:
				result = result.merge(aabb)
		for c in n.get_children():
			stack.append(c)
	return result
