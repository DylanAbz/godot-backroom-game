class_name Interactable
extends Area3D

## Zone interactive visée au regard (layer 8) : le joueur la détecte par
## raycast et déclenche interact() avec la touche E. La forme de collision
## est fournie par le créateur.

signal used(player: PlayerController)

var prompt := "E — Interagir"
var one_shot := false


func _init() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false


func interact(player: PlayerController) -> void:
	used.emit(player)
	if one_shot:
		queue_free()


## Fabrique standard : zone sphérique prête à poser.
static func create(p_prompt: String, radius: float, p_one_shot := false) -> Interactable:
	var area := Interactable.new()
	area.prompt = p_prompt
	area.one_shot = p_one_shot
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	cs.shape = sphere
	area.add_child(cs)
	return area
