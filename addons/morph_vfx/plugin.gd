@tool
extends EditorPlugin

const ADDON_NAME := "KeyMorph"

var _dock: Control
var _gizmo = preload("res://addons/morph_vfx/editor/morph_canvas_gizmo.gd").new()
var _edited_morph: MorphPolygon2D


func _enter_tree() -> void:
	add_custom_type(
		"MorphPolygon2D",
		"Node2D",
		preload("res://addons/morph_vfx/runtime/morph_polygon_2d.gd"),
		null
	)

	_dock = preload("res://addons/morph_vfx/editor/morph_timeline_dock.gd").new()
	add_control_to_bottom_panel(_dock, ADDON_NAME)

	var selection := get_editor_interface().get_selection()
	selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()
	print("%s: enabled" % ADDON_NAME)


func _exit_tree() -> void:
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)

	_unbind_morph()

	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null

	remove_custom_type("MorphPolygon2D")
	print("%s: disabled" % ADDON_NAME)


func _handles(object: Object) -> bool:
	return object is MorphPolygon2D


func _edit(object: Object) -> void:
	_bind_morph(object as MorphPolygon2D)


func _make_visible(visible: bool) -> void:
	if not visible:
		_unbind_morph()
	update_overlays()


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	_gizmo.draw_over(overlay)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	var handled: bool = _gizmo.handle_input(event)
	if handled:
		update_overlays()
	return handled


func _input(event: InputEvent) -> void:
	## Keyboard delete may not reach the canvas forwarder; catch it here.
	if _edited_morph == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_ev := event as InputEventKey
		if key_ev.keycode == KEY_DELETE or key_ev.keycode == KEY_BACKSPACE:
			if _gizmo.try_delete_selected_point():
				update_overlays()
				get_viewport().set_input_as_handled()


func _on_selection_changed() -> void:
	if _dock == null:
		return
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	var morph: MorphPolygon2D = null
	for node in selected:
		if node is MorphPolygon2D:
			morph = node
			break
	_dock.set_target(morph)
	if morph != null:
		make_bottom_panel_item_visible(_dock)
		_bind_morph(morph)
	else:
		_unbind_morph()
		update_overlays()


func _bind_morph(morph: MorphPolygon2D) -> void:
	if morph == _edited_morph:
		_gizmo.set_morph(morph)
		update_overlays()
		return

	_unbind_morph()
	_edited_morph = morph
	_gizmo.set_morph(_edited_morph)
	if _edited_morph != null and not _edited_morph.timeline_changed.is_connected(_on_morph_timeline_changed):
		_edited_morph.timeline_changed.connect(_on_morph_timeline_changed)
	update_overlays()


func _unbind_morph() -> void:
	if _edited_morph != null and _edited_morph.timeline_changed.is_connected(_on_morph_timeline_changed):
		_edited_morph.timeline_changed.disconnect(_on_morph_timeline_changed)
	_edited_morph = null
	_gizmo.set_morph(null)


func _on_morph_timeline_changed() -> void:
	## Key switch / retime / geometry edit — refresh viewport gizmo immediately.
	if _gizmo.has_method("on_timeline_changed"):
		_gizmo.on_timeline_changed()
	update_overlays()
