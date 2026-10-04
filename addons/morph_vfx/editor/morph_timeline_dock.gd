@tool
extends Control

var target: MorphPolygon2D

var _status: Label
var _play_btn: Button
var _track: Control
var _time_label: Label


func _ready() -> void:
	name = "KeyMorph"
	set_custom_minimum_size(Vector2(0, 120))
	_build_ui()
	set_process(true)


func set_target(node: MorphPolygon2D) -> void:
	if target != null and target.timeline_changed.is_connected(_on_timeline_changed):
		target.timeline_changed.disconnect(_on_timeline_changed)
	target = node
	if target != null:
		target.timeline_changed.connect(_on_timeline_changed)
	if _track != null and _track.has_method("set_target"):
		_track.set_target(target)
	_refresh()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)

	var prev_btn := Button.new()
	prev_btn.text = "|<"
	prev_btn.tooltip_text = "Previous keyframe"
	prev_btn.pressed.connect(func() -> void:
		if target: target.goto_adjacent_keyframe(-1)
	)
	bar.add_child(prev_btn)

	_play_btn = Button.new()
	_play_btn.text = "Play"
	_play_btn.pressed.connect(_toggle_play)
	bar.add_child(_play_btn)

	var next_btn := Button.new()
	next_btn.text = ">|"
	next_btn.tooltip_text = "Next keyframe"
	next_btn.pressed.connect(func() -> void:
		if target: target.goto_adjacent_keyframe(1)
	)
	bar.add_child(next_btn)

	var insert_btn := Button.new()
	insert_btn.text = "Insert Key"
	insert_btn.tooltip_text = "Insert a keyframe at the playhead"
	insert_btn.pressed.connect(func() -> void:
		if target: target.insert_keyframe_at_playhead()
	)
	bar.add_child(insert_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Delete Key"
	delete_btn.tooltip_text = "Delete the selected keyframe"
	delete_btn.pressed.connect(func() -> void:
		if target: target.delete_selected_keyframe()
	)
	bar.add_child(delete_btn)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)

	_time_label = Label.new()
	_time_label.custom_minimum_size.x = 90
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_time_label)

	_track = preload("res://addons/morph_vfx/editor/morph_timeline_track.gd").new()
	_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_track.scrubbed.connect(_on_scrubbed)
	_track.keyframe_clicked.connect(_on_key_clicked)
	root.add_child(_track)

	var help := Label.new()
	help.text = "Click an anchor to show handles. Orange/green bars start tangent to the edges. Double-click anchor = reset. curve_precision on the node."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color(0.7, 0.72, 0.76))
	root.add_child(help)


func _process(_delta: float) -> void:
	if target != null and target.playing and _track != null:
		_track.queue_redraw()
		_update_labels()


func _toggle_play() -> void:
	if target == null:
		return
	target.playing = not target.playing
	_refresh()


func _on_scrubbed(t: float) -> void:
	if target == null:
		return
	target.scrub_to(t)


func _on_key_clicked(index: int) -> void:
	if target == null:
		return
	target.select_keyframe(index)


func _on_timeline_changed() -> void:
	_refresh()


func _refresh() -> void:
	if _track != null:
		if _track.has_method("set_target"):
			_track.set_target(target)
		_track.queue_redraw()
	_update_labels()
	if _play_btn != null:
		_play_btn.text = "Stop" if target != null and target.playing else "Play"


func _update_labels() -> void:
	if _status == null or _time_label == null:
		return
	if target == null:
		_status.text = "No MorphPolygon2D selected"
		_time_label.text = ""
		return

	if target.playing:
		_status.text = "Playing — stop to edit keys"
	elif target.is_editing_keyframe():
		_status.text = "Editing keyframe %d — drag polygon points in the 2D view" % target.selected_keyframe
	else:
		_status.text = "Preview — click a key diamond to edit that pose"

	_time_label.text = "t=%.2f" % target.time
