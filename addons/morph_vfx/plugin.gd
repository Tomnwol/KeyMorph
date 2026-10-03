@tool
extends EditorPlugin

const ADDON_NAME := "Morph VFX"

var _dock: Control


func _enter_tree() -> void:
	add_custom_type(
		"MorphPolygon2D",
		"Polygon2D",
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

	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null

	remove_custom_type("MorphPolygon2D")
	print("%s: disabled" % ADDON_NAME)


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
