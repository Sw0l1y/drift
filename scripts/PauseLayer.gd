class_name PauseLayer
extends CanvasLayer
# In-game pause overlay + hidden dev-panel trigger. Runs while the tree is
# paused (PROCESS_MODE_ALWAYS). ESC toggles pause; typing "nathan" opens
# the dev tuning panel. Owns no game logic — just UI + flow.

const SECRET := "nathan"

var live_car = null   # passed in by Main so the dev panel can re-tune live

var _menu: Control
var _menu_box: VBoxContainer
var _dev: DevPanel
var _typed := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_menu()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			if _dev != null:
				return   # let the dev panel's own Close handle exit
			_toggle_pause()
			get_viewport().set_input_as_handled()
			return
		# Track the secret sequence (only when a panel isn't already up).
		if _dev == null and key.unicode != 0:
			var ch := char(key.unicode).to_lower()
			if ch.length() == 1 and ch >= "a" and ch <= "z":
				_typed = (_typed + ch).right(SECRET.length())
				if _typed == SECRET:
					_typed = ""
					_open_dev()

func _toggle_pause() -> void:
	if _menu.visible:
		_resume()
	else:
		_menu.visible = true
		get_tree().paused = true
		Ui.pop_in(_menu_box, 0.18)

func _resume() -> void:
	_menu.visible = false
	if _dev == null:
		get_tree().paused = false

func _open_dev() -> void:
	get_tree().paused = true
	_dev = DevPanel.new()
	_dev.live_car = live_car
	_dev.closed.connect(_on_dev_closed)
	add_child(_dev)

func _on_dev_closed() -> void:
	_dev = null
	if not _menu.visible:
		get_tree().paused = false

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.09, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_menu.add_child(vbox)
	_menu_box = vbox

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.92, 0.22, 0.18))
	vbox.add_child(title)

	vbox.add_child(_mk_button("RESUME", _resume))
	vbox.add_child(_mk_button("RESTART", func() -> void:
		get_tree().paused = false
		get_tree().reload_current_scene()))
	vbox.add_child(_mk_button("MENU", func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))

	var hint := Label.new()
	hint.text = "psst… type a name"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	vbox.add_child(hint)

func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 50)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func() -> void:
		Sfx.oneshot(self, Sfx.click(), -6.0)
		cb.call())
	Ui.style_button(b)
	return b
