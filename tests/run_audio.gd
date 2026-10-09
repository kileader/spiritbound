extends SceneTree

const RoomScene = preload("res://game/main.tscn")
const RoomAudio = preload("res://game/room_audio.gd")
const TEST_SETTINGS := "res://artifacts/audio-test.cfg"
const DT := 1.0 / 60.0

var checks := 0
var failures: Array[String] = []
var room
var audio

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	room = RoomScene.instantiate()
	room.get_node("Audio").settings_path = TEST_SETTINGS
	root.add_child(room)
	room.set_physics_process(false)
	audio = room.audio
	await process_frame
	_test_bus_routing_and_controls()
	await _test_music_loop_and_reset()
	_test_movement_cues()
	await _test_settings_input()
	_test_saved_settings()
	# Let the player process the mixer's stopped playbacks before deleting it.
	# Seeking the looping WAV creates several playback references in headless runs.
	audio.bgm_player.stop()
	audio.stop_sfx()
	await create_timer(0.2).timeout
	room.queue_free()
	await create_timer(0.1).timeout
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	if failures.is_empty():
		print("Spiritbound audio checks passed: %d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("Spiritbound audio checks failed: %d of %d" % [failures.size(), checks])
		quit(1)

func _test_bus_routing_and_controls() -> void:
	_expect(audio.bgm_player.bus == &"BGM" and audio.effect_player.bus == &"SFX" and audio.movement_player.bus == &"SFX", "Music and both kinds of effects must use separate BGM/SFX buses")
	for bus in ["SFX", "BGM"]:
		_expect(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == &"Master", "%s must feed the Master bus" % bus)
	_expect(is_equal_approx(audio.get_volume("Master"), 0.8) and is_equal_approx(audio.get_volume("BGM"), 0.45), "Fresh installs must start with a comfortable music level")
	for bus in ["Master", "SFX", "BGM"]:
		var slider: HSlider = room.sound_settings.sliders[bus]
		slider.value = 0
		_expect(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus)), "%s slider at zero must really mute its bus" % bus)
		slider.value = 50
		_expect(not AudioServer.is_bus_mute(AudioServer.get_bus_index(bus)) and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(bus)), 0.5), "%s slider must unmute and apply its displayed volume" % bus)
		_expect(room.sound_settings.value_labels[bus].text == "50%", "%s must show the live percentage" % bus)
	room.sound_settings.sliders.SFX.value = 0
	_expect(not AudioServer.is_bus_mute(AudioServer.get_bus_index("BGM")), "Muting effects must leave music enabled")
	room.sound_settings.sliders.SFX.value = 50
	room.sound_settings.sliders.BGM.value = 0
	_expect(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "Muting music must leave effects enabled")
	room.sound_settings.sliders.BGM.value = 50
	for kind in ["release", "dive", "crash", "win"]:
		audio.play_effect(kind)
		_expect(audio.effect_player.playing and audio.effect_player.stream == audio.sound_cues[kind], "%s must play through the effect player" % kind)

func _test_music_loop_and_reset() -> void:
	var music: AudioStreamWAV = audio.bgm_player.stream
	_expect(music.get_length() > 80.0 and music.loop_mode == AudioStreamWAV.LOOP_FORWARD and music.loop_end > music.loop_begin, "Forest Whisper must import as a full forward-looping track")
	_expect(audio.bgm_player.playing, "Music must start when the room enters the tree")
	audio.bgm_player.seek(10.0)
	await create_timer(0.08).timeout
	room.reset_room()
	_expect(audio.bgm_player.playing and audio.bgm_player.get_playback_position() >= 10.0, "Puzzle reset must leave the current music playing without restarting it")
	audio.bgm_player.seek(music.get_length() - 0.1)
	await create_timer(0.3).timeout
	_expect(audio.bgm_player.playing and audio.bgm_player.get_playback_position() < 1.0, "Music must continue playing after crossing the loop boundary")

func _test_movement_cues() -> void:
	var game = room.model
	for id in ["mouse", "bird", "bear"]:
		audio.stop_sfx()
		game.mode = "animal"
		game.active_id = id
		var animal: Dictionary = game.animal_by_id(id)
		animal.pushing = false
		audio.update_movement(game, DT)
		_expect(audio.movement_kind.is_empty(), "%s must stay quiet before it moves" % id)
		animal.position += Vector2(2, 0)
		audio.update_movement(game, DT)
		_expect(audio.movement_kind == id and audio.movement_player.playing, "%s displacement must trigger its own movement cue" % id)
		audio.update_movement(game, DT)
		_expect(audio.movement_kind.is_empty() and not audio.movement_player.playing, "%s must stop making movement sounds when position stops changing" % id)
	game.animal_by_id("bear").pushing = true
	audio.update_movement(game, DT)
	_expect(audio.movement_kind == "push", "Pushing the trunk must use the wood texture instead of ordinary bear steps")
	game.mode = "spirit"
	audio.update_movement(game, DT)
	_expect(audio.movement_kind.is_empty(), "Disembodied movement must not emit animal footsteps")
	game.mode = "won"
	audio.update_movement(game, DT)
	_expect(not audio.movement_player.playing, "Reaching home must leave no movement sounds playing")
	room.reset_room()

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _test_settings_input() -> void:
	await _key(KEY_M, true)
	_expect(room.sound_settings.visible and root.gui_get_focus_owner() == room.sound_settings.sliders.Master, "M must open sound controls with the Master slider focused")
	await _key(KEY_M, false)
	var before: Vector2 = room.model.animal_by_id("mouse").position
	var before_time: float = room.model.time
	await _key(KEY_RIGHT, true)
	await _key(KEY_SPACE, true)
	room._physics_process(DT)
	_expect(room.model.time == before_time and room.model.animal_by_id("mouse").position == before and room.model.mode == "animal", "Adjusting sound must not advance the puzzle, move, or release the Mouse")
	await _key(KEY_RIGHT, false)
	await _key(KEY_SPACE, false)
	await _key(KEY_DOWN, true)
	_expect(root.gui_get_focus_owner() == room.sound_settings.sliders.SFX, "Down must focus the SFX slider")
	await _key(KEY_DOWN, false)
	await _key(KEY_ESCAPE, true)
	room._physics_process(DT)
	_expect(not room.sound_settings.visible and room.model.mode == "animal", "Escape must close sound controls without a gameplay action")
	await _key(KEY_ESCAPE, false)
	room._physics_process(DT)
	_expect(room.model.time > before_time, "Gameplay must resume after the close press has passed")
	room.model.release()
	room._toggle_sound_settings()
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_B
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	room._physics_process(DT)
	_expect(not room.sound_settings.visible and room.model.mode == "spirit", "Gamepad B must close sound controls without reclaiming the released host")
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	event.button_index = JOY_BUTTON_START
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	_expect(room.sound_settings.visible, "Gamepad Start must open sound controls")
	event.pressed = false
	Input.parse_input_event(event)
	room.sound_settings.close()
	room.reset_room()

func _test_saved_settings() -> void:
	audio.set_volume("Master", 0.62)
	audio.set_volume("SFX", 0.0)
	audio.set_volume("BGM", 0.27)
	var reloaded := RoomAudio.new()
	reloaded.settings_path = TEST_SETTINGS
	root.add_child(reloaded)
	_expect(is_equal_approx(reloaded.get_volume("Master"), 0.62) and reloaded.get_volume("SFX") == 0.0 and is_equal_approx(reloaded.get_volume("BGM"), 0.27), "All three volume settings must survive a new audio instance")
	_expect(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "A saved zero volume must remain muted on launch")
	reloaded.queue_free()
	var invalid := ConfigFile.new()
	invalid.set_value("audio", "Master", "broken")
	invalid.set_value("audio", "SFX", 2.0)
	invalid.set_value("audio", "BGM", -1.0)
	invalid.save(TEST_SETTINGS)
	var sanitized := RoomAudio.new()
	sanitized.settings_path = TEST_SETTINGS
	root.add_child(sanitized)
	_expect(sanitized.get_volume("Master") == 0.8 and sanitized.get_volume("SFX") == 1.0 and sanitized.get_volume("BGM") == 0.0, "Malformed or out-of-range settings must fall back or clamp safely")
	sanitized.queue_free()
