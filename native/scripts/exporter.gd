extends Node

signal progress(completed: int, total: int)
signal finished(status: String, path: String)
const Roll = preload("res://scripts/roll.gd")
const Writer = preload("res://scripts/matroska.gd")
const Synth = preload("res://scripts/synth.gd")
var running = false
var cancelled = false

func cancel() -> void:
	cancelled = true

func render(path: String, settings: Dictionary, layers: Array, custom: Texture2D, synth: RefCounted, options: Dictionary) -> void:
	if running:
		return
	running = true
	cancelled = false
	var capture: Dictionary = options.get("capture",{})
	var source_audio: FileAccess
	var rate = Synth.RATE
	if not capture.is_empty():
		source_audio = FileAccess.open(capture.pcm,FileAccess.READ)
		rate = capture.rate
	var fps: float = options.fps
	var speed: float = options.speed
	var seconds = (options.end-options.start)/speed if capture.is_empty() else capture.duration
	var frames = ceili(seconds*fps)
	var sample_count = floori(frames*rate/fps)
	var output = Vector2i(options.width,options.height)
	var local = "user://recording-%d.mkv" % Time.get_ticks_usec() if path.begins_with("content://") else path+".part"
	var writer = Writer.new()
	if writer.start(local,output,fps,frames/fps,rate) != OK:
		if source_audio:
			source_audio.close()
			DirAccess.remove_absolute(capture.pcm)
		running = false
		finished.emit("exportFailed",path)
		return
	var viewport = SubViewport.new()
	viewport.size = output
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.gui_disable_input = true
	add_child(viewport)
	var canvas = Roll.new()
	canvas.size = Vector2(output)
	viewport.add_child(canvas)
	canvas.configure(settings,layers,custom)
	var failure = false
	var point_index = 0
	var touch_index = 0
	var scene_index = -1
	var hit_index = 0
	var hits: Array = capture.get("hits",[])
	for frame in range(frames):
		# Apply the next state at the start of a frame, outside the previous render callback.
		await get_tree().process_frame
		if cancelled:
			break
		var elapsed = frame/fps
		var song_time = options.start+elapsed*speed
		if not capture.is_empty():
			while scene_index < capture.scenes.size()-1 and (scene_index<0 or capture.scenes[scene_index+1][0]<=elapsed):
				scene_index += 1
				var scene = capture.scenes[scene_index]
				canvas.configure(scene[1],scene[2],scene[3])
			while point_index<capture.points.size()-1 and capture.points[point_index+1].x<=elapsed:
				point_index += 1
			var position: Vector2 = capture.points[point_index]
			song_time = position.y
			if point_index<capture.points.size()-1:
				var next_point: Vector2 = capture.points[point_index+1]
				var span = next_point.x-position.x
				if span>0 and absf(next_point.y-position.y)<=span*2.5:
					song_time = lerpf(position.y,next_point.y,clampf((elapsed-position.x)/span,0,1))
			while touch_index<capture.touches.size()-1 and capture.touches[touch_index+1][0]<=elapsed:
				touch_index += 1
			canvas.held = capture.touches[touch_index][1]
			while hit_index < hits.size() and hits[hit_index].x <= elapsed:
				canvas.key_hit(int(hits[hit_index].y),hits[hit_index].x)
				hit_index += 1
		canvas.present(song_time,elapsed)
		canvas.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var image = viewport.get_texture().get_image()
		if not image or image.is_empty():
			failure = true
			break
		var jpg = image.save_jpg_to_buffer(options.quality)
		if jpg.is_empty():
			failure = true
			break
		var first = floori(frame*rate/fps)
		var next = floori((frame+1)*rate/fps)
		if next > first:
			var audio: PackedByteArray
			if not capture.is_empty():
				var wanted = (next-first)*2
				if source_audio:
					audio = source_audio.get_buffer(mini(wanted, source_audio.get_length()-source_audio.get_position()))
				audio.resize(wanted)
			else:
				audio = synth.pcm(layers,first,next-first,options.start,speed,options.volume)
			audio = Synth.fade_clip_edges(audio,first,sample_count,rate)
			writer.block(2,roundi(float(first)*Writer.TICKS_PER_SECOND/rate),audio)
		writer.block(1,roundi(frame*Writer.TICKS_PER_SECOND/fps),jpg)
		if writer.error != OK:
			failure = true
			break
		if frame%12==0 or frame+1==frames:
			progress.emit(frame+1,frames)
	viewport.queue_free()
	if not capture.is_empty():
		if source_audio:
			source_audio.close()
		DirAccess.remove_absolute(capture.pcm)
	failure = (writer.finish()!=OK) or failure
	if not failure and not cancelled:
		failure = not save_file(local,path)
	if failure or cancelled:
		DirAccess.remove_absolute(local)
	running = false
	finished.emit("exportCancelled" if cancelled else "exportFailed" if failure else "videoSaved",path)

func save_file(local: String, path: String) -> bool:
	if not path.begins_with("content://"):
		return DirAccess.rename_absolute(local,path)==OK
	var from = FileAccess.open(local,FileAccess.READ)
	var to = FileAccess.open(path,FileAccess.WRITE)
	if not from or not to:
		return false
	while from.get_position()<from.get_length():
		to.store_buffer(from.get_buffer(mini(1024*1024,from.get_length()-from.get_position())))
		if to.get_error()!=OK:
			return false
	to.flush()
	var error = to.get_error()
	to.close()
	from.close()
	DirAccess.remove_absolute(local)
	return error==OK
