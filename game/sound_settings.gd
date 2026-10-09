extends Control

signal closed

var audio: Node
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var resume_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.05, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_top = -180
	panel.offset_right = 220
	panel.offset_bottom = 180
	var style := StyleBoxFlat.new()
	style.bg_color = Color("142923")
	style.border_color = Color("637b58")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(_label("Sound", 24, Color("f0d59d")))
	column.add_child(_label("Find a comfortable balance.", 14, Color("a4b8ad")))
	for bus in ["Master", "SFX", "BGM"]:
		_add_slider(column, bus)
	column.add_child(_label("Arrows / D-pad adjust · B / Esc close", 12, Color("a4b8ad")))
	resume_button = Button.new()
	resume_button.text = "Resume"
	resume_button.custom_minimum_size.y = 36
	resume_button.pressed.connect(close)
	column.add_child(resume_button)
	var controls: Array[Control] = [sliders.Master, sliders.SFX, sliders.BGM, resume_button]
	for i in controls.size():
		controls[i].focus_neighbor_top = controls[i].get_path_to(controls[posmod(i - 1, controls.size())])
		controls[i].focus_neighbor_bottom = controls[i].get_path_to(controls[(i + 1) % controls.size()])
	visible = false

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _add_slider(column: VBoxContainer, bus: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var label := _label(bus, 16, Color("d6e7cf"))
	label.custom_minimum_size.x = 66
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(0, 32)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = audio.get_volume(bus) * 100.0
	slider.tooltip_text = "Controls all sound" if bus == "Master" else "Sound effects" if bus == "SFX" else "Background music"
	var track := StyleBoxFlat.new()
	track.bg_color = Color("30463c")
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate()
	fill.bg_color = Color("b3bf83")
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	row.add_child(slider)
	var value_label := _label("%d%%" % slider.value, 15, Color("f0d59d"))
	value_label.custom_minimum_size.x = 46
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	sliders[bus] = slider
	value_labels[bus] = value_label
	slider.value_changed.connect(_volume_changed.bind(bus))

func _volume_changed(value: float, bus: String) -> void:
	audio.set_volume(bus, value / 100.0)
	value_labels[bus].text = "%d%%" % value

func open() -> void:
	visible = true
	sliders.Master.grab_focus()
	audio.stop_sfx()

func close() -> void:
	visible = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	closed.emit()
