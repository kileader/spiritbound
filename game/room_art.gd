@tool
extends Node2D

# A hand-shaped illustration of the existing room. Plants and leaf litter are
# floor decoration; the root ridges, creek and fallen trunk match the model.
const Model = preload("res://game/room_model.gd")
const FLOOR := Color("#56634c")
const INK := Color("#24382f")
const LEAF := Color("#526c43")
const MOSS := Color("#7e9058")
const WATER := Color("#347478")
const WATER_LIGHT := Color("#a2ccba")
const AMBER := Color("#f0d59d")

const TRUNK_SETTLE_SECONDS := 0.3
const StrokeMesh = preload("res://game/stroke_mesh.gd")
var _strokes: Array = []
var _stroke_index: int = 0
static var _unit_circle := _make_unit_circle()
static var _circle_mesh := _make_circle_mesh()
static var _curve_weights := _make_curve_weights()

static func _make_unit_circle() -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 24:
		points.append(Vector2.from_angle(TAU * float(index) / 24.0))
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

static func _make_curve_weights() -> Dictionary:
	var all_weights := {}
	for steps in [6, 16]:
		var weights := PackedVector3Array()
		for index in range(steps + 1):
			var t := float(index) / float(steps)
			weights.append(Vector3((1.0 - t) * (1.0 - t), 2.0 * t * (1.0 - t), t * t))
		all_weights[steps] = weights
	return all_weights

var model:
	set(value):
		model = value
		# Refresh both textures when the room geometry is replaced.
		for layer in [_forest_layer, _canopy_layer]:
			if is_instance_valid(layer):
				layer.model = value
				layer.queue_redraw()
				layer.get_parent().render_target_update_mode = SubViewport.UPDATE_ONCE

# Static illustrations render once into transparent viewport textures. Keeping
# their drawing commands alone still submits hundreds of WebGL calls each frame.
# Only the parent instance updates moving water and the trunk.
var _static_layer_kind: int = 0
var _forest_layer: Node2D
var _canopy_layer: Node2D
var _preview_time: float = 0.0
var _trunk_rect := Rect2(688, 431, 132, 72)
var _landing_from := Rect2(688, 431, 132, 72)
var _landing_age: float = TRUNK_SETTLE_SECONDS
var _was_bridge_open: bool = false
var _last_reset_serial: int = -1

func _ready() -> void:
	if model == null:
		model = Model.new()
	if _static_layer_kind != 0:
		set_process(false)
		queue_redraw()
		return
	_forest_layer = _make_static_layer("StillForest", 1, true)
	_canopy_layer = _make_static_layer("StillCanopy", 2, false)
	_update_trunk(0.0)
	queue_redraw()

func _make_static_layer(layer_name: String, kind: int, behind: bool) -> Node2D:
	var cache := SubViewport.new()
	cache.name = layer_name + "Cache"
	cache.size = Vector2i(1100, 700)
	cache.transparent_bg = true
	cache.disable_3d = true
	cache.gui_disable_input = true
	cache.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(cache)
	var layer: Node2D = get_script().new()
	layer.name = layer_name
	layer._static_layer_kind = kind
	layer.model = model
	cache.add_child(layer)
	var image := Sprite2D.new()
	image.name = layer_name + "Image"
	image.centered = false
	image.texture = cache.get_texture()
	image.show_behind_parent = behind
	add_child(image)
	return layer

func _process(delta: float) -> void:
	_preview_time += delta
	if model == null:
		return
	_update_trunk(delta)
	queue_redraw()

func _clock() -> float:
	return _preview_time if Engine.is_editor_hint() else float(model.render_time())

func _update_trunk(delta: float) -> void:
	var reset_serial: int = model.reset_serial
	if reset_serial != _last_reset_serial:
		# Reset is intentionally immediate; presentation never delays the puzzle.
		_last_reset_serial = reset_serial
		_was_bridge_open = model.bridge_open
		_trunk_rect = model.bridge if model.bridge_open else model.render_block()
		_landing_from = _trunk_rect
		_landing_age = TRUNK_SETTLE_SECONDS
		return
	if model.bridge_open and not _was_bridge_open:
		_landing_from = _trunk_rect
		_landing_age = 0.0
	if model.bridge_open:
		_landing_age = minf(_landing_age + delta, TRUNK_SETTLE_SECONDS)
		var phase := _landing_age / TRUNK_SETTLE_SECONDS
		var settle := 1.0 - pow(1.0 - phase, 3.0)
		var bridge: Rect2 = model.bridge
		_trunk_rect = Rect2(_landing_from.position.lerp(bridge.position, settle), _landing_from.size.lerp(bridge.size, settle))
		_trunk_rect.position.y += sin(phase * TAU) * 3.0 * (1.0 - phase)
	else:
		_trunk_rect = model.render_block()
	_was_bridge_open = model.bridge_open

func _random(seed: float) -> float:
	return fposmod(sin(seed * 127.1 + 311.7) * 43758.5453123, 1.0)

func _ellipse(center: Vector2, radii: Vector2, color: Color, angle: float = 0.0) -> void:
	draw_mesh(_circle_mesh, null, Transform2D(angle, radii, 0.0, center), color)

func _line(points: Array, color: Color, width: float = 1.0) -> void:
	_stroke(PackedVector2Array(points), color, width)

func _curve(a: Vector2, b: Vector2, c: Vector2, color: Color, width: float, steps: int = 16) -> void:
	var points := PackedVector2Array()
	for weights in _curve_weights[steps]:
		points.append(a * weights.x + b * weights.y + c * weights.z)
	_stroke(points, color, width)

func _stroke(points: PackedVector2Array, color: Color, width: float) -> void:
	if _stroke_index == _strokes.size():
		_strokes.append(StrokeMesh.new())
	var stroke = _strokes[_stroke_index]
	_stroke_index += 1
	draw_mesh(stroke.update(points, width), null, Transform2D.IDENTITY, Color(color, color.a * minf(1.0, width)))

func _glow(position: Vector2, radius: float, color: Color) -> void:
	for i in range(6, 0, -1):
		var scale_factor := float(i) / 6.0
		_ellipse(position, Vector2.ONE * radius * scale_factor,
			Color(color, color.a * (0.25 + (1.0 - scale_factor) * 0.4)))

func _fern(position: Vector2, size: float, angle: float = 0.0, color: Color = MOSS) -> void:
	var points := PackedVector2Array()
	for i in range(1, 7):
		var height := -size * float(i) / 6.0
		var width := size * 0.25 * (1.0 - float(i) / 8.0)
		points.append(position + Vector2(-width, height - size * 0.12).rotated(angle))
		points.append(position + Vector2(-1, height + 3).rotated(angle))
		points.append(position + Vector2(width, height - size * 0.12).rotated(angle))
		points.append(position + Vector2(-1, height + 3).rotated(angle))
	draw_polyline(points, color, 1.7, true)
	_line([position, position + Vector2(-2, -size * 0.5).rotated(angle), position + Vector2(0, -size).rotated(angle)], color, 1.4)

func _leaves(position: Vector2, size: float, seed: float, color: Color = LEAF) -> void:
	for i in range(5):
		var angle := _random(seed + float(i) * 9.0) * TAU
		var reach := size * (0.3 + _random(seed + float(i) * 3.0) * 0.6)
		_ellipse(position + Vector2.from_angle(angle) * reach, Vector2(size * 0.53, size * 0.27), color, angle)

func _path(start: Vector2, control: Vector2, finish: Vector2, width: float) -> void:
	_curve(start, control, finish, Color("#c1ab7330"), width)
	_curve(start, control, finish, Color("#e2c99316"), width * 0.55)

func _draw_floor() -> void:
	draw_rect(Rect2(0, 0, 1100, 700), Color("#263d30"))
	var points := PackedVector2Array([Vector2(24, 24), Vector2(1076, 24), Vector2(1076, 676), Vector2(24, 676)])
	draw_polygon(points, PackedColorArray([Color("#637155"), Color("#52684f"), Color("#445e4b"), FLOOR]))
	_glow(Vector2(214, 436), 250, Color("#d2c97638"))
	_glow(Vector2(776, 349), 278, Color("#cfc8842a"))
	_glow(Vector2(450, 140), 230, Color("#bdd7b820"))
	_path(Vector2(190, 542), Vector2(255, 530), Vector2(284, 417), 38)
	_path(Vector2(280, 417), Vector2(301, 415), Vector2(350, 417), 29)
	_path(Vector2(351, 417), Vector2(450, 388), Vector2(490, 245), 31)
	_path(Vector2(370, 422), Vector2(422, 477), Vector2(520, 467), 29)
	_path(Vector2(660, 467), Vector2(796, 479), Vector2(820, 467), 43)
	_path(Vector2(840, 446), Vector2(876, 351), Vector2(865, 245), 45)
	_path(Vector2(838, 492), Vector2(870, 568), Vector2(920, 572), 27)
	_path(Vector2(944, 572), Vector2(982, 572), Vector2(1022, 572), 27)
	for i in range(116):
		var x := 34.0 + _random(float(i) * 4.0 + 1.0) * 1032.0
		var y := 34.0 + _random(float(i) * 4.0 + 2.0) * 632.0
		if x > 523 and x < 657:
			continue
		var size := 2.0 + _random(float(i) * 4.0 + 3.0) * 7.0
		_ellipse(Vector2(x, y), Vector2(size, size * 0.44), Color("#263c2920") if i % 3 == 0 else Color("#c5c98c27"), _random(float(i) + 5.0) * TAU)
		if i % 5 == 0:
			_line([Vector2(x - 2, y + 3), Vector2(x, y - 2), Vector2(x + 3, y + 1)], Color("#a0ad6740"), 1.0)
	for item in [[76, 132, 24, -0.5], [107, 575, 23, -0.2], [244, 112, 20, 0.4], [416, 604, 24, -0.5],
		[461, 132, 19, 0.6], [698, 98, 25, -0.4], [839, 617, 21, 0.3], [892, 104, 26, 0.4]]:
		_fern(Vector2(item[0], item[1]), item[2], item[3], Color("#879865"))
	for item in [[110, 220, 23], [251, 631, 26], [400, 76, 24], [441, 559, 18], [706, 589, 19], [765, 102, 24], [890, 359, 21]]:
		_leaves(Vector2(item[0], item[1]), item[2], item[0] + item[1], Color("#557348"))

func _draw_stream_base() -> void:
	var river: Rect2 = model.river
	var left := river.position.x
	var right := river.end.x
	var points := PackedVector2Array([river.position, Vector2(right, river.position.y), river.end, Vector2(left, river.end.y)])
	draw_polygon(points, PackedColorArray([Color("#4e8986"), Color("#326b73"), Color("#285566"), Color("#42817d")]))
	for side in range(2):
		var bank := PackedVector2Array()
		var x := left if side == 0 else right
		for offset in range(0, int(river.size.y) + 15, 15):
			var y := minf(river.position.y + float(offset), river.end.y)
			bank.append(Vector2(x + sin(y * 0.062 + float(side)) * 2.2, y))
		draw_polyline(bank, Color("#29463b"), 6, true)
		draw_polyline(bank, Color("#95ae848f"), 2, true)
	for position in [Vector2(523, 146), Vector2(658, 185), Vector2(522, 332), Vector2(657, 364), Vector2(520, 586), Vector2(660, 627)]:
		_fern(position, 15.0 + _random(position.x + position.y) * 8.0,
			-0.6 if position.x < 530 else 0.65, Color("#a0af6d"))

func _draw_stream_flow() -> void:
	var river: Rect2 = model.river
	var left := river.position.x
	for i in range(34):
		var x := left + 12.0 + _random(float(i) + 360.0) * (river.size.x - 45.0)
		var y := river.position.y + fposmod(_random(float(i) + 180.0) * river.size.y + _clock() * (5.0 + float(i % 4)), river.size.y)
		var length := 8.0 + _random(float(i) + 400.0) * 23.0
		_curve(Vector2(x, y), Vector2(x + length * 0.55, y + 3), Vector2(x + length, y - 1),
			Color("#cbdfc582") if i % 4 == 0 else Color("#b2d4be38"), 1.4 if i % 4 == 0 else 0.8, 6)

func _ridge_points(wall: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array([wall.position + Vector2(3, 0)])
	for offset in range(16, int(wall.size.y) - 8, 24):
		var y := wall.position.y + float(offset)
		points.append(Vector2(wall.position.x + sin(y * 0.07) * 2.0, y))
	points.append(Vector2(wall.position.x + 3, wall.end.y))
	points.append(Vector2(wall.end.x - 3, wall.end.y))
	for offset in range(int(wall.size.y) - 13, 8, -24):
		var y := wall.position.y + float(offset)
		points.append(Vector2(wall.end.x + sin(y * 0.086) * 2.0, y))
	points.append(Vector2(wall.end.x - 2, wall.position.y))
	return points

func _draw_ridge(wall: Rect2, reclaimed: bool) -> void:
	var points := _ridge_points(wall)
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(4, 5))
	draw_colored_polygon(shadow, Color("#24342b63"))
	draw_colored_polygon(points, Color("#596552") if reclaimed else Color("#655f44"))
	var highlight := PackedVector2Array()
	highlight.append(wall.position + Vector2(3, 0))
	highlight.append(wall.position + Vector2(12, 0))
	highlight.append(Vector2(wall.position.x + 13, wall.end.y - 3))
	highlight.append(Vector2(wall.position.x + 3, wall.end.y - 3))
	draw_colored_polygon(highlight, Color("#9caa814d") if reclaimed else Color("#ab9c6950"))
	for offset in range(21, int(wall.size.y) - 15, 54 if reclaimed else 43):
		var y := wall.position.y + float(offset)
		var wobble := sin(y * 0.27) * 4.0
		if reclaimed:
			# Broken concrete panel seams are almost swallowed by moss and roots.
			_line([Vector2(wall.position.x + 1, y), Vector2(wall.position.x + 10, y + wobble), Vector2(wall.position.x + 18, y - 3), Vector2(wall.end.x - 1, y + 4)], Color("#324931a0"), 2)
			_line([Vector2(wall.position.x + 7, y + 8), Vector2(wall.position.x + 10, y + 19), Vector2(wall.position.x + 4, y + 24)], Color("#ced0ac47"), 1)
		_ellipse(Vector2(wall.position.x + 8 + sin(y) * 3, y + 13), Vector2(11, 18), Color("#677f4c"), -0.2)
		_ellipse(Vector2(wall.position.x + 7, y + 8), Vector2(8, 11), Color("#94a26270"), 0.3)
	var root := PackedVector2Array()
	for i in range(25):
		var t := float(i) / 24.0
		root.append(Vector2(wall.position.x + 15 + sin(t * TAU * 1.2) * 7, wall.position.y + wall.size.y * t))
	draw_polyline(root, Color("#3d5134"), 4, true)
	draw_polyline(root, Color("#b1b78372"), 1.2, true)
	_ellipse(wall.position + Vector2(wall.size.x * 0.5, 5), Vector2(wall.size.x * 0.48, 5), Color("#b1b18b5b"))
	_ellipse(Vector2(wall.position.x + wall.size.x * 0.5, wall.end.y - 3), Vector2(wall.size.x * 0.48, 4), Color("#344931"))

func _draw_thicket() -> void:
	var roof: Rect2 = model.covered_exit
	draw_rect(roof, Color("#344d36"))
	for i in range(26):
		var x := roof.position.x + 22 + _random(float(i) + 30.0) * (roof.size.x - 44.0)
		var y := roof.position.y + 26 + _random(float(i) + 82.0) * (roof.size.y - 52.0)
		if absf(y - 572) < 47:
			continue
		_ellipse(Vector2(x, y), Vector2(23.0 + _random(float(i) + 20.0) * 9.0, 22.0 + _random(float(i) + 9.0) * 9.0), Color("#4e6741") if i % 3 == 0 else Color("#405a39"), _random(float(i)) * TAU)
		_ellipse(Vector2(x - 6, y - 6), Vector2(17, 9), Color("#9cac6621"), -0.6)
	for y in range(45, 675, 91):
		if absf(float(y) - 572.0) < 51:
			continue
		_line([Vector2(950, y), Vector2(979, y + 19), Vector2(1001, y + 9), Vector2(1047, y + 28), Vector2(1073, y + 22)], Color("#293e2caf"), 4)
	_path(Vector2(944, 572), Vector2(985, 572), Vector2(1022, 572), 31)

func _draw_perch(position: Vector2, east: bool) -> void:
	_ellipse(position + Vector2(3, 11), Vector2(28, 8), Color("#26362c60"), -0.25)
	_line([position + Vector2(-19, 14), position + Vector2(-2, 9), position + Vector2(19, 4)], Color("#3f4b32"), 9)
	_line([position + Vector2(-19, 12), position + Vector2(-2, 7), position + Vector2(19, 2)], Color("#aa9670"), 5)
	_line([position + Vector2(-3, 7), position + Vector2(1, 27), position + Vector2(-6, 34)], Color("#92805a"), 7)
	_line([position + Vector2(10, 5), position + Vector2(17, -7), position + Vector2(29, -9)], Color("#aa976b"), 3)
	_line([position + Vector2(-2, 7), position + Vector2(-13, -3), position + Vector2(-18, -15)], Color("#9a8862"), 3)
	_ellipse(position + Vector2(-5, 6), Vector2(13, 3), Color("#d0ca9280"), -0.25)
	_fern(position + Vector2(-25, 33), 17, -0.35, Color("#a1b16e"))
	_leaves(position + Vector2(27, -10), 7, position.x, Color("#a2b574") if east else Color("#8ca96b"))

func _draw_homes() -> void:
	var burrow: Vector2 = model.burrow
	var food: Vector2 = model.food
	_ellipse(burrow + Vector2(0, 6), Vector2(32, 17), Color("#435137"))
	_line([burrow + Vector2(-35, 8), burrow + Vector2(-26, -12), burrow + Vector2(-7, -18), burrow + Vector2(20, -10), burrow + Vector2(28, 8)], Color("#91815b"), 11)
	_ellipse(burrow, Vector2(23, 15), Color("#263a2d"))
	_ellipse(burrow + Vector2(1, 8), Vector2(17, 4), Color("#d1ae723b"))
	_leaves(burrow + Vector2(-30, -10), 13, 135, Color("#91a768"))
	_fern(burrow + Vector2(37, 7), 24, 0.65, Color("#b0bc7a"))
	_ellipse(food + Vector2(9, 13), Vector2(37, 12), Color("#31482e65"))
	_line([food + Vector2(-27, 18), food + Vector2(8, 22), food + Vector2(27, 15)], Color("#83724d"), 15)
	_line([food + Vector2(-24, 14), food + Vector2(5, 18), food + Vector2(23, 12)], Color("#c0a065"), 5)
	_ellipse(food + Vector2(-22, 17), Vector2(6, 8), Color("#56583a"))
	_leaves(food + Vector2(21, -15), 19, 74, Color("#70894f"))
	_leaves(food + Vector2(29, 3), 13, 98, Color("#8fa562"))
	for offset in [Vector2(24, -14), Vector2(31, -7), Vector2(16, -21), Vector2(20, 1), Vector2(36, 3), Vector2(-2, 16)]:
		_ellipse(food + offset, Vector2(3, 3), Color("#d09c76"))
		_ellipse(food + offset + Vector2(-0.6, -0.7), Vector2.ONE, Color("#e7c99c"))
	_ellipse(Vector2(490, 245), Vector2(25, 20), Color("#ba9e5824"))
	for offset in [Vector2(-13, 8), Vector2(14, 4), Vector2(2, -12), Vector2(-7, -4), Vector2(5, 14)]:
		_ellipse(Vector2(490, 245) + offset, Vector2(2.2, 1.2), Color("#e0ca92"), offset.x * 0.12)
	for i in range(model.perches.size()):
		_draw_perch(model.perches[i], i == 1)

func _draw_exit() -> void:
	var position: Vector2 = model.exit_position
	var pulse := 0.9 + sin(_clock() * 1.7) * 0.06
	_glow(position, 67, Color(0.95, 0.79, 0.46, 0.3 * pulse))
	_ellipse(position + Vector2(0, 7), Vector2(41, 31), Color("#253c2c"))
	_line([position + Vector2(-36, 10), position + Vector2(-29, -25), position + Vector2(-8, -36), position + Vector2(23, -25), position + Vector2(35, 10)], Color("#7b7954"), 16)
	_line([position + Vector2(-35, 4), position + Vector2(-28, -26), position + Vector2(-5, -33), position + Vector2(20, -23)], Color("#afb07b"), 4)
	_ellipse(position + Vector2(0, 1), Vector2(28, 26), Color("#233c2c"))
	_ellipse(position + Vector2(0, 3), Vector2(25, 24), Color("#596948"))
	_ellipse(position + Vector2(0, 8), Vector2(20, 19), Color("#a29c62"))
	_ellipse(position + Vector2(0, 12), Vector2(13, 12), Color("#dbc18a"))
	_ellipse(position + Vector2(0, 16), Vector2(6, 5), AMBER)
	_ellipse(position + Vector2(0, 23), Vector2(27, 7), Color("#d9bc7a78"))
	_leaves(position + Vector2(-31, -18), 15, 200, Color("#8ea76a"))
	_leaves(position + Vector2(27, -24), 14, 215, Color("#89a167"))
	for item in [[-38, 13, 4], [33, 17, 5], [41, 22, 3]]:
		var p := position + Vector2(item[0], item[1])
		_line([p, p + Vector2(0, 6)], Color("#e0d8af"), 2)
		_ellipse(p, Vector2(item[2], item[2] * 0.55), Color("#edd59c"))

func _log_points(rect: Rect2) -> PackedVector2Array:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	return PackedVector2Array([Vector2(x + 10, y + 2), Vector2(x + w * 0.3, y), Vector2(x + w * 0.72, y + 3),
		Vector2(x + w - 9, y + 2), Vector2(x + w, y + h * 0.45), Vector2(x + w - 6, y + h - 3),
		Vector2(x + w * 0.65, y + h), Vector2(x + w * 0.32, y + h - 2), Vector2(x + 9, y + h - 1), Vector2(x, y + h * 0.55)])

func _draw_trunk() -> void:
	var rect := _trunk_rect
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	for offset in [10, 26, 47]:
		_line([Vector2(659, 439 + offset), Vector2(700, 441 + offset), Vector2(748, 438 + offset), Vector2(811, 441 + offset)], Color("#d0ba8040"), 2)
	var attachment := clampf((x - 662.0) / 26.0, 0.0, 1.0) if not model.bridge_open else 0.0
	for item in [[-22, 28], [-8, 38], [15, 29], [31, 23]]:
		var start := lerpf(818.0, x + w - 5.0, attachment)
		var dy: float = item[0]
		var reach: float = item[1]
		_line([Vector2(start, 467 + dy), Vector2(830, 470 + dy * 0.7), Vector2(840 + reach * 0.4, 467 + dy + 6)], Color("#665d3e"), 4)
		_line([Vector2(831, 470 + dy * 0.7), Vector2(837 + reach * 0.4, 463 + dy)], Color("#a18b57"), 1.5)
	var shadow_rect := Rect2(rect.position + Vector2(3, 6), rect.size)
	draw_colored_polygon(_log_points(shadow_rect), Color("#1c352b80"))
	var points := _log_points(rect)
	var colors := PackedColorArray()
	for point in points:
		var ratio := clampf((point.y - y) / h, 0.0, 1.0)
		colors.append(Color("#b09a71").lerp(Color("#535d3b"), ratio))
	draw_polygon(points, colors)
	for i in range(6):
		var ly := y + 6.0 + float(i) * (h - 12.0) / 5.0
		_curve(Vector2(x + 9, ly), Vector2(x + 65, ly + sin(float(i)) * 4), Vector2(x + w - 8, ly - 2),
			Color("#484d318a") if i % 2 == 1 else Color("#e0c99768"), 2.3 if i % 2 == 1 else 1.0)
	_ellipse(Vector2(x + 52, y + h * 0.46), Vector2(13, 6), Color("#676341"), -0.08)
	_ellipse(Vector2(x + 53, y + h * 0.46), Vector2(8, 3), Color("#ae9868"), -0.08)
	_ellipse(Vector2(x + 40, y + 8), Vector2(26, 7), Color("#869651"), 0.03)
	_ellipse(Vector2(x + 55, y + 7), Vector2(17, 4), Color("#b6be7952"))
	for item in [[x + 9, -1.0], [x + w - 8, 1.0]]:
		var ex: float = item[0]
		var direction: float = item[1]
		_ellipse(Vector2(ex, y + h * 0.5), Vector2(10, h * 0.45), Color("#d2b980"), direction * 0.09)
		_ellipse(Vector2(ex + direction * 0.6, y + h * 0.51), Vector2(7.3, h * 0.35), Color("#506343"), direction * 0.09)
		_ellipse(Vector2(ex + direction * 1.2, y + h * 0.53), Vector2(5.5, h * 0.29), Color("#253e2c"), direction * 0.09)
	if model.bridge_open:
		_line([Vector2(x + 22, y + h + 7), Vector2(x + 46, y + h + 9), Vector2(x + 75, y + h + 7)], Color("#cbe1c982"), 1.3)
		_line([Vector2(x + 88, y + h + 8), Vector2(x + 109, y + h + 6)], Color("#cbe1c95c"), 1)

func _draw_atmosphere() -> void:
	for i in range(8):
		var x := 90.0 + _random(float(i) + 781.0) * 810.0 + sin(_clock() * 0.16 + float(i)) * 8.0
		var y := 75.0 + _random(float(i) + 342.0) * 520.0 + cos(_clock() * 0.21 + float(i)) * 5.0
		var alpha := 0.25 + (sin(_clock() * 0.8 + float(i) * 2.0) + 1.0) * 0.13
		_ellipse(Vector2(x, y), Vector2.ONE * 1.1, Color(0.99, 0.92, 0.72, alpha))

func _draw_perimeter() -> void:
	for i in range(21):
		var x := float(i) * 56.0 - 10.0
		var top := 6.0 + _random(float(i) + 50.0) * 6.0
		_ellipse(Vector2(x, top), Vector2(38, 17.0 + _random(float(i)) * 10.0), Color("#334e34"), -0.2)
		_ellipse(Vector2(x + 6, top - 6), Vector2(29, 16), Color("#506840"), -0.2)
		_ellipse(Vector2(x + 17, 693), Vector2(37, 18), Color("#344e36"), 0.1)
	for i in range(12):
		var y := 44.0 + float(i) * 56.0
		_ellipse(Vector2(5, y), Vector2(18, 37), Color("#3b5537"), 0.2)
		_ellipse(Vector2(1095, y), Vector2(19, 38), Color("#324c34"), -0.1)
		if i % 3 == 0:
			_fern(Vector2(16, y + 22), 24, 1.25, Color("#668350"))

func _draw() -> void:
	_stroke_index = 0
	if model == null:
		return
	if _static_layer_kind == 1:
		_draw_floor()
		_draw_stream_base()
		_draw_thicket()
		_draw_homes()
		for wall in model.walls:
			_draw_ridge(wall, wall.position.x < 500)
		return
	if _static_layer_kind == 2:
		_draw_perimeter()
		return
	_draw_stream_flow()
	_draw_exit()
	_draw_trunk()
	_draw_atmosphere()
