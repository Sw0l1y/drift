extends Control

const VERSION := "0.7.0"
const SECRET := "nathan"

var _car_name: Label
var _car_desc: Label
var _dev: DevPanel = null
var _typed := ""

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	add_child(vbox)

	var title := Label.new()
	title.text = "DRIFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 110)
	title.add_theme_color_override("font_color", Color(0.92, 0.22, 0.18))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "sakura tōge · burn rubber · bank points"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.98, 0.72, 0.78))
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var play := Button.new()
	play.text = "PLAY"
	play.custom_minimum_size = Vector2(260, 56)
	play.add_theme_font_size_override("font_size", 28)
	play.pressed.connect(_start_game)
	vbox.add_child(play)

	# Car selector — cycles through the Garage registry.
	var selector := HBoxContainer.new()
	selector.alignment = BoxContainer.ALIGNMENT_CENTER
	selector.add_theme_constant_override("separation", 16)
	vbox.add_child(selector)

	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(52, 64)
	prev.add_theme_font_size_override("font_size", 24)
	prev.pressed.connect(_cycle_car.bind(-1))
	selector.add_child(prev)

	var car_box := VBoxContainer.new()
	car_box.custom_minimum_size = Vector2(300, 0)
	car_box.alignment = BoxContainer.ALIGNMENT_CENTER
	selector.add_child(car_box)

	_car_name = Label.new()
	_car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_name.add_theme_font_size_override("font_size", 30)
	_car_name.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	car_box.add_child(_car_name)

	_car_desc = Label.new()
	_car_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_desc.add_theme_font_size_override("font_size", 14)
	_car_desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	car_box.add_child(_car_desc)

	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(52, 64)
	next.add_theme_font_size_override("font_size", 24)
	next.pressed.connect(_cycle_car.bind(1))
	selector.add_child(next)

	_refresh_car()

	var quit := Button.new()
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(260, 44)
	quit.add_theme_font_size_override("font_size", 20)
	quit.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit)

	var controls := Label.new()
	controls.text = "WASD / arrows to drive · SPACE handbrake · R reset"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_font_size_override("font_size", 16)
	controls.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	vbox.add_child(controls)

	var version := Label.new()
	version.text = "v" + VERSION
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.position = Vector2(-90, -40)
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	add_child(version)

	play.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_ENTER and _dev == null:
			_start_game()
			return
		# Hidden dev panel: type "nathan".
		if _dev == null and key.unicode != 0:
			var ch := char(key.unicode).to_lower()
			if ch.length() == 1 and ch >= "a" and ch <= "z":
				_typed = (_typed + ch).right(SECRET.length())
				if _typed == SECRET:
					_typed = ""
					_open_dev()

func _open_dev() -> void:
	_dev = DevPanel.new()
	_dev.closed.connect(func() -> void: _dev = null)
	add_child(_dev)

func _cycle_car(dir: int) -> void:
	var n := Garage.cars().size()
	Garage.selected = (Garage.selected + dir + n) % n
	_refresh_car()

func _refresh_car() -> void:
	var def := Garage.cars()[Garage.selected]
	_car_name.text = def["name"]
	_car_desc.text = def["desc"]

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
