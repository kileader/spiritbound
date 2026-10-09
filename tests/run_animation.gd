extends SceneTree

const RoomScene = preload("res://game/main.tscn")
const DT := 1.0 / 60.0
const VIEW_NAMES := ["Mouse", "Bird", "Bear", "Spirit", "ReclaimedClearing", "Possession"]

var room
var game
var failures: Array[String] = []
var checks := 0
var draw_counts: Dictionary = {}
var poses_remained_valid := true
var accumulator := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	room = RoomScene.instantiate()
	root.add_child(room)
	game = room.model
	_disable_automatic_steps(room)
	_watch_draws(room)
	await _test_return_input_and_status()
	await _test_spirit_preparation()
	for rate in [30, 60, 144]:
		await _exercise_rate(rate)
	await process_frame
	await process_frame
	_expect(poses_remained_valid, "All animal and spirit positions and pose blends must remain finite and bounded")
	_expect(int(draw_counts.get("Mouse", 0)) > 1 and int(draw_counts.get("Bird", 0)) > 1 and int(draw_counts.get("Bear", 0)) > 1, "The headless smoke must execute actual animal drawing across pose transitions")
	_expect(int(draw_counts.get("ReclaimedClearing", 0)) > 1, "The headless smoke must execute moving water and trunk drawing")
	_expect(int(draw_counts.get("StillForest", 0)) >= 1 and int(draw_counts.get("StillCanopy", 0)) >= 1, "Both cached illustration layers must execute their own CanvasItem drawing")
	await _test_scenery_cache()
	_test_stroke_reuse()
	# Give the audio mixer a cycle to release the continuous music playback.
	room.queue_free()
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("Spiritbound animation checks passed: %d at 30/60/144 Hz" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("Spiritbound animation checks failed: %d of %d" % [failures.size(), checks])
		quit(1)


func _test_scenery_cache() -> void:
	var art = room.get_node("ReclaimedClearing")
	var before := [int(draw_counts.get("StillForest", 0)), int(draw_counts.get("StillCanopy", 0))]
	await _advance(60, 0.1, Vector2.RIGHT)
	_expect(before == [int(draw_counts.get("StillForest", 0)), int(draw_counts.get("StillCanopy", 0))], "Moving animals and water must leave the cached scenery untouched")
	# A different room model must invalidate the illustrations once, while
	# resetting the existing room must leave its unchanged scenery cached.
	art.model = preload("res://game/room_model.gd").new()
	await process_frame
	await process_frame
	_expect(int(draw_counts.get("StillForest", 0)) == before[0] + 1 and int(draw_counts.get("StillCanopy", 0)) == before[1] + 1, "Replacing room geometry must redraw both illustration layers once")
	art.model = game
	await process_frame
	await process_frame
	room.reset_room()
	_process_views(0.0)
	before = [int(draw_counts.get("StillForest", 0)), int(draw_counts.get("StillCanopy", 0))]
	await _advance(60, 0.1)
	_expect(before == [int(draw_counts.get("StillForest", 0)), int(draw_counts.get("StillCanopy", 0))], "Puzzle reset must preserve the scenery textures")


func _test_spirit_preparation() -> void:
	var spirit = room.get_node("Spirit")
	var prepared: Array[RID] = []
	for stroke in spirit._strokes:
		prepared.append(stroke.mesh.get_rid())
	_expect(not prepared.is_empty(), "The spirit's drawing meshes must be prepared during startup")
	game.release()
	_process_views(0.0)
	await process_frame
	await process_frame
	var displayed: Array[RID] = []
	for stroke in spirit._strokes:
		displayed.append(stroke.mesh.get_rid())
	_expect(spirit.visible and displayed == prepared, "The first spirit appearance must reuse its prepared body and curve meshes")
	room.reset_room()
	_process_views(0.0)


func _test_stroke_reuse() -> void:
	var stroke = preload("res://game/stroke_mesh.gd").new()
	var mesh: ArrayMesh = stroke.update(PackedVector2Array([Vector2.ZERO, Vector2(5, 2), Vector2(10, 0)]), 0.8)
	var identity := mesh.get_rid()
	stroke.update(PackedVector2Array([Vector2.ZERO, Vector2(6, -2), Vector2(12, 0)]), 1.4)
	_expect(mesh.get_rid() == identity and mesh.get_surface_count() == 1, "Animated stroke points and width must reuse their mesh resource")
	stroke.update(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(10, 0), Vector2(10, 10)]), 2.0, true)
	var vertices: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var valid := true
	for vertex in vertices:
		valid = valid and vertex.is_finite()
	_expect(mesh.get_rid() == identity and valid, "Stroke topology changes and repeated points must produce finite geometry")
	stroke.update(PackedVector2Array(), 1.0)
	_expect(mesh.get_surface_count() == 0, "An empty stroke must clear its previous geometry")


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
	return condition


func _test_return_input_and_status() -> void:
	var keyboard_bound := false
	var gamepad_bound := false
	for event in InputMap.action_get_events("return_host"):
		if event is InputEventKey:
			keyboard_bound = keyboard_bound or event.physical_keycode == KEY_ESCAPE
		elif event is InputEventJoypadButton:
			gamepad_bound = gamepad_bound or event.button_index == JOY_BUTTON_B
	_expect(keyboard_bound and gamepad_bound, "Return must be bound to Escape and gamepad B")
	game.release()
	room._refresh_status()
	_expect(room.status_label.text == "Spirit: Mouse", "The selected host status must use readable text instead of the missing arrow glyph")
	_expect(room.return_label.text == "B / Esc  return to Mouse", "The HUD must identify the animal that return will reclaim")
	var glyphs_supported := true
	for label in [room.status_label, room.return_label]:
		var font: Font = label.get_theme_font("font")
		for index in label.text.length():
			glyphs_supported = glyphs_supported and font.has_char(label.text.unicode_at(index))
	_expect(glyphs_supported, "The HUD font must contain every character used by the spirit status and return hint")
	game.animal_by_id("mouse").position = Vector2(240, 542)
	Input.action_press("return_host")
	# Godot exposes just-pressed actions on the next input frame, as it does
	# during normal play. A same-frame manual callback skips that boundary.
	await process_frame
	room._physics_process(DT)
	Input.action_release("return_host")
	_process_views(0.0)
	_expect(game.mode == "animal" and game.active_id == "mouse" and not room.get_node("Spirit").visible, "The return input must reclaim the body and hide the spirit in the actual scene")
	_expect(room.status_label.text == "Mouse", "Return input must update the HUD to the controlled animal")
	room.reset_room()


func _disable_automatic_steps(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_disable_automatic_steps(child)


func _watch_draws(node: Node) -> void:
	if node is CanvasItem:
		node.draw.connect(_on_draw.bind(str(node.name)))
	for child in node.get_children():
		_watch_draws(child)


func _on_draw(node_name: String) -> void:
	draw_counts[node_name] = int(draw_counts.get(node_name, 0)) + 1


func _process_views(delta: float) -> void:
	for node_name in VIEW_NAMES:
		room.get_node(node_name)._process(delta)
	for node_name in ["Mouse", "Bird", "Bear", "Spirit"]:
		var view = room.get_node(node_name)
		poses_remained_valid = poses_remained_valid and view.position.is_finite()
		for field in ["_move_blend", "_push_blend", "_rest_blend", "_flight_blend"]:
			var value: float = view.get(field)
			poses_remained_valid = poses_remained_valid and is_finite(value) and value >= -0.00001 and value <= 1.00001
		poses_remained_valid = poses_remained_valid and is_finite(view._turn_blend) and is_finite(view._wing_phase)
	var trunk: Rect2 = room.get_node("ReclaimedClearing")._trunk_rect
	poses_remained_valid = poses_remained_valid and trunk.position.is_finite() and trunk.size.is_finite()


func _frame(rate: int, direction: Vector2 = Vector2.ZERO) -> void:
	var delta := 1.0 / float(rate)
	accumulator += delta
	while accumulator >= DT - 0.000001:
		game.step(DT, direction)
		accumulator -= DT
	_process_views(delta)
	await process_frame


func _advance(rate: int, seconds: float, direction: Vector2 = Vector2.ZERO) -> void:
	for _frame_index in range(ceili(seconds * float(rate))):
		await _frame(rate, direction)


func _select_animal(id: String, at: Vector2) -> void:
	for animal in game.animals:
		animal.state = "resting"
		animal.velocity = Vector2.ZERO
	var animal: Dictionary = game.animal_by_id(id)
	animal.position = at
	animal.state = "controlled"
	game.active_id = id
	game.mode = "animal"
	game.step(0.0)
	_process_views(0.0)


func _exercise_rate(rate: int) -> void:
	room.reset_room()
	accumulator = 0.0
	_process_views(0.0)
	await _advance(rate, 0.2)
	await _advance(rate, 0.35, Vector2.RIGHT)
	var moving_mouse: Vector2 = room.get_node("Mouse").position
	await _advance(rate, 0.35)
	_expect(moving_mouse.x > game.burrow.x and room.get_node("Mouse")._move_blend < 0.1, "%d Hz: the Mouse must move and settle after input stops" % rate)

	_select_animal("bird", Vector2(490, 245))
	var bird = room.get_node("Bird")
	var previous_gait: float = game.animal_by_id("bird").gait
	var previous_phase: float = bird._wing_phase
	_process_views(1.0 / float(rate))
	_process_views(1.0 / float(rate))
	_expect(game.animal_by_id("bird").gait == previous_gait and bird._wing_phase != previous_phase, "%d Hz: wing motion must continue independently of travelled distance" % rate)
	await _advance(rate, 0.45, Vector2.RIGHT)
	var flying_blend: float = bird._flight_blend
	_expect(flying_blend > 0.0 and flying_blend < 1.0, "%d Hz: takeoff must blend through an intermediate flight pose" % rate)
	await _advance(rate, 0.5)
	_expect(bird._flight_blend < flying_blend, "%d Hz: landing must ease out of flight after movement stops" % rate)
	game.release()
	_process_views(0.0)
	_expect(room.get_node("Spirit").visible and room.get_node("Spirit").position == game.spirit_origin, "%d Hz: release must reveal the spirit at its new origin immediately" % rate)
	room.get_node("Possession").burst(game.effects[-1])
	await _advance(rate, 0.2)
	game.target_id = "bird"
	game.focus = 1.0
	_expect(game.possess(), "%d Hz: the nearby released Bird must remain reclaimable" % rate)
	_process_views(0.0)
	_expect(not room.get_node("Spirit").visible, "%d Hz: possession must hide the spirit without residual presentation lag" % rate)
	room.get_node("Possession").burst(game.effects[-1])
	await _advance(rate, 0.15)

	_select_animal("bear", Vector2(850, 467))
	await _advance(rate, 0.2, Vector2.LEFT)
	var bear = room.get_node("Bear")
	var braced_blend: float = bear._push_blend
	_expect(braced_blend > 0.0 and braced_blend < 1.0, "%d Hz: trunk pushing must ease into bracing rather than switch abruptly" % rate)
	game.release()
	await _advance(rate, 0.35)
	_expect(bear._push_blend < braced_blend, "%d Hz: the Bear must relax its pushing pose after release" % rate)
	_select_animal("bear", Vector2(855, 467))
	for _frame_index in range(rate * 3):
		await _frame(rate, Vector2.LEFT)
		if game.bridge_open:
			break
	_expect(game.bridge_open, "%d Hz: animated pushing must still open the trunk crossing" % rate)
	await _advance(rate, 0.4)
	_expect(room.get_node("ReclaimedClearing")._trunk_rect == game.bridge, "%d Hz: the falling trunk must finish settling onto the playable crossing" % rate)

	room.reset_room()
	_process_views(1.0 / float(rate))
	var reset_views_match := true
	for animal in game.animals:
		var view = room.get_node(animal.name)
		reset_views_match = reset_views_match and view.position == animal.position and view._last_reset_serial == game.reset_serial
	_expect(reset_views_match, "%d Hz: reset must place every view at its restored animal immediately" % rate)
	_expect(room.get_node("Mouse")._move_blend == 0.0 and bear._push_blend == 0.0 and bird._flight_blend == 0.0, "%d Hz: reset must clear movement, bracing, and flight follow-through" % rate)
	_expect(room.get_node("ReclaimedClearing")._trunk_rect == Rect2(688, 431, 132, 72), "%d Hz: reset must cancel trunk settling immediately" % rate)
	_expect(not room.get_node("Spirit").visible and game.effects.is_empty() and game.trail.is_empty(), "%d Hz: reset must clear possession visuals and their history" % rate)
	await process_frame
