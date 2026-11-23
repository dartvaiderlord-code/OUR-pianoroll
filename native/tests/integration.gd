extends SceneTree

const App = preload("res://Main.tscn")
const MIDI = preload("res://scripts/midi.gd")
const Synth = preload("res://scripts/synth.gd")
const Text = preload("res://scripts/strings.gd")
const Design = preload("res://scripts/design.gd")
const Roll = preload("res://scripts/roll.gd")

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, explanation: String) -> bool:
	if not condition:
		printerr(explanation)
		quit(1)
	return condition

func check_soft_onsets(note: Dictionary) -> bool:
	var synth = Synth.new()
	var bank = synth.instrument(note)
	var offset = 1488
	var original: PackedByteArray = bank.stream.data
	var resumed = synth.stream_from(note,float(offset)/Synth.RATE).data
	if not expect(abs(original.decode_s16(offset*2))>1000 and resumed.decode_s16(0)==0,
			"A late note uses a soft attack even if the original sample starts mid-wave"):
		return false
	var ramp = Synth.ATTACK_FRAMES
	if not expect(resumed.decode_s16(ramp*2)==original.decode_s16((offset+ramp)*2),
			"An attack keeps the original timing and samples after the envelope"):
		return false
	var sustained = note.duplicate()
	sustained.program = 16
	var continued = synth.stream_from(sustained,3.1)
	if not expect(continued.data.decode_s16(0)==0 and continued.loop_begin >= ramp and
			continued.loop_mode==AudioStreamWAV.LOOP_FORWARD,"Seeking into a loop should not repeat the attack"):
		return false
	var pcm = original.slice(offset*2,(offset+2*ramp)*2)
	var faded = Synth.fade_clip_edges(pcm,0,2*ramp,Synth.RATE)
	return expect(faded.decode_s16(0)==0 and faded.decode_s16(faded.size()-2)==0,
		"Exported PCM fades in and out at the clip boundaries")

func capture_audio(capture: AudioEffectCapture, duration: float) -> PackedFloat32Array:
	var samples = PackedFloat32Array()
	var deadline = Time.get_ticks_msec()+roundi(duration*1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(.05).timeout
		var available = capture.get_frames_available()
		if available > 0:
			for frame in capture.get_buffer(available):
				samples.append(frame.x)
	return samples

func audio_peak(samples: PackedFloat32Array) -> float:
	var peak = 0.0
	for sample in samples:
		peak = maxf(peak,absf(sample))
	return peak

func wave_start(samples: PackedFloat32Array) -> int:
	for i in range(samples.size()):
		if absf(samples[i]) > .001:
			return i
	return samples.size()

func onset_difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var start_a = wave_start(a)
	var start_b = wave_start(b)
	var frames = roundi(AudioServer.get_mix_rate()*.08)
	if start_a+frames > a.size() or start_b+frames > b.size():
		return 1.0
	var error = 0.0
	for i in range(frames):
		error = maxf(error,absf(a[start_a+i]-b[start_b+i]))
	return error

func check_dense_chord() -> bool:
	var transport = preload("res://scripts/transport.gd").new()
	var notes = []
	for pitch in range(30,78):
		var note = {"pitch":pitch,"start":0.0,"end":.36,"velocity":1.0,"program":0,"channel":0}
		notes.append(note)
	root.add_child(transport)
	transport.change_volume(1.0)
	var capture = AudioEffectCapture.new()
	capture.buffer_length = .6
	var capture_index = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0,capture)
	await create_timer(.08).timeout
	capture.clear_buffer()
	transport.audition(60,0,true)
	var solo_peak = audio_peak(await capture_audio(capture,.5))
	transport.audition(60,0,false)
	await create_timer(.20).timeout
	capture.clear_buffer()
	transport.replace([MIDI.layer("Chord A",notes,.5),MIDI.layer("Chord B",notes.duplicate(true),.5)])
	var start = Time.get_ticks_usec()
	transport.play()
	var cold_start_ms = (Time.get_ticks_usec()-start)/1000.0
	var cold = await capture_audio(capture,.65)
	var chord_peak = audio_peak(cold)
	transport.pause()
	transport.seek(0)
	var piano_bus = AudioServer.get_bus_index(&"Piano")
	AudioServer.set_bus_bypass_effects(piano_bus,true)
	capture.clear_buffer()
	transport.play()
	var warm = await capture_audio(capture,.65)
	AudioServer.set_bus_bypass_effects(piano_bus,false)
	var difference = onset_difference(cold,warm)
	AudioServer.remove_bus_effect(0,capture_index)
	transport.queue_free()
	await process_frame
	print("Native mixer: play request %.1f ms, peaks %.3f solo / %.3f chord, onset difference %.4f" %
		[cold_start_ms,solo_peak,chord_peak,difference])
	return expect(cold_start_ms < 25.0 and solo_peak>.12 and solo_peak<.25 and chord_peak>.5 and chord_peak<.92 and difference<.02,
		"A cold chord prepares without blocking Play and its attack matches warm playback with the limiter bypassed")

func check_photo(app: Control) -> bool:
	var image = Image.create(9,7,false,Image.FORMAT_RGB8)
	image.fill(Color("#2580d4"))
	var path = "user://gallery-selection-without-extension"
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(image.save_png_to_buffer())
	file.close()
	app.load_background(path)
	DirAccess.remove_absolute(path)
	if not expect(app.settings.background=="custom" and app.custom_background!=null,"Load a photo selected without an extension"):
		return false
	if not expect(app.custom_background.get_image().get_pixel(1,1).is_equal_approx(Color("#2580d4")),"Selected image replaces the piano-roll background"):
		return false
	if not expect(FileAccess.file_exists(app.BACKGROUND_FILE),"Custom photo persists locally"):
		return false
	app.set_option("background","theme",true)
	return true

func check_key_range(app: Control) -> bool:
	app.roll.build_keys()
	var width: float = app.roll.keyboard[60].size.x
	app.settings.range = 0
	app.pitch_field = "keyFrom"
	app.select_range_pitch(60)
	app.visible_key_count.value = 8
	app.roll.build_keys()
	var config = ConfigFile.new()
	if not expect(app.roll.keyboard.size()==8 and app.roll.keyboard.has(67) and not app.roll.keyboard.has(68) and
			app.roll.keyboard[60].size.x>width and app.last_key.text.begins_with("G4") and config.load(app.SETTINGS_FILE)==OK and
			config.get_value("style","keyFrom")==60 and config.get_value("style","keyTo")==67,
			"Eight keys from C4 to G4 widen the lanes and persist both endpoints"):
		return false
	app.select_range_pitch(61)
	app.pitch_field = "keyTo"
	app.select_range_pitch(61)
	app.roll.build_keys()
	var sharp: Rect2 = app.roll.keyboard[61]
	if not expect(app.roll.keyboard.size()==1 and sharp.size.x>0 and sharp.position.x>=0 and
			sharp.end.x<=app.roll.size.x and app.visible_key_count.value==1,
			"A single black key stays inside the roll and the count updates"):
		return false
	app.settings.range = 88
	app.apply_keyboard_range()
	return true

func check_background_cover() -> bool:
	var viewport = SubViewport.new()
	viewport.size = Vector2i(320,240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas = Roll.new()
	canvas.size = Vector2(320,240)
	viewport.add_child(canvas)
	var photo = Image.create(40,80,false,Image.FORMAT_RGB8)
	photo.fill(Color.GREEN)
	photo.fill_rect(Rect2i(15,35,10,10),Color.RED)
	var texture = ImageTexture.create_from_image(photo)
	var appearance = Design.defaults()
	appearance.background = "custom"
	appearance.backgroundShade = 0.0
	appearance.lanes = false
	appearance.bands = false
	appearance.strikeLine = false
	canvas.configure(appearance,[],texture)
	await process_frame
	await RenderingServer.frame_post_draw
	var initial = viewport.get_texture().get_image()
	appearance.range = 0
	appearance.keyFrom = 61
	appearance.keyTo = 68
	canvas.configure(appearance,[],texture)
	await process_frame
	await RenderingServer.frame_post_draw
	var narrowed = viewport.get_texture().get_image()
	var photo_area = Rect2i(0,0,320,int(canvas.impact))
	viewport.queue_free()
	return expect(initial.get_pixel(1,1).g>.9 and initial.get_pixel(318,photo_area.size.y-2).g>.9 and
			initial.get_pixel(124,96).r>.9 and initial.get_pixel(160,60).r>.9 and
			initial.get_pixel(114,96).g>.9 and initial.get_pixel(160,50).g>.9 and
			initial.get_region(photo_area).get_data()==narrowed.get_region(photo_area).get_data(),
			"The centered photo covers the roll with a square marker and is independent of the key range")

func check_note_bottom() -> bool:
	var viewport = SubViewport.new()
	viewport.size = Vector2i(320,240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas = Roll.new()
	canvas.size = Vector2(320,240)
	viewport.add_child(canvas)
	var appearance = Design.defaults()
	appearance.background = "black"
	appearance.noteFill = "solid"
	appearance.noteRoundness = 100.0
	appearance.range = 0
	appearance.keyFrom = 60
	appearance.keyTo = 60
	var notes = [{"pitch":60,"start":1.0,"end":2.0,"velocity":1.0,"channel":0,"program":0}]
	canvas.configure(appearance,[MIDI.layer("Note",notes,2.0,"#ff0000")],null)
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot = viewport.get_texture().get_image()
	var bottom = int(canvas.impact*(1.0-1.0/appearance.horizon))
	var color = snapshot.get_pixel(160,bottom-2)
	viewport.queue_free()
	return expect(color.r>.9 and color.g<.1,"A glowing rounded note has no highlight stripe across its bottom")

func touch_pitch_list(dialog: Window, point: Vector2, pressed: bool) -> void:
	var mouse = InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = point
	mouse.pressed = pressed
	dialog.push_input(mouse,true)
	var touch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = pressed
	dialog.push_input(touch,true)

func check_pitch_swipe(app: Control) -> bool:
	app.settings.range = 0
	app.apply_keyboard_range()
	app.appearance_dialog.popup_centered()
	app.first_key.pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	var picker = app.pitch_picker
	var rect: Rect2 = picker.list.get_global_rect()
	var initial_pitch: int = app.settings.keyFrom
	if not expect(rect.has_point(picker.rows[initial_pitch].get_global_rect().get_center()),
			"The pitch picker opens at the current endpoint"):
		return false
	var initial_scroll: int = picker.list.scroll_vertical
	var origin = rect.position+Vector2(rect.size.x*.5,rect.size.y*.80)
	touch_pitch_list(picker,origin,true)
	var drag = InputEventScreenDrag.new()
	drag.position = origin-Vector2(0,110)
	drag.relative = Vector2(0,-110)
	picker.push_input(drag,true)
	touch_pitch_list(picker,drag.position,false)
	if not expect(picker.list.scroll_vertical>=initial_scroll+100 and picker.visible and app.settings.keyFrom==initial_pitch,
			"Swiping the note rows scrolls the picker without choosing a note"):
		return false
	await process_frame
	for pitch in range(picker.rows.size()):
		var point: Vector2 = picker.rows[pitch].get_global_rect().get_center()
		if pitch != initial_pitch and rect.has_point(point):
			touch_pitch_list(picker,point,true)
			touch_pitch_list(picker,point,false)
			var selected: bool = app.settings.keyFrom==pitch and not picker.visible
			app.last_key.pressed.emit()
			await process_frame
			selected = selected and picker.visible and picker.title==app.label("lastKey") and picker.list.finger==-1
			picker.hide()
			app.appearance_dialog.hide()
			app.settings.range = 88
			app.apply_keyboard_range()
			return expect(selected,"Tapping a note after a swipe applies the range endpoint")
	return expect(false,"The pitch picker has visible rows after a swipe")

func check_scroll(app: Control) -> bool:
	root.content_scale_size = Vector2i(440,760)
	root.size = Vector2i(440,760)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	app.scroller.set_process_input(true)
	app.scroller.scroll_deadzone = 1000000
	var origin = app.roll.get_global_rect().position+Vector2(120,145)
	var touch = InputEventScreenTouch.new()
	touch.index = 2
	touch.position = origin
	touch.pressed = true
	root.push_input(touch,true)
	var drag = InputEventScreenDrag.new()
	drag.index = 2
	drag.position = origin-Vector2(0,118)
	drag.relative = Vector2(0,-118)
	root.push_input(drag,true)
	touch = InputEventScreenTouch.new()
	touch.index = 2
	touch.position = drag.position
	touch.pressed = false
	root.push_input(touch,true)
	if not expect(app.scroller.scroll_vertical >= 100,"A finger drag over the piano roll scrolls the page"):
		return false
	app.scroller.scroll_vertical = 0
	await process_frame
	await RenderingServer.frame_post_draw
	var key: Rect2 = app.roll.keyboard[60]
	touch = InputEventScreenTouch.new()
	touch.index = 3
	touch.position = app.roll.get_global_rect().position+Vector2(key.get_center().x,key.end.y-4)
	touch.pressed = true
	root.push_input(touch,true)
	if not expect(app.roll.held.get(3,-1)==60,"A touch on a key remains a piano input"):
		return false
	touch = touch.duplicate()
	touch.pressed = false
	root.push_input(touch,true)
	return expect(not app.roll.held.has(3) and app.scroller.scroll_vertical==0,"Releasing a key does not scroll")

func run() -> void:
	var midi = PackedByteArray([77,84,104,100,0,0,0,6,0,0,0,1,0,96,77,84,114,107,0,0,0,12,0,144,60,100,96,128,60,0,0,255,47,0])
	var data = MIDI.new().parse(midi)
	if not expect(data.get("notes",[]).size()==1 and is_equal_approx(data.get("duration",0.0),.5),"MIDI format 0 note and tempo"):
		return
	if not expect(MIDI.new().parse(midi.slice(0,21)).has("error"),"Truncated MIDI should fail"):
		return
	var melodic = MIDI.layer("test.mid",data.notes,data.duration)
	if not expect(MIDI.from_time(melodic,.25)==0 and MIDI.from_time(melodic,.5)==1,"Timeline searches"):
		return
	var audio = Synth.new().pcm([melodic],0,1600,0,1,.7)
	var max_value = 0
	for n in range(0,audio.size(),2):
		max_value = maxi(max_value,absi(audio.decode_s16(n)))
	if not expect(max_value>100,"Synth audio should contain an audible signal"):
		return
	if not check_soft_onsets(melodic.notes[0]):
		return
	if not await check_dense_chord():
		return
	if not expect(Text.label("keysBackground","en")=="Keys & Background","English labels"):
		return
	print("MIDI, truncation guard, seeking, PCM and localization passed.")

	var app = App.instantiate()
	root.add_child(app)
	await process_frame
	if not expect(app.active.size()==2 and app.music.duration>46.0,"App starts with two simultaneous MIDI demo parts"):
		return
	app.hit_size_slider.value = 250
	var config = ConfigFile.new()
	if not expect(config.load(app.SETTINGS_FILE)==OK and config.get_value("style","hitSize")==250.0 and
			app.roll.settings.hitSize==250.0,"Effect-size slider updates the roll and persists"):
		return
	app.hit_size_slider.value = 100
	if not check_key_range(app):
		return
	if not check_photo(app):
		return
	if not OS.get_cmdline_user_args().has("--video"):
		app.queue_free()
		await create_timer(.08).timeout
		quit()
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://native-interface.png")
	if not await check_background_cover():
		return
	if not await check_note_bottom():
		return
	if not await check_scroll(app):
		return
	if not await check_pitch_swipe(app):
		return
	print("Custom photo loading and touch scrolling checks passed.")
	app.music.play()
	await create_timer(1.35).timeout
	print("Native displayed frames/second: ", Engine.get_frames_per_second())
	app.music.pause()
	var video = "user://native-fullhd-144fps.mkv"
	app.exporter.render(video,app.settings,app.active,app.custom_background,app.music.synth,
		{"fps":144.0,"width":1920,"height":1080,"start":0.0,"end":.25,"speed":1.0,"volume":.7,"quality":.96})
	var result = await app.exporter.finished
	if not expect(result[0]=="videoSaved", "144 FPS offline export failed: "+str(result)):
		return
	print(ProjectSettings.globalize_path(video))

	app.music.seek(0)
	app.files.clear()
	app.refresh_files()
	for pref in ["ambient","bands","lanes","strikeLine"]:
		app.set_option(pref,false)
	app.set_option("background","black")
	app.set_option("hitStyle","fireworks")
	app.set_option("keyColor","#00ff00")
	for pref in ["beams","keys","ripples","particles"]:
		app.set_option(pref,true)
	app.roll.manual_hits.clear()
	app.export_request = {"fps":120.0,"width":640,"height":360,"start":0.0,"end":0.0,"speed":1.0,"volume":.7,"quality":.94,"live":true}
	var live_video = "user://native-live-120fps.mkv"
	app.start_live_export(live_video)
	app.music.pause()
	app.hit_size_slider.value = 225
	await create_timer(.10).timeout
	var key: Rect2 = app.roll.keyboard[60]
	app.roll.press_point(7,Vector2(key.get_center().x,key.end.y-3),true)
	if not expect(app.live_capture.touches.back()[1].get(7,-1)==60 and
			app.live_capture.scenes.back()[1].hitSize==225.0,"Recording captures the key state and user selection at the event"):
		return
	await create_timer(.27).timeout
	app.roll.press_point(7,Vector2.ZERO,false)
	await create_timer(.18).timeout
	if not expect(app.live_capture.hits.size()==1,"Live capture logs the exact key strike separately from the released key"):
		return
	app.finish_live_export()
	result = await app.exporter.finished
	if not expect(result[0]=="videoSaved","Live keyboard export failed: "+str(result)):
		return
	print(ProjectSettings.globalize_path(live_video))
	var effects = Design.defaults()
	effects.background = "black"
	effects.hitStyle = "fireworks"
	for pref in ["ambient","bands","lanes","strikeLine","beams","keys","glow"]:
		effects[pref] = false
	var stroke = MIDI.layer("effect.mid",[
		{"pitch":60,"start":0.0,"end":.1,"velocity":.85,"program":0,"channel":0}
	],.4,"#00ff00")
	for amount in [50,250]:
		effects.hitSize = float(amount)
		var clip = "user://native-effect-%d.mkv" % amount
		app.exporter.render(clip,effects.duplicate(),[stroke],null,app.music.synth,
			{"fps":120.0,"width":640,"height":360,"start":.28,"end":.29,"speed":1.0,"volume":.7,"quality":.96})
		result = await app.exporter.finished
		if not expect(result[0]=="videoSaved","Export with an explicit effect size: "+str(result)):
			return
		print(ProjectSettings.globalize_path(clip))
	app.queue_free()
	await create_timer(.08).timeout
	quit()
