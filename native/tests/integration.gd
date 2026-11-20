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
	if not OS.get_cmdline_user_args().has("--video"):
		quit()
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://native-interface.png")
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
	app.export_request = {"fps":120.0,"width":640,"height":360,"start":0.0,"end":0.0,"speed":1.0,"volume":.7,"quality":.94,"live":true}
	var live_video = "user://native-live-120fps.mkv"
	app.start_live_export(live_video)
	app.music.pause()
	var key: Rect2 = app.roll.keyboard[60]
	app.roll.press_point(7,Vector2(key.get_center().x,key.end.y-3),true)
	await create_timer(.30).timeout
	app.roll.press_point(7,Vector2.ZERO,false)
	app.finish_live_export()
	result = await app.exporter.finished
	if not expect(result[0]=="videoSaved","Live keyboard export failed: "+str(result)):
		return
	print(ProjectSettings.globalize_path(live_video))
	quit()
