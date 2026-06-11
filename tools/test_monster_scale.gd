extends SceneTree

# Vérifie la normalisation de taille : instancie chaque type de monstre et
# compare la hauteur rendue estimée (max AABB mesh / os, à l'échelle finale)
# avec la hauteur cible de MonsterSpawner.TYPES.
# Usage : godot --headless -s tools/test_monster_scale.gd

func _init() -> void:
	# Une frame pour que l'arbre soit actif (sinon _ready n'est pas appelé).
	await process_frame
	var monster_script := load("res://scripts/monster.gd")
	var spawner_script := load("res://scripts/monster_spawner.gd")
	for cfg in spawner_script.TYPES:
		var m: CharacterBody3D = monster_script.new()
		m.cfg = cfg
		root.add_child(m)
		var model: Node3D = m._model
		var s: float = model.scale.y
		var mesh_h: float = monster_script.combined_aabb(model).size.y * s
		var skel_h: float = monster_script.skeleton_rest_aabb(model).size.y * s
		print(str(cfg.get("model", "<photo_face>")).get_file(),
				"  cible=", cfg["height"],
				"  scale=", snappedf(s, 0.0001),
				"  h_mesh=", snappedf(mesh_h, 0.01),
				"  h_os=", snappedf(skel_h, 0.01))
		m.free()
	quit()
