class_name Sfx
# Procedurally synthesized sound bank — the project ships no audio assets,
# so every sound is generated into an AudioStreamWAV once and cached.
# Engine/skid loop and are pitch-shifted at runtime; the rest are one-shots.

const MR := 22050

static var _engine: AudioStreamWAV
static var _skid: AudioStreamWAV
static var _thud: AudioStreamWAV
static var _click: AudioStreamWAV
static var _whoosh: AudioStreamWAV
static var _chime: AudioStreamWAV

static func oneshot(parent: Node, stream: AudioStream, vol := 0.0, pitch := 1.0) -> void:
	# Fire-and-forget player; works while the tree is paused (menus/dev panel).
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol
	p.pitch_scale = pitch
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MR
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

static func engine() -> AudioStreamWAV:
	if _engine:
		return _engine
	# 0.5s loop; an 80Hz fundamental completes 40 whole cycles so it loops
	# seamlessly. Stacked harmonics give a buzzy combustion drone.
	var n := int(MR * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in n:
		var t := float(i) / MR
		var v := 0.0
		for k in range(1, 7):
			v += sin(TAU * 80.0 * k * t) / float(k)
		s[i] = v * 0.26 + (rng.randf() - 0.5) * 0.05
	_engine = _to_wav(s, true)
	return _engine

static func skid() -> AudioStreamWAV:
	if _skid:
		return _skid
	# Lowpassed white noise — a tyre hiss. Loops fine since it's noise.
	var n := int(MR * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var prev := 0.0
	for i in n:
		prev = lerpf(prev, rng.randf() * 2.0 - 1.0, 0.4)
		s[i] = prev * 0.55
	_skid = _to_wav(s, true)
	return _skid

static func thud() -> AudioStreamWAV:
	if _thud:
		return _thud
	var n := int(MR * 0.25)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var t := float(i) / MR
		var env: float = exp(-t * 17.0)
		s[i] = (sin(TAU * 70.0 * t) * 0.8 + (rng.randf() - 0.5) * 0.6) * env
	_thud = _to_wav(s, false)
	return _thud

static func click() -> AudioStreamWAV:
	if _click:
		return _click
	var n := int(MR * 0.05)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MR
		s[i] = sin(TAU * 880.0 * t) * exp(-t * 55.0) * 0.45
	_click = _to_wav(s, false)
	return _click

static func whoosh() -> AudioStreamWAV:
	if _whoosh:
		return _whoosh
	# Filtered-noise swell with a falling tone — an airtime landing.
	var n := int(MR * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var prev := 0.0
	for i in n:
		var t := float(i) / MR
		var env: float = sin(PI * clampf(t / 0.5, 0.0, 1.0))
		prev = lerpf(prev, rng.randf() * 2.0 - 1.0, 0.25)
		var tone := sin(TAU * lerpf(420.0, 120.0, t / 0.5) * t)
		s[i] = (prev * 0.6 + tone * 0.4) * env * 0.7
	_whoosh = _to_wav(s, false)
	return _whoosh

static func chime() -> AudioStreamWAV:
	if _chime:
		return _chime
	# Two-note rising chime for banking a drift.
	var n := int(MR * 0.4)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MR
		var v := 0.0
		if t < 0.22:
			v = sin(TAU * 660.0 * t) * exp(-t * 6.0)
		if t >= 0.12:
			v += sin(TAU * 988.0 * t) * exp(-(t - 0.12) * 6.0)
		s[i] = v * 0.4
	_chime = _to_wav(s, false)
	return _chime
