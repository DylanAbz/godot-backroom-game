class_name LevelRoot
extends Node3D

## Charge un niveau GLB, génère les collisions trimesh sur chaque mesh,
## puis bake le navmesh (sur thread) pour le pathfinding des monstres.

signal collisions_ready
signal nav_ready

var model_path := ""
var nav_region: NavigationRegion3D


func _ready() -> void:
	# Différé pour que le parent ait le temps de connecter les signaux.
	_build.call_deferred()


func _build() -> void:
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	var model: Node3D = load(model_path).instantiate()
	nav_region.add_child(model)

	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.create_trimesh_collision()
	collisions_ready.emit()

	# Indispensable : baker dans la même frame que la création des colliders
	# parse une scène vide (le serveur physique ne les a pas encore
	# enregistrés) → navmesh vide, portail jamais placé.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_height = 1.6
	nm.agent_radius = 0.5
	nm.agent_max_climb = 0.5
	nav_region.navigation_mesh = nm
	nav_region.bake_finished.connect(func() -> void: nav_ready.emit())
	nav_region.bake_navigation_mesh(true)
