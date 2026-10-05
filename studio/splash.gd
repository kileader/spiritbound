extends Control
## Copy studio/ into another Godot game and set this scene's next_scene_path.

@export_file("*.tscn") var next_scene_path: String
@export_range(0.0, 3.0, 0.05) var fade_in_seconds := 0.45
@export_range(0.0, 5.0, 0.1) var hold_seconds := 1.5
@export_range(0.0, 3.0, 0.05) var fade_out_seconds := 0.45

var _sequence: Tween
var _finished := false

func _ready() -> void:
	$Logo.modulate.a = 0.0
	_sequence = create_tween()
	_sequence.tween_property($Logo, "modulate:a", 1.0, fade_in_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sequence.tween_interval(hold_seconds)
	_sequence.tween_property($Logo, "modulate:a", 0.0, fade_out_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sequence.tween_callback(_finish)

func _input(event: InputEvent) -> void:
	var skip := false
	if event is InputEventKey:
		skip = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		skip = event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	elif event is InputEventJoypadButton:
		skip = event.pressed
	if skip:
		get_viewport().set_input_as_handled()
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_sequence.kill()
	# Let the skip press pass through one physics tick before the game loads,
	# so its first frame cannot interpret that same press as a gameplay action.
	await get_tree().physics_frame
	var error := get_tree().change_scene_to_file(next_scene_path)
	if error != OK:
		push_error("Studio splash could not open %s (error %d)" % [next_scene_path, error])
