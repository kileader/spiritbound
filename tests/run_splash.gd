extends SceneTree

const SharedSplashScene = preload("res://studio/phicid_splash.tscn")
const SplashScene = preload("res://game/startup.tscn")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _open_splash():
	change_scene_to_packed(SplashScene)
	await scene_changed
	current_scene._sequence.pause()
	return current_scene

func _expect_game() -> void:
	for frame in 10:
		await physics_frame
		await process_frame
		if current_scene != null and current_scene.scene_file_path == "res://game/main.tscn":
			break
	var entered_game := current_scene != null and current_scene.scene_file_path == "res://game/main.tscn"
	_expect(entered_game, "Splash must continue to Spiritbound's normal room scene")
	if entered_game:
		await physics_frame
		await process_frame
		_expect(current_scene.model.mode == "animal" and current_scene.model.active_id == "mouse", "Splash input must not accidentally release the starting Mouse")
		_expect(current_scene.model.possessions == 0 and not current_scene.model.bridge_open, "The game must start with fresh puzzle state")

func _run() -> void:
	_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://game/startup.tscn", "Normal project startup must enter the game's configured studio splash")
	var shared_splash = SharedSplashScene.instantiate()
	_expect(shared_splash.next_scene_path.is_empty(), "The reusable splash must not name a Spiritbound scene")
	shared_splash.free()
	var splash = await _open_splash()
	var logo: TextureRect = splash.get_node("Logo")
	_expect(splash.get_node("Black").color == Color.BLACK, "Splash backdrop must be opaque black")
	_expect(logo.texture != null and logo.modulate.a == 0.0, "The provided logo must be loaded and initially invisible")
	_expect(logo.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and logo.expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "Logo layout must fit and center the complete image without stretching or cropping")
	_expect(logo.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "Logo downscaling must use smooth mipmap filtering")
	_expect(logo.texture.get_image().has_mipmaps(), "The imported logo must contain mipmaps for clean downscaling")
	_expect(logo.get_rect().get_center().is_equal_approx(splash.size * 0.5), "Logo must stay centered in the viewport")
	_expect(splash.hold_seconds >= 1.0 and splash.hold_seconds <= 2.0, "Default logo hold must last one to two seconds")
	var sequence: Tween = splash._sequence
	sequence.custom_step(splash.fade_in_seconds * 0.5)
	_expect(logo.modulate.a > 0.0 and logo.modulate.a < 1.0, "Logo must fade in through intermediate opacity")
	sequence.custom_step(splash.fade_in_seconds * 0.5)
	sequence.custom_step(splash.hold_seconds * 0.8)
	_expect(is_equal_approx(logo.modulate.a, 1.0) and current_scene == splash, "Logo must hold at full opacity before the game begins")
	sequence.custom_step(splash.hold_seconds * 0.2 + splash.fade_out_seconds * 0.5)
	_expect(logo.modulate.a > 0.0 and logo.modulate.a < 1.0, "Logo must fade back toward black before entering the game")
	sequence.custom_step(splash.fade_out_seconds * 0.5 + 0.01)
	await _expect_game()

	# Exercise the real event path with an action already mapped by the room.
	splash = await _open_splash()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await _expect_game()
	key.pressed = false
	Input.parse_input_event(key)

	splash = await _open_splash()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await _expect_game()
	mouse.pressed = false
	Input.parse_input_event(mouse)

	splash = await _open_splash()
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	Input.parse_input_event(button)
	await _expect_game()
	button.pressed = false
	Input.parse_input_event(button)

	splash = await _open_splash()
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.3
	Input.parse_input_event(motion)
	var repeated_key := InputEventKey.new()
	repeated_key.keycode = KEY_SPACE
	repeated_key.pressed = true
	repeated_key.echo = true
	Input.parse_input_event(repeated_key)
	await process_frame
	_expect(current_scene == splash and not splash._finished, "Stick drift and held-key repeats must not skip the splash")
	motion.axis_value = 0.0
	Input.parse_input_event(motion)
	splash._finish()
	splash._finish()
	await _expect_game()
	_expect(current_scene.get_node_or_null("PhicidSplash") == null, "Splash must be removed completely after transition")
	current_scene.reset_room()
	_expect(current_scene.scene_file_path == "res://game/main.tscn", "Puzzle reset must not replay the studio splash")

	# Another game's opening scene must work without changing the shared files.
	splash = await _open_splash()
	splash.next_scene_path = "res://tests/splash_destination.tscn"
	splash._finish()
	await scene_changed
	_expect(current_scene.scene_file_path == "res://tests/splash_destination.tscn", "The shared splash must enter any configured destination scene")
	# Let the audio mixer release the room's stopped music after scene removal.
	await create_timer(0.1).timeout

	if failures.is_empty():
		print("Phicid startup splash checks passed: %d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
