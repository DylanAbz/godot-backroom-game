extends SceneTree

# Outil de debug : liste les os du squelette du modèle joueur (noms, parents,
# repères globaux au repos des bras) pour régler les poses procédurales.
# Usage : godot --headless -s tools/inspect_bones.gd

func _init() -> void:
	var inst: Node3D = (load("res://assets/character/escape_the_backrooms_hazmat.glb") as PackedScene).instantiate()
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	print("skeleton global scale hints: motion_scale=", skel.motion_scale)
	for i in skel.get_bone_count():
		var parent := skel.get_bone_parent(i)
		var pname := skel.get_bone_name(parent) if parent >= 0 else "-"
		print(i, "  ", skel.get_bone_name(i), "  (parent: ", pname, ")")
	for bname in ["RightArm_", "RightForeArm_", "RightHand_", "LeftArm_", "LeftForeArm_", "LeftHand_", "Hips_"]:
		for i in skel.get_bone_count():
			if not skel.get_bone_name(i).begins_with(bname):
				continue
			var rest := skel.get_bone_global_rest(i)
			print(skel.get_bone_name(i), " idx=", i, "\n  origin=", rest.origin,
					"\n  X=", rest.basis.x, "\n  Y=", rest.basis.y, "\n  Z=", rest.basis.z)
			break
	inst.free()
	quit()
