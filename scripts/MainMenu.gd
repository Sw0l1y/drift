extends Control

const VERSION := "0.2.0"

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
	subtitle.text = "sakura circuit · burn rubber · bank points"
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
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ENTER:
		_start_game()

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
