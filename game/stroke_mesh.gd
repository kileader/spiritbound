extends RefCounted

## Retain a stroke's GPU buffers while its control points animate. CanvasItem's
## draw_polyline recreates those buffers on every redraw in the web renderer.
var mesh := ArrayMesh.new()
var _point_count: int = 0
var _closed: bool = false


func update(points: PackedVector2Array, width: float, closed: bool = false) -> ArrayMesh:
	var count := points.size()
	if count < 2:
		mesh.clear_surfaces()
		_point_count = 0
		return mesh
	var vertices := PackedVector2Array()
	vertices.resize(count * 4)
	# Put the one-pixel feather across the edge, retaining the intended
	# visual weight. Subpixel strokes scale their opacity at the draw call.
	var half_core := maxf(0.0, width * 0.5 - 0.5)
	for index in count:
		var previous := points[(index - 1 + count) % count] if closed or index > 0 else points[index]
		var next := points[(index + 1) % count] if closed or index < count - 1 else points[index]
		var incoming := (points[index] - previous).normalized()
		var outgoing := (next - points[index]).normalized()
		if incoming == Vector2.ZERO:
			incoming = outgoing
		if outgoing == Vector2.ZERO:
			outgoing = incoming
		var normal := Vector2(-(incoming.y + outgoing.y), incoming.x + outgoing.x).normalized()
		var denominator := maxf(0.25, normal.dot(Vector2(-outgoing.y, outgoing.x)))
		var inner := normal * (half_core / denominator)
		var outer := normal * ((half_core + 1.0) / denominator)
		vertices[index * 4] = points[index] + inner
		vertices[index * 4 + 1] = points[index] - inner
		vertices[index * 4 + 2] = points[index] + outer
		vertices[index * 4 + 3] = points[index] - outer
	if count == _point_count and closed == _closed:
		mesh.surface_update_vertex_region(0, 0, vertices.to_byte_array())
		return mesh
	_point_count = count
	_closed = closed
	mesh.clear_surfaces()
	var colors := PackedColorArray()
	for index in count:
		colors.append_array(PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
	var indices := PackedInt32Array()
	for index in count if closed else count - 1:
		var a := index * 4
		var b := ((index + 1) % count) * 4
		indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1, a + 2, b + 2, a, a, b + 2, b, a + 1, b + 1, a + 3, a + 3, b + 1, b + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	return mesh
