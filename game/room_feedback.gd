extends Node2D

var model
var debug := false

func _ready() -> void:
	if OS.has_feature("web"):
		# The browser compiles the particle shader on its first rendered use.
		# Warm it in a tiny undisplayed viewport during startup, before release.
		var warmup := SubViewport.new()
		warmup.name = "ParticleWarmup"
		warmup.size = Vector2i(64, 64)
		warmup.transparent_bg = true
		warmup.disable_3d = true
		warmup.gui_disable_input = true
		warmup.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(warmup)
		var particles := _make_burst("release")
		particles.position = Vector2(32, 32)
		particles.preprocess = 0.1
		warmup.add_child(particles)
		get_tree().create_timer(0.25).timeout.connect(warmup.queue_free)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if model == null:
		return
	if model.mode == "spirit":
		_draw_tether()
	_draw_hosts()
	_draw_transitions()
	if debug:
		_draw_debug()

func _draw_tether() -> void:
	var origin: Vector2 = model.spirit_origin
	var spirit: Vector2 = model.render_spirit_position()
	var stretch: float = origin.distance_to(spirit) / model.spirit_range
	var points := PackedVector2Array()
	for i in 17:
		var along := float(i) / 16
		var point := origin.lerp(spirit, along)
		point += Vector2(0, sin(along * PI) * sin(model.render_time() * 3 + along * 5) * (1.0 - stretch) * 4)
		points.append(point)
	draw_polyline(points, Color(0.54, 0.9, 0.85, 0.25 + stretch * 0.4), 1.3, true)
	draw_circle(origin, 9 + sin(model.render_time() * 3) * 1.5, Color(0.4, 0.83, 0.75, 0.1))
	draw_circle(origin, 2.8, Color("baf8d9"))
	draw_arc(origin, model.spirit_range, 0, TAU, 90, Color(0.5, 0.8, 0.72, 0.13 + stretch * 0.24), 1.0, true)
	if stretch > 0.9:
		var angle := (spirit - origin).angle()
		draw_arc(origin, model.spirit_range, angle - 0.2, angle + 0.2, 18, Color("b7f1cf"), 2, true)

func _draw_hosts() -> void:
	for animal in model.animals:
		var pos: Vector2 = model.render_animal(animal.id).position
		var r: float = animal.radius
		if model.mode == "animal" and model.active_id == animal.id:
			# A soft connection, not a collision outline around every creature.
			draw_arc(pos, r + 8, 0.2, PI - 0.2, 28, Color(0.7, 0.91, 0.7, 0.5), 1.3, true)
		if model.mode == "spirit" and pos.distance_to(model.spirit_position) <= model.target_range:
			var selected: bool = model.target_id == animal.id
			var alpha := 0.8 if selected else 0.25
			draw_arc(pos, r + 11, 0, TAU, 48, Color(0.65, 0.91, 0.76, alpha), 1.1, true)
			if selected:
				draw_arc(pos, r + 14, -PI / 2, -PI / 2 + TAU * model.focus, 48, Color("f3e1a0"), 2.2, true)
				if model.focus >= 1:
					draw_circle(pos + Vector2(0, -r - 22), 2.5 + sin(model.render_time() * 5) * 0.5, Color("f3e1a0"))

func _draw_transitions() -> void:
	for effect in model.effects:
		var age: float = model.render_effect_age(effect)
		var pos: Vector2 = effect.position
		if effect.kind == "dive":
			# The recipient can already respond to input while the spirit dives.
			pos = model.render_animal(effect.host_id).position
		if effect.kind == "release" and age < 0.45:
			var u := age / 0.45
			draw_arc(pos, 6 + u * 42, 0, TAU, 56, Color(0.67, 1, 0.88, (1 - u) * 0.75), 2.4 * (1 - u) + 0.5, true)
		elif effect.kind == "dive" and age < 0.38:
			var u := age / 0.38
			var travel := smoothstep(0.0, 0.18, age)
			var streak := PackedVector2Array()
			for i in 18:
				var t := maxf(0.0, travel - (1.0 - float(i) / 17.0) * 0.22)
				var p: Vector2 = (effect.from as Vector2).lerp(pos, t)
				p.y -= sin(t * PI) * 10
				streak.append(p)
			draw_polyline(streak, Color(0.82, 1, 0.91, 1 - u), 3 * (1 - u) + 0.5, true)
			var head: Vector2 = streak[streak.size() - 1]
			draw_circle(head, 9.0 * (1.0 - u), Color(0.6, 1.0, 0.85, 0.2 * (1.0 - u)))
			draw_circle(head, 4.0 * (1.0 - u) + 0.5, Color(0.91, 1.0, 0.95, 1.0 - u))
			draw_arc(pos, 35 * (1 - u) + 5, 0, TAU, 56, Color(0.7, 1, 0.86, (1 - u) * 0.8), 2, true)
		elif effect.kind == "crash" and age < 1.5:
			var u := age / 1.5
			for side in [-1, 1]:
				draw_arc(pos + Vector2(0, side * 29), 10 + u * 65, 0.1, PI - 0.1, 40, Color(0.55, 0.85, 0.81, (1 - u) * 0.5), 1.6, true)
		elif effect.kind == "win" and age < 2:
			draw_arc(pos, 20 + age * 38, 0, TAU, 64, Color(1, 0.85, 0.45, (1 - age / 2) * 0.4), 2, true)

func _draw_debug() -> void:
	var font := ThemeDB.fallback_font
	for animal in model.animals:
		var pos: Vector2 = model.render_animal(animal.id).position
		draw_arc(pos, animal.radius, 0, TAU, 40, Color(1, 0.7, 0.4, 0.4), 1, true)
		draw_string(font, pos + Vector2(-18, animal.radius + 25), animal.name + " · " + animal.state, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e3e8cb"))
		if animal.state == "returning":
			draw_dashed_line(pos, animal.home, Color(0.9, 0.8, 0.5, 0.4), 1, 5)
	if model.mode == "spirit":
		draw_arc(model.render_spirit_position(), model.target_range, 0, TAU, 64, Color(0.8, 0.9, 1, 0.2), 1, true)
		draw_string(font, model.spirit_origin + Vector2(8, -12), "Release point", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e3e8cb"))

func burst(effect: Dictionary) -> void:
	var particles := _make_burst(effect.kind)
	particles.position = effect.position
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)

func _make_burst(kind: String) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 38 if kind == "crash" else 24
	particles.lifetime = 0.8 if kind == "crash" else 0.4
	particles.direction = Vector2.UP
	particles.spread = 180
	particles.gravity = Vector2(0, 95) if kind == "crash" else Vector2.ZERO
	particles.initial_velocity_min = 36
	particles.initial_velocity_max = 135 if kind == "crash" else 80
	particles.damping_min = 35
	particles.damping_max = 75
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.3
	var gradient := Gradient.new()
	var tint := Color("98dce0") if kind == "crash" else Color("d2ffe1")
	gradient.set_color(0, tint)
	tint.a = 0
	gradient.set_color(1, tint)
	particles.color_ramp = gradient
	return particles
