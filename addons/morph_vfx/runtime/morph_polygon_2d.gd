@tool
class_name MorphPolygon2D
extends Polygon2D
## Preview scrubbing + keyframe edit mode (edit only when a key is selected).

signal timeline_changed

enum Mode { PREVIEW, EDIT_KEY }

@export var shape: MorphShape2D:
	set(value):
		shape = value
		if shape != null and not shape.keyframes.is_empty():
			select_keyframe(0)
		else:
			selected_keyframe = -1
			mode = Mode.PREVIEW
			timeline_changed.emit()

@export var playing: bool = false:
	set(value):
		if value == playing:
			return
		if value:
			commit_edit()
			mode = Mode.PREVIEW
			selected_keyframe = -1
		playing = value
		if playing:
			_push_sampled_polygon()
		elif mode == Mode.EDIT_KEY:
			_load_selected_keyframe()
		timeline_changed.emit()

@export_range(0.0, 1.0, 0.001) var time: float = 0.0:
	set(value):
		time = clampf(value, 0.0, 1.0)
		if playing or mode == Mode.PREVIEW:
			_push_sampled_polygon()

@export var edit_keyframe: int = 0:
	set(value):
		if _ignore_edit_export:
			edit_keyframe = value
			return
		select_keyframe(value)

var mode: Mode = Mode.EDIT_KEY
var selected_keyframe: int = -1

var _syncing := false
var _ignore_edit_export := false
var _last_polygon: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	set_process(true)
	if selected_keyframe < 0 and shape != null and not shape.keyframes.is_empty():
		select_keyframe(0)
	elif playing or mode == Mode.PREVIEW:
		_push_sampled_polygon()
	else:
		_load_selected_keyframe()


func _process(delta: float) -> void:
	if shape == null:
		return

	if playing:
		if shape.duration > 0.0:
			time = fposmod(time + delta / shape.duration, 1.0)
		return

	if mode == Mode.EDIT_KEY and selected_keyframe >= 0:
		if not _polygons_equal(polygon, _last_polygon):
			_commit_polygon_to_keyframe()


func scrub_to(t: float) -> void:
	## Animation-style scrub: show interpolation, don't edit until a key is selected.
	commit_edit()
	playing = false
	mode = Mode.PREVIEW
	selected_keyframe = -1
	_set_edit_export(0)
	time = clampf(t, 0.0, 1.0)
	_push_sampled_polygon()
	timeline_changed.emit()


func select_keyframe(index: int) -> void:
	commit_edit()
	if playing:
		playing = false

	if shape == null or shape.keyframes.is_empty() or index < 0:
		selected_keyframe = -1
		mode = Mode.PREVIEW
		_set_edit_export(0)
		timeline_changed.emit()
		return

	selected_keyframe = clampi(index, 0, shape.keyframes.size() - 1)
	_set_edit_export(selected_keyframe)
	mode = Mode.EDIT_KEY
	var key := shape.keyframes[selected_keyframe]
	if key != null:
		time = key.time
	_load_selected_keyframe()
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
			if entries[i].index == selected_keyframe:
				current_pos = i
				break
	else:
		var best_i := 0
		var best_dist := INF
		for i in entries.size():
			var dist: float = absf(entries[i].time - time)
			if dist < best_dist:
				best_dist = dist
				best_i = i
		current_pos = best_i

	var next_pos := clampi(current_pos + step, 0, entries.size() - 1)
	select_keyframe(entries[next_pos].index)


func insert_keyframe_at_playhead() -> void:
	if shape == null:
		return
	commit_edit()
	var positions := shape.sample_polygon(time)
	if positions.is_empty() and selected_keyframe >= 0 and selected_keyframe < shape.keyframes.size():
		var key := shape.keyframes[selected_keyframe]
		if key != null:
			positions = key.get_positions()
	if positions.is_empty():
		positions = PackedVector2Array([
			Vector2(0, -80),
			Vector2(-80, 60),
			Vector2(80, 60),
		])

	var existing := shape.find_keyframe_at_time(time, 0.001)
	if existing >= 0:
		shape.keyframes[existing].set_positions(positions)
		shape.emit_changed()
		select_keyframe(existing)
		return

	var index := shape.insert_keyframe(time, positions)
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
	var best: int = entries[0].index
	var best_dist := INF
	for entry in entries:
		var dist: float = absf(entry.time - keep_time)
		if dist < best_dist:
			best_dist = dist
			best = entry.index
	select_keyframe(best)


func commit_edit() -> void:
	if mode == Mode.EDIT_KEY and selected_keyframe >= 0:
		_commit_polygon_to_keyframe()


func is_editing_keyframe() -> bool:
	return mode == Mode.EDIT_KEY and selected_keyframe >= 0


func _set_edit_export(value: int) -> void:
	_ignore_edit_export = true
	edit_keyframe = value
	_ignore_edit_export = false


func _load_selected_keyframe() -> void:
	if shape == null or selected_keyframe < 0 or selected_keyframe >= shape.keyframes.size():
		return
	var key := shape.keyframes[selected_keyframe]
	if key == null:
		return
	_syncing = true
	polygon = key.get_positions()
	_last_polygon = polygon.duplicate()
	_syncing = false


func _push_sampled_polygon() -> void:
	if shape == null:
		return
	_syncing = true
	polygon = shape.sample_polygon(time)
	_last_polygon = polygon.duplicate()
	_syncing = false


func _commit_polygon_to_keyframe() -> void:
	if _syncing or shape == null or selected_keyframe < 0:
		return
	if selected_keyframe >= shape.keyframes.size():
		return
	var key := shape.keyframes[selected_keyframe]
	if key == null:
		return

	var previous_count := key.points.size()
	key.set_positions(polygon)
	if polygon.size() != previous_count:
		shape.sync_topology_from(selected_keyframe)

	_last_polygon = polygon.duplicate()
	shape.emit_changed()


func _polygons_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true
