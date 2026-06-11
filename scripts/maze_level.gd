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
const ROOM_COUNT := 9
const BRAID_RATIO := 0.4
const WALL_B_RATIO := 0.15

var spawn_cell := Vector2i(2, 2)
var exit_cell := Vector2i.ZERO
var key_cell := Vector2i.ZERO
var key_collected := false
## Chemin spawn → sortie en cellules (pour la piste d'indices).
var guide_cells: Array[Vector2i] = []

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
	_generate_layout()
	_solve_layout()
	_build_visuals(root)
	_build_colliders(root)
	exit_hint = cell_center(exit_cell)
	_place_props(root)
	return root


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
	for i in ROOM_COUNT:
		var rw := randi_range(3, 5)
		var rh := randi_range(3, 5)
		var rx := randi_range(1, W - rw - 1)
		var ry := randi_range(1, H - rh - 1)
		_carve_room(Rect2i(rx, ry, rw, rh))

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
	_place_almond_water(root)


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
	var label := Label3D.new()
	label.text = text
	label.font_size = 60
	label.pixel_size = 0.004
	label.modulate = Color(0.45, 0.08, 0.05, 0.85)
	label.transform = anchor
	root.add_child(label)


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
