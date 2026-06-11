class_name GameManager
extends Node3D

## Orchestre la partie : environnement (brouillard, ambiance), chargement des
## niveaux, joueur, spawner de monstres, néons vacillants, portail de sortie
## placé aléatoirement loin du spawn, écrans de fin.
##
## Mode capture : lancer avec `-- --screenshot` pour générer des captures dans
## tools/screenshots/ puis quitter (vérification automatisée).

const LEVELS := [
	{"maze": true, "name": "Niveau 0 — Le Grand Labyrinthe", "lights": 44},
	{"path": "res://assets/original_backrooms.glb", "name": "Niveau 1 — Les Backrooms", "lights": 12},
	{"path": "res://assets/backrooms_another_level.glb", "name": "Niveau 2 — Plus profond", "lights": 26},
]
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SPAWN_POS := Vector3(0, 1.0, 0)

var level_index := 0
var level: LevelRoot
var player: PlayerController
var hud: HUD
var spawner: MonsterSpawner
var portal: Area3D
var game_over := false

var _lights: Array[Dictionary] = []
var _screenshot_mode := false
var _portal_mat: StandardMaterial3D
var _portal_light: OmniLight3D


func _ready() -> void:
	_screenshot_mode = "--screenshot" in OS.get_cmdline_user_args()
	_setup_environment()
	hud = HUD.new()
	add_child(hud)
	spawner = MonsterSpawner.new()
	add_child(spawner)
	add_child(AmbientAudio.new())
	_load_level()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.35)
	env.ambient_light_energy = 0.24
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.14, 0.08)
	env.fog_density = 0.035
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.6, 0.55, 0.35)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _load_level() -> void:
	_clear_lights()
	if portal != null and is_instance_valid(portal):
		portal.queue_free()
		portal = null
	if level != null and is_instance_valid(level):
		level.queue_free()
	var info: Dictionary = LEVELS[level_index]
	level = MazeLevel.new() if info.get("maze", false) else LevelRoot.new()
	if info.has("path"):
		level.model_path = info["path"]
	level.collisions_ready.connect(_on_collisions_ready, CONNECT_ONE_SHOT)
	level.nav_ready.connect(_on_nav_ready, CONNECT_ONE_SHOT)
	if level is MazeLevel:
		level.note_read.connect(func(text: String) -> void: hud.show_note(text))
		level.key_taken.connect(_on_key_taken)
	add_child(level)


func _on_collisions_ready() -> void:
	if player == null:
		player = PLAYER_SCENE.instantiate()
		add_child(player)
		player.health_changed.connect(hud.set_health)
		player.stamina_changed.connect(hud.set_stamina)
		player.damaged.connect(hud.flash_damage)
		player.died.connect(_on_player_died)
		player.focus_changed.connect(hud.set_prompt)
		spawner.player = player
	player.global_position = SPAWN_POS
	player.velocity = Vector3.ZERO
	spawner.active = true
	hud.show_level_name(LEVELS[level_index]["name"])
	if level is MazeLevel:
		hud.set_objective("Suivez les flèches jaunes · La clé est sous la lumière rouge")
	else:
		hud.set_objective("Trouvez le portail de sortie")
	if _screenshot_mode:
		_screenshot_mode = false
		_screenshot_flow()


func _on_nav_ready() -> void:
	# Laisse le serveur de navigation synchroniser la région bakée.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_place_portal()
	_place_flicker_lights()


func _place_portal() -> void:
	var best := Vector3.ZERO
	if level.exit_hint != Vector3.INF:
		# Niveau généré : la sortie est imposée par le générateur.
		best = level.exit_hint
	else:
		var map := get_world_3d().navigation_map
		var best_d := -1.0
		for i in 48:
			var p := NavigationServer3D.map_get_random_point(map, 1, true)
			if p.y > SPAWN_POS.y + 1.5:
				# Point sur le toit ou hors zone jouable : ignoré.
				continue
			var d := p.distance_to(SPAWN_POS)
			if d > best_d:
				best_d = d
				best = p
		if best_d < 5.0:
			return
	portal = Area3D.new()
	portal.collision_layer = 0
	portal.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.2, 1.4)
	shape.shape = box
	shape.position.y = 1.1
	portal.add_child(shape)
	# Porte lumineuse : seule source claire du niveau, visible de loin.
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 2.2, 0.25)
	_portal_mat = StandardMaterial3D.new()
	_portal_mat.emission_enabled = true
	_portal_mat.emission = Color(0.85, 1.0, 0.9)
	_portal_mat.emission_energy_multiplier = 2.5
	_portal_mat.albedo_color = Color(0.1, 0.12, 0.1)
	bm.material = _portal_mat
	mesh.mesh = bm
	mesh.position.y = 1.1
	portal.add_child(mesh)
	_portal_light = OmniLight3D.new()
	_portal_light.light_color = Color(0.7, 1.0, 0.85)
	_portal_light.light_energy = 2.0
	_portal_light.omni_range = 8.0
	_portal_light.position.y = 1.5
	portal.add_child(_portal_light)
	portal.body_entered.connect(_on_portal_entered)
	add_child(portal)
	portal.global_position = best
	if level is MazeLevel and not level.key_collected:
		# Porte verrouillée : lueur rouge tant que la clé n'est pas trouvée.
		_portal_mat.emission = Color(1.0, 0.25, 0.18)
		_portal_mat.emission_energy_multiplier = 1.2
		_portal_light.light_color = Color(1.0, 0.3, 0.2)
		_portal_light.light_energy = 1.2


func _on_key_taken() -> void:
	hud.show_toast("Vous avez la clé ! Retournez à la porte SORTIE.")
	hud.set_objective("Suivez les flèches jaunes jusqu'à la porte SORTIE")
	if _portal_mat != null:
		_portal_mat.emission = Color(0.85, 1.0, 0.9)
		_portal_mat.emission_energy_multiplier = 2.5
	if _portal_light != null and is_instance_valid(_portal_light):
		_portal_light.light_color = Color(0.7, 1.0, 0.85)
		_portal_light.light_energy = 2.0


func _on_portal_entered(body: Node3D) -> void:
	if body != player or game_over:
		return
	if level is MazeLevel and not level.key_collected:
		hud.show_toast("La porte est verrouillée. Trouvez la clé sous la lumière rouge.")
		return
	level_index += 1
	if level_index >= LEVELS.size():
		game_over = true
		player.dead = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.show_win()
		return
	spawner.active = false
	spawner.clear()
	_load_level()


func _place_flicker_lights() -> void:
	var map := get_world_3d().navigation_map
	var count: int = LEVELS[level_index].get("lights", 16)
	for i in count:
		var p := NavigationServer3D.map_get_random_point(map, 1, true)
		if p.y > SPAWN_POS.y + 1.5:
			continue
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.93, 0.68)
		light.light_energy = 0.5
		light.omni_range = 5.0
		add_child(light)
		light.global_position = p + Vector3(0, 2.3, 0)
		_lights.append({
			"node": light,
			"phase": randf() * TAU,
			"next_flick": randf_range(2.0, 15.0),
			"flick_end": 0.0,
		})


func _clear_lights() -> void:
	for entry in _lights:
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
	_lights.clear()


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry in _lights:
		var light: OmniLight3D = entry["node"]
		if not is_instance_valid(light):
			continue
		entry["next_flick"] -= delta
		entry["flick_end"] -= delta
		if entry["next_flick"] <= 0.0:
			entry["next_flick"] = randf_range(3.0, 18.0)
			entry["flick_end"] = randf_range(0.06, 0.3)
		if entry["flick_end"] > 0.0:
			light.light_energy = 0.05
		else:
			light.light_energy = 0.5 * (0.85 + 0.15 * sin(t * 7.0 + entry["phase"]))


func _unhandled_input(event: InputEvent) -> void:
	if game_over and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _on_player_died() -> void:
	game_over = true
	hud.show_death()


# --- Mode capture automatisée ---------------------------------------------

func _screenshot_flow() -> void:
	await get_tree().create_timer(2.0).timeout
	DirAccess.make_dir_recursive_absolute("res://tools/screenshots")
	await _capture("shot_forward.png")
	player.head.rotation.x = -1.1
	await get_tree().create_timer(0.2).timeout
	await _capture("shot_down.png")
	player.head.rotation.x = 0.0
	var fwd: Vector3 = -player.global_transform.basis.z
	spawner.spawn_at(player.global_position + fwd * 5.0, 0)
	await get_tree().create_timer(1.2).timeout
	await _capture("shot_monster.png")
	# Vérification du combat : un coup de tuyau sur un monstre proche.
	var victim := spawner.spawn_at(player.global_position + fwd * 1.8, 2)
	await get_tree().create_timer(0.4).timeout
	player._try_attack()
	await get_tree().create_timer(0.18).timeout
	await _capture("shot_combat.png")
	player._try_attack()
	await get_tree().create_timer(0.8).timeout
	player._try_attack()
	await get_tree().create_timer(0.5).timeout
	await _capture("shot_combat_kill.png")
	if is_instance_valid(victim):
		victim.queue_free()
	if level is MazeLevel:
		var key_pos: Vector3 = level.cell_center(level.key_cell)
		player.global_position = key_pos + Vector3(0, 0.3, 2.5)
		player.rotation.y = 0.0
		player.head.rotation.x = -0.15
		await get_tree().create_timer(0.4).timeout
		await _capture("shot_key.png")
		player.head.rotation.x = 0.0
	# Vérification du portail : téléporte le joueur devant.
	for i in 600:
		if portal != null:
			break
		await get_tree().process_frame
	if portal != null:
		var p := portal.global_position
		player.global_position = p + Vector3(0, 0.3, 3.5)
		var to_portal := p - player.global_position
		player.rotation.y = atan2(-to_portal.x, -to_portal.z)
		player.head.rotation.x = 0.0
		await get_tree().create_timer(0.4).timeout
		await _capture("shot_portal.png")
	# Vérification du second niveau.
	spawner.active = false
	spawner.clear()
	level_index = 1
	_load_level()
	await level.collisions_ready
	await level.nav_ready
	await get_tree().create_timer(2.0).timeout
	await _capture("shot_level2.png")
	get_tree().quit()


func _capture(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshots/" + fname)
