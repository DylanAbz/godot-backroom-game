class_name MazeLevel
extends LevelRoot

## Niveau généré : grand labyrinthe backrooms construit avec les pièces
## modulaires du pack Loafbrr (CC0). Murs/sols/plafonds rendus en MultiMesh
## (3-4 draw calls pour toute la map), collisions en BoxShape3D partagées
## (bien plus rapide à baker que des trimesh).
##
## Génération : recursive backtracker, puis salles ouvertes avec piliers,
## puis "braiding" (suppression de culs-de-sac) pour créer des boucles.
## Expose la cellule de sortie (la plus lointaine du spawn), une cellule
## pour la clé et le chemin spawn→sortie (utilisé pour poser des indices).

signal note_read(text: String)
signal key_taken
signal water_drunk

const CELL := 3.0
const W := 31
const H := 31
const WALL_T := 0.25
const PACK := "res://assets/BackroomsLikeAssetRe_Godot/LoafbrrAssets/BackroomsLikeAsset2/Scenes/"
const ROOM_COUNT := 5
const HALL_COUNT := 3
const CORRIDOR_COUNT := 9
const BRAID_RATIO := 0.6
const WALL_B_RATIO := 0.15

var spawn_cell := Vector2i(2, 2)
var exit_cell := Vector2i.ZERO
var key_cell := Vector2i.ZERO
var key_collected := false
## Chemin spawn → sortie en cellules (pour la piste d'indices).
var guide_cells: Array[Vector2i] = []
## Variante "humide" : flaques réfléchissantes, gouttes, néons plus instables.
var wet := false
## Centres (monde) des zones de panne : aucun néon n'y est placé.
var blackout_centers: Array[Vector3] = []

var _key_node: Node3D
var _key_light: OmniLight3D

# h_walls[x][y] : mur sur le bord nord (-Z) de la cellule (x,y), y ∈ 0..H.
# v_walls[x][y] : mur sur le bord ouest (-X) de la cellule (x,y), x ∈ 0..W.
var _h_walls: Array[PackedByteArray] = []
var _v_walls: Array[PackedByteArray] = []
var _rooms: Array[Rect2i] = []


func _create_content() -> Node3D:
	var root := Node3D.new()
	root.name = "Maze"
	wet = randf() < WET_CHANCE
	_generate_layout()
	_solve_layout()
	_pick_blackout_zones()
	_build_visuals(root)
	_build_colliders(root)
	exit_hint = cell_center(exit_cell)
	_place_props(root)
	return root


## Tire des zones circulaires de panne, loin du spawn, de la clé et de la
## sortie (leurs repères lumineux doivent rester visibles).
func _pick_blackout_zones() -> void:
	blackout_centers.clear()
	var protected: Array[Vector2i] = [spawn_cell, key_cell, exit_cell]
	for attempt in 60:
		if blackout_centers.size() >= BLACKOUT_COUNT:
			break
		var c := Vector2i(randi_range(3, W - 4), randi_range(3, H - 4))
		var center := cell_center(c)
		var ok := true
		for p in protected:
			if cell_center(p).distance_to(center) < BLACKOUT_RADIUS + 6.0:
				ok = false
				break
		for other in blackout_centers:
			if other.distance_to(center) < BLACKOUT_RADIUS * 2.0:
				ok = false
				break
		if ok:
			blackout_centers.append(center)


## Vrai si la position (monde) est dans une zone de panne de courant.
func is_blackout(p: Vector3) -> bool:
	for center in blackout_centers:
		if Vector2(p.x, p.z).distance_to(Vector2(center.x, center.z)) < BLACKOUT_RADIUS:
			return true
	return false


func _setup_collisions(_content: Node3D) -> void:
	pass  # Collisions déjà créées dans _create_content().


func _process(delta: float) -> void:
	if _key_node != null and is_instance_valid(_key_node):
		_key_node.rotate_y(delta * 1.8)


## Centre d'une cellule en coordonnées monde (le spawn est à l'origine).
func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x - spawn_cell.x) * CELL, 0.0, (c.y - spawn_cell.y) * CELL)


# --- Génération du plan ----------------------------------------------------

func _generate_layout() -> void:
	for x in W:
		var col := PackedByteArray()
		col.resize(H + 1)
		col.fill(1)
		_h_walls.append(col)
	for x in W + 1:
		var col := PackedByteArray()
		col.resize(H)
		col.fill(1)
		_v_walls.append(col)

	# Recursive backtracker.
	var visited: Array[PackedByteArray] = []
	for x in W:
		var col := PackedByteArray()
		col.resize(H)
		visited.append(col)
	var stack: Array[Vector2i] = [spawn_cell]
	visited[spawn_cell.x][spawn_cell.y] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.x < W and n.y >= 0 and n.y < H and visited[n.x][n.y] == 0:
				options.append(n)
		if options.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = options[randi() % options.size()]
		_remove_wall_between(c, next)
		visited[next.x][next.y] = 1
		stack.append(next)

	# Salles ouvertes (la première autour du spawn), piliers ajoutés au rendu.
	_carve_room(Rect2i(spawn_cell.x - 1, spawn_cell.y - 1, 3, 3))
	# Grands halls à piliers : l'identité visuelle des backrooms.
	for i in HALL_COUNT:
		var hw := randi_range(6, 9)
		var hh := randi_range(5, 8)
		_carve_room(Rect2i(randi_range(1, W - hw - 1), randi_range(1, H - hh - 1), hw, hh))
	for i in ROOM_COUNT:
		var rw := randi_range(3, 5)
		var rh := randi_range(3, 5)
		var rx := randi_range(1, W - rw - 1)
		var ry := randi_range(1, H - rh - 1)
		_carve_room(Rect2i(rx, ry, rw, rh))

	# Longs couloirs droits (parfois larges de 2 cellules) : casse l'effet
	# "labyrinthe de jardin" au profit de l'étage de bureaux infini.
	for i in CORRIDOR_COUNT:
		var length := randi_range(8, 18)
		var width := 2 if randf() < 0.35 else 1
		if randf() < 0.5:
			var x := randi_range(1, maxi(1, W - length - 1))
			var y := randi_range(1, H - width - 1)
			_carve_room(Rect2i(x, y, mini(length, W - 1 - x), width))
		else:
			var x := randi_range(1, W - width - 1)
			var y := randi_range(1, maxi(1, H - length - 1))
			_carve_room(Rect2i(x, y, width, mini(length, H - 1 - y)))

	# Braiding : ouvre une partie des culs-de-sac pour créer des boucles.
	for x in W:
		for y in H:
			var c := Vector2i(x, y)
			if _wall_count(c) == 3 and randf() < BRAID_RATIO:
				var dirs: Array[Vector2i] = []
				for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var n: Vector2i = c + d
					if n.x >= 0 and n.x < W and n.y >= 0 and n.y < H and _has_wall_between(c, n):
						dirs.append(n)
				if not dirs.is_empty():
					_remove_wall_between(c, dirs[randi() % dirs.size()])


func _carve_room(r: Rect2i) -> void:
	_rooms.append(r)
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y + 1, r.end.y):
			_h_walls[x][y] = 0
	for x in range(r.position.x + 1, r.end.x):
		for y in range(r.position.y, r.end.y):
			_v_walls[x][y] = 0


func _remove_wall_between(a: Vector2i, b: Vector2i) -> void:
	if b.y == a.y - 1:
		_h_walls[a.x][a.y] = 0
	elif b.y == a.y + 1:
		_h_walls[a.x][a.y + 1] = 0
	elif b.x == a.x - 1:
		_v_walls[a.x][a.y] = 0
	else:
		_v_walls[a.x + 1][a.y] = 0


func _has_wall_between(a: Vector2i, b: Vector2i) -> bool:
	if b.y == a.y - 1:
		return _h_walls[a.x][a.y] == 1
	if b.y == a.y + 1:
		return _h_walls[a.x][a.y + 1] == 1
	if b.x == a.x - 1:
		return _v_walls[a.x][a.y] == 1
	return _v_walls[a.x + 1][a.y] == 1


func _wall_count(c: Vector2i) -> int:
	var n := 0
	n += _h_walls[c.x][c.y]
	n += _h_walls[c.x][c.y + 1]
	n += _v_walls[c.x][c.y]
	n += _v_walls[c.x + 1][c.y]
	return n


## BFS depuis le spawn : sortie = cellule la plus lointaine, clé = cellule à
## mi-distance la plus éloignée de la sortie, chemin spawn→sortie mémorisé.
func _solve_layout() -> void:
	var dist: Array[PackedInt32Array] = []
	var parent := {}
	for x in W:
		var col := PackedInt32Array()
		col.resize(H)
		col.fill(-1)
		dist.append(col)
	dist[spawn_cell.x][spawn_cell.y] = 0
	var queue: Array[Vector2i] = [spawn_cell]
	var head := 0
	var far_cell := spawn_cell
	var far_d := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = dist[c.x][c.y]
		if d > far_d:
			far_d = d
			far_cell = c
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + dir
			if n.x < 0 or n.x >= W or n.y < 0 or n.y >= H:
				continue
			if dist[n.x][n.y] >= 0 or _has_wall_between(c, n):
				continue
			dist[n.x][n.y] = d + 1
			parent[n] = c
			queue.append(n)
	exit_cell = far_cell

	guide_cells.clear()
	var walk := exit_cell
	while walk != spawn_cell:
		guide_cells.push_front(walk)
		walk = parent[walk]
	guide_cells.push_front(spawn_cell)

	var best_score := -1.0
	key_cell = spawn_cell
	for x in W:
		for y in H:
			var d: int = dist[x][y]
			if d < int(far_d * 0.4) or d > int(far_d * 0.7):
				continue
			var c := Vector2i(x, y)
			if guide_cells.has(c):
				continue
			var score := Vector2(c - exit_cell).length()
			if score > best_score:
				best_score = score
				key_cell = c


# --- Construction ----------------------------------------------------------

func _build_visuals(root: Node3D) -> void:
	var wall_a_mesh := _module_mesh(PACK + "Wall/br_wall_a_3x_3.tscn")
	var wall_b_mesh := _module_mesh(PACK + "Wall/br_wall_b_3x_3.tscn")
	var floor_mesh := _module_mesh(PACK + "Floor/br_floor_3x_3.tscn")
	var post_mesh := _module_mesh(PACK + "Wall/br_wall_a_post_3m.tscn")

	# Sols (y=0) + plafonds : la même tuile posée à y=3, sa face inférieure
	# (matériau dalles BRC) devient le plafond à 2.75 m.
	var floor_xf: Array[Transform3D] = []
	for x in W:
		for y in H:
			var p := cell_center(Vector2i(x, y))
			floor_xf.append(Transform3D(Basis.IDENTITY, p))
			floor_xf.append(Transform3D(Basis.IDENTITY, p + Vector3(0, 3.0, 0)))
	root.add_child(_multimesh(floor_mesh, floor_xf, "Floors"))

	# Murs : variante B (plinthe) saupoudrée pour casser la répétition.
	var wall_a_xf: Array[Transform3D] = []
	var wall_b_xf: Array[Transform3D] = []
	for xf in _wall_transforms():
		if randf() < WALL_B_RATIO:
			wall_b_xf.append(xf)
		else:
			wall_a_xf.append(xf)
	root.add_child(_multimesh(wall_a_mesh, wall_a_xf, "WallsA"))
	root.add_child(_multimesh(wall_b_mesh, wall_b_xf, "WallsB"))

	# Piliers dans les salles (une intersection sur deux).
	var post_xf: Array[Transform3D] = []
	for r in _rooms:
		for x in range(r.position.x + 1, r.end.x):
			for y in range(r.position.y + 1, r.end.y):
				if (x - r.position.x) % 2 == 0 and (y - r.position.y) % 2 == 0:
					var corner := cell_center(Vector2i(x, y)) - Vector3(CELL / 2.0, 0, CELL / 2.0)
					post_xf.append(Transform3D(Basis.IDENTITY, corner))
	root.add_child(_multimesh(post_mesh, post_xf, "Posts"))


func _wall_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var rot90 := Basis(Vector3.UP, PI / 2.0)
	for x in W:
		for y in H + 1:
			if _h_walls[x][y] == 1:
				var p := cell_center(Vector2i(x, y)) + Vector3(0, 0, -CELL / 2.0)
				result.append(Transform3D(Basis.IDENTITY, p))
	for x in W + 1:
		for y in H:
			if _v_walls[x][y] == 1:
				var p := cell_center(Vector2i(x, y)) + Vector3(-CELL / 2.0, 0, 0)
				result.append(Transform3D(rot90, p))
	return result


func _build_colliders(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "MazeColliders"
	body.collision_layer = 1

	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(CELL, 3.0, WALL_T)
	for xf in _wall_transforms():
		var cs := CollisionShape3D.new()
		cs.shape = wall_shape
		cs.transform = xf.translated(Vector3(0, 1.5, 0))
		body.add_child(cs)

	var post_shape := BoxShape3D.new()
	post_shape.size = Vector3(0.4, 3.0, 0.4)
	for r in _rooms:
		for x in range(r.position.x + 1, r.end.x):
			for y in range(r.position.y + 1, r.end.y):
				if (x - r.position.x) % 2 == 0 and (y - r.position.y) % 2 == 0:
					var cs := CollisionShape3D.new()
					cs.shape = post_shape
					cs.position = cell_center(Vector2i(x, y)) \
							- Vector3(CELL / 2.0, -1.5, CELL / 2.0)
					body.add_child(cs)

	# Sol et plafond : deux grandes boîtes couvrant tout le labyrinthe.
	var center := (cell_center(Vector2i.ZERO) + cell_center(Vector2i(W - 1, H - 1))) / 2.0
	var floor_cs := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(W * CELL, 0.5, H * CELL)
	floor_cs.shape = floor_shape
	floor_cs.position = center + Vector3(0, -0.25, 0)
	body.add_child(floor_cs)
	var ceil_cs := CollisionShape3D.new()
	var ceil_shape := BoxShape3D.new()
	ceil_shape.size = Vector3(W * CELL, 0.25, H * CELL)
	ceil_cs.shape = ceil_shape
	ceil_cs.position = center + Vector3(0, 2.875, 0)
	body.add_child(ceil_cs)

	root.add_child(body)


# --- Props : indices, clé, sortie ------------------------------------------

const NOTE_SPAWN := "Jour 41 dans le labyrinthe.\n\nJ'ai peint des flèches JAUNES au sol : elles mènent à la PORTE.\nMais elle est verrouillée de l'autre côté.\n\nLa CLÉ est cachée sous la LUMIÈRE ROUGE.\n\nNe cours pas trop longtemps. Ils t'entendent.\n— M."
const NOTE_MIDWAY := "Tu es à mi-chemin. Les flèches ne mentent pas.\n\nSi tu n'as pas encore la clé, cherche la lueur rouge dans les couloirs.\n— M."
const NOTE_KEY := "C'est là. La lumière rouge.\n\nPrends la clé et NE TE RETOURNE PAS.\n— M."
const SCRAWLS: Array[String] = [
	"ILS T'ENTENDENT",
	"N'ÉTEINS PAS LA LAMPE",
	"PAS DE SOMMEIL",
	"NE RESTE PAS ICI",
	"SOUS LA LUMIÈRE ROUGE",
	"COURS",
	"DERRIÈRE TOI ?",
]

## Police "écrite avec les doigts" (Sinister Sunday, licence non commerciale).
const BLOOD_FONT := preload("res://assets/fonts/sinister-sunday/Sinister Sunday.otf")
const BLACKOUT_COUNT := 3
const BLACKOUT_RADIUS := 10.0  # m
## Proportion de parties où le niveau 0 est "humide" (flaques, gouttes).
const WET_CHANCE := 0.35

const PHOTO_DIR := "res://assets/images/"
const POSTER_COUNT := 14
## Messages écrits au sang près des affiches de disparus.
const PHOTO_MESSAGES: Array[String] = [
	"TU L'AS VU ?",
	"ILS ÉTAIENT QUATRE",
	"ELLE SOURIT ENCORE",
	"IL NE CLIGNE JAMAIS DES YEUX",
	"NE LEUR PARLE PAS",
	"C'ÉTAIT MON AMI",
	"ILS ME SUIVENT",
	"CE N'EST PLUS LUI",
]


func _place_props(root: Node3D) -> void:
	_place_guide_arrows(root)
	_place_key(root)
	# Note d'intro sur un mur de la salle de spawn, face au joueur.
	_place_note(root, spawn_cell + Vector2i.UP, NOTE_SPAWN)
	if guide_cells.size() > 8:
		_place_note(root, guide_cells[guide_cells.size() / 2], NOTE_MIDWAY)
	_place_note(root, _neighbor_towards(key_cell, spawn_cell), NOTE_KEY)
	_place_exit_dressing(root)
	for i in 10:
		var c := Vector2i(randi_range(1, W - 2), randi_range(1, H - 2))
		_place_scrawl(root, c, SCRAWLS[randi() % SCRAWLS.size()])
	_place_photos(root)
	_place_almond_water(root)
	_place_puddles(root)
	_place_drip_emitters(root)


## Affiches "DISPARU" : les photos de assets/images placardées au hasard sur
## les murs, avec un message au sang (et ses coulures) sur un mur tout proche.
func _place_photos(root: Node3D) -> void:
	var textures := load_photo_textures()
	if textures.is_empty():
		return
	for i in POSTER_COUNT:
		var c := Vector2i(randi_range(1, W - 2), randi_range(1, H - 2))
		if Vector2(c - spawn_cell).length() < 3.0 or c == key_cell or c == exit_cell:
			continue
		var anchor := _wall_anchor(c, randf_range(1.4, 1.6))
		if anchor == Transform3D.IDENTITY:
			continue
		var msg_text := PHOTO_MESSAGES[randi() % PHOTO_MESSAGES.size()]
		root.add_child(_make_poster(textures[i % textures.size()], anchor, msg_text))
		_place_blood_trail(root, c, anchor)
		# Le message au sang : sur la même cellule ou une voisine accessible.
		var msg_cell := c
		if randf() < 0.6:
			msg_cell = _neighbor_towards(c,
					Vector2i(randi_range(0, W - 1), randi_range(0, H - 1)))
		_place_blood_message(root, msg_cell, msg_text)


## Traînée de sang au sol : éclaboussures de plus en plus grosses qui mènent
## du couloir jusqu'au pied de l'affiche, où une mare s'est formée.
func _place_blood_trail(root: Node3D, cell: Vector2i, poster_anchor: Transform3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.02, 0.015, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.35
	var foot := poster_anchor.origin
	foot.y = 0.0
	var start := cell_center(_neighbor_towards(cell,
			Vector2i(randi_range(0, W - 1), randi_range(0, H - 1))))
	var count := randi_range(5, 8)
	for i in count:
		var f := float(i) / float(count - 1)
		var pos := start.lerp(foot, f) \
				+ Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)) * (1.0 - f)
		root.add_child(_floor_splat(mat, pos, lerpf(0.1, 0.35, f)))
	# La mare au pied du mur.
	root.add_child(_floor_splat(mat, foot, randf_range(0.5, 0.8)))


## Tache plate posée sur le sol (forme légèrement aplatie et orientée au hasard).
func _floor_splat(mat: StandardMaterial3D, pos: Vector3, radius: float) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(radius * 2.0, radius * randf_range(1.3, 2.0))
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos + Vector3(0, 0.012, 0)
	mi.rotation.y = randf() * TAU
	return mi


## Flaques au sol : quelques taches d'humidité sombres, ou partout en mode
## humide (surface lisse → reflets spéculaires des néons).
func _place_puddles(root: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.045, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.04
	mat.metallic = 0.6
	for i in (60 if wet else 10):
		var c := Vector2i(randi_range(1, W - 2), randi_range(1, H - 2))
		var pos := cell_center(c) + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		root.add_child(_floor_splat(mat, pos, randf_range(0.35, 1.0)))


## Gouttes d'eau : émetteurs 3D qui jouent un "plip" à intervalle aléatoire.
func _place_drip_emitters(root: Node3D) -> void:
	for i in (24 if wet else 8):
		var c := Vector2i(randi_range(1, W - 2), randi_range(1, H - 2))
		var sp := AudioStreamPlayer3D.new()
		sp.stream = HorrorAudio.water_drip()
		sp.max_distance = 14.0
		sp.unit_size = 4.0
		sp.volume_db = -6.0
		sp.position = cell_center(c) + Vector3(0, 2.4, 0)
		root.add_child(sp)
		var timer := Timer.new()
		timer.one_shot = true
		sp.add_child(timer)
		timer.timeout.connect(func() -> void:
			sp.pitch_scale = randf_range(0.8, 1.3)
			sp.play()
			timer.start(randf_range(1.5, 6.0) if wet else randf_range(4.0, 14.0)))
		timer.call_deferred("start", randf_range(0.5, 8.0))


## Charge toutes les images du dossier (les `.import` listés par DirAccess
## dans un build exporté sont ramenés au nom de la ressource). Statique :
## aussi utilisée par Monster pour le visage du "Disparu".
static func load_photo_textures() -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var dir := DirAccess.open(PHOTO_DIR)
	if dir == null:
		return result
	var seen := {}
	for f in dir.get_files():
		var fname := f.trim_suffix(".import")
		if seen.has(fname):
			continue
		seen[fname] = true
		if not fname.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			continue
		var tex := load(PHOTO_DIR + fname)
		if tex is Texture2D:
			result.append(tex)
	result.shuffle()
	return result


func _make_poster(tex: Texture2D, anchor: Transform3D, blood_text: String) -> Node3D:
	var poster := Node3D.new()
	poster.transform = anchor
	poster.add_to_group("photo_posters")
	# Légèrement de travers, comme scotchée à la va-vite.
	poster.rotate_object_local(Vector3.FORWARD, randf_range(-0.07, 0.07))

	var paper := MeshInstance3D.new()
	var pm := QuadMesh.new()
	pm.size = Vector2(0.42, 0.58)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.87, 0.85, 0.76)
	pmat.emission_enabled = true
	pmat.emission = Color(0.87, 0.85, 0.76)
	pmat.emission_energy_multiplier = 0.10
	pmat.roughness = 0.95
	pm.material = pmat
	paper.mesh = pm
	poster.add_child(paper)

	var header := Label3D.new()
	header.text = "DISPARU"
	header.font_size = 60
	header.pixel_size = 0.0021
	header.modulate = Color(0.14, 0.11, 0.1)
	header.position = Vector3(0, 0.235, 0.004)
	poster.add_child(header)

	var photo := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var pw := 0.3
	var ph := clampf(pw * float(tex.get_height()) / maxf(float(tex.get_width()), 1.0),
			0.22, 0.38)
	qm.size = Vector2(pw, ph)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 0.08
	mat.roughness = 0.9
	qm.material = mat
	photo.mesh = qm
	photo.position = Vector3(0, -0.01, 0.004)
	poster.add_child(photo)

	var footer := Label3D.new()
	footer.text = "VU POUR LA DERNIÈRE FOIS : NIVEAU 0"
	footer.font_size = 30
	footer.pixel_size = 0.0011
	footer.modulate = Color(0.2, 0.16, 0.15)
	footer.position = Vector3(0, -0.245, 0.004)
	poster.add_child(footer)

	_add_poster_blood_message(poster, blood_text)

	# On chuchote près des affiches… et parfois un rire lointain.
	var breath := AudioStreamPlayer3D.new()
	breath.stream = HorrorAudio.whisper()
	breath.max_distance = 8.0
	breath.unit_size = 2.5
	breath.volume_db = -9.0
	breath.autoplay = true
	poster.add_child(breath)
	var laugh := AudioStreamPlayer3D.new()
	laugh.stream = preload("res://assets/audio/witch_laugh.mp3")
	laugh.max_distance = 18.0
	laugh.unit_size = 5.0
	laugh.volume_db = -10.0
	poster.add_child(laugh)
	var timer := Timer.new()
	timer.one_shot = true
	laugh.add_child(timer)
	timer.timeout.connect(func() -> void:
		laugh.pitch_scale = randf_range(0.7, 0.95)
		laugh.play()
		timer.start(randf_range(40.0, 120.0)))
	timer.call_deferred("start", randf_range(20.0, 90.0))
	return poster


## Graffiti sanglant collé au même mur que l'affiche : plus lisible que le
## message secondaire aléatoire, et toujours visible près de la photo.
func _add_poster_blood_message(poster: Node3D, text: String) -> void:
	var label := _blood_label_node(text, 0.0048, Color(0.5, 0.015, 0.01, 0.98))
	label.font_size = 76
	label.position = Vector3(randf_range(-1.05, -0.82) if randf() < 0.5
			else randf_range(0.82, 1.05), randf_range(-0.08, 0.22), 0.007)
	label.rotate_object_local(Vector3.FORWARD, randf_range(-0.16, 0.16))
	poster.add_child(label)

	var drip_mat := StandardMaterial3D.new()
	drip_mat.albedo_color = Color(0.36, 0.01, 0.008, 0.9)
	drip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drip_mat.roughness = 0.42
	for i in randi_range(5, 9):
		var dm := QuadMesh.new()
		dm.size = Vector2(randf_range(0.012, 0.04), randf_range(0.16, 0.55))
		dm.material = drip_mat
		var drip := MeshInstance3D.new()
		drip.mesh = dm
		drip.position = Vector3(label.position.x + randf_range(-0.55, 0.55),
				label.position.y - randf_range(0.15, 0.45), 0.006)
		poster.add_child(drip)


## Message écrit au sang, avec des coulures qui dégoulinent sous les lettres.
func _place_blood_message(root: Node3D, cell: Vector2i, text: String) -> void:
	var anchor := _wall_anchor(cell, randf_range(1.45, 1.85))
	if anchor == Transform3D.IDENTITY:
		return
	root.add_child(_blood_label(text, anchor, 0.0042, Color(0.5, 0.05, 0.03, 0.95)))

	var drip_mat := StandardMaterial3D.new()
	drip_mat.albedo_color = Color(0.42, 0.03, 0.02, 0.88)
	drip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drip_mat.roughness = 0.55
	for i in randi_range(3, 6):
		var dm := QuadMesh.new()
		dm.size = Vector2(randf_range(0.012, 0.032), randf_range(0.12, 0.42))
		dm.material = drip_mat
		var drip := MeshInstance3D.new()
		drip.mesh = dm
		drip.transform = anchor
		drip.translate_object_local(Vector3(randf_range(-0.55, 0.55),
				-0.1 - dm.size.y / 2.0, 0.001))
		root.add_child(drip)


## Bouteilles d'eau d'amande (lore Backrooms) : soignent le joueur.
func _place_almond_water(root: Node3D) -> void:
	var bottle_mesh := CylinderMesh.new()
	bottle_mesh.top_radius = 0.04
	bottle_mesh.bottom_radius = 0.055
	bottle_mesh.height = 0.28
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.92, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.45
	bottle_mesh.material = mat
	for i in 8:
		var c := Vector2i(randi_range(1, W - 2), randi_range(1, H - 2))
		if Vector2(c - spawn_cell).length() < 4.0 or c == key_cell or c == exit_cell:
			continue
		var bottle := Interactable.create("E — Boire l'eau d'amande", 0.65, true)
		var mi := MeshInstance3D.new()
		mi.mesh = bottle_mesh
		bottle.add_child(mi)
		# Posée au sol, légèrement décalée du centre du couloir.
		bottle.position = cell_center(c) \
				+ Vector3(randf_range(-0.8, 0.8), 0.14, randf_range(-0.8, 0.8))
		bottle.used.connect(func(p: PlayerController) -> void:
			p.heal(35.0)
			water_drunk.emit())
		root.add_child(bottle)


## Flèches jaunes peintes au sol le long du chemin spawn → sortie.
func _place_guide_arrows(root: Node3D) -> void:
	var head := PrismMesh.new()
	head.size = Vector3(0.5, 0.65, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.78, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.92, 0.78, 0.12)
	mat.emission_energy_multiplier = 0.35
	mat.roughness = 0.9
	head.material = mat
	for i in range(0, guide_cells.size() - 1, 3):
		var dir := (cell_center(guide_cells[i + 1]) - cell_center(guide_cells[i])).normalized()
		var mi := MeshInstance3D.new()
		mi.mesh = head
		# Prisme couché à plat (pointe vers -Z local) puis orienté vers la suite.
		mi.basis = Basis(Vector3.UP, atan2(-dir.x, -dir.z)) * Basis(Vector3.RIGHT, -PI / 2.0)
		mi.position = cell_center(guide_cells[i]) + Vector3(0, 0.03, 0)
		root.add_child(mi)


## Carte magnétique flottante sous une lumière rouge visible de loin.
func _place_key(root: Node3D) -> void:
	var center := cell_center(key_cell)
	_key_light = OmniLight3D.new()
	_key_light.light_color = Color(1.0, 0.15, 0.1)
	_key_light.light_energy = 1.6
	_key_light.omni_range = 11.0
	_key_light.position = center + Vector3(0, 2.3, 0)
	root.add_child(_key_light)

	var key := Interactable.create("E — Prendre la clé", 0.7, true)
	var card := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.03, 0.36)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.8
	bm.material = mat
	card.mesh = bm
	key.add_child(card)
	key.position = center + Vector3(0, 1.15, 0)
	key.used.connect(_on_key_used)
	root.add_child(key)
	_key_node = key


func _on_key_used(_player: PlayerController) -> void:
	key_collected = true
	_key_node = null
	if _key_light != null and is_instance_valid(_key_light):
		# La salle passe au vert : repère "déjà fouillé" + feedback victoire.
		_key_light.light_color = Color(0.3, 1.0, 0.45)
		_key_light.light_energy = 0.9
	key_taken.emit()


## Papier lisible collé sur un mur bordant la cellule donnée.
func _place_note(root: Node3D, cell: Vector2i, text: String) -> void:
	var anchor := _wall_anchor(cell, 1.45)
	if anchor == Transform3D.IDENTITY:
		return
	var note := Interactable.create("E — Lire la note", 0.55)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.26, 0.34)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.8, 0.62)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.8, 0.62)
	mat.emission_energy_multiplier = 0.12
	qm.material = mat
	quad.mesh = qm
	note.add_child(quad)
	note.transform = anchor
	note.used.connect(func(_p: PlayerController) -> void: note_read.emit(text))
	root.add_child(note)


## Inscription griffonnée sur un mur bordant la cellule donnée.
func _place_scrawl(root: Node3D, cell: Vector2i, text: String) -> void:
	var anchor := _wall_anchor(cell, randf_range(1.3, 1.9))
	if anchor == Transform3D.IDENTITY:
		return
	root.add_child(_blood_label(text, anchor, 0.004, Color(0.45, 0.08, 0.05, 0.85)))


## Label3D "écrit au sang" : police tracée au doigt, légèrement de travers.
func _blood_label(text: String, anchor: Transform3D, size: float, col: Color) -> Label3D:
	var label := _blood_label_node(text, size, col)
	label.transform = anchor
	label.rotate_object_local(Vector3.FORWARD, randf_range(-0.09, 0.09))
	return label


func _blood_label_node(text: String, size: float, col: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = BLOOD_FONT
	label.font_size = 60
	label.pixel_size = size
	label.modulate = col
	label.outline_size = 4
	label.outline_modulate = Color(0.08, 0.0, 0.0, 0.8)
	return label


func _place_exit_dressing(root: Node3D) -> void:
	var exit_sign := Label3D.new()
	exit_sign.text = "SORTIE"
	exit_sign.font_size = 96
	exit_sign.pixel_size = 0.005
	exit_sign.modulate = Color(0.5, 1.0, 0.6)
	exit_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	exit_sign.position = cell_center(exit_cell) + Vector3(0, 2.45, 0)
	root.add_child(exit_sign)
	_place_scrawl(root, exit_cell, "LA CLÉ. IL FAUT LA CLÉ.")


## Transform plaqué contre un mur existant autour de la cellule (face vers
## l'intérieur), ou IDENTITY si la cellule n'a aucun mur.
func _wall_anchor(cell: Vector2i, height: float) -> Transform3D:
	cell = cell.clamp(Vector2i.ZERO, Vector2i(W - 1, H - 1))
	var sides: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	sides.shuffle()
	for side in sides:
		if not _has_wall_between(cell, cell + side):
			continue
		var d := Vector3(side.x, 0, side.y)
		var pos := cell_center(cell) + d * (CELL / 2.0 - WALL_T / 2.0 - 0.02) \
				+ Vector3(0, height, 0)
		# Le +Z du Label3D/Quad doit pointer vers l'intérieur de la cellule.
		return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), pos)
	return Transform3D.IDENTITY


## Voisin accessible de `cell` le plus proche (à vol d'oiseau) de `target` —
## utilisé pour poser la note de la clé dans le couloir d'approche.
func _neighbor_towards(cell: Vector2i, target: Vector2i) -> Vector2i:
	var best := cell
	var best_d := INF
	for side in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = cell + side
		if n.x < 0 or n.x >= W or n.y < 0 or n.y >= H:
			continue
		if _has_wall_between(cell, n):
			continue
		var d := Vector2(n - target).length()
		if d < best_d:
			best_d = d
			best = n
	return best


func _module_mesh(path: String) -> Mesh:
	var inst: MeshInstance3D = (load(path) as PackedScene).instantiate()
	var mesh: Mesh = inst.mesh
	inst.free()
	return mesh


func _multimesh(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	return mmi
