@tool
class_name MorphShape2D
extends Resource
## Animated polygon defined by keyframes with a shared point topology.

@export var closed: bool = true
@export var duration: float = 1.0
@export var loop: bool = true
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
			if not is_equal_approx(entries[i].time, entries[0].time):
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
		var dist: float = absf(entry.time - t)
		if dist <= tolerance and dist < best_dist:
			best_dist = dist
			best = entry.index
	return best


func insert_keyframe(time: float, positions: PackedVector2Array) -> int:
	var key := ShapeKeyframe.new()
	key.time = clampf(time, 0.0, 1.0)
	key.set_positions(positions)
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
		var positions := key.get_positions()
		var next := PackedVector2Array()
		next.resize(count)
		for p in count:
			if p < positions.size():
				next[p] = positions[p]
			elif p < source.points.size() and source.points[p] != null:
				next[p] = source.points[p].position
			elif positions.size() > 0:
				next[p] = positions[positions.size() - 1]
			else:
				next[p] = Vector2.ZERO
		key.set_positions(next)
	emit_changed()


func sample_polygon(t: float) -> PackedVector2Array:
	## MVP: linear positions only (Bezier tessellation comes later).
	var entries := get_timeline_entries()
	if entries.is_empty():
		return PackedVector2Array()

	t = clampf(t, 0.0, 1.0)
	if entries.size() == 1 or t <= entries[0].time:
		return (entries[0].key as ShapeKeyframe).get_positions()
	if t >= entries[entries.size() - 1].time:
		return (entries[entries.size() - 1].key as ShapeKeyframe).get_positions()

	var i := 0
	while i < entries.size() - 1 and entries[i + 1].time < t:
		i += 1

	var a: ShapeKeyframe = entries[i].key
	var b: ShapeKeyframe = entries[i + 1].key
	var span: float = float(entries[i + 1].time) - float(entries[i].time)
	var alpha: float = 0.0 if span <= 0.0 else (t - float(entries[i].time)) / span
	return _lerp_keys(a, b, alpha)


func _lerp_keys(a: ShapeKeyframe, b: ShapeKeyframe, alpha: float) -> PackedVector2Array:
	var count := mini(a.points.size(), b.points.size())
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		var pa: BezierPoint = a.points[i]
		var pb: BezierPoint = b.points[i]
		if pa == null or pb == null:
			out[i] = Vector2.ZERO
		else:
			out[i] = pa.position.lerp(pb.position, alpha)
	return out
