@tool
extends RefCounted
## Bezier handles: big, tangent-aligned stubs, visible only on the selected anchor.

enum DragKind { NONE, ANCHOR, HANDLE_IN, HANDLE_OUT }

const ANCHOR_RADIUS_PX := 6.0
const HANDLE_SIZE_PX := 9.0
const ANCHOR_HIT_PX := 12.0
const HANDLE_HIT_PX := 12.0
const HANDLE_VISIBLE_EPS := 1.0
const STUB_LENGTH_PX := 32.0
const LINE_WIDTH := 2.0

var morph: MorphPolygon2D

var _drag_kind: DragKind = DragKind.NONE
var _drag_index: int = -1
var _active_index: int = -1


func set_morph(node: MorphPolygon2D) -> void:
	morph = node
	_drag_kind = DragKind.NONE
	_drag_index = -1
	if morph == null:
		_active_index = -1


func draw_over(overlay: Control) -> void:
	if morph == null or morph.shape == null:
		return
	if not morph.is_editing_keyframe():
		return

	var key := morph.get_edit_keyframe()
	if key == null or key.points.is_empty():
		return

	var xform := _world_to_overlay()

	## Control polygon (anchors only — no tessellation verts).
	for i in key.points.size():
		var point: BezierPoint = key.points[i]
		if point == null:
			continue
		var anchor := xform * point.position
		var selected := i == _active_index
		var fill := Color(1.0, 0.85, 0.15) if selected else Color(1, 1, 1)
		overlay.draw_circle(anchor, ANCHOR_RADIUS_PX, fill)
		overlay.draw_arc(anchor, ANCHOR_RADIUS_PX, 0.0, TAU, 28, Color(0, 0, 0, 0.85), 2.0, true)

		if not selected:
			continue

		var tangent_screen := _tangent_screen(key, i, xform, anchor)
		var hin_local := point.position + point.handle_in
		var hout_local := point.position + point.handle_out
		var hin := xform * hin_local
		var hout := xform * hout_local

		if point.handle_in.length() <= HANDLE_VISIBLE_EPS:
			hin = anchor - tangent_screen * STUB_LENGTH_PX
		if point.handle_out.length() <= HANDLE_VISIBLE_EPS:
			hout = anchor + tangent_screen * STUB_LENGTH_PX

		overlay.draw_line(anchor, hin, Color(1.0, 0.45, 0.1, 1.0), LINE_WIDTH, true)
		overlay.draw_line(anchor, hout, Color(0.15, 0.9, 0.45, 1.0), LINE_WIDTH, true)
		_draw_handle_square(overlay, hin, Color(1.0, 0.45, 0.1))
		_draw_handle_square(overlay, hout, Color(0.15, 0.9, 0.45))


func handle_input(event: InputEvent) -> bool:
	if morph == null or morph.shape == null or not morph.is_editing_keyframe():
		return false

	var key := morph.get_edit_keyframe()
	if key == null:
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false

		if mb.pressed:
			var hit := _hit_test(mb.position, key)
			if hit.kind == DragKind.NONE:
				if _active_index >= 0:
					_active_index = -1
					return true
				return false

			_active_index = hit.index
			if mb.double_click and hit.kind == DragKind.ANCHOR:
				var point: BezierPoint = key.points[hit.index]
				if point != null:
					point.reset_handles()
					morph.notify_geometry_edited()
				_drag_kind = DragKind.NONE
				_drag_index = -1
				return true

			_drag_kind = hit.kind
			_drag_index = hit.index

			var drag_point: BezierPoint = key.points[hit.index]
			if drag_point != null and (
				hit.kind == DragKind.HANDLE_IN or hit.kind == DragKind.HANDLE_OUT
			):
				_ensure_handle_seed(key, hit.index, hit.kind, mb.position)
			return true

		if _drag_kind != DragKind.NONE:
			_drag_kind = DragKind.NONE
			_drag_index = -1
			morph.notify_geometry_edited()
			return true

	elif event is InputEventMouseMotion:
		if _drag_kind == DragKind.NONE or _drag_index < 0:
			return false
		if _drag_index >= key.points.size():
			return false
		var point: BezierPoint = key.points[_drag_index]
		if point == null:
			return false

		var local := _overlay_to_local((event as InputEventMouseMotion).position)
		match _drag_kind:
			DragKind.ANCHOR:
				point.position = local
			DragKind.HANDLE_IN:
				point.handle_in = BezierPoint.clamp_handle(local - point.position)
			DragKind.HANDLE_OUT:
				point.handle_out = BezierPoint.clamp_handle(local - point.position)
		morph.notify_geometry_edited()
		return true

	return false


func _ensure_handle_seed(key: ShapeKeyframe, index: int, kind: DragKind, overlay_pos: Vector2) -> void:
	var point: BezierPoint = key.points[index]
	if point == null:
		return
	var tangent := morph.edge_tangent_at(key, index)
	var local := _overlay_to_local(overlay_pos)
	var from_mouse := local - point.position

	if kind == DragKind.HANDLE_IN and point.handle_in.length() <= HANDLE_VISIBLE_EPS:
		if from_mouse.length() > HANDLE_VISIBLE_EPS:
			point.handle_in = BezierPoint.clamp_handle(from_mouse)
		else:
			point.handle_in = BezierPoint.clamp_handle(-tangent * 48.0)
		## Keep the opposite stub facing it until the user edits it.
		if point.handle_out.length() <= HANDLE_VISIBLE_EPS:
			point.handle_out = BezierPoint.clamp_handle(-point.handle_in)
		morph.notify_geometry_edited()
	elif kind == DragKind.HANDLE_OUT and point.handle_out.length() <= HANDLE_VISIBLE_EPS:
		if from_mouse.length() > HANDLE_VISIBLE_EPS:
			point.handle_out = BezierPoint.clamp_handle(from_mouse)
		else:
			point.handle_out = BezierPoint.clamp_handle(tangent * 48.0)
		if point.handle_in.length() <= HANDLE_VISIBLE_EPS:
			point.handle_in = BezierPoint.clamp_handle(-point.handle_out)
		morph.notify_geometry_edited()


func _hit_test(overlay_pos: Vector2, key: ShapeKeyframe) -> Dictionary:
	var xform := _world_to_overlay()
	var best_kind: DragKind = DragKind.NONE
	var best_index := -1
	var best_dist := INF

	## Handles only for the active anchor.
	if _active_index >= 0 and _active_index < key.points.size():
		var point: BezierPoint = key.points[_active_index]
		if point != null:
			var anchor := xform * point.position
			var tangent_screen := _tangent_screen(key, _active_index, xform, anchor)
			var hin := xform * (point.position + point.handle_in)
			var hout := xform * (point.position + point.handle_out)
			if point.handle_in.length() <= HANDLE_VISIBLE_EPS:
				hin = anchor - tangent_screen * STUB_LENGTH_PX
			if point.handle_out.length() <= HANDLE_VISIBLE_EPS:
				hout = anchor + tangent_screen * STUB_LENGTH_PX

			var din := overlay_pos.distance_to(hin)
			if din <= HANDLE_HIT_PX and din < best_dist:
				best_dist = din
				best_kind = DragKind.HANDLE_IN
				best_index = _active_index

			var dout := overlay_pos.distance_to(hout)
			if dout <= HANDLE_HIT_PX and dout < best_dist:
				best_dist = dout
				best_kind = DragKind.HANDLE_OUT
				best_index = _active_index

	if best_kind != DragKind.NONE:
		return {"kind": best_kind, "index": best_index}

	for i in key.points.size():
		var point2: BezierPoint = key.points[i]
		if point2 == null:
			continue
		var anchor2 := xform * point2.position
		var d := overlay_pos.distance_to(anchor2)
		if d <= ANCHOR_HIT_PX and d < best_dist:
			best_dist = d
			best_kind = DragKind.ANCHOR
			best_index = i

	return {"kind": best_kind, "index": best_index}


func _draw_handle_square(overlay: Control, center: Vector2, fill: Color) -> void:
	var half := HANDLE_SIZE_PX * 0.5
	var rect := Rect2(center - Vector2(half, half), Vector2(HANDLE_SIZE_PX, HANDLE_SIZE_PX))
	overlay.draw_rect(rect, fill, true)
	overlay.draw_rect(rect, Color(0, 0, 0, 0.85), false, 1.5)


func _tangent_screen(key: ShapeKeyframe, index: int, xform: Transform2D, anchor_screen: Vector2) -> Vector2:
	var tangent := morph.edge_tangent_at(key, index)
	var point: BezierPoint = key.points[index]
	var tip := xform * (point.position + tangent * 32.0)
	var screen_dir := tip - anchor_screen
	if screen_dir.length_squared() < 0.0001:
		return Vector2.RIGHT
	return screen_dir.normalized()


func _world_to_overlay() -> Transform2D:
	return morph.get_viewport_transform() * morph.get_global_transform()


func _overlay_to_local(overlay_pos: Vector2) -> Vector2:
	return _world_to_overlay().affine_inverse() * overlay_pos
