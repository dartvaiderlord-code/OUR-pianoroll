extends RefCounted

var active = false
var start_ticks = 0
var rate = 48000
var effect: AudioEffectCapture
var file: FileAccess
var path = ""
var points: Array[Vector2] = []
var touches = []
var hits: Array[Vector2] = []
var scenes = []

func start() -> bool:
	path = "user://live-audio-%d.pcm" % Time.get_ticks_usec()
	file = FileAccess.open(path,FileAccess.WRITE)
	if not file:
		return false
	rate = roundi(AudioServer.get_mix_rate())
	effect = AudioEffectCapture.new()
	effect.buffer_length = 2.0
	AudioServer.add_bus_effect(0,effect)
	start_ticks = Time.get_ticks_usec()
	active = true
	return true

func elapsed() -> float:
	return (Time.get_ticks_usec()-start_ticks)/1000000.0

func add_scene(settings: Dictionary, layers: Array, background: Texture2D) -> void:
	var files = []
	for layer in layers:
		files.append(layer.duplicate())
	scenes.append([elapsed(),settings.duplicate(),files,background])

func add_frame(position: float, held: Dictionary) -> void:
	var time = elapsed()
	points.append(Vector2(time,position))
	if touches.is_empty() or touches.back()[1] != held:
		touches.append([time,held.duplicate()])
	drain()

func add_hit(pitch: int) -> void:
	hits.append(Vector2(elapsed(),pitch))

func drain() -> void:
	var available = effect.get_frames_available()
	if available<=0:
		return
	var sound = effect.get_buffer(available)
	var bytes = PackedByteArray()
	bytes.resize(sound.size()*2)
	for i in range(sound.size()):
		var stereo = sound[i]
		bytes.encode_s16(i*2,roundi(clampf((stereo.x+stereo.y)*.5,-1,1)*32767))
	file.store_buffer(bytes)

func finish() -> Dictionary:
	drain()
	var runtime = elapsed()
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0,i)==effect:
			AudioServer.remove_bus_effect(0,i)
			break
	effect = null
	file.close()
	file = null
	active = false
	return {"duration":runtime,"points":points,"touches":touches,"hits":hits,"scenes":scenes,"pcm":path,"rate":rate}
