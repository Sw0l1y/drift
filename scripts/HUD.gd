class_name HUD
extends CanvasLayer

var speed_label: Label
var score_label: Label
var drift_label: Label
var combo_label: Label
var flash_label: Label
var hint_label: Label
var air_label: Label
var compass: Compass

var _flash_tw: Tween
var _score_tw: Tween
var _shown_score := 0.0
var _target_score := 0
var _drift_shown := false
var _air_shown := false

func _ready() -> void:
	score_label = _make_label(Vector2(24, 16), 30, Color(1, 1, 1))
	score_label.text = "SCORE 0"

	speed_label = _make_label(Vector2(24, -80), 44, Color(1, 0.85, 0.4))
	speed_label.anchor_top = 1.0
	speed_label.anchor_bottom = 1.0
	speed_label.text = "0 km/h"

	drift_label = _make_label(Vector2(0, -190), 40, Color(1.0, 0.62, 0.68))
	drift_label.anchor_left = 0.0
	drift_label.anchor_right = 1.0
	drift_label.anchor_top = 1.0
	drift_label.anchor_bottom = 1.0
	drift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drift_label.visible = false

	combo_label = _make_label(Vector2(0, -140), 26, Color(1.0, 0.45, 0.9))
	combo_label.anchor_left = 0.0
	combo_label.anchor_right = 1.0
	combo_label.anchor_top = 1.0
	combo_label.anchor_bottom = 1.0
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.visible = false

	air_label = _make_label(Vector2(0, 90), 34, Color(0.55, 0.8, 1.0))
	air_label.anchor_left = 0.0
	air_label.anchor_right = 1.0
	air_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	air_label.visible = false

	flash_label = _make_label(Vector2(0, 140), 38, Color(1, 1, 1))
	flash_label.anchor_left = 0.0
	flash_label.anchor_right = 1.0
	flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_label.visible = false

	compass = Compass.new()
	compass.anchor_left = 0.5
	compass.anchor_right = 0.5
	compass.offset_left = -220
	compass.offset_right = 220
	compass.offset_top = 12
	compass.offset_bottom = 56
	add_child(compass)

	hint_label = _make_label(Vector2(-450, 64), 16, Color(1, 1, 1, 0.55))
	hint_label.anchor_left = 1.0
	hint_label.anchor_right = 1.0
	hint_label.text = "WASD drive · SPACE handbrake · R reset · ESC pause"

func set_speed(kmh: float) -> void:
	# Updates every frame — never animate (it'd just feel laggy).
	speed_label.text = "%d km/h" % int(kmh)

func set_total(score: int) -> void:
	if score == _target_score:
		return
	# Roll the number up to the new total and pulse — satisfying feedback
	# when points bank. Retargets smoothly if score jumps again mid-roll.
	_target_score = score
	if _score_tw != null and _score_tw.is_valid():
		_score_tw.kill()
	_score_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_score_tw.tween_method(_set_score_display, _shown_score, float(score), 0.4)
	_pulse(score_label)

func _set_score_display(v: float) -> void:
	_shown_score = v
	score_label.text = "SCORE %d" % int(round(v))

func set_heading(deg: float) -> void:
	compass.set_heading(deg)

func set_air(active: bool, points: int) -> void:
	if active and not _air_shown:
		_air_shown = true
		air_label.visible = true
		_fade_in(air_label)
	elif not active and _air_shown:
		_air_shown = false
		air_label.visible = false
	if active:
		air_label.text = "AIR  +%d" % points

func set_drift(active: bool, points: float, multiplier: float) -> void:
	if active and not _drift_shown:
		_drift_shown = true
		drift_label.visible = true
		combo_label.visible = true
		_fade_in(drift_label)
		_fade_in(combo_label)
	elif not active and _drift_shown:
		_drift_shown = false
		drift_label.visible = false
		combo_label.visible = false
	if active:
		drift_label.text = "DRIFT %d" % int(points)
		combo_label.text = "x%.1f" % multiplier

func flash(text: String, color: Color) -> void:
	flash_label.text = text
	flash_label.add_theme_color_override("font_color", color)
	flash_label.visible = true
	flash_label.pivot_offset = flash_label.size * 0.5
	flash_label.modulate.a = 0.0
	flash_label.scale = Vector2(0.82, 0.82)
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	# Pop in (fade fast, scale with a touch of overshoot), hold, fade out.
	_flash_tw.tween_property(flash_label, "modulate:a", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	_flash_tw.parallel().tween_property(flash_label, "scale", Vector2.ONE, 0.26) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_flash_tw.tween_interval(0.95)
	_flash_tw.tween_property(flash_label, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	_flash_tw.tween_callback(func() -> void: flash_label.visible = false)

func _fade_in(c: Control, dur := 0.12) -> void:
	c.modulate.a = 0.0
	create_tween().set_ease(Tween.EASE_OUT).tween_property(c, "modulate:a", 1.0, dur)

func _pulse(lbl: Label) -> void:
	# Grow from the left anchor so the readout doesn't shift sideways.
	lbl.pivot_offset = Vector2(0, lbl.size.y * 0.5)
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(lbl, "scale", Vector2(1.13, 1.13), 0.09)
	t.tween_property(lbl, "scale", Vector2.ONE, 0.13)

func _make_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l
