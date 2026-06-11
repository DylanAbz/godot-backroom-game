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
## Chemin spawn → sortie en cellules (pour la piste d'indices).
var guide_cells: Array[Vector2i] = []

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
	return root


func _setup_collisions(_content: Node3D) -> void:
	pass  # Collisions déjà créées dans _create_content().


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
