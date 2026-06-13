extends Node
# Drives the looping engine + tyre-skid players from a car's live state.
# Works with either car via the shared contract (flat_speed, is_drifting).

var car

var _engine: AudioStreamPlayer
var _skid: AudioStreamPlayer

func _ready() -> void:
	_engine = AudioStreamPlayer.new()
	_engine.stream = Sfx.engine()
	_engine.volume_db = -12.0
	add_child(_engine)
	_engine.play()

	_skid = AudioStreamPlayer.new()
	_skid.stream = Sfx.skid()
	_skid.volume_db = -60.0
	add_child(_skid)
	_skid.play()

func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var sp: float = car.flat_speed
	# Engine note rises with speed; volume swells off idle.
	_engine.pitch_scale = clampf(0.7 + sp / 46.0 * 1.9, 0.7, 2.7)
	var vol_target := lerpf(-13.0, -4.5, clampf(sp / 30.0, 0.0, 1.0))
	_engine.volume_db = lerpf(_engine.volume_db, vol_target, clampf(6.0 * delta, 0.0, 1.0))
	# Tyre skid fades in while drifting.
	var skid_target := -7.0 if car.is_drifting else -60.0
	_skid.volume_db = lerpf(_skid.volume_db, skid_target, clampf(9.0 * delta, 0.0, 1.0))
	_skid.pitch_scale = clampf(0.8 + sp / 50.0, 0.8, 1.7)
