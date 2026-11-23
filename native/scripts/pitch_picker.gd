extends AcceptDialog

signal pitch_selected(pitch: int)

const Design = preload("res://scripts/design.gd")
const TouchScroll = preload("res://scripts/touch_scroll.gd")

var list: ScrollContainer
var rows: Array[Button] = []

func _ready() -> void:
	list = TouchScroll.new()
	list.touch_enabled = true
	list.touch_tap = choose_from_touch
	list.keeps_touch = func(point):
		var bar = list.get_v_scroll_bar()
		return bar.is_visible_in_tree() and bar.get_global_rect().has_point(point)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.custom_minimum_size = Vector2(230,220)
	list.follow_focus = true
	add_child(list)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",3)
	list.add_child(content)
	for pitch in range(128):
		var row = Button.new()
		row.text = Design.pitch_label(pitch)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size.y = 36
		row.pressed.connect(choose.bind(pitch))
		content.add_child(row)
		rows.append(row)
	visibility_changed.connect(func():
		if not visible:
			list.reset_touch())

func show_pitch(pitch: int) -> void:
	popup_centered_clamped(Vector2i(280,350),.88)
	await get_tree().process_frame
	if visible:
		list.follow_focus = false
		rows[pitch].grab_focus()
		list.ensure_control_visible(rows[pitch])
		list.follow_focus = true

func choose_from_touch(point: Vector2) -> void:
	for pitch in range(rows.size()):
		if rows[pitch].get_global_rect().has_point(point):
			choose(pitch)
			return

func choose(pitch: int) -> void:
	hide()
	pitch_selected.emit(pitch)
