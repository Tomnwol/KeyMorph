@tool
class_name BezierPoint
extends Resource
## One control point of a morphable polygon (Bezier handles come later).

@export var position: Vector2 = Vector2.ZERO
@export var handle_in: Vector2 = Vector2.ZERO
@export var handle_out: Vector2 = Vector2.ZERO
@export var mirrored: bool = true
