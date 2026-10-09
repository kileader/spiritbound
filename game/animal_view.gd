@tool
extends Node2D
class_name AnimalView

## The illustrated body is separate from the model's collision and movement.
## All poses face local +X; ground gait follows distance actually travelled.
## Flight and changes of pose blend continuously on the render clock.
@export_enum("mouse", "bird", "bear", "spirit") var animal_id: String = "mouse"
var model
var _animal_pose: Dictionary = {}
var _pose_animal_id: String = ""
var _last_reset_serial: int = -1
var _visual_time: float = 0.0
var _move_blend: float = 0.0
var _push_blend: float = 0.0
var _rest_blend: float = 0.0
var _turn_blend: float = 0.0
var _flight_blend: float = 0.0
var _wing_phase: float = 0.0
const StrokeMesh = preload("res://game/stroke_mesh.gd")
var _strokes: Array = []
var _stroke_index: int = 0
var _lines: Array = []
var _line_index: int = 0
var _preparing: bool = false

func _ready() -> void:
	if Engine.is_editor_hint() and model == null:
		model = preload("res://game/room_model.gd").new()
	if animal_id == "spirit":
		# Allocate the spirit's meshes during room startup, while the splash is
		# handing over. Its first appearance should only update existing buffers.
		_preparing = true
		_draw_spirit()
		_preparing = false

const TAU_F: float = PI * 2.0
static var _unit_circle := _make_unit_circle()
static var _circle_mesh := _make_circle_mesh()
static var _curve_weights := _make_curve_weights()

static func _make_unit_circle() -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 40:
		points.append(Vector2.from_angle(TAU_F * float(index) / 40.0))
	return points

static func _make_circle_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO]) + _unit_circle
	var indices := PackedInt32Array()
	for index in _unit_circle.size():
		indices.append_array(PackedInt32Array([0, index + 1, (index + 1) % _unit_circle.size() + 1]))
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh

static func _make_curve_weights() -> PackedVector4Array:
	var weights := PackedVector4Array()
	for index in 21:
		var t := float(index) / 20.0
		var inverse := 1.0 - t
		weights.append(Vector4(inverse * inverse * inverse, 3.0 * inverse * inverse * t, 3.0 * inverse * t * t, t * t * t))
	return weights


func _process(delta: float) -> void:
	if model == null:
		visible = false
		return
	_visual_time = model.render_time()
	if animal_id == "spirit":
		visible = model.mode == "spirit"
		position = model.render_spirit_position()
	else:
		_animal_pose = model.render_animal(animal_id)
		visible = not _animal_pose.is_empty()
		if visible:
			position = _animal_pose.position
			if _last_reset_serial != model.reset_serial or _pose_animal_id != animal_id:
				_reset_pose()
			_advance_pose(clampf(delta, 0.0, 0.1))
	queue_redraw()


func _reset_pose() -> void:
	_last_reset_serial = model.reset_serial
	_pose_animal_id = animal_id
	_move_blend = clampf(float(_animal_pose.get("move_amount", 0.0)), 0.0, 1.0)
	_push_blend = 1.0 if _animal_pose.get("pushing", false) else 0.0
	_rest_blend = 1.0 if _animal_pose.get("state", "") == "resting" else 0.0
	_turn_blend = float(_animal_pose.get("turn", 0.0))
	_flight_blend = smoothstep(0.0, 0.35, _move_blend)
	_wing_phase = 0.0


func _advance_pose(delta: float) -> void:
	# Pose easing adds follow-through without delaying the actual input or body position.
	# Exponential weights keep takeoff, landing, and bracing consistent across frame rates.
	var movement: float = clampf(float(_animal_pose.get("move_amount", 0.0)), 0.0, 1.0)
	_move_blend = lerpf(_move_blend, movement, 1.0 - exp(-delta * 18.0))
	_push_blend = lerpf(_push_blend, 1.0 if _animal_pose.get("pushing", false) else 0.0, 1.0 - exp(-delta * 10.0))
	_rest_blend = lerpf(_rest_blend, 1.0 if _animal_pose.get("state", "") == "resting" else 0.0, 1.0 - exp(-delta * 7.0))
	_turn_blend = lerpf(_turn_blend, float(_animal_pose.get("turn", 0.0)), 1.0 - exp(-delta * 12.0))
	var flight_target: float = smoothstep(0.0, 0.35, _move_blend)
	var flight_rate: float = 10.0 if flight_target > _flight_blend else 7.0
	_flight_blend = lerpf(_flight_blend, flight_target, 1.0 - exp(-delta * flight_rate))
	# Flight muscles keep beating through a slow takeoff; travelled distance cannot
	# provide a continuous flap clock when acceleration, braking, or walls stop motion.
	_wing_phase = fposmod(_wing_phase + delta * lerpf(10.5, 17.0, _move_blend), TAU_F)


func _draw() -> void:
	_stroke_index = 0
	_line_index = 0
	if model == null:
		return
	if animal_id == "spirit":
		_draw_spirit()
		return
	var animal: Dictionary = _animal_pose
	if animal.is_empty():
		return
	var amount: float = _move_blend
	var gait: float = float(animal.get("gait", 0.0))
	var facing: float = float(animal.get("facing", 0.0))
	var time: float = _visual_time
	match animal_id:
		"mouse":
			_draw_mouse(animal, amount, gait, facing, time)
		"bird":
			_draw_bird(animal, amount, gait, facing, time)
		"bear":
			_draw_bear(animal, amount, gait, facing, time)
	draw_set_transform(Vector2.ZERO)


func _oval(center: Vector2, radii: Vector2, color: Color, angle: float = 0.0, edge: Color = Color.TRANSPARENT, width: float = 1.0) -> void:
	# Transform the shared geometry in native code instead of evaluating 40
	# trigonometric points in GDScript for every body part on every web frame.
	var points := Transform2D(angle, radii, 0.0, center) * _unit_circle
	if not _preparing:
		draw_mesh(_circle_mesh, null, Transform2D(angle, radii, 0.0, center), color)
	_stroke(points, color, 0.6, true)
	if edge.a > 0.0:
		_stroke(points, edge, width, true)


func _shape(points: Array, color: Color, edge: Color = Color.TRANSPARENT, width: float = 1.0) -> void:
	var packed := PackedVector2Array(points)
	draw_colored_polygon(packed, color)
	if edge.a > 0.0:
		_stroke(packed, edge, width, true)


func _curve(start: Vector2, control_a: Vector2, control_b: Vector2, end: Vector2, color: Color, width: float = 1.0) -> void:
	var points := PackedVector2Array()
	for weights in _curve_weights:
		points.append(start * weights.x + control_a * weights.y + control_b * weights.z + end * weights.w)
	_stroke(points, color, width)


func _stroke(points: PackedVector2Array, color: Color, width: float, closed: bool = false) -> void:
	if _stroke_index == _strokes.size():
		_strokes.append(StrokeMesh.new())
	var stroke = _strokes[_stroke_index]
	_stroke_index += 1
	var mesh: ArrayMesh = stroke.update(points, width, closed)
	if not _preparing:
		draw_mesh(mesh, null, Transform2D.IDENTITY, Color(color, color.a * minf(1.0, width)))


func _line(start: Vector2, end: Vector2, color: Color, width: float) -> void:
	# Trail length varies, so keep two-point strokes in a separate pool. Growing
	# a trail must not replace the meshes used for the spirit's body and curves.
	if _line_index == _lines.size():
		_lines.append(StrokeMesh.new())
	var line = _lines[_line_index]
	_line_index += 1
	var mesh: ArrayMesh = line.update(PackedVector2Array([start, end]), width)
	if not _preparing:
		draw_mesh(mesh, null, Transform2D.IDENTITY, Color(color, color.a * minf(1.0, width)))


func _arc(radius: float, start: float, end: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in 12:
		points.append(Vector2.from_angle(lerpf(start, end, float(index) / 11.0)) * radius)
	_stroke(points, color, width)


func _shadow(radii: Vector2, height: float = 0.0) -> void:
	_oval(Vector2(0.0, 4.0 + height * 0.35), radii * 1.15, Color(0.025, 0.06, 0.065, 0.07))
	_oval(Vector2(0.0, 4.0 + height * 0.35), radii, Color(0.025, 0.06, 0.065, 0.14))
	_oval(Vector2(0.0, 4.0 + height * 0.35), radii * 0.7, Color(0.025, 0.06, 0.065, 0.10))


func _draw_mouse(_animal: Dictionary, amount: float, gait: float, facing: float, time: float) -> void:
	_shadow(Vector2(12.0, 7.5))
	var quiet: float = 1.0 - amount
	var sniff: float = pow(maxf(0.0, sin(time * 1.65 + 0.9)), 10.0) * quiet
	var stride_phase: float = gait * 0.65
	var stride: float = sin(stride_phase)
	var twist: float = stride * 0.032 * amount + sin(time * 2.3) * 0.025 * sniff
	var bounce: float = (0.5 - 0.5 * cos(stride_phase * 2.0)) * amount * 0.65
	draw_set_transform(Vector2(0.0, -bounce), facing + twist)
	var ink := Color("#443c33")
	var fur := Color("#b8a48a")
	var light := Color("#dbccb0")
	var tail_sway: float = sin(gait * 0.65) * 3.5 * amount + sin(time * 1.4) * 1.0
	_curve(Vector2(-10.0, 0.0), Vector2(-20.0, 1.0 + tail_sway), Vector2(-30.0, 12.0 + tail_sway), Vector2(-31.0, 5.0 + tail_sway), Color("#655248"), 2.5)
	_curve(Vector2(-10.0, 0.0), Vector2(-20.0, 1.0 + tail_sway), Vector2(-30.0, 12.0 + tail_sway), Vector2(-31.0, 5.0 + tail_sway), Color("#b9927f"), 1.3)
	# Opposite feet swap together: a quick scurry, rather than a floating token.
	for side in [-1.0, 1.0]:
		var step: float = stride * side * amount
		_oval(Vector2(-6.0 + step * 2.6, side * 7.5), Vector2(3.5, 1.8), Color("#a18771"), side * 0.2)
		_oval(Vector2(6.0 - step * 2.4, side * 6.7), Vector2(2.8, 1.6), Color("#c1a68c"), -side * 0.3)
	_oval(Vector2(-2.5, 0.0), Vector2(11.5, 7.3 + quiet * sin(time * 3.3) * 0.15), fur, 0.0, ink, 1.0)
	_oval(Vector2(-3.4, -1.0), Vector2(8.3, 4.8), light)
	_curve(Vector2(-10.0, 3.0), Vector2(-7.0, 5.0), Vector2(-2.0, 5.0), Vector2(1.0, 3.8), Color("#8e7d69"), 0.8)
	# Ears sit behind the tapered head, with a small warm inner membrane.
	for side in [-1.0, 1.0]:
		_oval(Vector2(4.1, side * 6.2), Vector2(4.4, 4.0), light, side * 0.35, ink, 0.8)
		_oval(Vector2(4.7, side * 6.5), Vector2(2.7, 2.6), Color("#b99688"))
	var reach: float = sniff * 1.2
	_shape([Vector2(1.0, -5.0), Vector2(7.0, -5.5), Vector2(13.0 + reach, -2.6), Vector2(16.2 + reach, 0.0), Vector2(13.0 + reach, 2.6), Vector2(7.0, 5.5), Vector2(1.0, 5.0)], light, ink, 0.85)
	_curve(Vector2(5.0, -3.5), Vector2(8.0, -2.6), Vector2(11.0, -2.3), Vector2(13.0, -1.3), Color("#ece0c6"), 1.0)
	var blink_clock: float = fposmod(time + 0.6, 5.7)
	var blink: float = 1.0 - 0.80 * smoothstep(5.43, 5.54, blink_clock) * (1.0 - smoothstep(5.59, 5.7, blink_clock))
	for side in [-1.0, 1.0]:
		_oval(Vector2(10.3 + reach * 0.3, side * 3.0), Vector2(1.25, 1.0 * blink), Color("#202b28"))
		draw_circle(Vector2(10.7, side * 2.8), 0.3, Color(0.95, 0.93, 0.85, blink))
		for whisker in range(3):
			var spread: float = float(whisker) * 1.8
			_curve(Vector2(13.2 + reach, side * 1.2), Vector2(17.0, side * 2.5), Vector2(18.0, side * (3.0 + spread)), Vector2(20.0 - spread * 0.3, side * (3.0 + spread)), Color(0.83, 0.81, 0.71, 0.75), 0.55)
	_oval(Vector2(16.1 + reach, 0.0), Vector2(1.45, 1.3), Color("#7a6255"))
	# Short fur strokes read as a back, not a face drawn onto a circle.
	for index in range(3):
		var start := Vector2(-7.0 + float(index) * 3.0, -1.8)
		_line(start, start + Vector2(-1.6, 0.7), Color("#9e8c73"), 0.65)


func _draw_bird(_animal: Dictionary, _amount: float, _gait: float, facing: float, time: float) -> void:
	var flight: float = _flight_blend
	var height: float = flight * 10.0
	_shadow(Vector2(12.0 + flight * 4.0, 7.0 + flight * 1.8), height)
	var turn: float = clampf(_turn_blend * 1.5, -0.22, 0.22)
	var glide: float = pow(maxf(0.0, sin(time * 1.8)), 4.0)
	var flap: float = sin(_wing_phase)
	var stretch: float = lerpf(0.78 + flap * 0.22, 1.0, glide * 0.8)
	var wing: float = lerpf(7.0, 22.0 * stretch, flight)
	var quiet: float = 1.0 - flight
	var peck: float = pow(maxf(0.0, sin(time * 1.25 + 1.0)), 12.0) * quiet
	draw_set_transform(Vector2(0.0, -height - flap * 0.8 * flight * (1.0 - glide * 0.8)), facing + turn)
	var ink := Color("#26484b")
	var white := Color("#efead7")
	var teal := Color("#4c8b87")
	# Three tapering tail feathers trail behind the body.
	_shape([Vector2(-8.0, -4.0), Vector2(-20.0, -5.8), Vector2(-17.0, -0.6), Vector2(-21.0, 0.0), Vector2(-17.0, 0.6), Vector2(-20.0, 5.8), Vector2(-8.0, 4.0)], teal, ink, 0.7)
	_line(Vector2(-12.0, 0.0), Vector2(-19.0, 0.0), white.darkened(0.15), 1.0)
	for side in [-1.0, 1.0]:
		# Feet tuck continuously into the silhouette, where the body occludes them.
		var ankle: Vector2 = Vector2(4.0, side * 9.0).lerp(Vector2(1.0, side * 4.8), flight)
		var outer_toe: Vector2 = Vector2(7.0, side * 8.4).lerp(Vector2(4.0, side * 4.3), flight)
		var inner_toe: Vector2 = Vector2(5.5, side * 11.0).lerp(Vector2(3.0, side * 5.3), flight)
		_line(Vector2(1.0, side * 4.0), ankle, Color("#956c43"), 1.3)
		_line(ankle, outer_toe, Color("#956c43"), 0.9)
		_line(ankle, inner_toe, Color("#956c43"), 0.9)
	# The wing silhouette expands and contracts in bursts; at rest it folds along the back.
	for side in [-1.0, 1.0]:
		var tip: float = side * wing * (1.0 + side * turn * 0.6)
		_shape([Vector2(3.0, side * 2.0), Vector2(1.5, side * 7.0), Vector2(-3.5, tip), Vector2(-8.0, tip * 0.95), Vector2(-15.5, tip * 0.62), Vector2(-12.0, side * 4.0), Vector2(-3.0, side * 2.0)], white, ink, 0.8)
		_shape([Vector2(-0.5, side * 5.0), Vector2(-3.5, tip * 0.91), Vector2(-8.0, tip * 0.91), Vector2(-14.0, tip * 0.6), Vector2(-8.0, side * 5.0)], teal)
		for feather in range(3):
			var offset: float = float(feather) * 2.5
			_curve(Vector2(-3.0 - offset, side * 5.0), Vector2(-4.0 - offset, side * 8.0), Vector2(-6.0 - offset, tip * 0.65), Vector2(-5.0 - offset, tip * (0.88 - float(feather) * 0.11)), Color("#2d6466"), 0.75)
	_oval(Vector2(-1.0, 0.0), Vector2(11.0, 6.7), white, 0.0, ink, 0.9)
	_oval(Vector2(-4.0, 0.0), Vector2(7.2, 4.4), Color("#72a59a"))
	_curve(Vector2(-9.0, -1.0), Vector2(-5.0, -3.0), Vector2(-1.0, -3.0), Vector2(2.0, -1.5), Color("#a9c2af"), 1.0)
	var head_x: float = 9.0 + peck * 2.5
	_oval(Vector2(head_x, 0.0), Vector2(6.7, 5.5 - peck * 0.7), white, 0.0, ink, 0.75)
	_shape([Vector2(head_x + 4.7, -2.0), Vector2(head_x + 10.0 + peck, 0.0), Vector2(head_x + 4.7, 2.0)], Color("#c6a15b"), Color("#6c6343"), 0.55)
	_line(Vector2(head_x + 5.0, 0.0), Vector2(head_x + 9.0, 0.0), Color("#817143"), 0.6)
	for side in [-1.0, 1.0]:
		_oval(Vector2(head_x + 2.1, side * 2.5), Vector2(1.05, 0.9), Color("#223d3b"))
		draw_circle(Vector2(head_x + 2.35, side * 2.45), 0.24, Color("#f7f0d9"))


func _draw_bear(_animal: Dictionary, amount: float, gait: float, facing: float, time: float) -> void:
	_shadow(Vector2(32.0, 24.0))
	var push: float = _push_blend
	var quiet: float = 1.0 - amount
	var breath: float = sin(time * 1.6) * quiet
	var stride: float = sin(gait)
	var weight: float = stride * amount
	var feeding: float = pow(maxf(0.0, sin(time * 0.95 + 0.5)), 6.0) * quiet * _rest_blend * (1.0 - push)
	draw_set_transform(Vector2(0.0, weight * 0.7), facing + weight * 0.022, Vector2(1.0 + breath * 0.007, 1.0 + breath * 0.013))
	var ink := Color("#352f29")
	var dark := Color("#574b3c")
	var fur := Color("#82705a")
	var shoulder := Color("#9d8567")
	# Four separate, broad feet plant before the body rolls over them.
	for side in [-1.0, 1.0]:
		var step: float = stride * side * amount
		var front_x: float = lerpf(15.0 - step * 2.8, 25.0, push)
		var rear_x: float = -17.0 + step * 2.3 - push * 3.0
		_oval(Vector2(rear_x, side * (17.5 + absf(step) * 0.5)), Vector2(9.0, 7.0), dark, side * 0.1, ink, 1.0)
		_oval(Vector2(front_x, side * (16.8 + absf(step) * 0.6)), Vector2(9.3, 7.1), fur.darkened(0.15), -side * 0.15, ink, 1.0)
		for toe in range(3):
			var toe_y: float = side * 16.8 + float(toe - 1) * 2.5
			_line(Vector2(front_x + 6.3, toe_y), Vector2(front_x + 8.2, toe_y), Color("#c6b58f"), 1.2)
	draw_circle(Vector2(-30.0, 0.0), 3.3, dark)
	_oval(Vector2(-7.0, 0.0), Vector2(25.5, 21.8), fur, 0.0, ink, 1.3)
	_oval(Vector2(-10.0, 2.8), Vector2(23.0, 17.0), dark.lightened(0.06))
	_oval(Vector2(-9.0, -3.5), Vector2(21.0, 15.8), fur)
	# The shoulder mass rises through the stride and lowers against a heavy object.
	var shoulder_x: float = 7.0 + push * 2.0
	_oval(Vector2(shoulder_x, -weight * 0.8), Vector2(19.7, 19.5), shoulder, -weight * 0.035)
	_oval(Vector2(shoulder_x - 2.0, -4.3), Vector2(15.0, 12.8), Color("#ac9373"))
	_curve(Vector2(-22.0, -8.0), Vector2(-15.0, -15.0), Vector2(-3.0, -16.0), Vector2(5.0, -12.0), Color("#b69c7a"), 1.15)
	for index in range(7):
		var offset: float = float(index)
		var origin := Vector2(-21.0 + offset * 4.6, -5.0 + sin(offset * 1.6) * 5.0)
		_line(origin, origin + Vector2(-2.6, 1.8), Color("#66543f"), 0.9)
	var head_x: float = 22.0 + feeding * 1.5 + push * 1.4
	for side in [-1.0, 1.0]:
		_oval(Vector2(head_x - 1.5, side * 11.0), Vector2(5.6, 5.1), dark, side * 0.25, ink, 0.9)
		_oval(Vector2(head_x - 0.6, side * 11.0), Vector2(3.2, 2.8), Color("#ad9173"))
	_oval(Vector2(head_x, 0.0), Vector2(13.0, 12.4 - feeding * 0.6), fur, 0.0, ink, 1.0)
	_oval(Vector2(head_x + 1.0, -1.0), Vector2(9.2, 8.0), shoulder)
	_oval(Vector2(head_x + 8.5, 0.0), Vector2(7.0, 6.5), Color("#c2a887"), 0.0, Color("#756248"), 0.6)
	_oval(Vector2(head_x + 12.0, 0.0), Vector2(4.1, 3.5), Color("#2b302b"))
	_curve(Vector2(head_x + 10.0, -1.4), Vector2(head_x + 11.0, -2.0), Vector2(head_x + 12.5, -2.0), Vector2(head_x + 13.0, -1.3), Color("#5c6153"), 0.7)
	for side in [-1.0, 1.0]:
		_oval(Vector2(head_x + 5.6, side * 6.3), Vector2(1.35, 1.0), Color("#292f28"))
		_curve(Vector2(head_x + 2.0, side * 7.4), Vector2(head_x + 4.0, side * 8.1), Vector2(head_x + 7.0, side * 8.0), Vector2(head_x + 8.0, side * 6.9), Color("#b69a75"), 0.8)
		_line(Vector2(head_x + 2.0, side * 4.7), Vector2(head_x + 7.0, side * 5.4), Color(0.37, 0.31, 0.24, push), 1.2)


func _draw_spirit() -> void:
	var time: float = _visual_time
	var float_y: float = sin(time * 3.0) * 1.5
	var trail: Array = model.trail if model != null else []
	# Fading ribbons retain the spirit's recent path, without pointing at a moving host.
	for index in range(1, trail.size()):
		var age: float = float(trail[index].get("age", 0.0))
		var opacity: float = clampf(1.0 - age / 0.55, 0.0, 1.0)
		if opacity <= 0.0:
			continue
		var start: Vector2 = trail[index - 1].position - position
		var end: Vector2 = trail[index].position - position
		_line(start + Vector2(0.0, float_y), end + Vector2(0.0, float_y), Color(0.40, 0.86, 0.81, opacity * 0.07), 15.0 * opacity)
		_line(start + Vector2(0.0, float_y), end + Vector2(0.0, float_y), Color(0.74, 0.97, 0.89, opacity * 0.32), 3.4 * opacity + 0.5)
	for ring in range(5):
		var radius: float = 22.0 - float(ring) * 3.0
		_oval(Vector2(0.0, float_y), Vector2(radius, radius), Color(0.39, 0.85, 0.78, 0.018 + float(ring) * 0.008))
	if not _preparing:
		draw_set_transform(Vector2(0.0, float_y))
	var twist: float = sin(time * 2.1) * 2.8
	_curve(Vector2(-5.0, -3.0), Vector2(-15.0 - twist, 0.0), Vector2(-3.0, 19.0), Vector2(-14.0 + twist, 24.0), Color(0.53, 0.93, 0.83, 0.15), 6.0)
	_curve(Vector2(3.0, -4.0), Vector2(14.0 + twist, 3.0), Vector2(6.0, 16.0), Vector2(14.0 - twist, 19.0), Color(0.67, 0.97, 0.85, 0.33), 2.0)
	_curve(Vector2(-4.0, 2.0), Vector2(-6.0, 9.0), Vector2(2.0 + twist, 17.0), Vector2(-5.0 + twist, 22.0), Color(0.88, 1.0, 0.92, 0.7), 2.3)
	_oval(Vector2.ZERO, Vector2(8.2, 9.5), Color(0.65, 0.97, 0.88, 0.45), time * 0.3)
	_oval(Vector2(0.0, -1.0), Vector2(5.5, 6.8), Color("#e7fff1"), time * 0.3)
	_oval(Vector2(-0.7, -2.3), Vector2(2.7, 4.0), Color("#ffffff"), time * 0.3)
	for index in range(3):
		var theta: float = time * (0.7 + float(index) * 0.13) + float(index) * 2.1
		var radius: float = 14.0 + float(index) * 1.3
		_arc(radius, theta, theta + 0.45, Color(0.74, 0.98, 0.86, 0.40 - float(index) * 0.06), 0.9)
	if not _preparing:
		draw_set_transform(Vector2.ZERO)
