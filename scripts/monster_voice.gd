class_name MonsterVoice
extends AudioStreamPlayer3D

## Voix 3D d'un monstre : observe l'état du Monster parent et joue cris/rires
## sur les transitions, avec cooldown anti-spam. Volontairement séparé de
## monster.gd (purement additif, attaché par le spawner).
##
## - stalker  : rire de sorcière quand il charge, ricanements en rôdant
## - ambusher : hurlement au déclenchement du burst
## - rusher   : cri au début de la charge
## - brute    : râle grave (cri ralenti) quand elle vous a entendu
## - smiler   : cri aigu quand il se met à courir
## - tous     : cri étouffé à la mort

const SCREAM_A := preload("res://assets/audio/scream_a.mp3")
const SCREAM_B := preload("res://assets/audio/scream_b.mp3")
const WITCH_LAUGH := preload("res://assets/audio/witch_laugh.mp3")

var monster: Monster

var _cd := 0.0
var _engaged := false
var _was_commit := false
var _was_burst := false
var _played_death := false


func _ready() -> void:
	max_distance = 45.0
	unit_size = 12.0


func _process(delta: float) -> void:
	if monster == null or not is_instance_valid(monster):
		return
	_cd = maxf(_cd - delta, 0.0)
	if monster._dying:
		if not _played_death:
			_played_death = true
			_play(SCREAM_B, 0.7, true)
		return
	var p := monster.player
	if p == null or not is_instance_valid(p) or p.dead:
		return
	var to_p := p.global_position - monster.global_position
	var dist := to_p.length()
	to_p.y = 0.0

	match monster._behavior:
		"stalker":
			if monster._commit and not _was_commit:
				_play(WITCH_LAUGH, randf_range(0.85, 1.0), true)
			elif not monster._commit and dist < 32.0 and randf() < delta * 0.03:
				# Ricanement occasionnel pendant qu'il rôde.
				_play(WITCH_LAUGH, randf_range(0.8, 1.05))
			_was_commit = monster._commit
		"ambusher":
			var burst: bool = monster._state == "burst"
			if burst and not _was_burst:
				_play(SCREAM_A, 1.25, true)
			_was_burst = burst
		_:
			# rusher / brute / smiler : cri au début de la poursuite, détectée
			# par "avance vite vers le joueur" (sans dépendre des internes).
			var planar := Vector3(monster.velocity.x, 0.0, monster.velocity.z)
			var chasing := dist < 30.0 and planar.length() > monster._speed * 0.7 \
					and to_p.normalized().dot(planar.normalized()) > 0.6
			if chasing and not _engaged:
				match monster._behavior:
					"rusher":
						_play(SCREAM_A, randf_range(0.95, 1.15))
					"brute":
						_play(SCREAM_B, 0.55)
					"smiler":
						_play(SCREAM_B, 1.15)
			_engaged = chasing


func _play(sound: AudioStream, pitch := 1.0, force := false) -> void:
	if not force and (_cd > 0.0 or playing):
		return
	_cd = randf_range(6.0, 12.0)
	stream = sound
	pitch_scale = pitch
	play()
