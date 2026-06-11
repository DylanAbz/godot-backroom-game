class_name Monster
extends CharacterBody3D

## Monstre générique : charge n'importe quel GLB, le normalise à une hauteur
## cible (les modèles ont des échelles très variées), puis poursuit le joueur
## via le navmesh (repli en ligne droite si pas de chemin).

const DETECT_RANGE := 30.0
const DESPAWN_RANGE := 70.0
const DAMAGE := 18.0
const ATTACK_COOLDOWN := 1.3

var cfg := {}
var player: PlayerController
var health := 90.0

var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _model: Node3D
var _dying := false
var _stagger := 0.0
var _speed := 4.0
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
			_anim.get_animation(list[0]).loop_mode = Animation.LOOP_LINEAR
			_anim.play(list[0])


## Coup reçu : dégâts, recul et bref étourdissement ; mort en dessous de 0.
func take_hit(damage: float, knockback: Vector3) -> void:
	if _dying:
		return
	health -= damage
	_stagger = 0.45
	velocity += knockback
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
	if _stagger > 0.0:
		# Sonné : subit le recul avec friction, sans poursuivre.
		_stagger -= delta
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		if not _floats and not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return
	var hunting := player != null and is_instance_valid(player) and not player.dead
	var dist := INF
	if hunting:
		dist = global_position.distance_to(player.global_position)
		if dist > DESPAWN_RANGE:
			queue_free()
			return
	var chasing := hunting and dist <= DETECT_RANGE

	var dir := Vector3.ZERO
	if chasing:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.35
			_agent.target_position = player.global_position
		dir = _agent.get_next_path_position() - global_position
		dir.y = 0.0
		if dir.length() < 0.05:
			# Pas de chemin (navmesh pas encore prêt) : ligne droite.
			dir = player.global_position - global_position
			dir.y = 0.0
		if dist <= _attack_range:
			# Reste à distance d'attaque au lieu de fusionner avec la caméra.
			dir = Vector3.ZERO
			if _attack_cd <= 0.0:
				_attack_cd = ATTACK_COOLDOWN
				player.take_damage(DAMAGE)
	else:
		dir = _wander(delta)

	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	var speed := _speed if chasing else _speed * 0.45
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	if _floats:
		var target_y := global_position.y
		if chasing:
			target_y = player.global_position.y + _hover
		velocity.y = clampf((target_y - global_position.y) * 2.0, -2.0, 2.0) \
				+ sin(Time.get_ticks_msec() / 1000.0 * 2.0 + _bob_phase) * 0.35
	elif not is_on_floor():
		velocity.y -= _gravity * delta

	move_and_slide()

	# Les modèles glTF font face à +Z.
	var face := dir
	if chasing:
		face = player.global_position - global_position
	if Vector2(face.x, face.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), 8.0 * delta)


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
