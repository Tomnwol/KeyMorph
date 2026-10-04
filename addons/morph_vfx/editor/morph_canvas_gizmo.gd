@tool
extends RefCounted
## Bezier handles + double-click on edge to insert a shape-preserving point.

enum DragKind { NONE, ANCHOR, HANDLE_IN, HANDLE_OUT }

const ANCHOR_RADIUS_PX := 6.0
const HANDLE_SIZE_PX := 9.0
const ANCHOR_HIT_PX := 14.0
const HANDLE_HIT_PX := 14.0
const EDGE_HIT_PX := 12.0
const HANDLE_VISIBLE_EPS := 1.0
const STUB_LENGTH_PX := 32.0
const LINE_WIDTH := 2.0
const EDGE_SAMPLE_STEPS := 24

var morph: MorphPolygon2D

var _drag_kind: DragKind = DragKind.NONE
var _drag_index: int = -1
var _active_index: int = -1
var _last_keyframe_index: int = -999
var _hover_edge: int = -1
var _hover_t: float = 0.5
var _drag_moved: bool = false
var _press_pos: Vector2 = Vector2.ZERO


func set_morph(node: MorphPolygon2D) -> void:
	morph = node
	_drag_kind = DragKind.NONE
	_drag_index = -1
	_active_index = -1
	_last_keyframe_index = -999
	_hover_edge = -1
	_drag_moved = false


func on_timeline_changed() -> void:
	## Only clear the selected anchor when the edited keyframe actually changes.
	var idx := -1
	if morph != null and morph.is_editing_keyframe():
		idx = morph.selected_keyframe
	if idx == _last_keyframe_index:
		return
	_last_keyframe_index = idx
	_drag_kind = DragKind.NONE
	_drag_index = -1
	_active_index = -1
	_hover_edge = -1
	_drag_moved = false


func draw_over(overlay: Control) -> void:
	if morph == null or morph.shape == null:
		return
	if not morph.is_editing_keyframe():
		return

	var key := morph.get_edit_keyframe()
	if key == null or key.points.is_empty():
		return

	var xform := _world_to_overlay()

	## Hover hint where a new point would be inserted.
	if _hover_edge >= 0 and _active_index < 0 and _drag_kind == DragKind.NONE:
		var hint := _edge_point_local(key, _hover_edge, _hover_t)
		var hint_screen := xform * hint
		overlay.draw_circle(hint_screen, 5.0, Color(0.4, 0.85, 1.0, 0.9))
		overlay.draw_arc(hint_screen, 5.0, 0.0, TAU, 20, Color(0, 0, 0, 0.75), 1.5, true)

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
		var hin := xform * (point.position + point.handle_in)
		var hout := xform * (point.position + point.handle_out)

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

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion

		if _drag_kind != DragKind.NONE and _drag_index >= 0:
			return _handle_drag_motion(motion.position, key)

		## Hover preview for edge insert.
		var edge_hit := _hit_edge(motion.position, key)
		var prev_edge := _hover_edge
		var prev_t := _hover_t
		if int(edge_hit.edge) >= 0 and _hit_test(motion.position, key).kind == DragKind.NONE:
			_hover_edge = int(edge_hit.edge)
			_hover_t = float(edge_hit.t)
		else:
			_hover_edge = -1
		if _hover_edge != prev_edge or not is_equal_approx(_hover_t, prev_t):
			return true
		## Consume while hovering the shape so the editor doesn't steal selection.
		return _is_over_shape(motion.position, key)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false

		if mb.pressed:
			_press_pos = mb.position
			_drag_moved = false
			var hit := _hit_test(mb.position, key)
			var edge_hit := _hit_edge(mb.position, key)

			if mb.double_click:
				if hit.kind == DragKind.ANCHOR:
					var point: BezierPoint = key.points[hit.index]
					if point != null:
						point.reset_handles()
						morph.notify_geometry_edited()
					_clear_drag()
					return true

				if int(edge_hit.edge) >= 0:
					var new_index := morph.insert_point_on_edge(int(edge_hit.edge), float(edge_hit.t))
					if new_index >= 0:
						_active_index = new_index
						_hover_edge = -1
					_clear_drag()
					return true

			if hit.kind != DragKind.NONE:
				_active_index = hit.index
				_hover_edge = -1
				_drag_kind = hit.kind
				_drag_index = hit.index
				var drag_point: BezierPoint = key.points[hit.index]
				if drag_point != null and (
					hit.kind == DragKind.HANDLE_IN or hit.kind == DragKind.HANDLE_OUT
				):
					_ensure_handle_seed(key, hit.index, hit.kind, mb.position)
				return true

			## Click on edge / fill: keep the node selected (do NOT return false).
			if int(edge_hit.edge) >= 0 or _is_over_shape(mb.position, key):
				_active_index = -1
				_clear_drag()
				return true

			## Outside the shape: allow the editor to change selection.
			_active_index = -1
			_clear_drag()
			return false

		## Mouse button released.
		if _drag_kind != DragKind.NONE:
			var moved := _drag_moved
			_clear_drag()
			if moved:
				morph.notify_geometry_edited()
			return true

		## Release after edge/shape click — still consume so focus stays.
		if _is_over_shape(mb.position, key) or _hit_edge(mb.position, key).edge >= 0:
			return true

	return false


func _handle_drag_motion(overlay_pos: Vector2, key: ShapeKeyframe) -> bool:
	if _drag_index < 0 or _drag_index >= key.points.size():
		return false
	var point: BezierPoint = key.points[_drag_index]
	if point == null:
		return false

	if overlay_pos.distance_to(_press_pos) > 2.0:
		_drag_moved = true

	var local := _overlay_to_local(overlay_pos)
	match _drag_kind:
		DragKind.ANCHOR:
			point.position = local
		DragKind.HANDLE_IN:
			point.handle_in = BezierPoint.clamp_handle(local - point.position)
		DragKind.HANDLE_OUT:
			point.handle_out = BezierPoint.clamp_handle(local - point.position)

	## Live preview without emitting timeline_changed every pixel (avoids side effects).
	morph.queue_redraw()
	return true


func _clear_drag() -> void:
	_drag_kind = DragKind.NONE
	_drag_index = -1
	_drag_moved = false


func _is_over_shape(overlay_pos: Vector2, key: ShapeKeyframe) -> bool:
	if morph == null or morph.shape == null:
		return false
	if _hit_edge(overlay_pos, key).edge >= 0:
		return true
	var local := _overlay_to_local(overlay_pos)
	var poly := morph.shape.tessellate_keyframe(key)
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(local, poly)


func _ensure_handle_seed(key: ShapeKeyframe, index: int, kind: DragKind, overlay_pos: Vector2) -> void:
	## Option A: only seed the grabbed handle — never touch the opposite one.
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
		morph.notify_geometry_edited()
	elif kind == DragKind.HANDLE_OUT and point.handle_out.length() <= HANDLE_VISIBLE_EPS:
		if from_mouse.length() > HANDLE_VISIBLE_EPS:
			point.handle_out = BezierPoint.clamp_handle(from_mouse)
		else:
			point.handle_out = BezierPoint.clamp_handle(tangent * 48.0)
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


func _hit_edge(overlay_pos: Vector2, key: ShapeKeyframe) -> Dictionary:
	var xform := _world_to_overlay()
	var count := key.points.size()
	if count < 2:
		return {"edge": -1, "t": 0.5}

	var segment_count := count if morph.shape.closed else count - 1
	var best_edge := -1
	var best_t := 0.5
	var best_dist := INF

	for edge_i in segment_count:
		var a: BezierPoint = key.points[edge_i]
		var b: BezierPoint = key.points[(edge_i + 1) % count]
		if a == null or b == null:
			continue
		var p0 := a.position
		var p1 := a.position + a.handle_out
		var p2 := b.position + b.handle_in
		var p3 := b.position
		for s in EDGE_SAMPLE_STEPS + 1:
			var tt := float(s) / float(EDGE_SAMPLE_STEPS)
			tt = clampf(tt, 0.05, 0.95)
			var local_pt := MorphShape2D._cubic(p0, p1, p2, p3, tt)
			var screen_pt := xform * local_pt
			var dist := overlay_pos.distance_to(screen_pt)
			if dist <= EDGE_HIT_PX and dist < best_dist:
				best_dist = dist
				best_edge = edge_i
				best_t = tt

	return {"edge": best_edge, "t": best_t}


func _edge_point_local(key: ShapeKeyframe, edge_index: int, t: float) -> Vector2:
	var count := key.points.size()
	var a: BezierPoint = key.points[edge_index]
	var b: BezierPoint = key.points[(edge_index + 1) % count]
	if a == null or b == null:
		return Vector2.ZERO
	return MorphShape2D._cubic(
		a.position,
		a.position + a.handle_out,
		b.position + b.handle_in,
		b.position,
		t
	)


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
