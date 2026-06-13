class_name Ui
# Shared UI feel helpers, applying design-engineering principles to the
# game's menus: responsive buttons (press/hover feedback), and entrance
# animations that ease out, start from ~0.96 (never from nothing), stay
# under 300ms, and stagger. Motion is tuned crisp/energetic to match the
# arcade-drift mood.

const ENTER := 0.26      # entrance duration
const PRESS := 0.10      # press-down feedback
const RELEASE := 0.15    # release / hover settle

static func style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(Color(0.17, 0.15, 0.22, 0.92), Color(1, 1, 1, 0.12)))
	b.add_theme_stylebox_override("hover", _box(Color(0.26, 0.22, 0.32, 0.96), Color(1.0, 0.82, 0.4, 0.5)))
	b.add_theme_stylebox_override("pressed", _box(Color(0.12, 0.1, 0.16, 1.0), Color(1.0, 0.82, 0.4, 0.7)))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(1.0, 0.82, 0.4, 0.55)))
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.5))
	# Keep the scale pivot centred so press/hover feedback scales in place.
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func() -> void: _scale(b, 0.96, PRESS))
	b.button_up.connect(func() -> void: _scale(b, 1.0, RELEASE))
	b.mouse_entered.connect(func() -> void: _scale(b, 1.03, RELEASE))
	b.mouse_exited.connect(func() -> void: _scale(b, 1.0, RELEASE))

static func _box(bg: Color, border: Color, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 9.0
	s.content_margin_bottom = 9.0
	return s

static func _scale(c: Control, to: float, dur: float) -> void:
	if not c.is_inside_tree():
		return
	if c.has_meta("_stw"):
		var old: Tween = c.get_meta("_stw")
		if old != null and old.is_valid():
			old.kill()
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(c, "scale", Vector2(to, to), dur)
	c.set_meta("_stw", t)

# Fade + gentle scale-up entrance (panels, overlays). Scales from 0.97 so
# nothing appears from nothing; eases out; centred pivot.
static func pop_in(c: Control, dur := ENTER) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.modulate.a = 0.0
	c.scale = Vector2(0.97, 0.97)
	var t := c.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(c, "modulate:a", 1.0, dur)
	t.tween_property(c, "scale", Vector2.ONE, dur)

# Staggered fade for a set of controls — each comes in just after the last.
static func stagger_fade(items: Array, step := 0.05, dur := 0.24) -> void:
	var i := 0
	for c: Control in items:
		if c == null:
			continue
		c.modulate.a = 0.0
		var t := c.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_interval(i * step)
		t.tween_property(c, "modulate:a", 1.0, dur)
		i += 1
