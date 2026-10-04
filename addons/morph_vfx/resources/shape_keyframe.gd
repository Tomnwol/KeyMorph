@tool
class_name ShapeKeyframe
extends Resource
## A full polygon pose at a normalized time in [0, 1].

@export_range(0.0, 1.0, 0.001) var time: float = 0.0
@export var points: Array[BezierPoint] = []


func get_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i].position if points[i] != null else Vector2.ZERO
	return out


func set_positions(positions: PackedVector2Array) -> void:
	## Keep existing BezierPoint resources when possible so handles survive.
	var next: Array[BezierPoint] = []
	next.resize(positions.size())
	for i in positions.size():
		var point: BezierPoint
		if i < points.size() and points[i] != null:
			point = points[i]
		else:
			point = BezierPoint.new()
		point.position = positions[i]
		next[i] = point
	points = next
	emit_changed()


func set_control_points(controls: Array[BezierPoint]) -> void:
	var next: Array[BezierPoint] = []
	next.resize(controls.size())
	for i in controls.size():
		if controls[i] != null:
			next[i] = controls[i].duplicate_point()
		else:
			next[i] = BezierPoint.new()
	points = next
	emit_changed()


func duplicate_control_points() -> Array[BezierPoint]:
	var out: Array[BezierPoint] = []
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i].duplicate_point() if points[i] != null else BezierPoint.new()
	return out
