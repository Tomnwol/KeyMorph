@tool
class_name MorphShape2D
extends Resource
## Animated Bezier polygon defined by keyframes with a shared point topology.

@export var closed: bool = true
@export var duration: float = 1.0
@export var loop: bool = true
@export_range(2, 64, 1, "or_greater") var curve_precision: int = 12
@export var keyframes: Array[ShapeKeyframe] = []


func get_timeline_entries() -> Array[Dictionary]:
	## Sorted by time: [{ "index": int, "time": float, "key": ShapeKeyframe }, ...]
	var entries: Array[Dictionary] = []
	for i in keyframes.size():
		var key := keyframes[i]
		if key == null:
			continue
		entries.append({"index": i, "time": key.time, "key": key})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)

	## Mirror the evenly-spaced fallback used by sampling when all times are equal.
	if entries.size() > 1:
		var all_same := true
		for i in range(1, entries.size()):
			if not is_equal_approx(float(entries[i].time), float(entries[0].time)):
				all_same = false
				break
		if all_same:
			for i in entries.size():
				entries[i].time = float(i) / float(entries.size() - 1)
	return entries


func find_keyframe_at_time(t: float, tolerance: float = 0.02) -> int:
	var best := -1
	var best_dist := INF
	for entry in get_timeline_entries():
		var dist: float = absf(float(entry.time) - t)
		if dist <= tolerance and dist < best_dist:
			best_dist = dist
			best = int(entry.index)
	return best


func insert_keyframe(time: float, positions: PackedVector2Array) -> int:
	var controls: Array[BezierPoint] = []
	controls.resize(positions.size())
	for i in positions.size():
		var point := BezierPoint.new()
		point.position = positions[i]
		controls[i] = point
	return insert_keyframe_controls(time, controls)


func insert_keyframe_controls(time: float, controls: Array[BezierPoint]) -> int:
	var key := ShapeKeyframe.new()
	key.time = clampf(time, 0.0, 1.0)
	key.set_control_points(controls)
	keyframes.append(key)
	var index := keyframes.size() - 1
	if keyframes.size() > 1:
		sync_topology_from(index)
	emit_changed()
	return index


func remove_keyframe(index: int) -> void:
	if index < 0 or index >= keyframes.size():
		return
	keyframes.remove_at(index)
	emit_changed()


func sync_topology_from(source_index: int) -> void:
	## Keep the same point count on every keyframe (required for morphing).
	if source_index < 0 or source_index >= keyframes.size():
		return
	var source := keyframes[source_index]
	if source == null:
		return
	var count := source.points.size()
	for i in keyframes.size():
		if i == source_index:
			continue
		var key := keyframes[i]
		if key == null:
			continue
		var next: Array[BezierPoint] = []
		next.resize(count)
		for p in count:
			if p < key.points.size() and key.points[p] != null:
				next[p] = key.points[p]
			else:
				var point := BezierPoint.new()
				if p < source.points.size() and source.points[p] != null:
					point.position = source.points[p].position
				elif key.points.size() > 0 and key.points[key.points.size() - 1] != null:
					point.position = key.points[key.points.size() - 1].position
				next[p] = point
		key.points = next
		key.emit_changed()
	emit_changed()


func sample_control_points(t: float) -> Array[BezierPoint]:
	var entries := get_timeline_entries()
	var out: Array[BezierPoint] = []
	if entries.is_empty():
		return out

	t = clampf(t, 0.0, 1.0)
	if entries.size() == 1 or t <= float(entries[0].time):
		return (entries[0].key as ShapeKeyframe).duplicate_control_points()
	if t >= float(entries[entries.size() - 1].time):
		return (entries[entries.size() - 1].key as ShapeKeyframe).duplicate_control_points()

	var i := 0
	while i < entries.size() - 1 and float(entries[i + 1].time) < t:
		i += 1

	var a: ShapeKeyframe = entries[i].key
	var b: ShapeKeyframe = entries[i + 1].key
	var span: float = float(entries[i + 1].time) - float(entries[i].time)
	var alpha: float = 0.0 if span <= 0.0 else (t - float(entries[i].time)) / span
	return _lerp_control_points(a, b, alpha)


func sample_polygon(t: float) -> PackedVector2Array:
	return tessellate_controls(sample_control_points(t))


func tessellate_keyframe(key: ShapeKeyframe) -> PackedVector2Array:
	if key == null:
		return PackedVector2Array()
	return tessellate_controls(key.points)


func tessellate_controls(points: Array[BezierPoint]) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	if points.size() == 1:
		var only: BezierPoint = points[0]
		out.append(only.position if only != null else Vector2.ZERO)
		return out

	var count := points.size()
	var first: BezierPoint = points[0]
	out.append(first.position if first != null else Vector2.ZERO)

	var segment_count := count if closed else count - 1
	var steps: int = maxi(curve_precision, 2)
	for i in segment_count:
		var a: BezierPoint = points[i]
		var b: BezierPoint = points[(i + 1) % count]
		if a == null or b == null:
			continue
		var p0 := a.position
		var p1 := a.position + a.handle_out
		var p2 := b.position + b.handle_in
		var p3 := b.position
		for s in range(1, steps + 1):
			if closed and i == segment_count - 1 and s == steps:
				break
			var tt := float(s) / float(steps)
			out.append(_cubic(p0, p1, p2, p3, tt))
	return out


func _lerp_control_points(a: ShapeKeyframe, b: ShapeKeyframe, alpha: float) -> Array[BezierPoint]:
	var count := mini(a.points.size(), b.points.size())
	var out: Array[BezierPoint] = []
	out.resize(count)
	for i in count:
		var pa: BezierPoint = a.points[i]
		var pb: BezierPoint = b.points[i]
		if pa == null or pb == null:
			out[i] = BezierPoint.new()
		else:
			out[i] = pa.lerp_toward(pb, alpha)
	return out


static func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return (
		u * u * u * p0
		+ 3.0 * u * u * t * p1
		+ 3.0 * u * t * t * p2
		+ t * t * t * p3
	)
