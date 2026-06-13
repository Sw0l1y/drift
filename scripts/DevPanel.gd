class_name DevPanel
extends Control
# Hidden developer tuning panel (opened by typing "nathan"). Edits the
# Tuning store live, manages profiles, and persists to disk. If handed a
# live_car, changes re-apply to it immediately so you can feel them.

signal closed

var live_car = null   # optional: a spawned car to re-tune on the fly

var _profile_option: OptionButton
var _spinboxes: Dictionary = {}   # "car/key" -> SpinBox
var _new_name: LineEdit

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fill the viewport directly (offsets zeroed) so margins/centering math
	# has a real rect to work from regardless of the parent's size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# CenterContainer centers the panel; the panel's height is capped below
	# the viewport so it can actually be centered (and scrolls if needed).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560, 600)
	panel.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var title := Label.new()
	title.text = "⚙  DEV TUNING"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	root.add_child(title)

	# --- profile row ---
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	root.add_child(prow)
	var plabel := Label.new()
	plabel.text = "Profile:"
	plabel.add_theme_font_size_override("font_size", 18)
	prow.add_child(plabel)
	_profile_option = OptionButton.new()
	_profile_option.custom_minimum_size = Vector2(190, 0)
	_profile_option.item_selected.connect(_on_profile_selected)
	prow.add_child(_profile_option)
	var reset_btn := _mk_button("Reset", _on_reset)
	prow.add_child(reset_btn)
	var del_btn := _mk_button("Delete", _on_delete)
	prow.add_child(del_btn)

	# --- new profile row ---
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	root.add_child(nrow)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "new profile name…"
	_new_name.custom_minimum_size = Vector2(250, 0)
	nrow.add_child(_new_name)
	nrow.add_child(_mk_button("+ Create", _on_create))

	# --- param sections ---
	_build_section(root, "COUPE  ·  KAZE", "coupe")
	_build_section(root, "TRUCK  ·  TANUKI", "truck")

	# --- footer ---
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 12)
	frow.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(frow)
	var save := _mk_button("SAVE", _on_save)
	save.custom_minimum_size = Vector2(160, 48)
	save.add_theme_font_size_override("font_size", 22)
	frow.add_child(save)
	var close := _mk_button("CLOSE", _on_close)
	close.custom_minimum_size = Vector2(160, 48)
	close.add_theme_font_size_override("font_size", 22)
	frow.add_child(close)

	_refresh_profiles()
	_refresh_values()

func _build_section(root: VBoxContainer, heading: String, car: String) -> void:
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 20)
	h.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	root.add_child(h)
	for key: String in Tuning.SCHEMA[car]:
		var spec: Array = Tuning.SCHEMA[car][key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		root.add_child(row)
		var lbl := Label.new()
		lbl.text = spec[4]
		lbl.custom_minimum_size = Vector2(190, 0)
		lbl.add_theme_font_size_override("font_size", 16)
		row.add_child(lbl)
		var sb := SpinBox.new()
		sb.min_value = spec[1]
		sb.max_value = spec[2]
		sb.step = spec[3]
		sb.custom_minimum_size = Vector2(170, 0)
		sb.value_changed.connect(_on_value_changed.bind(car, key))
		row.add_child(sb)
		_spinboxes[car + "/" + key] = sb

func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func() -> void:
		Sfx.oneshot(self, Sfx.click(), -7.0)
		cb.call())
	return b

func _refresh_profiles() -> void:
	_profile_option.clear()
	var names := Tuning.profile_names()
	for i in names.size():
		_profile_option.add_item(names[i])
		if names[i] == Tuning.current:
			_profile_option.select(i)

func _refresh_values() -> void:
	for path: String in _spinboxes:
		var parts := path.split("/")
		var sb: SpinBox = _spinboxes[path]
		# Set without re-triggering a write.
		sb.set_block_signals(true)
		sb.value = Tuning.get_val(parts[0], parts[1])
		sb.set_block_signals(false)

func _on_value_changed(value: float, car: String, key: String) -> void:
	Tuning.set_val(car, key, value)
	_apply_live()

func _on_profile_selected(idx: int) -> void:
	Tuning.current = _profile_option.get_item_text(idx)
	_refresh_values()
	_apply_live()

func _on_create() -> void:
	Tuning.add_profile(_new_name.text)
	_new_name.text = ""
	_refresh_profiles()
	_refresh_values()
	_apply_live()

func _on_reset() -> void:
	Tuning.reset_current()
	_refresh_values()
	_apply_live()

func _on_delete() -> void:
	Tuning.delete_profile(Tuning.current)
	_refresh_profiles()
	_refresh_values()
	_apply_live()

func _on_save() -> void:
	Tuning.save_cfg()
	var t := get_node_or_null("SavedToast")
	if t == null:
		var toast := Label.new()
		toast.name = "SavedToast"
		toast.text = "✓ saved"
		toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		toast.add_theme_font_size_override("font_size", 22)
		toast.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		add_child(toast)
		toast.position.y -= 80
		get_tree().create_timer(1.2).timeout.connect(toast.queue_free)

func _on_close() -> void:
	closed.emit()
	queue_free()

func _apply_live() -> void:
	if live_car != null and is_instance_valid(live_car):
		live_car.apply_tuning()
