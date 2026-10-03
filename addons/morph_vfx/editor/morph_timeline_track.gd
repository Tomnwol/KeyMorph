@tool
extends Control
## Click empty track to scrub, click a key diamond to edit that keyframe.

signal scrubbed(time: float)
signal keyframe_clicked(index: int)

var target: MorphPolygon2D


func _ready() -> void:
	custom_minimum_size.y = 56
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_target(node: MorphPolygon2D) -> void:
	target = node
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if target == null or target.shape == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t := _time_at_x(event.position.x)
		var hit := _hit_keyframe(event.position)
		if hit >= 0:
			keyframe_clicked.emit(hit)
		else:
			scrubbed.emit(t)
		accept_event()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _hit_keyframe(event.position) < 0:
			scrubbed.emit(_time_at_x(event.position.x))
			accept_event()


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
		var x := _x_at_time(entry.time)
		var selected: bool = entry.index == target.selected_keyframe and target.is_editing_keyframe()
		var color := Color(1.0, 0.85, 0.2) if selected else Color(0.45, 0.8, 1.0)
		_draw_diamond(Vector2(x, track_y), 7.0, color)

	var play_x := _x_at_time(target.time)
	draw_line(Vector2(play_x, 8), Vector2(play_x, size.y - 8), Color(1, 0.4, 0.35), 2.0)

	var status := "EDIT key %s" % target.selected_keyframe if target.is_editing_keyframe() else "PREVIEW"
	if target.playing:
		status = "PLAYING"
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
		var key_pos := Vector2(_x_at_time(entry.time), track_y)
		if key_pos.distance_to(pos) <= 10.0:
			return entry.index
	return -1
