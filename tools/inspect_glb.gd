extends SceneTree

# Outil de debug : liste animations, dimensions et structure de chaque GLB.
# Usage : godot --headless -s tools/inspect_glb.gd

const PATHS := [
	"res://assets/character/escape_the_backrooms_hazmat.glb",
	"res://assets/character/backrooms_rigged_hazmat.glb",
	"res://assets/character/partygoer_from_backrooms.glb",
	"res://assets/character/bacteria_-_kane_pixels_backrooms.glb",
	"res://assets/character/smiler_backrooms.glb",
	"res://assets/character/backrooms_smiler_rig.glb",
	"res://assets/character/kitty_-_backrooms_entity.glb",
	"res://assets/character/smiler_entity3_backrooms.glb",
	"res://assets/original_backrooms.glb",
	"res://assets/backrooms_another_level.glb",
]

func _init() -> void:
	for path in PATHS:
		print("\n=== ", path, " ===")
		var packed: PackedScene = load(path)
		if packed == null:
			print("  ECHEC DE CHARGEMENT")
			continue
		var inst := packed.instantiate()
		_dump_tree(inst, 0)
		var aabb := _combined_aabb(inst)
		print("  AABB position=", aabb.position, " size=", aabb.size)
		inst.free()
	quit()

func _dump_tree(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth + 1)
	var info := indent + node.get_class() + " \"" + node.name + "\""
	if node is AnimationPlayer:
		info += "  anims=" + str(node.get_animation_list())
	print(info)
	if depth < 2:
		for child in node.get_children():
			_dump_tree(child, depth + 1)
	elif node.get_child_count() > 0:
		print(indent + "  ... (" + str(node.get_child_count()) + " enfants)")

func _combined_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var xform: Transform3D = Transform3D.IDENTITY
			var p := n
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
