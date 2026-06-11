class_name AmbientAudio
extends AudioStreamPlayer

## Drone sonore généré procéduralement (aucun fichier audio dans le projet) :
## bourdonnement grave de néons + souffle filtré, pour l'ambiance pesante.

const RATE := 22050.0

var _playback: AudioStreamGeneratorPlayback
var _p1 := 0.0
var _p2 := 0.0
var _lfo := 0.0
var _noise := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	stream = gen
	volume_db = -16.0
	play()
	_playback = get_stream_playback()


func _process(_delta: float) -> void:
	if _playback == null:
		return
	for i in _playback.get_frames_available():
		_p1 += TAU * 49.0 / RATE
		_p2 += TAU * 97.3 / RATE
		_lfo += TAU * 0.13 / RATE
		# Bruit brun : intégration filtrée de bruit blanc.
		_noise = _noise * 0.985 + (randf() * 2.0 - 1.0) * 0.03
		var swell := 0.7 + 0.3 * sin(_lfo)
		var s := (sin(_p1) * 0.32 + sin(_p2) * 0.14 + _noise) * swell
		_playback.push_frame(Vector2(s, s))
