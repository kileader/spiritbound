extends RefCounted
## The exact prototype room. Coordinates and collision rules are intentionally
## explicit: there is no level system or progression behind this experiment.

const WIDTH := 1100.0
const HEIGHT := 700.0
const FOCUS_SECONDS := 0.23
const SPEED := {"mouse": 185.0, "bird": 230.0, "bear": 150.0}
const RETURN_SPEED := {"mouse": 74.0, "bird": 82.0, "bear": 64.0}
const ACCELERATION := {"mouse": 4200.0, "bird": 950.0, "bear": 560.0}
const BRAKING := {"mouse": 6000.0, "bird": 1650.0, "bear": 2200.0}

var walls: Array[Rect2] = [Rect2(300, 24, 26, 376), Rect2(300, 434, 26, 242), Rect2(922, 24, 22, 532), Rect2(922, 588, 22, 88)]
var river := Rect2(530, 24, 120, 652)
var bridge := Rect2(524, 441, 132, 52)
var covered_exit := Rect2(944, 24, 132, 652)
var mouse_gap := Rect2(300, 400, 26, 34)
var exit_gap := Rect2(922, 556, 22, 32)
var perches: Array[Vector2] = [Vector2(360, 500), Vector2(720, 245)]
var burrow := Vector2(190, 542)
var food := Vector2(865, 245)
var exit_position := Vector2(1022, 572)
var spirit_range := 115.0
var target_range := 72.0

var time := 0.0
var mode := "animal"
var active_id := "mouse"
var animals: Array[Dictionary] = []
var spirit_position := Vector2(190, 542)
var spirit_origin := Vector2.ZERO
var spirit_has_origin := false
var anchor_id := ""
var target_id := ""
var focus := 0.0
var pending_possession := false
var manual_target := false
var bridge_open := false
var block := Rect2(688, 431, 132, 72)
var possessions := 0
var effects: Array[Dictionary] = []
var trail: Array[Dictionary] = []
var event_serial := 0
var reset_serial := 0
var _previous_animals: Dictionary = {}
var _previous_spirit := Vector2.ZERO
var _previous_mode := "animal"
var _previous_time := 0.0
var _previous_block := Rect2()
var _render_step := 0.0

func _init() -> void:
	reset()

func reset() -> void:
	reset_serial += 1
	time = 0.0
	mode = "animal"
	active_id = "mouse"
	animals = [
		_body("mouse", "Mouse", burrow, 10.0, burrow, true, -0.9),
		_body("bird", "Bird", Vector2(490, 245), 14.0, perches[0], false, 1.5),
		_body("bear", "Bear", food, 30.0, food, false, PI),
	]
	spirit_position = burrow
	spirit_origin = Vector2.ZERO
	spirit_has_origin = false
	anchor_id = ""
	target_id = ""
	focus = 0.0
	pending_possession = false
	manual_target = false
	bridge_open = false
	block = Rect2(688, 431, 132, 72)
	possessions = 0
	effects.clear()
	trail.clear()
	event_serial = 0
	_capture_render_state()
	_render_step = 0.0

func _body(id: String, title: String, pos: Vector2, radius: float, home: Vector2, visited: bool, facing: float) -> Dictionary:
	return {"id": id, "name": title, "position": pos, "radius": radius,
		"home": home, "visited": visited, "state": "controlled" if id == "mouse" else "resting",
		"velocity": Vector2.ZERO, "facing": facing, "move_amount": 0.0,
		"gait": 0.0, "turn": 0.0, "pushing": false}

func animal_by_id(id: String) -> Dictionary:
	for animal in animals:
		if animal.id == id:
			return animal
	return {}

# Rules run at a fixed tick; drawings interpolate between the last two ticks.
# Keeping this visual-only preserves collision, targeting and the fixed tether.
func _capture_render_state() -> void:
	_previous_animals.clear()
	for animal in animals:
		_previous_animals[animal.id] = animal.duplicate()
	_previous_spirit = spirit_position
	_previous_mode = mode
	_previous_time = time
	_previous_block = block

func _render_fraction(fraction: float) -> float:
	return clampf(Engine.get_physics_interpolation_fraction() if fraction < 0 else fraction, 0.0, 1.0)

func render_animal(id: String, fraction: float = -1.0) -> Dictionary:
	var animal := animal_by_id(id)
	if animal.is_empty():
		return {}
	var pose := animal.duplicate()
	var before: Dictionary = _previous_animals.get(id, animal)
	var blend := _render_fraction(fraction)
	pose.position = (before.position as Vector2).lerp(animal.position, blend)
	pose.facing = lerp_angle(before.facing, animal.facing, blend)
	for field in ["gait", "move_amount", "turn"]:
		pose[field] = lerpf(before[field], animal[field], blend)
	return pose

func render_spirit_position(fraction: float = -1.0) -> Vector2:
	if _previous_mode != mode:
		return spirit_position
	return _previous_spirit.lerp(spirit_position, _render_fraction(fraction))

func render_time(fraction: float = -1.0) -> float:
	return lerpf(_previous_time, time, _render_fraction(fraction))

func render_block(fraction: float = -1.0) -> Rect2:
	return Rect2(_previous_block.position.lerp(block.position, _render_fraction(fraction)), block.size)

func render_effect_age(effect: Dictionary, fraction: float = -1.0) -> float:
	return maxf(0.0, float(effect.age) - _render_step * (1.0 - _render_fraction(fraction)))

func _overlaps(pos: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.y, rect.position.y, rect.end.y))
	return pos.distance_to(closest) < radius - 0.001

func can_occupy(animal: Dictionary, pos: Vector2) -> bool:
	var radius: float = animal.radius
	if pos.x < 24 + radius or pos.x > WIDTH - 24 - radius or pos.y < 24 + radius or pos.y > HEIGHT - 24 - radius:
		return false
	if animal.id == "bird":
		return not _overlaps(pos, radius, covered_exit)
	for wall in walls:
		if _overlaps(pos, radius, wall):
			return false
	if not bridge_open and _overlaps(pos, radius, block):
		return false
	if _overlaps(pos, radius, river):
		if not bridge_open or pos.y - radius < bridge.position.y or pos.y + radius > bridge.end.y:
			return false
	return true

func _guide_mouse(animal: Dictionary, motion: Vector2, dt: float) -> void:
	if animal.id != "mouse" or absf(motion.x) < absf(motion.y) or absf(motion.x) < 0.001:
		return
	var gaps: Array[Rect2] = [mouse_gap, exit_gap]
	if bridge_open:
		gaps.append(bridge)
	for gap in gaps:
		var middle := gap.get_center().y
		var pos: Vector2 = animal.position
		if pos.x > gap.position.x - 44 and pos.x < gap.end.x + 44 and absf(pos.y - middle) < 42:
			var guided := Vector2(pos.x, move_toward(pos.y, middle, 120.0 * dt))
			if can_occupy(animal, guided):
				animal.position = guided

func _push_trunk(animal: Dictionary, motion: Vector2) -> void:
	if animal.id != "bear" or bridge_open or motion.x >= 0:
		return
	var pos: Vector2 = animal.position
	if pos.x < block.end.x + float(animal.radius) - 3 or absf(pos.y - block.get_center().y) > 32:
		return
	if not _overlaps(pos + motion, animal.radius, block):
		return
	animal.pushing = true
	block.position.x += motion.x
	if block.position.x <= river.position.x + 5:
		block.position.x = bridge.position.x
		bridge_open = true
		_effect("crash", bridge.get_center())

func _move(animal: Dictionary, motion: Vector2, dt: float, controlled: bool = false) -> void:
	if controlled:
		_guide_mouse(animal, motion, dt)
		_push_trunk(animal, motion)
	var pos: Vector2 = animal.position
	if can_occupy(animal, pos + Vector2(motion.x, 0)):
		pos.x += motion.x
	else:
		animal.velocity.x = 0.0
	if can_occupy(animal, pos + Vector2(0, motion.y)):
		pos.y += motion.y
	else:
		animal.velocity.y = 0.0
	animal.position = pos

func _mouse_waypoint(mouse: Dictionary) -> Vector2:
	var pos: Vector2 = mouse.position
	if pos.x > 900:
		return Vector2(pos.x, 572) if absf(pos.y - 572) > 2 else Vector2(890, 572)
	if pos.x > 338:
		if pos.x > 650:
			return Vector2(maxf(685, pos.x), 467) if absf(pos.y - 467) > 2 else Vector2(490, 467)
		if pos.x > 510:
			return Vector2(pos.x, 467) if absf(pos.y - 467) > 2 else Vector2(490, 467)
		return Vector2(maxf(347, pos.x), 417) if absf(pos.y - 417) > 2 else Vector2(278, 417)
	if pos.x > 278:
		return Vector2(pos.x, 417) if absf(pos.y - 417) > 2 else Vector2(270, 417)
	return mouse.home

func _return_home(dt: float) -> void:
	for animal in animals:
		if animal.state != "returning":
			continue
		var pos: Vector2 = animal.position
		var home: Vector2 = animal.home
		if pos.distance_to(home) < 2:
			animal.position = home
			animal.state = "resting"
			continue
		var waypoint: Vector2 = _mouse_waypoint(animal) if animal.id == "mouse" else home
		var offset := waypoint - pos
		if offset.length() > 0.01:
			_move(animal, offset.normalized() * minf(offset.length(), float(RETURN_SPEED[animal.id]) * dt), dt)

func valid_targets() -> Array[Dictionary]:
	var valid: Array[Dictionary] = []
	if mode != "spirit":
		return valid
	for animal in animals:
		if animal.id != "bug" and spirit_position.distance_to(animal.position) <= target_range:
			valid.append(animal)
	return valid

func _set_target(id: String) -> void:
	if target_id == id:
		return
	target_id = id
	focus = 0.0
	pending_possession = false
	manual_target = false

func _update_target(dt: float) -> void:
	var valid := valid_targets()
	var current_valid := false
	var other_available := false
	for animal in valid:
		current_valid = current_valid or animal.id == target_id
		other_available = other_available or animal.id != anchor_id
	if not current_valid or (not manual_target and target_id == anchor_id and other_available):
		var best_id := ""
		var best_distance := INF
		for animal in valid:
			var score := spirit_position.distance_to(animal.position) + (1000.0 if animal.id == anchor_id and other_available else 0.0)
			if score < best_distance:
				best_distance = score
				best_id = animal.id
		_set_target(best_id)
	focus = minf(1.0, focus + dt / FOCUS_SECONDS) if not target_id.is_empty() else 0.0

func cycle_target(direction: int = 1) -> void:
	var targets := valid_targets()
	if targets.size() < 2:
		return
	var index := 0
	for i in targets.size():
		if targets[i].id == target_id:
			index = i
	_set_target(targets[posmod(index + direction, targets.size())].id)
	manual_target = true

func release() -> bool:
	if mode != "animal":
		return false
	var animal := animal_by_id(active_id)
	spirit_position = animal.position
	spirit_origin = animal.position
	spirit_has_origin = true
	anchor_id = animal.id
	if animal.id == "bird":
		animal.home = perches[0] if spirit_position.distance_to(perches[0]) < spirit_position.distance_to(perches[1]) else perches[1]
	animal.state = "returning"
	animal.velocity = Vector2.ZERO
	mode = "spirit"
	# A release appears at its new origin immediately, including when called
	# directly between ticks rather than through step().
	_previous_spirit = spirit_position
	active_id = ""
	target_id = ""
	focus = 0.0
	pending_possession = false
	manual_target = false
	trail.clear()
	_effect("release", spirit_position)
	_update_target(0.0)
	return true

func possess() -> bool:
	if mode != "spirit" or focus < 1:
		return false
	for animal in valid_targets():
		if animal.id == target_id:
			_effect("dive", animal.position, spirit_position, animal.id)
			animal.state = "controlled"
			animal.visited = true
			animal.velocity = Vector2.ZERO
			active_id = animal.id
			mode = "animal"
			target_id = ""
			focus = 0.0
			pending_possession = false
			manual_target = false
			possessions += 1
			return true
	return false

func _effect(kind: String, at: Vector2, from: Vector2 = Vector2.ZERO, host_id: String = "") -> void:
	event_serial += 1
	effects.append({"id": event_serial, "kind": kind, "position": at, "from": from, "age": 0.0, "host_id": host_id})

func _update_poses(dt: float, previous: Array[Vector2]) -> void:
	if dt <= 0:
		return
	for i in animals.size():
		var animal := animals[i]
		var motion: Vector2 = animal.position - previous[i]
		var amount := clampf(motion.length() / dt / float(SPEED[animal.id]), 0.0, 1.0)
		animal.move_amount = move_toward(animal.move_amount, amount, dt * 9)
		animal.turn = 0.0
		if motion.length() > 0.01:
			var before: float = animal.facing
			var turning_speed := 18.0 if animal.id == "mouse" else 9.0 if animal.id == "bird" else 6.0
			animal.facing = lerp_angle(before, motion.angle(), minf(1.0, dt * turning_speed))
			animal.turn = angle_difference(before, animal.facing)
			var stride := 17.0 if animal.id == "mouse" else 70.0 if animal.id == "bird" else 65.0
			animal.gait += motion.length() / stride * TAU

func step(dt: float, input_direction: Vector2 = Vector2.ZERO, action: bool = false, cycle: int = 0) -> void:
	dt = clampf(dt, 0.0, 0.05)
	_capture_render_state()
	_render_step = dt
	time += dt
	for effect in effects:
		effect.age += dt
	effects = effects.filter(func(effect: Dictionary) -> bool: return effect.age < 2.0)
	for point in trail:
		point.age += dt
	trail = trail.filter(func(point: Dictionary) -> bool: return point.age < 0.35)
	var previous: Array[Vector2] = []
	for animal in animals:
		previous.append(animal.position)
		animal.pushing = false
	if mode == "won":
		_update_poses(dt, previous)
		return
	var was_spirit := mode == "spirit"
	var direction := input_direction.limit_length(1.0)
	if mode == "animal":
		var animal := animal_by_id(active_id)
		var desired := direction * float(SPEED[animal.id])
		var acceleration: float = BRAKING[animal.id] if direction.length() < 0.01 else ACCELERATION[animal.id]
		animal.velocity = (animal.velocity as Vector2).move_toward(desired, acceleration * dt)
		_move(animal, animal.velocity * dt, dt, true)
		var all_visited := true
		for host in animals:
			all_visited = all_visited and host.visited
		if animal.id == "mouse" and bridge_open and all_visited and (animal.position as Vector2).distance_to(exit_position) < 30:
			mode = "won"
			_effect("win", exit_position)
		elif action:
			release()
	else:
		spirit_position += direction * 185.0 * dt
		spirit_position.x = clampf(spirit_position.x, 30, WIDTH - 30)
		spirit_position.y = clampf(spirit_position.y, 30, HEIGHT - 30)
	_return_home(dt)
	if mode == "spirit":
		# The tether is a snapshot of the release point, not the returning animal.
		spirit_position = spirit_origin + (spirit_position - spirit_origin).limit_length(spirit_range)
		_update_target(dt)
		if cycle != 0:
			cycle_target(cycle)
		if action and was_spirit and not target_id.is_empty():
			pending_possession = true
		if pending_possession:
			possess()
		if dt > 0 and mode == "spirit":
			trail.append({"position": spirit_position, "age": 0.0})
	_update_poses(dt, previous)
