class_name HorrorAudio
extends RefCounted

## Sons d'ambiance localisés, synthétisés en AudioStreamWAV au lancement
## (aucun fichier audio nécessaire) : buzz de néon en boucle, goutte d'eau,
## chuchotement en boucle. Les streams sont mis en cache et partagés entre
## tous les AudioStreamPlayer3D.

const RATE := 22050

static var _buzz: AudioStreamWAV
static var _drip: AudioStreamWAV
static var _whisper: AudioStreamWAV


## Bourdonnement de néon : 100 Hz + harmoniques, boucle d'une seconde.
static func neon_buzz() -> AudioStreamWAV:
	if _buzz != null:
		return _buzz
	var s := PackedFloat32Array()
	s.resize(RATE)
	for i in RATE:
		var t := float(i) / RATE
		var v := sin(TAU * 100.0 * t) * 0.45 + sin(TAU * 200.0 * t) * 0.25 \
				+ sin(TAU * 300.0 * t) * 0.12 + (randf() * 2.0 - 1.0) * 0.06
		# Grésillement irrégulier : modulation à 8 Hz (entière → boucle propre).
		v *= 0.82 + 0.18 * sin(TAU * 8.0 * t)
		s[i] = v * 0.55
	_buzz = _wav(s, true)
	return _buzz


## Goutte d'eau : "plip" descendant, avec un petit rebond d'écho.
static func water_drip() -> AudioStreamWAV:
	if _drip != null:
		return _drip
	var n := int(RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := 420.0 + 1300.0 * exp(-t * 14.0)
		phase += TAU * freq / RATE
		var v := sin(phase) * exp(-t * 16.0)
		if t > 0.24:
			v += sin(phase * 0.7) * exp(-(t - 0.24) * 26.0) * 0.3
		s[i] = v * 0.85
	_drip = _wav(s, false)
	return _drip


## Souffle/chuchotement : bruit filtré en bouffées, boucle de 3 secondes.
static func whisper() -> AudioStreamWAV:
	if _whisper != null:
		return _whisper
	var n := RATE * 3
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var bp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := randf() * 2.0 - 1.0
		lp = lp * 0.9 + white * 0.1
		bp = bp * 0.96 + (lp - bp) * 0.4
		# Bouffées irrégulières mais périodiques sur 3 s (boucle sans couture).
		var breath := maxf(0.0,
				sin(TAU * t / 3.0) * 0.55 + sin(TAU * t / 1.5 + 1.3) * 0.45)
		s[i] = bp * breath * 1.6
	_whisper = _wav(s, true)
	return _whisper


static func _wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav
