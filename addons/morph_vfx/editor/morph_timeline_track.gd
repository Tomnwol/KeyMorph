@tool
extends Control
## Click empty track to scrub; click+drag a key diamond to move it in time.

signal scrubbed(time: float)
signal keyframe_clicked(index: int)
signal keyframe_dragged(index: int, time: float)

var target: MorphPolygon2D

var _drag_key_index: int = -1
var _scrubbing: bool = false


func _ready() -> void:
	custom_minimum_size.y = 56
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(false)


func set_target(node: MorphPolygon2D) -> void:
	## Do not clear an in-progress drag when the same node is re-bound on refresh.
	var changed := target != node
	target = node
	if changed:
		_stop_interaction()
	queue_redraw()


func notify_external_refresh() -> void:
	## Redraw only — keeps drag/scrub state intact.
	queue_redraw()


func _stop_interaction() -> void:
	_drag_key_index = -1
	_scrubbing = false
	set_process_input(false)


func _gui_input(event: InputEvent) -> void:
	if target == null or target.shape == null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _hit_keyframe(event.position)
			if hit >= 0:
				_drag_key_index = hit
				_scrubbing = false
				set_process_input(true)
				keyframe_clicked.emit(hit)
				accept_event()
			else:
				_drag_key_index = -1
				_scrubbing = true
				set_process_input(true)
				scrubbed.emit(_time_at_x(event.position.x))
				accept_event()
		else:
			_stop_interaction()
			accept_event()
		queue_redraw()
		return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_handle_drag_to(event.position.x)


func _input(event: InputEvent) -> void:
	## Keep dragging even if the cursor leaves the track control.
	if _drag_key_index < 0 and not _scrubbing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_stop_interaction()
		queue_redraw()
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var local_x := get_local_mouse_position().x
		_handle_drag_to(local_x)


func _handle_drag_to(local_x: float) -> void:
	var t := _time_at_x(local_x)
	if _drag_key_index >= 0:
		keyframe_dragged.emit(_drag_key_index, t)
		queue_redraw()
	elif _scrubbing:
		scrubbed.emit(t)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.12, 0.13, 0.16))
	draw_rect(rect, Color(0.25, 0.27, 0.32), false, 1.0)

	var track_y := size.y * 0.55
	draw_line(Vector2(8, track_y), Vector2(size.x - 8, track_y), Color(0.35, 0.38, 0.45), 2.0)

	if target == null or target.shape == null:
		draw_string(ThemeDB.fallback_font, Vector2(12, 18), "Select a MorphPolygon2D", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.7))
		return

	for entry in target.shape.get_timeline_entries():
		var x := _x_at_time(float(entry.time))
		var selected: bool = int(entry.index) == target.selected_keyframe and target.is_editing_keyframe()
		var dragging: bool = int(entry.index) == _drag_key_index
		var color := Color(1.0, 0.85, 0.2) if selected or dragging else Color(0.45, 0.8, 1.0)
		_draw_diamond(Vector2(x, track_y), 8.0 if dragging else 7.0, color)

	var play_x := _x_at_time(target.time)
	draw_line(Vector2(play_x, 8), Vector2(play_x, size.y - 8), Color(1, 0.4, 0.35), 2.0)

	var status := "PREVIEW"
	if target.playing:
		status = "PLAYING"
	elif _drag_key_index >= 0:
		var drag_t := target.time
		if _drag_key_index < target.shape.keyframes.size():
			var drag_key: ShapeKeyframe = target.shape.keyframes[_drag_key_index]
			if drag_key != null:
				drag_t = drag_key.time
		status = "MOVE key %d  t=%.2f" % [_drag_key_index, drag_t]
	elif target.is_editing_keyframe():
		status = "EDIT key %d" % target.selected_keyframe
	draw_string(ThemeDB.fallback_font, Vector2(12, 16), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85))


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0, 0.7), 1.0, true)


func _time_at_x(x: float) -> float:
	var left := 8.0
	var right := maxf(size.x - 8.0, left + 1.0)
	return clampf((x - left) / (right - left), 0.0, 1.0)


func _x_at_time(t: float) -> float:
	var left := 8.0
	var right := maxf(size.x - 8.0, left + 1.0)
	return lerpf(left, right, clampf(t, 0.0, 1.0))


func _hit_keyframe(pos: Vector2) -> int:
	if target == null or target.shape == null:
		return -1
	var track_y := size.y * 0.55
	for entry in target.shape.get_timeline_entries():
		var key_pos := Vector2(_x_at_time(float(entry.time)), track_y)
		if key_pos.distance_to(pos) <= 12.0:
			return int(entry.index)
	return -1
