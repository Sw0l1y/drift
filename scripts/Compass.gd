class_name Compass
extends Control
# Scrolling heading strip at the top of the HUD. Cardinal/intercardinal
# markers slide past a fixed centre pointer as the car turns.

const HALF_FOV := 70.0     # degrees visible to each side of centre
const TICK_STEP := 15

var heading := 0.0         # bearing in degrees, 0 = North

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_heading(deg: float) -> void:
	heading = deg
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var ppd := w / (HALF_FOV * 2.0)
	var font := ThemeDB.fallback_font

	# Backing bar.
	draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, 0.4), true)
	draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.12), false, 1.0)

	var cardinals := ["N", "E", "S", "W"]
	var inter := ["NE", "SE", "SW", "NW"]
	for a in range(0, 360, TICK_STEP):
		var diff := wrapf(float(a) - heading, -180.0, 180.0)
		if absf(diff) > HALF_FOV:
			continue
		var x := cx + diff * ppd
		var is_card := a % 90 == 0
		var is_inter := a % 45 == 0 and not is_card
		var tick_h := h * 0.22
		if is_card:
			tick_h = h * 0.42
		elif is_inter:
			tick_h = h * 0.32
		var base_y := h * 0.62
		draw_line(Vector2(x, base_y), Vector2(x, base_y - tick_h), Color(1, 1, 1, 0.75), 2.0)
		if is_card:
			var lbl: String = cardinals[floori(a / 90.0)]
			var col := Color(1.0, 0.4, 0.3) if lbl == "N" else Color(1, 1, 1)
			var ts := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			draw_string(font, Vector2(x - ts.x * 0.5, h * 0.42), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		elif is_inter:
			var lbl: String = inter[floori((a - 45) / 90.0)]
			var ts := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			draw_string(font, Vector2(x - ts.x * 0.5, h * 0.4), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))

	# Centre pointer.
	var ptr := PackedVector2Array([Vector2(cx - 7, 0), Vector2(cx + 7, 0), Vector2(cx, 12)])
	draw_colored_polygon(ptr, Color(1.0, 0.82, 0.3))
	draw_line(Vector2(cx, 0), Vector2(cx, h), Color(1.0, 0.82, 0.3, 0.6), 1.5)

	# Numeric readout below the strip.
	var card: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(round(heading / 45.0)) % 8]
	var txt := "%03d°  %s" % [int(round(wrapf(heading, 0.0, 360.0))), card]
	var size_t := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(font, Vector2(cx - size_t.x * 0.5, h + 16), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.85))
