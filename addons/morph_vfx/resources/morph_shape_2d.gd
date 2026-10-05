@tool
class_name MorphShape2D
extends Resource
## Animated Bezier polygon defined by keyframes with a shared point topology.

@export var closed: bool = true
@export var duration: float = 1.0 ## Seconds for a full 0→1 cycle when playing.
@export var loop: bool = true
@export var ease: MorphEasing.Type = MorphEasing.Type.LINEAR
@export var ease_mode: MorphEasing.Mode = MorphEasing.Mode.BETWEEN_KEYS
@export_range(0.0, 2.5, 0.01) var smooth_blend: float = 0.0
## 0 = linear keys only. 1 = full Cardinal/Catmull. >1 exaggerates the spline deviation (more punch).
@export_range(-1.0, 1.0, 0.01) var smooth_tension: float = 0.0
## Cardinal tension: 0 = Catmull-Rom, >0 tighter/closer to linear, <0 longer tangents (more punch).
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


func bake_display_times_to_keys() -> void:
	## If every key shares the same stored time, persist the evenly-spaced display times.
	var entries := get_timeline_entries()
	if entries.size() <= 1:
		return
	var raw_same := true
	var first_time := keyframes[int(entries[0].index)].time
	for i in range(1, entries.size()):
		var key: ShapeKeyframe = keyframes[int(entries[i].index)]
		if key == null or not is_equal_approx(key.time, first_time):
			raw_same = false
			break
	if not raw_same:
		return
	for i in entries.size():
		var key2: ShapeKeyframe = keyframes[int(entries[i].index)]
		if key2 != null:
			key2.time = float(i) / float(entries.size() - 1)
	emit_changed()


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


func insert_point_on_edge(edge_index: int, t: float, topology_source: int = 0) -> int:
	## Insert a vertex on the same edge of every keyframe (De Casteljau),
	## so the silhouette stays unchanged for the user.
	if keyframes.is_empty():
		return -1
	if topology_source < 0 or topology_source >= keyframes.size():
		topology_source = 0
	sync_topology_from(topology_source)

	var ref_key := keyframes[topology_source]
	if ref_key == null or ref_key.points.size() < 2:
		return -1
	var count := ref_key.points.size()
	var segment_count := count if closed else count - 1
	if edge_index < 0 or edge_index >= segment_count:
		return -1

	t = clampf(t, 0.05, 0.95)
	for key in keyframes:
		if key == null or key.points.size() < 2:
			continue
		_split_keyframe_edge(key, edge_index, t)

	emit_changed()
	return edge_index + 1


func remove_point_at(point_index: int) -> bool:
	## Remove the same control point index on every keyframe.
	if keyframes.is_empty():
		return false
	var ref: ShapeKeyframe = null
	for key in keyframes:
		if key != null:
			ref = key
			break
	if ref == null:
		return false
	var min_points := 3 if closed else 2
	if ref.points.size() <= min_points:
		return false
	if point_index < 0 or point_index >= ref.points.size():
		return false

	for key in keyframes:
		if key == null:
			continue
		if point_index >= key.points.size():
			continue
		key.points.remove_at(point_index)
		key.emit_changed()

	emit_changed()
	return true


func _split_keyframe_edge(key: ShapeKeyframe, edge_index: int, t: float) -> void:
	var count := key.points.size()
	var a: BezierPoint = key.points[edge_index]
	var b: BezierPoint = key.points[(edge_index + 1) % count]
	if a == null or b == null:
		return

	var p0 := a.position
	var p1 := a.position + a.handle_out
	var p2 := b.position + b.handle_in
	var p3 := b.position

	var p01 := p0.lerp(p1, t)
	var p12 := p1.lerp(p2, t)
	var p23 := p2.lerp(p3, t)
	var p012 := p01.lerp(p12, t)
	var p123 := p12.lerp(p23, t)
	var p0123 := p012.lerp(p123, t)

	a.handle_out = BezierPoint.clamp_handle(p01 - p0)
	b.handle_in = BezierPoint.clamp_handle(p23 - p3)

	var mid := BezierPoint.new()
	mid.position = p0123
	mid.handle_in = BezierPoint.clamp_handle(p012 - p0123)
	mid.handle_out = BezierPoint.clamp_handle(p123 - p0123)

	key.points.insert(edge_index + 1, mid)
	key.emit_changed()


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
	if ease_mode == MorphEasing.Mode.GLOBAL_TIMELINE:
		t = MorphEasing.apply(ease, t)

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
	if ease_mode == MorphEasing.Mode.BETWEEN_KEYS:
		alpha = MorphEasing.apply(ease, alpha)

	var linear := _lerp_control_points(a, b, alpha)
	if smooth_blend <= 0.001 or entries.size() < 3:
		return linear

	var k0: ShapeKeyframe = _entry_key(entries, i - 1)
	var k1: ShapeKeyframe = a
	var k2: ShapeKeyframe = b
	var k3: ShapeKeyframe = _entry_key(entries, i + 2)
	var spline := _cardinal_control_points(k0, k1, k2, k3, alpha, smooth_tension)
	## weight can exceed 1 to exaggerate beyond pure spline.
	return _blend_control_points(linear, spline, smooth_blend)


func _entry_key(entries: Array[Dictionary], index: int) -> ShapeKeyframe:
	var n := entries.size()
	if n == 0:
		return null
	if loop:
		index = wrapi(index, 0, n)
	else:
		index = clampi(index, 0, n - 1)
	return entries[index].key as ShapeKeyframe


func _cardinal_control_points(
	k0: ShapeKeyframe,
	k1: ShapeKeyframe,
	k2: ShapeKeyframe,
	k3: ShapeKeyframe,
	t: float,
	tension: float
) -> Array[BezierPoint]:
	var count := mini(
		mini(k0.points.size() if k0 else 0, k1.points.size() if k1 else 0),
		mini(k2.points.size() if k2 else 0, k3.points.size() if k3 else 0)
	)
	var out: Array[BezierPoint] = []
	out.resize(count)
	for i in count:
		var p0: BezierPoint = k0.points[i] if k0 else null
		var p1: BezierPoint = k1.points[i] if k1 else null
		var p2: BezierPoint = k2.points[i] if k2 else null
		var p3: BezierPoint = k3.points[i] if k3 else null
		if p0 == null or p1 == null or p2 == null or p3 == null:
			out[i] = BezierPoint.new()
			continue
		var mixed := BezierPoint.new()
		mixed.position = _cardinal(p0.position, p1.position, p2.position, p3.position, t, tension)
		mixed.handle_in = _cardinal(p0.handle_in, p1.handle_in, p2.handle_in, p3.handle_in, t, tension)
		mixed.handle_out = _cardinal(p0.handle_out, p1.handle_out, p2.handle_out, p3.handle_out, t, tension)
		out[i] = mixed
	return out


func _blend_control_points(
	a: Array[BezierPoint],
	b: Array[BezierPoint],
	weight: float
) -> Array[BezierPoint]:
	## linear + (spline - linear) * weight — weight>1 adds extra punch.
	var count := mini(a.size(), b.size())
	var out: Array[BezierPoint] = []
	out.resize(count)
	weight = maxf(weight, 0.0)
	for i in count:
		var pa: BezierPoint = a[i]
		var pb: BezierPoint = b[i]
		if pa == null or pb == null:
			out[i] = BezierPoint.new()
		else:
			out[i] = pa.lerp_toward(pb, weight)
	return out


static func _cardinal(
	p0: Vector2,
	p1: Vector2,
	p2: Vector2,
	p3: Vector2,
	t: float,
	tension: float
) -> Vector2:
	## Cardinal spline (tension 0 = Catmull-Rom). Negative tension = longer tangents.
	var s := (1.0 - tension) * 0.5
	var m1 := s * (p2 - p0)
	var m2 := s * (p3 - p1)
	var t2 := t * t
	var t3 := t2 * t
	var h00 := 2.0 * t3 - 3.0 * t2 + 1.0
	var h10 := t3 - 2.0 * t2 + t
	var h01 := -2.0 * t3 + 3.0 * t2
	var h11 := t3 - t2
	return h00 * p1 + h10 * m1 + h01 * p2 + h11 * m2


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
