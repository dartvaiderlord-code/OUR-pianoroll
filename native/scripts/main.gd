extends Control

const MIDI = preload("res://scripts/midi.gd")
const Text = preload("res://scripts/strings.gd")
const Design = preload("res://scripts/design.gd")
const Roll = preload("res://scripts/roll.gd")
const Wave = preload("res://scripts/wave.gd")
const Transport = preload("res://scripts/transport.gd")
const Exporter = preload("res://scripts/exporter.gd")
const LiveCapture = preload("res://scripts/live_capture.gd")
const TouchScroll = preload("res://scripts/touch_scroll.gd")
const BackgroundImage = preload("res://scripts/background_image.gd")
const APP_ICON = preload("res://assets/icon.png")
const BACKGROUND_FILE = "user://background.webp"
const SETTINGS_FILE = "user://interface.cfg"
var settings: Dictionary = Design.defaults()
var files: Array = []
var active: Array = []
var limit = 4
var muted_volume = .7
var custom_background: Texture2D
var music: Node
var exporter: Node
var layout: Control
var scroller: ScrollContainer
var shell: VBoxContainer
var roll: Control
var wave: Control
var stage: VBoxContainer
var transport_bar: VBoxContainer
var intro: Control
var side: VBoxContainer
var tracks: VBoxContainer
var count_label: Label
var legend: HBoxContainer
var elapsed: Label
var duration_label: Label
var key_count: Label
var toggle_button: Button
var volume_button: Button
var volume_slider: HSlider
var hit_size_slider: HSlider
var record_button: Button
var full_button: Button
var empty_label: Label
var notice_label: Label
var notice_key = ""
var notice_args = {}
var notices: Array = []
var picker: FileDialog
var effects_dialog: AcceptDialog
var appearance_dialog: AcceptDialog
var key_range_fields: VBoxContainer
var first_key: OptionButton
var last_key: OptionButton
var visible_key_count: SpinBox
var export_dialog: ConfirmationDialog
var export_progress: ConfirmationDialog
var export_bar: ProgressBar
var export_fields = {}
var export_request = {}
var export_mode = "offline"
var live_capture = LiveCapture.new()
var live_path = ""
var settings_visible = true
var immersive = false
var compact = false
var skin: Dictionary
var next_transport_update = 0

func label(key: String, values := {}) -> String:
	return Text.label(key,settings.language,values)

func _ready() -> void:
	read_settings()
	files = MIDI.demo()
	music = Transport.new()
	music.process_priority = -10
	add_child(music)
	exporter = Exporter.new()
	add_child(exporter)
	exporter.progress.connect(export_progress_update)
	exporter.finished.connect(export_done)
	configure_display()
	rebuild()
	get_window().files_dropped.connect(load_files)
	get_window().size_changed.connect(display_changed)
	Engine.max_fps = 0
	if OS.get_name() == "Windows":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	refresh_files()
	if OS.get_cmdline_user_args().has("--smoke"):
		assert(active.size()==2)
		assert(is_equal_approx(music.duration,46.08))
		assert(label("settings")=="Настройки" or label("settings")=="Settings")
		print("OUR-pianoroll app smoke passed")
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--export-smoke"):
		# This path uses the same renderer and muxer as the video dialog.
		exporter.render("user://native-120fps-smoke.mkv",settings,active,custom_background,music.synth,
			{"fps":120.0,"width":640,"height":360,"start":0.0,"end":.5,"speed":1.0,"volume":.7,"quality":.95})

func mobile() -> bool:
	return OS.get_name() == "Android"

func configure_display() -> void:
	var size_data = get_window().size
	var next = size_data.x < size_data.y or (not mobile() and size_data.x < 790)
	compact = next
	if mobile():
		get_window().content_scale_size = Vector2i(440,780) if next else Vector2i(890,500)

func display_changed() -> void:
	var previous = compact
	configure_display()
	if previous != compact and not immersive:
		rebuild()
	elif is_instance_valid(roll):
		roll.custom_minimum_size.y = maxf(260,size.y-95) if immersive else roll_height()

func read_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_FILE)==OK:
		for key in Design.SETTINGS_KEYS:
			var value = config.get_value("style",key,settings[key])
			if typeof(value) == typeof(settings[key]):
				settings[key] = value
		limit = clampi(config.get_value("session","limit",4),1,16)
	if FileAccess.file_exists(BACKGROUND_FILE):
		var image = Image.load_from_file(BACKGROUND_FILE)
		if image and not image.is_empty():
			custom_background = ImageTexture.create_from_image(image)
	if not custom_background and settings.background == "custom":
		settings.background = "theme"
	settings.hitSize = clampf(settings.hitSize,Design.MIN_HIT_SIZE,Design.MAX_HIT_SIZE)
	if settings.range not in [0,88,128]:
		settings.range = 88
	settings.keyFrom = clampi(settings.keyFrom,0,127)
	settings.keyTo = clampi(settings.keyTo,settings.keyFrom,127)

func save_settings() -> void:
	var config = ConfigFile.new()
	for key in Design.SETTINGS_KEYS:
		config.set_value("style",key,settings[key])
	config.set_value("session","limit",limit)
	config.save(SETTINGS_FILE)

func box_style(color: String, border: String, radius := 8, pad := 7) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color(color)
	box.border_color = Color(border)
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad*.65
	box.content_margin_bottom = pad*.65
	return box

func theme_style() -> Theme:
	var theme_data = Theme.new()
	theme_data.default_font_size = 15 if compact else 16
	var text_color = Color(skin.text)
	for type in ["Button","OptionButton","CheckButton","CheckBox","ColorPickerButton","LineEdit","SpinBox"]:
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			theme_data.set_color(key,type,text_color)
	for type in ["Button","OptionButton","ColorPickerButton"]:
		theme_data.set_stylebox("normal",type,box_style(skin.field,skin.line))
		theme_data.set_stylebox("hover",type,box_style(skin.line,skin.fill))
		theme_data.set_stylebox("pressed",type,box_style(skin.line,skin.accent))
		theme_data.set_stylebox("disabled",type,box_style(skin.panel,skin.line))
	theme_data.set_stylebox("normal","LineEdit",box_style(skin.field,skin.line))
	theme_data.set_stylebox("panel","PopupMenu",box_style(skin.panel,skin.line))
	theme_data.set_color("font_color","PopupMenu",text_color)
	theme_data.set_stylebox("hover","PopupMenu",box_style(skin.field,skin.line))
	theme_data.set_stylebox("panel","AcceptDialog",box_style(skin.panel,skin.line,12,15))
	theme_data.set_stylebox("embedded_border","Window",box_style(skin.panel,skin.line,9,8))
	theme_data.set_color("title_color","Window",text_color)
	theme_data.set_color("font_color","Label",text_color)
	return theme_data

func spacing(parent: Node, horizontal: bool, amount := 8):
	var row = HBoxContainer.new() if horizontal else VBoxContainer.new()
	row.add_theme_constant_override("separation",amount)
	parent.add_child(row)
	return row

func panel(parent: Node, tint: String, border: String, padding := 9) -> PanelContainer:
	var pane = PanelContainer.new()
	pane.add_theme_stylebox_override("panel",box_style(tint,border,9,padding))
	parent.add_child(pane)
	return pane

func title_at(parent: Node, text: String, font := 15, dim := false) -> Label:
	var field = Label.new()
	field.text = text
	field.add_theme_font_size_override("font_size",font)
	if dim:
		field.add_theme_color_override("font_color",Color(skin.sub))
	parent.add_child(field)
	return field

func spring(parent: Node) -> void:
	var control = Control.new()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(control)

func button(parent: Node, text: String, action: Callable, primary := false) -> Button:
	var control = Button.new()
	control.text = text
	control.custom_minimum_size.y = 36 if mobile() else 32
	if primary:
		control.add_theme_stylebox_override("normal",box_style(skin.fill,skin.accent))
		control.add_theme_stylebox_override("hover",box_style(skin.accent,skin.gold))
		control.add_theme_color_override("font_color",Color(skin.base))
		control.add_theme_color_override("font_hover_color",Color(skin.base))
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func option(parent: Node, choices: Dictionary, current, update: Callable) -> OptionButton:
	var control = OptionButton.new()
	if mobile():
		control.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	var keys = choices.keys()
	for key in keys:
		control.add_item(choices[key])
	control.select(maxi(0,keys.find(current)))
	control.item_selected.connect(func(index): update.call(keys[index]))
	parent.add_child(control)
	return control

func localized_choices(keys: Dictionary) -> Dictionary:
	var choices = {}
	for key in keys:
		choices[key] = label(keys[key])
	return choices

func rebuild() -> void:
	var last_scroll = scroller.scroll_vertical if is_instance_valid(scroller) else 0
	if is_instance_valid(roll):
		roll.release_touches()
	if layout:
		remove_child(layout)
		layout.queue_free()
	skin = Design.theme_colors(settings)
	theme = theme_style()
	layout = Control.new()
	layout.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(layout)
	var backdrop = ColorRect.new()
	backdrop.color = Color(skin.base)
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	layout.add_child(backdrop)
	scroller = TouchScroll.new()
	scroller.touch_enabled = mobile()
	scroller.keeps_touch = keep_touch_for_control
	scroller.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroller)
	shell = spacing(scroller,false,11)
	shell.size_flags_horizontal = SIZE_EXPAND_FILL

	var margin = MarginContainer.new()
	for edge in ["left","right"]:
		margin.add_theme_constant_override("margin_"+edge,12 if compact else 28)
	margin.add_theme_constant_override("margin_top",12 if compact else 20)
	shell.add_child(margin)
	var content = spacing(margin,false,12)
	var heading = spacing(content,not compact,8)
	intro = heading
	var brand = spacing(heading,true,10)
	brand.size_flags_horizontal = SIZE_EXPAND_FILL
	var icon = TextureRect.new()
	icon.texture = APP_ICON
	icon.custom_minimum_size = Vector2(43,43) if compact else Vector2(50,50)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	brand.add_child(icon)
	title_at(brand,"OUR-pianoroll",27 if compact else 35)
	var commands = spacing(heading,true,7)
	commands.size_flags_vertical = Control.SIZE_SHRINK_END
	option(commands,{"ru":"Русский","en":"English"},settings.language,func(value): set_option("language",value,true))
	option(commands,{"classic":label("classicTheme"),"soviet":label("sovietTheme")},settings.theme,func(value): set_option("theme",value,true))
	button(commands,label("settings"),toggle_settings)

	var bench = spacing(content,not compact,12)
	var workspace = spacing(bench,false,9)
	workspace.size_flags_horizontal = SIZE_EXPAND_FILL
	stage = spacing(panel(workspace,skin.panel,skin.line,7),false,5)
	var stage_top = spacing(stage,true,6)
	title_at(stage_top,label("pianoRoll"),17)
	spring(stage_top)
	legend = spacing(stage_top,true,5)
	if compact:
		legend.hide()
	key_count = title_at(stage_top,keyboard_count_label(),12,true)
	record_button = button(stage_top,label("stop" if live_capture.active else "video"),show_export)
	record_button.tooltip_text = label("stopRecording" if live_capture.active else "exportVideo")
	full_button = button(stage_top,"⛶",toggle_fullscreen)
	full_button.tooltip_text = label("fullscreen")
	roll = Roll.new()
	roll.custom_minimum_size = Vector2(0,roll_height())
	roll.size_flags_vertical = SIZE_EXPAND_FILL
	roll.audition.connect(on_audition)
	var roll_frame = MarginContainer.new()
	roll_frame.clip_contents = true
	roll_frame.size_flags_vertical = SIZE_EXPAND_FILL
	stage.add_child(roll_frame)
	roll_frame.add_child(roll)
	empty_label = title_at(roll,"",14,true)
	empty_label.mouse_filter = MOUSE_FILTER_IGNORE
	empty_label.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	empty_label.grow_horizontal = GROW_DIRECTION_BOTH
	empty_label.position.y = 38
	build_transport(workspace)
	build_side(bench)
	notice_label = title_at(content,"",14,true)
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var footer = spacing(content,true,6)
	title_at(footer,label("localFiles"),12,true)
	spring(footer)
	button(footer,label("downloadHtml"),pick_html)
	if not compact:
		title_at(footer,label("space")+"   "+label("playPause")+"   ← → "+label("seek"),12,true)
	build_dialogs()
	apply_roll(true)
	refresh_track_content()
	show_notice()
	show_state()
	if last_scroll > 0:
		scroller.set_deferred("scroll_vertical",last_scroll)
	if immersive:
		apply_immersive()

func keep_touch_for_control(point: Vector2) -> bool:
	for popup in [effects_dialog,appearance_dialog,export_dialog,export_progress,picker]:
		if is_instance_valid(popup) and popup.visible:
			return true
	if is_instance_valid(roll) and roll.get_global_rect().has_point(point) and point.y >= roll.get_global_rect().position.y + roll.impact:
		return true
	for control in [wave,volume_slider,hit_size_slider]:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return true
	var bar = scroller.get_v_scroll_bar()
	return bar.is_visible_in_tree() and bar.get_global_rect().has_point(point)

func build_transport(parent: Node) -> void:
	transport_bar = spacing(panel(parent,skin.panel,skin.line,7),false,4)
	wave = Wave.new()
	wave.min_value = 0
	wave.max_value = 1
	wave.step = 0.00001
	wave.custom_minimum_size = Vector2(0,35)
	var none = StyleBoxEmpty.new()
	for key in ["slider","grabber_area","grabber_area_highlight"]:
		wave.add_theme_stylebox_override(key,none)
	wave.value_changed.connect(func(value):
		music.seek(value*music.duration)
		show_state()
	)
	transport_bar.add_child(wave)
	var times = spacing(transport_bar,true,3)
	elapsed = title_at(times,"00:00",12,true)
	spring(times)
	duration_label = title_at(times,"00:00",12,true)
	var row = spacing(transport_bar,true,6)
	button(row,"↤",func(): music.seek(0)).tooltip_text = label("restart")
	toggle_button = button(row,"▶︎",music.toggle,true)
	var loop = button(row,"↻",func(): music.loop = not music.loop)
	loop.toggle_mode = true
	loop.set_pressed_no_signal(music.loop)
	loop.tooltip_text = label("repeat")
	spring(row)
	volume_button = button(row,"♪",toggle_mute)
	var volume = HSlider.new()
	volume_slider = volume
	volume.custom_minimum_size.x = 58 if compact else 86
	volume.min_value = 0
	volume.max_value = 1
	volume.step = .01
	volume.value = music.volume
	volume.tooltip_text = label("volume")
	volume.value_changed.connect(func(value):
		music.change_volume(value)
		show_state()
	)
	row.add_child(volume)
	option(row,{.5:label("speedHalf"),.75:label("speedThreeQuarter"),1.0:"1×",1.25:label("speedOneQuarter"),1.5:label("speedOneHalf"),2.0:"2×"},music.speed,music.change_speed).tooltip_text = label("speed")

func build_side(parent: Node) -> void:
	var pane = panel(parent,skin.panel,skin.line,11)
	if not compact:
		pane.custom_minimum_size.x = 282
	side = spacing(pane,false,8)
	pane.visible = settings_visible and not immersive
	var top = spacing(side,true)
	title_at(top,label("settings"),17)
	spring(top)
	button(top,"×",toggle_settings).tooltip_text = label("closeSettings")
	side.add_child(HSeparator.new())
	var row = spacing(side,true)
	title_at(row,label("midiLayers"),15)
	spring(row)
	count_label = title_at(row,"0 / 4",13,true)
	var limits = spacing(side,true,4)
	title_at(limits,label("simultaneous"),13,true)
	spring(limits)
	number(limits,limit,1,16,1,func(value): set_limit(int(value)))
	var listing = ScrollContainer.new()
	if mobile():
		listing.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		listing.custom_minimum_size.y = 100
	listing.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(listing)
	tracks = spacing(listing,false,5)
	tracks.size_flags_horizontal = SIZE_EXPAND_FILL
	var file_actions = spacing(side,true,5)
	button(file_actions,label("addMidi"),pick_midi,true).size_flags_horizontal = SIZE_EXPAND_FILL
	button(file_actions,label("demo"),use_demo)
	side.add_child(HSeparator.new())
	title_at(side,label("visualEffects"),15)
	var colors = spacing(side,true,5)
	color_control(colors,"noteColor",Design.track_color(settings,{"color":"","demo":""}),func(value): set_option("noteColor",value))
	color_control(colors,"keyColor",Design.key_color(settings),func(value): set_option("keyColor",value))
	var effects_keys = {"glow":"neonNotes","keys":"keyGlow","particles":"particles","beams":"lightColumns"}
	for key in effects_keys:
		check(side,effects_keys[key],key)
	option(labeled(side,"keyHitEffect"),localized_choices(Design.HIT_STYLES),settings.hitStyle,func(value): set_option("hitStyle",value))
	var hit_size_row = spacing(side,true,6)
	title_at(hit_size_row,label("hitSize"),13)
	hit_size_slider = HSlider.new()
	hit_size_slider.min_value = Design.MIN_HIT_SIZE
	hit_size_slider.max_value = Design.MAX_HIT_SIZE
	hit_size_slider.step = 5.0
	hit_size_slider.value = settings.hitSize
	hit_size_slider.custom_minimum_size.x = 68
	hit_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hit_size_slider.tooltip_text = label("hitSize")
	hit_size_row.add_child(hit_size_slider)
	var hit_percent = title_at(hit_size_row,"%d%%" % roundi(settings.hitSize),12,true)
	hit_percent.custom_minimum_size.x = 36
	hit_size_slider.value_changed.connect(func(value):
		hit_percent.text = "%d%%" % roundi(value)
		set_option("hitSize",value)
	)
	var actions = spacing(side,true,5)
	button(actions,label("keysBackground"),func(): appearance_dialog.popup_centered_clamped(Vector2i(445,0),.92))
	button(actions,label("moreEffects"),func(): effects_dialog.popup_centered_clamped(Vector2i(420,0),.92))

func number(parent: Node, value: float, low: float, high: float, step_data: float, on_change: Callable) -> SpinBox:
	var field = SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = step_data
	field.value = value
	field.value_changed.connect(on_change)
	parent.add_child(field)
	return field

func check(parent: Node, label_key: String, pref: String) -> void:
	var box = CheckButton.new()
	box.text = label(label_key)
	box.button_pressed = settings[pref]
	box.toggled.connect(func(value): set_option(pref,value))
	parent.add_child(box)

func color_control(parent: Node, key: String, color: Color, change: Callable) -> void:
	var row = spacing(parent,true,4)
	if not key.is_empty():
		title_at(row,label(key),12,true)
	var box = ColorPickerButton.new()
	if mobile():
		box.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	box.color = color
	box.edit_alpha = false
	box.custom_minimum_size = Vector2(25,25)
	box.color_changed.connect(func(value): change.call("#"+value.to_html(false)))
	row.add_child(box)

func labeled(parent: Node, key: String) -> HBoxContainer:
	var row = spacing(parent,true,8)
	title_at(row,label(key),14)
	spring(row)
	return row

func dialog(key: String) -> AcceptDialog:
	var popup = AcceptDialog.new()
	popup.title = label(key)
	popup.ok_button_text = label("close")
	layout.add_child(popup)
	return popup

func build_dialogs() -> void:
	effects_dialog = dialog("extraEffects")
	var effects = spacing(effects_dialog,false,5)
	var checks = {"ambient":"ambient","ripples":"strikeRipples","bands":"horizontalBands","lanes":"verticalLanes","strikeLine":"strikeLine","layerKeys":"layerKeyColors"}
	for key in checks:
		check(effects,checks[key],key)
	option(labeled(effects,"noteFill"),localized_choices(Design.FILLS),settings.noteFill,func(value): set_option("noteFill",value))
	number(labeled(effects,"noteRoundness"),settings.noteRoundness,0,100,1,func(value): set_option("noteRoundness",value)).suffix = "%"
	option(labeled(effects,"noteHorizon"),{2.5:label("shortHorizon"),4.5:label("normalHorizon"),7.0:label("longHorizon")},settings.horizon,func(value): set_option("horizon",value))
	button(effects,label("resetAppearance"),reset_appearance)

	appearance_dialog = dialog("keysBackground")
	var appearance = spacing(appearance_dialog,false,8)
	option(labeled(appearance,"keyStyle"),localized_choices(Design.KEY_STYLES),settings.keyStyle,func(value): set_option("keyStyle",value))
	option(labeled(appearance,"keyRange"),{88:label("standardKeys"),128:label("fullKeys"),0:label("customKeyRange")},settings.range,
		func(value):
			settings.range = value
			apply_keyboard_range())
	key_range_fields = spacing(appearance,false,5)
	var pitches = {}
	for pitch in range(128):
		pitches[pitch] = Design.pitch_label(pitch)
	first_key = option(labeled(key_range_fields,"firstKey"),pitches,settings.keyFrom,func(value):
		settings.keyFrom = value
		settings.keyTo = maxi(settings.keyTo,value)
		apply_keyboard_range())
	last_key = option(labeled(key_range_fields,"lastKey"),pitches,settings.keyTo,func(value):
		settings.keyTo = value
		settings.keyFrom = mini(settings.keyFrom,value)
		apply_keyboard_range())
	visible_key_count = number(labeled(key_range_fields,"keyQuantity"),settings.keyTo-settings.keyFrom+1,1,128,1,func(value):
		var count = int(value)
		settings.keyFrom = mini(settings.keyFrom,128-count)
		settings.keyTo = settings.keyFrom+count-1
		apply_keyboard_range())
	key_range_fields.visible = settings.range == 0
	var choices = localized_choices(Design.BACKGROUNDS)
	if not custom_background:
		choices.erase("custom")
	option(labeled(appearance,"rollBackground"),choices,settings.background,func(value): set_option("background",value))
	button(appearance,label("uploadImage"),pick_background)
	number(labeled(appearance,"backgroundShade"),settings.backgroundShade,0,85,1,func(value): set_option("backgroundShade",value)).suffix = "%"

	export_dialog = ConfirmationDialog.new()
	export_dialog.title = label("exportVideo")
	export_dialog.ok_button_text = label("exportStart")
	export_dialog.cancel_button_text = label("cancel")
	export_dialog.confirmed.connect(prepare_export)
	layout.add_child(export_dialog)
	var video = spacing(export_dialog,false,5)
	title_at(video,label("codecDescription"),13,true)
	option(labeled(video,"exportMode"),{"offline":label("recordingMode"),"live":label("liveRecording")},export_mode,func(value):
		export_mode = value
		for key in ["start","end"]:
			export_fields[key].get_parent().visible = value=="offline"
	)
	var hint = title_at(video,label("videoHelp"),13,true)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 280
	export_fields.clear()
	for item in [
		["width","videoWidth","1920"],["height","videoHeight","1080"],["fps","videoFps","120"],
		["quality","videoQuality","96"],["start","videoStart","0"],["end","videoEnd","0"]
	]:
		var input = LineEdit.new()
		input.text = item[2]
		input.custom_minimum_size.x = 100
		labeled(video,item[1]).add_child(input)
		export_fields[item[0]] = input
		if item[0] in ["start","end"]:
			input.get_parent().visible = export_mode=="offline"

	export_progress = ConfirmationDialog.new()
	export_progress.title = label("exporting")
	export_progress.get_ok_button().hide()
	export_progress.cancel_button_text = label("exportCancel")
	export_progress.canceled.connect(exporter.cancel)
	layout.add_child(export_progress)
	export_bar = ProgressBar.new()
	export_bar.custom_minimum_size.x = 260
	export_progress.add_child(export_bar)

func set_option(key: String, value, full := false) -> void:
	settings[key] = value
	save_settings()
	if full:
		rebuild()
	else:
		apply_roll(key=="noteColor")
		if key=="noteColor":
			refresh_track_content()

func keyboard_count_label() -> String:
	if settings.range != 0:
		return label("fullKeys" if settings.range == 128 else "standardKeys")
	var pitches = Design.keyboard_range(settings)
	return label("customKeyCount",{"count":pitches.y-pitches.x+1})

func apply_keyboard_range() -> void:
	key_range_fields.visible = settings.range == 0
	first_key.select(settings.keyFrom)
	last_key.select(settings.keyTo)
	visible_key_count.set_value_no_signal(settings.keyTo-settings.keyFrom+1)
	roll.release_touches()
	save_settings()
	apply_roll()

func reset_appearance() -> void:
	var saved_language = settings.language
	var saved_theme = settings.theme
	settings = Design.defaults()
	settings.language = saved_language
	settings.theme = saved_theme
	save_settings()
	rebuild()

func apply_roll(refresh_wave := false) -> void:
	if roll and is_instance_valid(roll):
		roll.configure(settings,active,custom_background)
		key_count.text = keyboard_count_label()
		if refresh_wave:
			wave.configure(active,music.duration,settings)
		if live_capture.active:
			live_capture.add_scene(settings,active,custom_background)

func toggle_settings() -> void:
	settings_visible = not settings_visible
	side.get_parent().visible = settings_visible and not immersive

func track_name(track: Dictionary) -> String:
	return track.name if track.demo.is_empty() else label(track.demo)

func refresh_track_content() -> void:
	for child in tracks.get_children():
		tracks.remove_child(child)
		child.queue_free()
	count_label.text = "%d / %d" % [active.size(),limit]
	var active_indexes = []
	for index in range(files.size()):
		var track = files[index]
		var inside = track.enabled and active_indexes.size()<limit
		if inside:
			active_indexes.append(index)
		var row = spacing(panel(tracks,skin.field,skin.line,4),true,3)
		var tone = Design.track_color(settings,track)
		var marker = title_at(row,"♪",16)
		marker.modulate = tone
		var details = spacing(row,false,0)
		details.size_flags_horizontal = SIZE_EXPAND_FILL
		var name = title_at(details,track_name(track),13)
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.tooltip_text = track_name(track)
		var status = "layerDisabled" if not track.enabled else "layerOverLimit" if not inside else "demo" if not track.demo.is_empty() else ""
		title_at(details,(label(status)+" · " if not status.is_empty() else "")+clock(track.duration),11,true)
		var color_choice = ColorPickerButton.new()
		if mobile():
			color_choice.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		color_choice.edit_alpha = false
		color_choice.color = tone
		color_choice.custom_minimum_size = Vector2(23,23)
		color_choice.tooltip_text = label("layerColor")
		color_choice.color_changed.connect(func(value):
			track.color = "#"+value.to_html(false)
			apply_roll(true)
			refresh_legend()
		)
		row.add_child(color_choice)
		button(row,"◉",func(): show_note_colors(track)).tooltip_text = label("noteColors")
		button(row,"♪" if track.enabled else "−",func():
			track.enabled = not track.enabled
			refresh_files()
		).tooltip_text = label("toggleLayer")
		button(row,"×",func():
			files.remove_at(index)
			refresh_files()
		).tooltip_text = label("removeLayer",{"name":track_name(track)})
	refresh_legend()

func refresh_legend() -> void:
	for child in legend.get_children():
		legend.remove_child(child)
		child.queue_free()
	for index in range(mini(active.size(),3)):
		var track = active[index]
		var item = title_at(legend,"● "+track_name(track).get_basename().left(15),11,true)
		item.modulate = Design.track_color(settings,track).lightened(.3)

func show_note_colors(track: Dictionary) -> void:
	var popup = dialog("noteColors")
	var items = spacing(popup,false,6)
	title_at(items,track_name(track),14,true)
	option(labeled(items,"noteColorMode"),localized_choices(Design.NOTE_MODES),track.mode,func(value):
		track.mode = value
		apply_roll(true)
	)
	popup.close_requested.connect(popup.queue_free)
	popup.confirmed.connect(popup.queue_free)
	popup.popup_centered_clamped(Vector2i(320,0),.90)

func refresh_files() -> void:
	active.clear()
	for track in files:
		if track.enabled and active.size()<limit:
			active.append(track)
	music.replace(active.duplicate())
	apply_roll(true)
	refresh_track_content()
	show_state()

func set_limit(value: int) -> void:
	limit = value
	save_settings()
	refresh_files()

func use_demo() -> void:
	if not files.is_empty() and not files[0].demo.is_empty():
		music.seek(0)
	else:
		music.pause()
		files = MIDI.demo()
		refresh_files()
		music.seek(0)
	notices.clear()
	notice_key = ""
	show_notice()
	music.play()

func select_path(title: String, mode: FileDialog.FileMode, filters_data: PackedStringArray) -> FileDialog:
	if is_instance_valid(picker):
		picker.queue_free()
	picker = FileDialog.new()
	picker.title = title
	picker.use_native_dialog = true
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = mode
	picker.filters = filters_data
	layout.add_child(picker)
	return picker

func pick_midi() -> void:
	var dialog_midi = select_path(label("loadMidi"),FileDialog.FILE_MODE_OPEN_FILES,["*.mid,*.midi,*.smf ; MIDI"])
	dialog_midi.files_selected.connect(load_files)
	dialog_midi.popup_centered_ratio(.8)

func load_files(paths: PackedStringArray) -> void:
	notices.clear()
	notice_key = ""
	var imported = []
	var new_files = []
	for track in files:
		if track.demo.is_empty():
			new_files.append(track)
	for path in paths:
		if new_files.size()+imported.size()>=16:
			notices.append(["midiFileLimit",{}])
			break
		var file = FileAccess.open(path,FileAccess.READ)
		var midi_name = path.get_file().uri_decode().get_file()
		if not file:
			notices.append(["fileError",{"name":midi_name,"errorKey":"midiReadFailed"}])
			continue
		if file.get_length()>16*1024*1024:
			notices.append(["fileError",{"name":midi_name,"errorKey":"midiTooLarge"}])
			continue
		var parsed = MIDI.new().parse(file.get_buffer(file.get_length()))
		if parsed.has("error"):
			notices.append(["fileError",{"name":midi_name,"errorKey":parsed.error}])
		else:
			imported.append([midi_name,parsed])
	if not imported.is_empty():
		var palette = MIDI.COLORS.duplicate()
		if settings.theme=="soviet":
			palette = ["#ff685d","#ffc86f","#ff86a5","#e8ac76"] + palette.slice(2)
		for item in imported:
			var color_scheme = "" if new_files.is_empty() else palette[new_files.size()%palette.size()]
			new_files.append(MIDI.layer(item[0],item[1].notes,item[1].duration,color_scheme))
		if not files.is_empty() and not files[0].demo.is_empty():
			music.pause()
			music.seek(0)
		files = new_files
		refresh_files()
	show_notice()

func pick_background() -> void:
	var formats = ["*.jpg,*.jpeg,*.png,*.webp,*.bmp ; Image"]
	if mobile():
		formats = ["*.jpg,*.jpeg,*.png,*.webp,*.bmp,*.heic,*.heif,*.avif,*.gif ; Image ; image/*"]
	var picker_image = select_path(label("uploadImage"),FileDialog.FILE_MODE_OPEN_FILE,formats)
	picker_image.file_selected.connect(load_background)
	picker_image.popup_centered_ratio(.8)

func load_background(path: String) -> void:
	var image = BackgroundImage.load_selected(path)
	if not image or image.is_empty():
		set_notice("imageOpenFailed")
		return
	custom_background = ImageTexture.create_from_image(image)
	var saved = image.save_webp(BACKGROUND_FILE,false,.87)
	set_option("background","custom",true)
	set_notice("" if saved == OK else "imageSessionOnly")

func pick_html() -> void:
	var save = select_path(label("downloadHtml"),FileDialog.FILE_MODE_SAVE_FILE,["*.html ; HTML"])
	save.current_file = "our-pianoroll.html"
	save.file_selected.connect(func(path):
		var output = FileAccess.open(path,FileAccess.WRITE)
		if output:
			output.store_buffer(FileAccess.get_file_as_bytes("res://assets/our-pianoroll.html"))
	)
	save.popup_centered_ratio(.8)

func set_notice(key: String, values := {}) -> void:
	notice_key = key
	notice_args = values
	show_notice()

func show_notice() -> void:
	var parts = []
	if not notice_key.is_empty():
		parts.append(label(notice_key,notice_args))
	for item in notices:
		var args = item[1].duplicate()
		if args.has("errorKey"):
			args.error = label(args.errorKey)
		parts.append(label(item[0],args))
	notice_label.text = " · ".join(parts)
	notice_label.visible = not parts.is_empty()

func toggle_mute() -> void:
	if music.volume > 0:
		muted_volume = music.volume
		music.change_volume(0)
	else:
		music.change_volume(muted_volume)
	show_state()

func clock(seconds: float) -> String:
	var value = floori(seconds+.00001)
	return "%d:%02d:%02d" % [value/3600,value/60%60,value%60] if value>=3600 else "%02d:%02d" % [value/60,value%60]

func show_state() -> void:
	if not is_instance_valid(roll):
		return
	toggle_button.text = "Ⅱ" if music.playing else "▶︎"
	toggle_button.tooltip_text = label("pause" if music.playing else "play")
	toggle_button.disabled = active.is_empty()
	volume_button.text = "♪" if music.volume>0 else "×"
	volume_button.tooltip_text = label("mute" if music.volume>0 else "unmute")
	volume_slider.set_value_no_signal(music.volume)
	var progress = music.position/music.duration if music.duration>0 else 0.0
	wave.set_value_no_signal(progress)
	wave.queue_redraw()
	elapsed.text = clock(music.position)
	duration_label.text = clock(music.duration)
	roll.present(music.position)
	empty_label.visible = active.is_empty()
	empty_label.text = label("emptyRoll" if files.is_empty() else "layersDisabled")

func roll_height() -> float:
	return clampf(size.y*.46,240,410) if compact else clampf(size.y*.52,365,587)

func apply_immersive() -> void:
	intro.visible = not immersive
	side.get_parent().visible = settings_visible and not immersive
	transport_bar.get_parent().visible = not immersive
	roll.custom_minimum_size.y = maxf(260,size.y-95) if immersive else roll_height()
	full_button.tooltip_text = label("exitFullscreen" if immersive else "fullscreen")

func toggle_fullscreen() -> void:
	immersive = not immersive
	if not mobile():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if immersive else DisplayServer.WINDOW_MODE_WINDOWED)
	apply_immersive()

func show_export() -> void:
	if live_capture.active:
		finish_live_export()
		return
	if exporter.running:
		return
	export_fields.start.text = str(maxf(0,minf(music.position,music.duration-.001)))
	export_fields.end.text = str(music.duration)
	export_dialog.popup_centered_clamped(Vector2i(365,0),.9)

func prepare_export() -> void:
	var values = {}
	for key in export_fields:
		var input = export_fields[key].text.replace(",",".")
		if not input.is_valid_float() or not is_finite(input.to_float()):
			set_notice("exportInvalid")
			return
		values[key] = input.to_float()
	var bad_range = export_mode=="offline" and (values.start<0 or values.end>music.duration+.00001 or values.end<=values.start)
	if values.width<128 or values.height<128 or values.width>8192 or values.height>8192 or values.fps<1 or values.quality<1 or values.quality>100 or bad_range:
		set_notice("exportInvalid")
		return
	values.width = roundi(values.width)
	values.height = roundi(values.height)
	values.quality /= 100.0
	values.speed = music.speed
	values.volume = music.volume
	values.live = export_mode=="live"
	export_request = values
	var location = select_path(label("exportVideo"),FileDialog.FILE_MODE_SAVE_FILE,["*.mkv ; Matroska"])
	location.current_file = "our-pianoroll.mkv"
	location.file_selected.connect(start_export)
	location.popup_centered_ratio(.8)

func start_export(path: String) -> void:
	if export_request.live:
		start_live_export(path)
		return
	render_export(path,export_request)

func render_export(path: String, options: Dictionary) -> void:
	music.pause()
	export_bar.value = 0
	export_bar.max_value = 1
	export_progress.popup_centered_clamped(Vector2i(315,0),.87)
	exporter.render(path,settings.duplicate(),active.duplicate(),custom_background,music.synth,options)

func start_live_export(path: String) -> void:
	live_capture = LiveCapture.new()
	if not live_capture.start():
		set_notice("recordingStartFailed")
		return
	live_path = path
	live_capture.add_scene(settings,active,custom_background)
	var start = live_capture.start_ticks/1000000.0
	for hit in roll.manual_hits:
		var relative = hit.x-start
		if relative > -Roll.HIT_LIFETIME:
			live_capture.hits.append(Vector2(relative,hit.y))
	live_capture.add_frame(music.position,roll.held)
	record_button.text = label("stop")
	record_button.tooltip_text = label("stopRecording")
	if not active.is_empty():
		music.play()

func on_audition(pitch: int, pointer: int, pressed: bool) -> void:
	if live_capture.active:
		var at = live_capture.elapsed()
		live_capture.add_touch(roll.held,at)
		if pressed:
			live_capture.add_hit(pitch,at)
	music.audition(pitch,pointer,pressed)

func finish_live_export() -> void:
	live_capture.add_frame(music.position,roll.held)
	var captured = live_capture.finish()
	var options = export_request.duplicate()
	options.capture = captured
	record_button.text = label("video")
	record_button.tooltip_text = label("exportVideo")
	render_export(live_path,options)

func export_progress_update(completed: int, total: int) -> void:
	export_bar.max_value = total
	export_bar.value = completed

func export_done(status: String, path: String) -> void:
	export_progress.hide()
	set_notice(status,{"path":path})
	if OS.get_cmdline_user_args().has("--export-smoke"):
		print(status+" "+ProjectSettings.globalize_path(path))
		get_tree().quit(0 if status=="videoSaved" else 1)

func _process(_delta: float) -> void:
	if not music or not is_instance_valid(roll):
		return
	if music.playing:
		roll.present(music.position)
		var tick = Time.get_ticks_msec()
		if tick >= next_transport_update:
			next_transport_update = tick + 25
			show_state()
	elif roll.playback_time != music.position or toggle_button.text == "Ⅱ":
		show_state()
	elif not roll.manual_hits.is_empty():
		roll.present(music.position)
	if live_capture.active:
		live_capture.add_frame(music.position,roll.held)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.is_echo():
		return
	match event.keycode:
		KEY_SPACE: music.toggle()
		KEY_LEFT: music.seek(music.position-5)
		KEY_RIGHT: music.seek(music.position+5)
		KEY_ESCAPE:
			if immersive:
				toggle_fullscreen()
