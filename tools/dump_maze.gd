extends SceneTree

# Debug : génère un plan de MazeLevel et l'imprime en ASCII pour juger le
# layout (couloirs, salles, boucles) sans lancer le jeu.
# Usage : godot --headless -s tools/dump_maze.gd

func _init() -> void:
	var lvl: Node = load("res://scripts/maze_level.gd").new()
	lvl._generate_layout()
	lvl._solve_layout()
	var w: int = lvl.W
	var h: int = lvl.H
	for y in h:
		var top := ""
		var mid := ""
		for x in w:
			top += "+" + ("--" if lvl._h_walls[x][y] == 1 else "  ")
			var cell := "  "
			if Vector2i(x, y) == lvl.spawn_cell:
				cell = "S "
			elif Vector2i(x, y) == lvl.exit_cell:
				cell = "E "
			elif Vector2i(x, y) == lvl.key_cell:
				cell = "K "
			mid += ("|" if lvl._v_walls[x][y] == 1 else " ") + cell
		print(top + "+")
		print(mid + ("|" if lvl._v_walls[w][y] == 1 else " "))
	var bottom := ""
	for x in w:
		bottom += "+" + ("--" if lvl._h_walls[x][h] == 1 else "  ")
	print(bottom + "+")
	lvl.free()
	quit()
