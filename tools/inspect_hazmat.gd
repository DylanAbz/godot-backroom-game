extends SceneTree

# Dump complet du modèle joueur : squelette, os, meshes.

func _init() -> void:
	var packed: PackedScene = load("res://assets/character/escape_the_backrooms_hazmat.glb")
	var inst := packed.instantiate()
	_dump(inst, 0)
	inst.free()
	quit()

func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var line := indent + node.get_class() + " \"" + node.name + "\""
	if node is Node3D:
		line += " pos=" + str(node.position) + " scale=" + str(node.scale)
	print(line)
	if node is Skeleton3D:
		for i in node.get_bone_count():
			print(indent + "  bone[", i, "] = ", node.get_bone_name(i))
	if node is AnimationPlayer:
		print(indent + "  anims=", node.get_animation_list())
	for child in node.get_children():
		_dump(child, depth + 1)
