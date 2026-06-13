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

var _flash_timer := 0.0

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

func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		flash_label.modulate.a = clampf(_flash_timer / 0.6, 0.0, 1.0)
		if _flash_timer <= 0.0:
			flash_label.visible = false

func set_speed(kmh: float) -> void:
	speed_label.text = "%d km/h" % int(kmh)

func set_total(score: int) -> void:
	score_label.text = "SCORE %d" % score

func set_heading(deg: float) -> void:
	compass.set_heading(deg)

func set_air(active: bool, points: int) -> void:
	air_label.visible = active
	if active:
		air_label.text = "AIR  +%d" % points

func set_drift(active: bool, points: float, multiplier: float) -> void:
	drift_label.visible = active
	combo_label.visible = active
	if active:
		drift_label.text = "DRIFT %d" % int(points)
		combo_label.text = "x%.1f" % multiplier

func flash(text: String, color: Color) -> void:
	flash_label.text = text
	flash_label.add_theme_color_override("font_color", color)
	flash_label.visible = true
	flash_label.modulate.a = 1.0
	_flash_timer = 1.6

func _make_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l
