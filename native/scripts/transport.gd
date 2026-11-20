extends Node

const MIDI = preload("res://scripts/midi.gd")
const Synth = preload("res://scripts/synth.gd")
const POLYPHONY = 128
const CHORD_PEAK_TARGET = .73
const PREVIEW_STEP = 13
const PREVIEW_LENGTH = Synth.RATE/10
const ONSET_WINDOW = .001
const NORMAL_SCHEDULING_DELAY = .032
var synth = Synth.new()
var layers: Array = []
var indexes: Array = []
var duration = 0.0
var position = 0.0
var speed = 1.0
var volume = .7
var loop = false
var playing = false
var anchor = 0.0
var anchor_ticks = 0
var player: AudioStreamPlayer
var playback: AudioStreamPlaybackPolyphonic
var voices: Array = []
var auditions: Dictionary = {}

func _ready() -> void:
	player = AudioStreamPlayer.new()
	var poly = AudioStreamPolyphonic.new()
	poly.polyphony = POLYPHONY
	player.stream = poly
	player.bus = &"Piano"
	add_child(player)
	player.play()
	playback = player.get_stream_playback()
	change_volume(volume)

func _exit_tree() -> void:
	stop_notes()
	if playback:
		for id in auditions.values():
			playback.stop_stream(id)
	auditions.clear()
	player.stop()
	playback = null

func change_volume(value: float) -> void:
	volume = clampf(value,0,1)
	player.volume_db = linear_to_db(maxf(.000001,volume))

func replace(active: Array) -> void:
	layers = active
	duration = 0
	for layer in layers:
		duration = maxf(duration,layer.duration)
	seek(minf(position,duration))
	if duration <= 0:
		pause()

func play() -> void:
	if duration <= 0 or playing:
		return
	if position >= duration-.001:
		position = 0
	playing = true
	start_clock()

func pause() -> void:
	playing = false
	stop_notes()

func toggle() -> void:
	if playing:
		pause()
	else:
		play()

func seek(at: float) -> void:
	position = clampf(at,0,duration)
	stop_notes()
	if playing:
		if position >= duration:
			pause()
		else:
			start_clock()

func change_speed(value: float) -> void:
	speed = value
	if playing:
		seek(position)

func start_clock() -> void:
	anchor = position
	indexes.clear()
	var pending: Array = []
	for layer in layers:
		var next = MIDI.next_note(layer,position)
		indexes.append(next)
		for i in range(MIDI.from_time(layer,position),next):
			var note = layer.notes[i]
			if note.end > position:
				prepare_note(pending,note,position,(position-note.start)/speed)
	collect_new_notes(pending)
	start_notes(pending)
	anchor_ticks = Time.get_ticks_usec()

func prepare_note(pending: Array, note: Dictionary, onset: float, offset: float) -> void:
	if pending.size() >= POLYPHONY:
		return
	var wav = synth.stream_from(note,offset)
	if not wav:
		return
	pending.append({"stream":wav,"onset":onset,"end":note.end,"gain":pow(note.velocity,1.65)*.31})

func collect_new_notes(pending: Array) -> void:
	for row in range(layers.size()):
		var layer = layers[row]
		var at = indexes[row]
		while at < layer.notes.size() and layer.notes[at].start <= position:
			var note = layer.notes[at]
			if note.end > position:
				var delay = (position-note.start)/speed
				prepare_note(pending,note,note.start,0.0 if delay <= NORMAL_SCHEDULING_DELAY else delay)
			at += 1
		indexes[row] = at

func start_notes(pending: Array) -> void:
	if pending.is_empty():
		return
	pending.sort_custom(func(a,b): return a.onset < b.onset)
	var first = 0
	while first < pending.size():
		var end = first
		var total = 0.0
		var limit: float = pending[first].onset+ONSET_WINDOW*speed
		while end < pending.size() and pending[end].onset <= limit:
			total += pending[end].gain
			end += 1
		# Keep the same gain through the whole attack instead of riding each peak of a chord.
		var scale = chord_gain(pending,first,end) if total > CHORD_PEAK_TARGET else 1.0
		for i in range(first,end):
			pending[i].gain_db = linear_to_db(maxf(.00001,pending[i].gain*scale))
		first = end
	# Publish the prepared voices together so a mixer callback cannot split their onset.
	AudioServer.lock()
	for note in pending:
		var id = playback.play_stream(note.stream,0,note.gain_db,1.0,AudioServer.PLAYBACK_TYPE_STREAM)
		if id != AudioStreamPlaybackPolyphonic.INVALID_ID:
			voices.append({"id":id,"end":note.end})
	AudioServer.unlock()

func chord_gain(pending: Array, first: int, end: int) -> float:
	var preview = PackedFloat32Array()
	preview.resize(ceili(float(PREVIEW_LENGTH)/PREVIEW_STEP))
	for i in range(first,end):
		var note: Dictionary = pending[i]
		var pcm: PackedByteArray = note.stream.data
		var frames = mini(pcm.size()/2,roundi((note.end-position)*Synth.RATE/speed))
		var count = mini(preview.size(),ceili(float(frames)/PREVIEW_STEP))
		var gain: float = note.gain/32767.0
		for frame in range(count):
			preview[frame] += pcm.decode_s16(frame*PREVIEW_STEP*2)*gain
	var peak = CHORD_PEAK_TARGET
	for sample in preview:
		peak = maxf(peak,absf(sample))
	return CHORD_PEAK_TARGET/peak

func schedule() -> void:
	for i in range(voices.size()-1,-1,-1):
		if voices[i].end <= position:
			playback.stop_stream(voices[i].id)
			voices.remove_at(i)
	var pending: Array = []
	collect_new_notes(pending)
	start_notes(pending)

func stop_notes() -> void:
	if playback:
		for voice in voices:
			playback.stop_stream(voice.id)
	voices.clear()

func audition(pitch: int, pointer: int, pressed: bool) -> void:
	if auditions.has(pointer):
		playback.stop_stream(auditions[pointer])
		auditions.erase(pointer)
	if pressed:
		var bank = synth.instrument({"pitch":pitch,"program":0,"channel":0})
		var id = playback.play_stream(bank.stream,0,linear_to_db(.23),1.0,AudioServer.PLAYBACK_TYPE_STREAM)
		if id != AudioStreamPlaybackPolyphonic.INVALID_ID:
			auditions[pointer] = id

func _process(_delta: float) -> void:
	if not playing:
		return
	position = minf(duration,anchor+(Time.get_ticks_usec()-anchor_ticks)*speed/1000000.0)
	if position >= duration:
		if loop and duration > 0:
			seek(0)
		else:
			pause()
	else:
		schedule()
