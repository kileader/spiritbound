extends Node2D

const RoomModel = preload("res://game/room_model.gd")
var model = RoomModel.new()
var debug := false
var status_label: Label
var controller_label: Label
var return_label: Label
var last_effect := 0
var sound_player: AudioStreamPlayer
var sound_cues: Dictionary = {}

func _ready() -> void:
	_setup_input()
	for child in get_children():
		if "model" in child:
			child.model = model
	$Possession.debug = debug
	_build_hud()
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	for kind in ["release", "dive", "crash", "win"]:
		sound_cues[kind] = _make_sound(kind)
	Input.joy_connection_changed.connect(_controller_changed)
	_controller_changed(0, false)

func _setup_input() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT], JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_bind("move_right", [KEY_D, KEY_RIGHT], JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0)
	_bind("move_up", [KEY_W, KEY_UP], JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0)
	_bind("move_down", [KEY_S, KEY_DOWN], JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0)
	_bind("possess", [KEY_SPACE], JOY_BUTTON_A)
	_bind("return_host", [KEY_ESCAPE], JOY_BUTTON_B)
	_bind("reset_room", [KEY_R], JOY_BUTTON_Y)
	_bind("target_previous", [KEY_Q], JOY_BUTTON_LEFT_SHOULDER)
	_bind("target_next", [KEY_E], JOY_BUTTON_RIGHT_SHOULDER)
	_bind("inspect_room", [KEY_F1], JOY_BUTTON_BACK)

func _bind(action: String, keys: Array, button: int, axis: int = -1, value: float = 0.0) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, 0.18)
	for code in keys:
		var key := InputEventKey.new()
		key.physical_keycode = code
		InputMap.action_add_event(action, key)
	var joy := InputEventJoypadButton.new()
	joy.button_index = button
	InputMap.action_add_event(action, joy)
	if axis >= 0:
		var stick := InputEventJoypadMotion.new()
		stick.axis = axis
		stick.axis_value = value
		InputMap.action_add_event(action, stick)

func _physics_process(dt: float) -> void:
	if Input.is_action_just_pressed("reset_room"):
		reset_room()
	if Input.is_action_just_pressed("inspect_room"):
		_toggle_debug()
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.18)
	var cycle := int(Input.is_action_just_pressed("target_next")) - int(Input.is_action_just_pressed("target_previous"))
	model.step(dt, direction, Input.is_action_just_pressed("possess"), cycle, Input.is_action_just_pressed("return_host"))
	_present_feedback()
	_refresh_status()

func reset_room() -> void:
	model.reset()
	last_effect = 0
	sound_player.stop()
	for node in $Possession.get_children():
		node.queue_free()
	_refresh_status()

func _toggle_debug() -> void:
	debug = not debug
	$Possession.debug = debug

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var bar := Panel.new()
	bar.position = Vector2(0, 700)
	bar.size = Vector2(1100, 60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101f20")
	style.border_color = Color("2d4644")
	style.border_width_top = 1
	bar.add_theme_stylebox_override("panel", style)
	canvas.add_child(bar)
	status_label = Label.new()
	status_label.position = Vector2(24, 10)
	status_label.size = Vector2(260, 28)
	status_label.add_theme_color_override("font_color", Color("d6e7cf"))
	status_label.add_theme_font_size_override("font_size", 16)
	bar.add_child(status_label)
	var controls := Label.new()
	controls.position = Vector2(275, 10)
	controls.text = "A / Space  release · enter     LB/RB / Q/E  choose     Y / R  reset"
	controls.add_theme_color_override("font_color", Color("a4b8ad"))
	controls.add_theme_font_size_override("font_size", 13)
	bar.add_child(controls)
	controller_label = Label.new()
	controller_label.position = Vector2(24, 37)
	controller_label.add_theme_color_override("font_color", Color("728e84"))
	controller_label.add_theme_font_size_override("font_size", 10)
	bar.add_child(controller_label)
	return_label = Label.new()
	return_label.position = Vector2(275, 37)
	return_label.add_theme_color_override("font_color", Color("a4b8ad"))
	return_label.add_theme_font_size_override("font_size", 11)
	bar.add_child(return_label)
	var inspect := Button.new()
	inspect.position = Vector2(955, 12)
	inspect.size = Vector2(122, 32)
	inspect.text = "Inspect · F1"
	inspect.focus_mode = Control.FOCUS_NONE
	inspect.pressed.connect(_toggle_debug)
	bar.add_child(inspect)
	_refresh_status()

func _controller_changed(_device: int, _connected: bool) -> void:
	if controller_label:
		controller_label.text = "Left stick / D-pad" if not Input.get_connected_joypads().is_empty() else "WASD / arrows · connect a gamepad"

func _refresh_status() -> void:
	if not status_label:
		return
	if model.mode == "won":
		status_label.text = "Home reached"
	elif model.mode == "spirit":
		status_label.text = "Spirit" if model.target_id.is_empty() else "Spirit: " + model.animal_by_id(model.target_id).name
	else:
		status_label.text = model.animal_by_id(model.active_id).name
	if return_label:
		return_label.text = "B / Esc  return to " + model.animal_by_id(model.anchor_id).name if model.mode == "spirit" else "B / Esc  return after release"

func _present_feedback() -> void:
	for effect in model.effects:
		if effect.id <= last_effect:
			continue
		last_effect = effect.id
		$Possession.burst(effect)
		var devices := Input.get_connected_joypads()
		if not devices.is_empty():
			var strong := 0.24 if effect.kind == "crash" else 0.07
			Input.start_joy_vibration(devices[0], 0.16, strong, 0.12)
		_play_sound(effect.kind)

func _play_sound(kind: String) -> void:
	sound_player.stream = sound_cues[kind]
	sound_player.volume_db = -13
	sound_player.play()

func _make_sound(kind: String) -> AudioStreamWAV:
	# Small synthesized cues: an airy release, a settling dive, and a low splash.
	# This is one room's sound palette, not an audio or asset management system.
	var duration := 0.6 if kind == "crash" else 0.25
	var sample_rate := 22050
	var bytes := PackedByteArray()
	bytes.resize(int(duration * sample_rate) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for i in int(duration * sample_rate):
		var t := float(i) / sample_rate
		var progress := t / duration
		var envelope := sin(progress * PI) * pow(1.0 - progress, 2.0)
		var frequency := lerpf(260.0, 760.0, progress) if kind == "release" else lerpf(650.0, 180.0, progress)
		var value := sin(t * frequency * TAU) * 0.18
		if kind == "crash":
			value = rng.randf_range(-0.3, 0.3) + sin(t * 62 * TAU) * 0.16
		elif kind == "win":
			value = (sin(t * 440 * TAU) + sin(t * 660 * TAU)) * 0.12
		bytes.encode_s16(i * 2, int(clampf(value * envelope, -1.0, 1.0) * 32767))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = sample_rate
	sound.data = bytes
	return sound
