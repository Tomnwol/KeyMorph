@tool
class_name MorphPolygon2D
extends Node2D
## Bezier morph polygon. Fill is drawn tessellated; only control anchors are editable.
## Assign a ShaderMaterial on this CanvasItem; UV = bounding-box 0..1.

signal timeline_changed

enum Mode { PREVIEW, EDIT_KEY }

@export var shape: MorphShape2D:
	set(value):
		shape = value
		_sync_from_shape()
		if shape != null and not shape.keyframes.is_empty():
			select_keyframe(0)
		else:
			selected_keyframe = -1
			mode = Mode.PREVIEW
			queue_redraw()
			timeline_changed.emit()

@export var color: Color = Color(0.3, 0.75, 1.0, 0.85):
	set(value):
		color = value
		queue_redraw()

@export var ease: MorphEasing.Type = MorphEasing.Type.LINEAR:
	set(value):
		ease = value
		if shape != null:
			shape.ease = ease
		queue_redraw()

@export var ease_mode: MorphEasing.Mode = MorphEasing.Mode.BETWEEN_KEYS:
	set(value):
		ease_mode = value
		if shape != null:
			shape.ease_mode = ease_mode
		queue_redraw()

@export_range(0.0, 2.5, 0.01) var smooth_blend: float = 0.0:
	set(value):
		smooth_blend = clampf(value, 0.0, 2.5)
		if shape != null:
			shape.smooth_blend = smooth_blend
		queue_redraw()

@export_range(-1.0, 1.0, 0.01) var smooth_tension: float = 0.0:
	set(value):
		smooth_tension = clampf(value, -1.0, 1.0)
		if shape != null:
			shape.smooth_tension = smooth_tension
		queue_redraw()

@export_range(0.05, 30.0, 0.05, "or_greater", "suffix:s") var duration: float = 1.0:
	set(value):
		duration = maxf(value, 0.05)
		if shape != null:
			shape.duration = duration

@export var draw_outline: bool = true:
	set(value):
		draw_outline = value
		queue_redraw()

@export_range(2, 64, 1) var curve_precision: int = 12:
	set(value):
		curve_precision = clampi(value, 2, 64)
		if shape != null:
			shape.curve_precision = curve_precision
		queue_redraw()

@export var playing: bool = false:
	set(value):
		if value == playing:
			return
		if value:
			mode = Mode.PREVIEW
			selected_keyframe = -1
		playing = value
		queue_redraw()
		timeline_changed.emit()

@export_range(0.0, 1.0, 0.001) var time: float = 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(time, next):
			return
		time = next
		## In edit mode, Time in the inspector retimes the selected keyframe.
		if not _syncing_time_from_key and is_editing_keyframe():
			var key := get_edit_keyframe()
			if key != null and not is_equal_approx(key.time, time):
				key.time = time
				if shape != null:
					shape.emit_changed()
				timeline_changed.emit()
		if playing or mode == Mode.PREVIEW or is_editing_keyframe():
			queue_redraw()

@export var edit_keyframe: int = 0:
	set(value):
		if _ignore_edit_export:
			edit_keyframe = value
			return
		select_keyframe(value)

var mode: Mode = Mode.EDIT_KEY
var selected_keyframe: int = -1
## Set by the editor gizmo when an anchor is selected.
var editor_selected_point: int = -1

var _ignore_edit_export := false
var _syncing_time_from_key := false


func _ready() -> void:
	set_process(true)
	_sync_from_shape()
	if selected_keyframe < 0 and shape != null and not shape.keyframes.is_empty():
		select_keyframe(0)
	else:
		queue_redraw()


func _process(delta: float) -> void:
	if shape == null:
		return
	if playing and duration > 0.0:
		time = fposmod(time + delta / duration, 1.0)
		queue_redraw()


func _draw() -> void:
	var points := get_display_polygon()
	if points.size() >= 3:
		_draw_filled_polygon(points)
	if draw_outline and points.size() >= 2:
		var looped := points.duplicate()
		if shape == null or shape.closed:
			looped.append(points[0])
		draw_polyline(looped, Color(color.r, color.g, color.b, 1.0), 2.0, true)


func _draw_filled_polygon(points: PackedVector2Array) -> void:
	## Robust fill: normal triangulation, then convex decompose, then centroid fan.
	## Keeps shaders visible even when the morph self-intersects mid-blend.
	var draw_points := points
	var indices := Geometry2D.triangulate_polygon(points)

	if indices.size() < 3:
		var convex_parts := Geometry2D.decompose_polygon_in_convex(points)
		if not convex_parts.is_empty():
			for part in convex_parts:
				if part.size() < 3:
					continue
				_draw_triangulated(part, Geometry2D.triangulate_polygon(part))
			return
		var fan := _centroid_fan(points)
		draw_points = fan.points
		indices = fan.indices

	_draw_triangulated(draw_points, indices)


func _draw_triangulated(points: PackedVector2Array, indices: PackedInt32Array) -> void:
	if points.size() < 3 or indices.size() < 3:
		return
	var uvs := compute_uvs(points)
	for i in range(0, indices.size() - 2, 3):
		var ia := indices[i]
		var ib := indices[i + 1]
		var ic := indices[i + 2]
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= points.size() or ib >= points.size() or ic >= points.size():
			continue
		var tri := PackedVector2Array([points[ia], points[ib], points[ic]])
		## Skip degenerate triangles.
		if absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) < 0.0001:
			continue
		var tri_uv := PackedVector2Array([uvs[ia], uvs[ib], uvs[ic]])
		var tri_color := PackedColorArray([color, color, color])
		draw_polygon(tri, tri_color, tri_uv)


func _centroid_fan(points: PackedVector2Array) -> Dictionary:
	## Always produces triangles; overlaps are OK for VFX morph transitions.
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= float(points.size())

	var extended := points.duplicate()
	extended.append(centroid)
	var center_i := extended.size() - 1
	var indices := PackedInt32Array()
	var n := points.size()
	for i in n:
		var j := (i + 1) % n
		indices.append(center_i)
		indices.append(i)
		indices.append(j)
	return {"points": extended, "indices": indices}


func get_display_polygon() -> PackedVector2Array:
	if shape == null:
		return PackedVector2Array()
	if is_editing_keyframe():
		var key := get_edit_keyframe()
		if key != null:
			return shape.tessellate_keyframe(key)
	return shape.sample_polygon(time)


func scrub_to(t: float) -> void:
	playing = false
	mode = Mode.PREVIEW
	selected_keyframe = -1
	_set_edit_export(0)
	time = clampf(t, 0.0, 1.0)
	queue_redraw()
	timeline_changed.emit()


func select_keyframe(index: int) -> void:
	if playing:
		playing = false

	if shape == null or shape.keyframes.is_empty() or index < 0:
		selected_keyframe = -1
		mode = Mode.PREVIEW
		_set_edit_export(0)
		queue_redraw()
		timeline_changed.emit()
		return

	selected_keyframe = clampi(index, 0, shape.keyframes.size() - 1)
	_set_edit_export(selected_keyframe)
	mode = Mode.EDIT_KEY
	var key := shape.keyframes[selected_keyframe]
	if key != null:
		_set_time_from_key(key.time)
	queue_redraw()
	timeline_changed.emit()


func select_keyframe_at_time(t: float, tolerance: float = 0.02) -> bool:
	if shape == null:
		return false
	var index := shape.find_keyframe_at_time(t, tolerance)
	if index < 0:
		return false
	select_keyframe(index)
	return true


func goto_adjacent_keyframe(step: int) -> void:
	if shape == null:
		return
	var entries := shape.get_timeline_entries()
	if entries.is_empty():
		return

	var current_pos := 0
	if selected_keyframe >= 0:
		for i in entries.size():
			if int(entries[i].index) == selected_keyframe:
				current_pos = i
				break
	else:
		var best_i := 0
		var best_dist := INF
		for i in entries.size():
			var dist: float = absf(float(entries[i].time) - time)
			if dist < best_dist:
				best_dist = dist
				best_i = i
		current_pos = best_i

	var next_pos := clampi(current_pos + step, 0, entries.size() - 1)
	select_keyframe(int(entries[next_pos].index))


func insert_keyframe_at_playhead() -> void:
	if shape == null:
		return
	var controls := shape.sample_control_points(time)
	if controls.is_empty():
		controls = [] as Array[BezierPoint]
		controls.append(_make_point(Vector2(0, -80)))
		controls.append(_make_point(Vector2(-80, 60)))
		controls.append(_make_point(Vector2(80, 60)))

	var existing := shape.find_keyframe_at_time(time, 0.001)
	if existing >= 0:
		shape.keyframes[existing].set_control_points(controls)
		shape.emit_changed()
		select_keyframe(existing)
		return

	var index := shape.insert_keyframe_controls(time, controls)
	select_keyframe(index)


func delete_selected_keyframe() -> void:
	if shape == null or selected_keyframe < 0:
		return
	if shape.keyframes.size() <= 1:
		return
	var remove_index := selected_keyframe
	var keep_time := time
	selected_keyframe = -1
	mode = Mode.PREVIEW
	shape.remove_keyframe(remove_index)
	var entries := shape.get_timeline_entries()
	if entries.is_empty():
		timeline_changed.emit()
		return
	var best: int = int(entries[0].index)
	var best_dist := INF
	for entry in entries:
		var dist: float = absf(float(entry.time) - keep_time)
		if dist < best_dist:
			best_dist = dist
			best = int(entry.index)
	select_keyframe(best)


func commit_edit() -> void:
	pass


func move_keyframe_time(index: int, new_time: float) -> void:
	if shape == null or index < 0 or index >= shape.keyframes.size():
		return
	var key := shape.keyframes[index]
	if key == null:
		return
	var next := clampf(new_time, 0.0, 1.0)
	if is_equal_approx(key.time, next):
		return
	key.time = next
	if selected_keyframe == index:
		_set_time_from_key(key.time)
	shape.emit_changed()
	queue_redraw()
	timeline_changed.emit()


func begin_keyframe_drag(index: int) -> void:
	if shape == null:
		return
	shape.bake_display_times_to_keys()
	select_keyframe(index)


func _set_time_from_key(key_time: float) -> void:
	_syncing_time_from_key = true
	time = key_time
	_syncing_time_from_key = false


func is_editing_keyframe() -> bool:
	return mode == Mode.EDIT_KEY and selected_keyframe >= 0


func get_edit_keyframe() -> ShapeKeyframe:
	if not is_editing_keyframe() or shape == null:
		return null
	if selected_keyframe < 0 or selected_keyframe >= shape.keyframes.size():
		return null
	return shape.keyframes[selected_keyframe]


func notify_geometry_edited() -> void:
	if shape != null:
		shape.emit_changed()
	queue_redraw()
	timeline_changed.emit()


func insert_point_on_edge(edge_index: int, t: float) -> int:
	if shape == null or not is_editing_keyframe():
		return -1
	var new_index := shape.insert_point_on_edge(edge_index, t, selected_keyframe)
	if new_index < 0:
		return -1
	queue_redraw()
	timeline_changed.emit()
	return new_index


func remove_point_at(point_index: int) -> bool:
	if shape == null or not is_editing_keyframe():
		return false
	if not shape.remove_point_at(point_index):
		return false
	queue_redraw()
	timeline_changed.emit()
	return true


func edge_tangent_at(key: ShapeKeyframe, index: int) -> Vector2:
	## Unit direction for handle_out; handle_in faces opposite (-tangent).
	## Blends the two edge directions meeting at the vertex.
	if key == null or key.points.is_empty():
		return Vector2.RIGHT
	var count := key.points.size()
	index = wrapi(index, 0, count)
	var curr: BezierPoint = key.points[index]
	if curr == null:
		return Vector2.RIGHT

	var prev_i := wrapi(index - 1, 0, count)
	var next_i := wrapi(index + 1, 0, count)
	var prev_p: BezierPoint = key.points[prev_i]
	var next_p: BezierPoint = key.points[next_i]
	if prev_p == null or next_p == null:
		return Vector2.RIGHT

	var incoming := curr.position - prev_p.position
	var outgoing := next_p.position - curr.position
	if incoming.length_squared() < 0.0001 and outgoing.length_squared() < 0.0001:
		return Vector2.RIGHT
	if incoming.length_squared() < 0.0001:
		return outgoing.normalized()
	if outgoing.length_squared() < 0.0001:
		return incoming.normalized()

	var tangent := incoming.normalized() + outgoing.normalized()
	if tangent.length_squared() < 0.0001:
		## Sharp fold: fall back to chord through neighbors.
		tangent = next_p.position - prev_p.position
		if tangent.length_squared() < 0.0001:
			return Vector2.RIGHT
	return tangent.normalized()


func _make_point(pos: Vector2) -> BezierPoint:
	var point := BezierPoint.new()
	point.position = pos
	return point


func _set_edit_export(value: int) -> void:
	_ignore_edit_export = true
	edit_keyframe = value
	_ignore_edit_export = false


func _sync_from_shape() -> void:
	if shape == null:
		return
	curve_precision = shape.curve_precision
	ease = shape.ease
	ease_mode = shape.ease_mode
	smooth_blend = shape.smooth_blend
	smooth_tension = shape.smooth_tension
	duration = maxf(shape.duration, 0.05)


func compute_uvs(points: PackedVector2Array) -> PackedVector2Array:
	return _uvs_bounding_box(points)


func _uvs_bounding_box(points: PackedVector2Array) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	if points.is_empty():
		return uvs
	var min_v := points[0]
	var max_v := points[0]
	for p in points:
		min_v.x = minf(min_v.x, p.x)
		min_v.y = minf(min_v.y, p.y)
		max_v.x = maxf(max_v.x, p.x)
		max_v.y = maxf(max_v.y, p.y)
	var size := max_v - min_v
	size.x = maxf(size.x, 0.0001)
	size.y = maxf(size.y, 0.0001)
	uvs.resize(points.size())
	for i in points.size():
		uvs[i] = Vector2(
			(points[i].x - min_v.x) / size.x,
			(points[i].y - min_v.y) / size.y
		)
	return uvs
