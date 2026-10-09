extends Node
## Audio presentation reads room state; it never changes puzzle rules.

const MUSIC = preload("res://audio/forest_whisper.wav")
const DEFAULT_VOLUMES := {"Master": 0.8, "SFX": 1.0, "BGM": 0.45}
const MOVEMENT_INTERVALS := {"mouse": 0.13, "bird": 0.3, "bear": 0.43, "push": 0.5}

var settings_path := "user://audio.cfg"
var volumes: Dictionary = DEFAULT_VOLUMES.duplicate()
var bgm_player: AudioStreamPlayer
var effect_player: AudioStreamPlayer
var movement_player: AudioStreamPlayer
var sound_cues: Dictionary = {}
var movement_kind := ""
var movement_cooldown := 0.0
var previous_positions: Dictionary = {}
var previous_reset_serial := -1

func _ready() -> void:
	_load_settings()
	bgm_player = _player("BGM", "BGM")
	bgm_player.stream = MUSIC
	# Stream playback keeps the loop and bus mixing consistent in web exports.
	bgm_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	effect_player = _player("Effects", "SFX")
	effect_player.volume_db = -13.0
	movement_player = _player("Movement", "SFX")
	movement_player.volume_db = -18.0
	for kind in ["release", "dive", "crash", "win", "mouse", "bird", "bear", "push"]:
		sound_cues[kind] = _make_sound(kind)
	bgm_player.play()

func _exit_tree() -> void:
	bgm_player.stop()
	effect_player.stop()
	movement_player.stop()

func _player(player_name: String, bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus
	add_child(player)
	return player

func get_volume(bus: String) -> float:
	return volumes[bus]

func set_volume(bus: String, value: float) -> void:
	if not DEFAULT_VOLUMES.has(bus) or not is_finite(value):
		return
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	var config := ConfigFile.new()
	for name in volumes:
		config.set_value("audio", name, volumes[name])
	var error := config.save(settings_path)
	if error != OK:
		push_warning("Could not save sound settings (error %d)" % error)

func _load_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	for bus in DEFAULT_VOLUMES:
		var value: Variant = config.get_value("audio", bus, DEFAULT_VOLUMES[bus])
		if (value is float or value is int) and is_finite(float(value)):
			volumes[bus] = clampf(float(value), 0.0, 1.0)
		_apply_volume(bus)

func _apply_volume(bus: String) -> void:
	var index := AudioServer.get_bus_index(bus)
	var value: float = volumes[bus]
	# Zero is a real mute, with a finite gain so unmuting stays predictable.
	AudioServer.set_bus_mute(index, value == 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(value) if value > 0.0 else -80.0)

func play_effect(kind: String) -> void:
	if sound_cues.has(kind):
		effect_player.stream = sound_cues[kind]
		effect_player.play()

func stop_sfx() -> void:
	effect_player.stop()
	movement_player.stop()
	movement_kind = ""
	movement_cooldown = 0.0
	previous_positions.clear()

func update_movement(model, dt: float) -> void:
	if model.reset_serial != previous_reset_serial:
		stop_sfx()
		previous_reset_serial = model.reset_serial
	var kind := ""
	for animal in model.animals:
		var position: Vector2 = animal.position
		var previous: Vector2 = previous_positions.get(animal.id, position)
		if model.mode == "animal" and animal.id == model.active_id:
			# Actual displacement avoids footsteps while pressing against a wall.
			if animal.pushing:
				kind = "push"
			elif position.distance_squared_to(previous) > 0.01:
				kind = animal.id
		previous_positions[animal.id] = position
	if kind != movement_kind:
		movement_player.stop()
		movement_cooldown = 0.0
		movement_kind = kind
	if kind.is_empty():
		return
	movement_cooldown -= dt
	if movement_cooldown <= 0.0:
		movement_player.stream = sound_cues[kind]
		movement_player.play()
		movement_cooldown = MOVEMENT_INTERVALS[kind]

func _make_sound(kind: String) -> AudioStreamWAV:
	# Short deterministic textures: leaf scuffs, soft wing air, weighty paws,
	# wood creak, and the room's existing spirit/splash cues. No asset system.
	var durations := {"crash": 0.6, "mouse": 0.065, "bird": 0.22, "bear": 0.16, "push": 0.42}
	var duration: float = durations.get(kind, 0.25)
	var sample_rate := 22050
	var bytes := PackedByteArray()
	bytes.resize(int(duration * sample_rate) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var filtered_noise := 0.0
	for i in int(duration * sample_rate):
		var t := float(i) / sample_rate
		var progress := t / duration
		var envelope := sin(progress * PI) * pow(1.0 - progress, 2.0)
		var noise := rng.randf_range(-1.0, 1.0)
		filtered_noise = lerpf(filtered_noise, noise, 0.18)
		var frequency := lerpf(260.0, 760.0, progress) if kind == "release" else lerpf(650.0, 180.0, progress)
		var value := sin(t * frequency * TAU) * 0.18
		match kind:
			"crash":
				value = noise * 0.3 + sin(t * 62.0 * TAU) * 0.16
			"win":
				value = (sin(t * 440.0 * TAU) + sin(t * 660.0 * TAU)) * 0.12
			"mouse":
				value = (noise - filtered_noise) * 0.26 + filtered_noise * 0.2
			"bird":
				value = filtered_noise * 1.1 * pow(sin(progress * PI), 2.0)
			"bear":
				value = filtered_noise * 0.65 + sin(t * lerpf(95.0, 48.0, progress) * TAU) * 0.3
			"push":
				value = sin(t * (118.0 + sin(t * 34.0) * 14.0) * TAU) * 0.13 + filtered_noise * 0.5
		bytes.encode_s16(i * 2, int(clampf(value * envelope, -1.0, 1.0) * 32767))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = sample_rate
	sound.data = bytes
	return sound
