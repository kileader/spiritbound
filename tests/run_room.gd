extends SceneTree

const Model = preload("res://game/room_model.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_test_mouse_and_flight_constraints()
	_test_possession_focus_and_targeting()
	_test_fixed_release_origin()
	_test_idle_bounds()
	_test_fresh_release_and_reset()
	_test_trunk_and_exit_constraints()
	_test_complete_possession_chain()
	_test_rendered_movement()
	_test_rendered_angle_wrap()
	_test_render_state_isolation()
	_test_rendered_release_and_reset()
	_test_rendered_spirit_and_timestamps()
	if failures.is_empty():
		print("Spiritbound room checks passed: %d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("Spiritbound room checks failed: %d of %d" % [failures.size(), checks])
		quit(1)


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
	return condition


func _tick(game, frames: int, direction: Vector2 = Vector2.ZERO) -> void:
	for _frame in range(frames):
		game.step(DT, direction)


func _body_position(game) -> Vector2:
	if game.mode == "spirit":
		return game.spirit_position
	return game.animal_by_id(game.active_id).position


func _move_to(game, destination: Vector2, tolerance: float = 5.0) -> bool:
	for _frame in range(2400):
		if game.mode == "won":
			return true
		var position: Vector2 = _body_position(game)
		if position.distance_to(destination) <= tolerance:
			return true
		game.step(DT, position.direction_to(destination))
	return _expect(false, "Could not move %s to %s; stopped at %s" % [game.active_id, destination, _body_position(game)])


func _transfer_to(game, id: String) -> bool:
	if game.mode == "animal" and not _expect(game.release(), "Release must succeed before transferring to %s" % id):
		return false
	if not _expect(game.mode == "spirit", "A transfer to %s must start in spirit mode" % id):
		return false
	for _frame in range(1800):
		var target: Dictionary = game.animal_by_id(id)
		var direction := Vector2.ZERO
		if game.spirit_position.distance_to(target.position) > game.target_range - 12.0:
			direction = game.spirit_position.direction_to(target.position)
		game.step(DT, direction)
		if game.target_id == id and game.focus >= 1.0:
			return _expect(game.possess() and game.active_id == id, "A valid focused %s must always be possessable" % id)
	return _expect(false, "Could not transfer to %s from release origin %s" % [id, game.spirit_origin])


func _reach_first_bird(game) -> bool:
	return _move_to(game, Vector2(270, 417)) and _move_to(game, Vector2(350, 417)) and _move_to(game, Vector2(490, 245))


func _select_animal(game, id: String, position: Vector2) -> Dictionary:
	for animal in game.animals:
		animal.state = "resting"
	var animal: Dictionary = game.animal_by_id(id)
	animal.position = position
	animal.state = "controlled"
	if animal.has("velocity"):
		animal.velocity = Vector2.ZERO
	game.mode = "animal"
	game.active_id = id
	return animal


func _target_present(game, id: String) -> bool:
	for target in game.valid_targets():
		if target.id == id:
			return true
	return false


func _test_mouse_and_flight_constraints() -> void:
	var game = Model.new()
	_move_to(game, Vector2(278, 245))
	game.release()
	_tick(game, 180, Vector2.RIGHT)
	_expect(not _target_present(game, "bird"), "The first root wall and limited tether must prevent a direct transfer")
	game = Model.new()
	if _reach_first_bird(game):
		_expect(game.animal_by_id("mouse").position.x > 326.0, "The Mouse must fit through the root slit")
		_transfer_to(game, "bird")

	game = Model.new()
	var mouse: Dictionary = _select_animal(game, "mouse", Vector2(490, 467))
	_tick(game, 120, Vector2.RIGHT)
	_expect(mouse.position.x <= game.river.position.x - mouse.radius + 0.01, "The Mouse must not cross the unbridged river")
	game = Model.new()
	var bird: Dictionary = _select_animal(game, "bird", Vector2(490, 245))
	_move_to(game, Vector2(800, 245))
	_move_to(game, Vector2(200, 245))
	_expect(bird.position.x < 300.0, "The Bird must fly across the river and roots")
	game = Model.new()
	var bear: Dictionary = _select_animal(game, "bear", Vector2(370, 417))
	_tick(game, 120, Vector2.LEFT)
	_expect(bear.position.x > 326.0, "The Bear must not fit through the Mouse slit")


func _test_possession_focus_and_targeting() -> void:
	var game = Model.new()
	if not _reach_first_bird(game):
		return
	var release_position: Vector2 = game.animal_by_id("mouse").position
	_expect(game.release(), "Release must succeed while controlling an animal")
	_expect(game.spirit_position == release_position, "Release must emerge at the animal's current position")
	_expect(game.spirit_has_origin and game.spirit_origin == release_position, "Release must snapshot the tether origin")
	_expect(game.target_id == "bird", "A nearby new host must be targeted before the animal just released")
	_expect(not game.possess(), "Focus must complete before direct possession")
	game.step(DT, Vector2.ZERO, true)
	_expect(game.mode == "spirit", "An early action must begin buffering without skipping focus")
	_tick(game, 15)
	_expect(game.mode == "animal" and game.active_id == "bird", "An early action must possess the Bird when focus finishes")

	game = Model.new()
	game.release()
	game.target_id = "bird"
	game.focus = 1.0
	_expect(not game.possess(), "A stale focused target must not bypass range validation")

	game = Model.new()
	if not _reach_first_bird(game):
		return
	game.release()
	game.cycle_target()
	_expect(game.target_id == "mouse", "Manual cycling must allow reclaiming the released Mouse")
	_tick(game, 15)
	_expect(_target_present(game, "bird"), "The Bird must still be valid during the short reclaim focus")
	_expect(game.target_id == "mouse" and game.focus >= 1.0, "Manual targeting must persist while another host is available")
	_expect(game.possess() and game.active_id == "mouse", "A valid focused reclaim must always succeed")


func _test_fixed_release_origin() -> void:
	var game = Model.new()
	if not _reach_first_bird(game):
		return
	var release_position: Vector2 = game.animal_by_id("mouse").position
	game.release()
	_tick(game, 700)
	var mouse: Dictionary = game.animal_by_id("mouse")
	_expect(mouse.state == "resting" and mouse.position == game.burrow, "The released Mouse must autonomously return through its slit")
	_expect(mouse.position.distance_to(release_position) > game.spirit_range, "The return host must move beyond the release tether")
	_expect(game.spirit_position == release_position, "An idle spirit must remain at the release point as its former host returns")
	_expect(game.spirit_origin == release_position, "The tether origin must not follow the returning animal")
	var remained_in_range := true
	for _frame in range(180):
		game.step(DT, Vector2.RIGHT)
		remained_in_range = remained_in_range and game.spirit_position.distance_to(release_position) <= game.spirit_range + 0.001
	_expect(remained_in_range, "Spirit movement must stay inside the fixed release radius every step")
	_expect(absf(game.spirit_position.distance_to(release_position) - game.spirit_range) < 0.001, "Spirit movement must reach the fixed radius instead of the former host")


func _test_fresh_release_and_reset() -> void:
	var game = Model.new()
	game.release()
	var first_origin: Vector2 = game.spirit_origin
	_tick(game, 15)
	if not _expect(game.possess(), "The Mouse must be reclaimable at its burrow"):
		return
	_move_to(game, Vector2(240, 520))
	var second_origin: Vector2 = game.animal_by_id("mouse").position
	game.release()
	_expect(game.spirit_has_origin and game.spirit_origin == second_origin, "A second release must establish a fresh origin")
	_expect(game.spirit_origin != first_origin and first_origin == game.burrow, "A previous release point must remain a snapshot")
	game.reset()
	_expect(game.mode == "animal" and game.active_id == "mouse", "Reset must immediately restore control of the Mouse")
	_expect(not game.spirit_has_origin, "Reset must clear the active tether origin")
	_expect(game.focus == 0.0 and game.target_id == "", "Reset must clear focus and targeting")
	_expect(game.possessions == 0 and not game.bridge_open, "Reset must clear possession count and the trunk crossing")
	_expect(game.block.position.x == 688.0, "Reset must restore the fallen trunk")


func _test_idle_bounds() -> void:
	var game = Model.new()
	game.release()
	_tick(game, 3600)
	_expect(game.mode == "spirit" and game.spirit_position == game.burrow and game.spirit_origin == game.burrow, "A minute of idle time must preserve the spirit and its release point")
	_expect(game.animal_by_id("mouse").position == game.burrow and game.animal_by_id("bird").position == Vector2(490, 245) and game.animal_by_id("bear").position == game.food, "Idle animation must not move resting hosts or change the puzzle")
	_expect(not game.bridge_open and game.block == Rect2(688, 431, 132, 72), "Idle animation must not alter environmental geometry")
	_expect(game.effects.is_empty(), "Completed transition effects must expire during a long idle")
	_expect(game.trail.size() <= 60, "The idle spirit trail must remain bounded to less than a second of history")


func _test_trunk_and_exit_constraints() -> void:
	var game = Model.new()
	_select_animal(game, "mouse", Vector2(850, 467))
	var initial_x: float = game.block.position.x
	_tick(game, 100, Vector2.LEFT)
	_expect(game.block.position.x == initial_x and not game.bridge_open, "The Mouse must not move the heavy trunk")
	game = Model.new()
	var bear: Dictionary = _select_animal(game, "bear", Vector2(855, 467))
	for _frame in range(300):
		if game.bridge_open:
			break
		game.step(DT, Vector2.LEFT)
	_expect(game.bridge_open, "The Bear must be able to push the trunk into the stream")
	_tick(game, 120, Vector2.LEFT)
	_expect(bear.position.x >= game.river.end.x + bear.radius - 0.01, "The hollow trunk crossing must remain too narrow for the Bear")
	var mouse: Dictionary = _select_animal(game, "mouse", Vector2(490, 467))
	_move_to(game, Vector2(685, 467))
	_expect(mouse.position.x > game.river.end.x, "The Mouse must be able to traverse the hollow trunk")
	_select_animal(game, "mouse", Vector2(590, 453))
	game.release()
	_tick(game, 1200)
	_expect(mouse.state == "resting" and mouse.position == game.burrow, "A Mouse released off the trunk center must still find its burrow")

	game = Model.new()
	game.bridge_open = true
	mouse = _select_animal(game, "mouse", Vector2(875, 245))
	_tick(game, 100, Vector2.RIGHT)
	_expect(mouse.position.x < 922.0, "The Mouse must use the final opening rather than bypass its roots")
	game = Model.new()
	var bird: Dictionary = _select_animal(game, "bird", Vector2(900, 572))
	_tick(game, 100, Vector2.RIGHT)
	_expect(bird.position.x <= 944.0 - bird.radius + 0.01 and game.mode != "won", "The Bird must not fly into the covered exit")


func _test_complete_possession_chain() -> void:
	var game = Model.new()
	if not _reach_first_bird(game) or not _transfer_to(game, "bird"):
		return
	if not _move_to(game, Vector2(835, 245)) or not _transfer_to(game, "bear"):
		return
	_expect(game.animal_by_id("bird").home == game.perches[1], "The Bird must choose the east perch when released on the east bank")
	_move_to(game, Vector2(855, 467))
	for _frame in range(300):
		if game.bridge_open:
			break
		game.step(DT, Vector2.LEFT)
	if not _expect(game.bridge_open, "The full chain must open the trunk crossing"):
		return
	_move_to(game, Vector2(775, 245))
	game.release()
	var east_origin: Vector2 = game.spirit_origin
	_tick(game, 300)
	_expect(game.animal_by_id("bear").state == "resting", "The Bear must return to its food location after release")
	_expect(game.animal_by_id("bird").state == "resting", "The Bird must remain available at its east perch")
	_expect(game.spirit_position == east_origin, "Waiting for the east hosts must not drag the spirit")
	if not _transfer_to(game, "bird") or not _move_to(game, Vector2(360, 500)):
		return
	game.release()
	_tick(game, 300)
	_expect(game.animal_by_id("bird").state == "resting", "The Bird must return to its west perch")
	_expect(game.animal_by_id("mouse").state == "resting", "The Mouse must wait at its burrow for the return transfer")
	if not _transfer_to(game, "mouse"):
		return
	_expect(game.animal_by_id("bird").home == game.perches[0], "The final Bird release must choose the west perch")
	var destinations: Array[Vector2] = [Vector2(270, 417), Vector2(350, 417), Vector2(490, 467), Vector2(685, 467), Vector2(875, 572), Vector2(980, 572), Vector2(1022, 572)]
	for destination in destinations:
		if not _move_to(game, destination):
			return
	_expect(game.mode == "won", "The intended animal chain must complete the exact room")
	_expect(game.possessions == 4, "The solution must require four successful transfers")
	var visited_all := true
	for animal in game.animals:
		visited_all = visited_all and animal.visited
	_expect(visited_all, "Every animal must be used before completing the room")
	game.reset()
	_expect(game.mode == "animal" and game.active_id == "mouse" and game.animal_by_id("mouse").position == Vector2(190, 542), "Reset after completion must restore the starting Mouse")
	_expect(not game.bridge_open and not game.spirit_has_origin and game.possessions == 0, "Reset after completion must clear puzzle and tether state")
	_expect(not game.animal_by_id("bird").visited and not game.animal_by_id("bear").visited, "Reset must clear previously visited hosts")


func _test_rendered_movement() -> void:
	var game = Model.new()
	var before: Dictionary = game.animal_by_id("mouse").duplicate(true)
	game.step(DT, Vector2.RIGHT)
	var current: Dictionary = game.animal_by_id("mouse")
	var start: Dictionary = game.render_animal("mouse", 0.0)
	var middle: Dictionary = game.render_animal("mouse", 0.5)
	var end: Dictionary = game.render_animal("mouse", 1.0)
	_expect(start.position.is_equal_approx(before.position) and end.position.is_equal_approx(current.position), "Rendered movement must include the previous and current physics positions")
	_expect(middle.position.is_equal_approx((before.position as Vector2).lerp(current.position, 0.5)), "A rendered frame between ticks must place the Mouse between its physics positions")
	_expect(middle.position != start.position and middle.position != end.position, "Interpolation must produce a distinct intermediate position while moving")
	var pose_fields_interpolate := true
	for field in ["gait", "move_amount", "turn"]:
		pose_fields_interpolate = pose_fields_interpolate and is_equal_approx(middle[field], (float(before[field]) + float(current[field])) * 0.5)
	_expect(pose_fields_interpolate, "Gait, movement blend, and turn must advance between physics ticks with the body")
	_expect(game.render_animal("mouse", 2.0).position.is_equal_approx(current.position), "An oversized render fraction must not extrapolate animal movement")

	game = Model.new()
	_select_animal(game, "bear", Vector2(855, 467))
	var previous_block: Rect2 = game.block
	for _frame in range(120):
		previous_block = game.block
		game.step(DT, Vector2.LEFT)
		if previous_block.position != game.block.position:
			break
	_expect(previous_block.position != game.block.position, "The trunk interpolation fixture must actually push the trunk")
	_expect(game.render_block(0.0).position.is_equal_approx(previous_block.position) and game.render_block(1.0).position.is_equal_approx(game.block.position), "The rendered trunk must preserve the previous and current push positions")
	_expect(game.render_block(0.5).position.is_equal_approx(previous_block.position.lerp(game.block.position, 0.5)), "The trunk must move smoothly between push ticks")


func _test_rendered_angle_wrap() -> void:
	var game = Model.new()
	var mouse: Dictionary = game.animal_by_id("mouse")
	mouse.facing = PI - 0.05
	var previous_facing: float = mouse.facing
	game.step(DT, Vector2.from_angle(-PI + 0.2))
	# Equivalent facing angles can be represented on either side of +/-PI.
	mouse.facing = wrapf(mouse.facing, -PI, PI)
	var middle: Dictionary = game.render_animal("mouse", 0.5)
	_expect(previous_facing > 3.0 and mouse.facing < -3.0, "The angle fixture must straddle the wrap boundary")
	_expect(absf(middle.facing) > 3.0, "Crossing the facing wrap must take the short turn rather than spin through zero")
	_expect(is_equal_approx(angle_difference(previous_facing, middle.facing), angle_difference(previous_facing, mouse.facing) * 0.5), "The intermediate facing must halve the shortest angular distance")


func _test_render_state_isolation() -> void:
	var game = Model.new()
	game.step(DT, Vector2.RIGHT)
	game.release()
	game.step(DT, Vector2.UP)
	var animals_before: Array = game.animals.duplicate(true)
	var effects_before: Array = game.effects.duplicate(true)
	var physics_time: float = game.time
	var physics_spirit: Vector2 = game.spirit_position
	var physics_origin: Vector2 = game.spirit_origin
	var physics_block: Rect2 = game.block
	var original_render_position: Vector2 = game.render_animal("mouse", 0.5).position
	var pose: Dictionary = game.render_animal("mouse", 0.5)
	pose.position = Vector2(-1000, -1000)
	pose.facing = 0.0
	pose.state = "changed by renderer"
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		game.render_spirit_position(fraction)
		game.render_time(fraction)
		game.render_block(fraction)
		for effect in game.effects:
			game.render_effect_age(effect, fraction)
	_expect(game.animals == animals_before, "Render snapshots and caller edits must not mutate physics animal state")
	_expect(game.effects == effects_before, "Reading rendered effect ages must not mutate their simulation ages")
	_expect(game.time == physics_time and game.spirit_position == physics_spirit and game.spirit_origin == physics_origin and game.block == physics_block, "Reading rendered frames must leave time, tether, spirit, and environmental state unchanged")
	_expect(game.render_animal("mouse", 0.5).position == original_render_position, "Mutating one returned pose must not change later render snapshots")


func _test_rendered_release_and_reset() -> void:
	var game = Model.new()
	_move_to(game, Vector2(240, 520))
	game.release()
	var origin: Vector2 = game.spirit_origin
	var fresh_release_snaps := true
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		fresh_release_snaps = fresh_release_snaps and game.render_spirit_position(fraction).is_equal_approx(origin)
	_expect(fresh_release_snaps, "The first release must appear at its origin without sweeping from the starting spirit position")
	_tick(game, 15)
	if not _expect(game.possess(), "The render reset fixture must reclaim the nearby Mouse"):
		return
	_move_to(game, Vector2(260, 560))
	game.step(DT, Vector2.ZERO, true)
	origin = game.spirit_origin
	var next_release_snaps := true
	for fraction in [0.0, 0.5, 1.0]:
		next_release_snaps = next_release_snaps and game.render_spirit_position(fraction).is_equal_approx(origin)
	_expect(next_release_snaps, "A release through the physics step must not sweep from the previous possession's origin")
	game.step(DT, Vector2.RIGHT)
	var previous_serial: int = game.reset_serial
	game.reset()
	_expect(game.reset_serial == previous_serial + 1, "Reset must identify a new presentation session")
	var reset_snaps := true
	for fraction in [0.0, 0.5, 1.0]:
		reset_snaps = reset_snaps and game.render_animal("mouse", fraction).position == game.burrow
		reset_snaps = reset_snaps and game.render_spirit_position(fraction) == game.burrow
		reset_snaps = reset_snaps and game.render_block(fraction) == Rect2(688, 431, 132, 72)
		reset_snaps = reset_snaps and game.render_time(fraction) == 0.0
	_expect(reset_snaps, "Reset must replace all render snapshots immediately without a sweep or old animation time")
	_expect(game.effects.is_empty() and game.trail.is_empty(), "Reset must clear lingering visual history")


func _test_rendered_spirit_and_timestamps() -> void:
	var game = Model.new()
	game.release()
	var release_effect: Dictionary = game.effects[0]
	_expect(game.render_effect_age(release_effect, 0.0) == 0.0, "A newly emitted effect must not render at a negative age")
	game.step(DT, Vector2.RIGHT)
	_expect(is_equal_approx(game.render_effect_age(release_effect, 0.0), 0.0) and is_equal_approx(game.render_effect_age(release_effect, 0.5), DT * 0.5) and is_equal_approx(game.render_effect_age(release_effect, 1.0), DT), "Existing transition effects must advance smoothly with interpolated frame time")
	var render_bounds_hold := true
	var render_times_hold := true
	var effect_times_hold := true
	for frame in range(240):
		var previous_time: float = game.time
		var direction := Vector2.RIGHT if frame < 120 else Vector2.UP if frame < 180 else Vector2.LEFT
		game.step(DT, direction)
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0, 2.0]:
			render_bounds_hold = render_bounds_hold and game.render_spirit_position(fraction).distance_to(game.spirit_origin) <= game.spirit_range + 0.001
			var timestamp: float = game.render_time(fraction)
			render_times_hold = render_times_hold and timestamp >= previous_time - 0.00001 and timestamp <= game.time + 0.00001
			for effect in game.effects:
				var age: float = game.render_effect_age(effect, fraction)
				effect_times_hold = effect_times_hold and age >= 0.0 and age <= float(effect.age) + 0.00001
	_expect(render_bounds_hold, "Interpolated spirit frames must remain inside the fixed release tether")
	_expect(render_times_hold, "Rendered animation time must remain between completed physics ticks")
	_expect(effect_times_hold, "Rendered effect ages must remain bounded by simulation age without extrapolation")
	_expect(game.effects.is_empty(), "Interpolation must not keep expired transition effects alive")
