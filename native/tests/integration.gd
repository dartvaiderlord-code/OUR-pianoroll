extends SceneTree

const App = preload("res://Main.tscn")
const MIDI = preload("res://scripts/midi.gd")
const Synth = preload("res://scripts/synth.gd")
const Text = preload("res://scripts/strings.gd")

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, explanation: String) -> bool:
	if not condition:
		printerr(explanation)
		quit(1)
	return condition

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
	if not expect(Text.label("keysBackground","en")=="Keys & Background","English labels"):
		return
	print("MIDI, truncation guard, seeking, PCM and localization passed.")

	var app = App.instantiate()
	root.add_child(app)
	await process_frame
	if not expect(app.active.size()==2 and app.music.duration>46.0,"App starts with two simultaneous MIDI demo parts"):
		return
	if not check_photo(app):
		return
	if not OS.get_cmdline_user_args().has("--video"):
		quit()
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://native-interface.png")
	if not await check_scroll(app):
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
	for pref in ["ambient","bands","lanes","strikeLine","beams"]:
		app.set_option(pref,false)
	app.set_option("background","black")
	app.set_option("hitStyle","fireworks")
	app.roll.manual_hits.clear()
	app.export_request = {"fps":120.0,"width":640,"height":360,"start":0.0,"end":0.0,"speed":1.0,"volume":.7,"quality":.94,"live":true}
	var live_video = "user://native-live-120fps.mkv"
	app.start_live_export(live_video)
	app.music.pause()
	await create_timer(.10).timeout
	var key: Rect2 = app.roll.keyboard[60]
	app.roll.press_point(7,Vector2(key.get_center().x,key.end.y-3),true)
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
	quit()
