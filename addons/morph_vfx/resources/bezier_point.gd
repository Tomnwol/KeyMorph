@tool
class_name BezierPoint
extends Resource
## Anchor + two independent cubic Bezier handles (relative offsets).

const MAX_HANDLE_LENGTH := 256.0

@export var position: Vector2 = Vector2.ZERO
@export var handle_in: Vector2 = Vector2.ZERO
@export var handle_out: Vector2 = Vector2.ZERO


static func clamp_handle(value: Vector2) -> Vector2:
	if value.length() > MAX_HANDLE_LENGTH:
		return value.limit_length(MAX_HANDLE_LENGTH)
	return value


func reset_handles() -> void:
	handle_in = Vector2.ZERO
	handle_out = Vector2.ZERO
	emit_changed()


func duplicate_point() -> BezierPoint:
	var copy := BezierPoint.new()
	copy.position = position
	copy.handle_in = handle_in
	copy.handle_out = handle_out
	return copy


func lerp_toward(other: BezierPoint, alpha: float) -> BezierPoint:
	var mixed := BezierPoint.new()
	mixed.position = position.lerp(other.position, alpha)
	mixed.handle_in = handle_in.lerp(other.handle_in, alpha)
	mixed.handle_out = handle_out.lerp(other.handle_out, alpha)
	return mixed
