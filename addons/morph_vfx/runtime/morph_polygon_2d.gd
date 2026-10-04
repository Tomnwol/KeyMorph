@tool
class_name MorphPolygon2D
extends Node2D
## Bezier morph polygon. Fill is drawn tessellated; only control anchors are editable.

signal timeline_changed

enum Mode { PREVIEW, EDIT_KEY }

@export var shape: MorphShape2D:
	set(value):
		shape = value
		_sync_precision_from_shape()
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
		time = clampf(value, 0.0, 1.0)
		if playing or mode == Mode.PREVIEW:
			queue_redraw()

@export var edit_keyframe: int = 0:
	set(value):
		if _ignore_edit_export:
			edit_keyframe = value
			return
		select_keyframe(value)

var mode: Mode = Mode.EDIT_KEY
var selected_keyframe: int = -1

var _ignore_edit_export := false


func _ready() -> void:
	set_process(true)
	_sync_precision_from_shape()
	if selected_keyframe < 0 and shape != null and not shape.keyframes.is_empty():
		select_keyframe(0)
	else:
		queue_redraw()


func _process(delta: float) -> void:
	if shape == null:
		return
	if playing and shape.duration > 0.0:
		time = fposmod(time + delta / shape.duration, 1.0)
		queue_redraw()


func _draw() -> void:
	var points := get_display_polygon()
	if points.size() >= 3:
		draw_colored_polygon(points, color)
	if points.size() >= 2:
		var looped := points.duplicate()
		if shape == null or shape.closed:
			looped.append(points[0])
		draw_polyline(looped, Color(color.r, color.g, color.b, 1.0), 2.0, true)


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
		time = key.time
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


func _sync_precision_from_shape() -> void:
	if shape != null:
		curve_precision = shape.curve_precision
