class_name MonsterSpawner
extends Node3D

## Fait apparaître des monstres aléatoires autour du joueur (hors de vue,
## entre 16 et 32 m), posés au sol par raycast. Les deux modèles hazmat sont
## exclus : ce sont des personnages jouables.

const TYPES := [
	{"model": "res://assets/character/partygoer_from_backrooms.glb", "height": 2.1,
		"speed": 4.2, "hp": 110.0, "behavior": "stalker", "damage": 24.0, "atk_cd": 1.5},
	{"model": "res://assets/character/bacteria_-_kane_pixels_backrooms.glb", "height": 2.4,
		"speed": 2.6, "hp": 190.0, "behavior": "brute", "damage": 32.0, "atk_cd": 2.0,
		"stagger_mult": 0.35},
	{"model": "res://assets/character/kitty_-_backrooms_entity.glb", "height": 2.0,
		"speed": 5.3, "hp": 70.0, "behavior": "rusher", "damage": 13.0, "atk_cd": 1.0},
	{"model": "res://assets/character/smiler_backrooms.glb", "height": 1.1,
		"speed": 4.0, "floats": true, "hover": 1.3, "hp": 80.0,
		"behavior": "smiler", "damage": 20.0, "atk_cd": 1.3},
	{"model": "res://assets/character/backrooms_smiler_rig.glb", "height": 1.7,
		"speed": 4.4, "hp": 95.0, "behavior": "smiler", "damage": 20.0, "atk_cd": 1.3},
	{"model": "res://assets/character/smiler_entity3_backrooms.glb", "height": 0.9,
		"speed": 5.0, "floats": true, "hover": 1.4, "hp": 60.0,
		"behavior": "ambusher", "damage": 16.0, "atk_cd": 1.1},
	# "Le Disparu" : silhouette noire au visage de photo (les affiches DISPARU
	# du niveau 0). Rare — voir PHOTO_CHANCE, jamais tiré au hasard uniforme.
	{"photo_face": true, "height": 2.2,
		"speed": 4.5, "hp": 120.0, "behavior": "smiler", "damage": 26.0, "atk_cd": 1.4},
]

const MAX_MONSTERS := 5
const MIN_SPAWN_DIST := 9.0
const PHOTO_CHANCE := 0.1

var active := false
var player: PlayerController
var monsters: Array[Monster] = []

var _next_spawn := 6.0


func _physics_process(delta: float) -> void:
	if not active or player == null or player.dead:
		return
	_next_spawn -= delta
	if _next_spawn <= 0.0:
		_next_spawn = randf_range(10.0, 18.0)
		_try_spawn()


func _try_spawn() -> void:
	# Pas de filter() typé ici : les instances libérées (mortes/despawn) ne
	# peuvent plus être converties en Monster par le lambda.
	var alive: Array[Monster] = []
	for m in monsters:
		if is_instance_valid(m):
			alive.append(m)
	monsters = alive
	if monsters.size() >= MAX_MONSTERS:
		return
	for attempt in 8:
		var ang := randf() * TAU
		var d := randf_range(10.0, 26.0)
		# Rayon lancé depuis sous le plafond (pas au-dessus du toit, sinon les
		# monstres apparaissent sur le bâtiment). Hors des murs : aucun sol
		# touché, la tentative est simplement rejetée.
		var origin := player.global_position + Vector3(cos(ang) * d, 1.5, sin(ang) * d)
		var hit := _raycast_down(origin)
		if hit == Vector3.INF:
			continue
		if absf(hit.y - player.global_position.y) > 2.0:
			continue
		if hit.distance_to(player.global_position) > MIN_SPAWN_DIST:
			var idx := TYPES.size() - 1 if randf() < PHOTO_CHANCE \
					else randi() % (TYPES.size() - 1)
			spawn_at(hit, idx)
			return


func spawn_at(pos: Vector3, type_idx: int) -> Monster:
	var m := Monster.new()
	m.cfg = TYPES[type_idx]
	m.player = player
	add_child(m)
	m.global_position = pos + Vector3(0, 0.2, 0)
	monsters.append(m)
	return m


func clear() -> void:
	for m in monsters:
		if is_instance_valid(m):
			m.queue_free()
	monsters.clear()


func _raycast_down(from: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30, 0), 1)
	var result := space.intersect_ray(query)
	return result.get("position", Vector3.INF)
