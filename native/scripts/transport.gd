extends Node

const MIDI = preload("res://scripts/midi.gd")
const Synth = preload("res://scripts/synth.gd")
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
	poly.polyphony = 128
	player.stream = poly
	add_child(player)
	player.play()
	playback = player.get_stream_playback()
	change_volume(volume)

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
	anchor_ticks = Time.get_ticks_usec()
	indexes.clear()
	for layer in layers:
		var next = MIDI.next_note(layer,position)
		indexes.append(next)
		for i in range(MIDI.from_time(layer,position),next):
			var note = layer.notes[i]
			if note.end > position:
				sound_note(note,(position-note.start)/speed)
	schedule()

func sound_note(note: Dictionary, offset: float) -> void:
	var bank = synth.instrument(note)
	if bank.damper > 0 and offset >= bank.damper:
		return
	var wav: AudioStreamWAV = bank.stream
	var seconds = wav.get_length()
	if offset >= seconds and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		return
	var start = offset
	if bank.loop_end > bank.loop_begin:
		var sample_start = float(bank.loop_begin)/Synth.RATE
		var span = float(bank.loop_end-bank.loop_begin)/Synth.RATE
		if start > sample_start:
			start = sample_start + fposmod(start-sample_start,span)
	var id = playback.play_stream(wav,start,linear_to_db(maxf(.00001,pow(note.velocity,1.65)*.31)))
	if id != AudioStreamPlaybackPolyphonic.INVALID_ID:
		voices.append({"id":id,"end":note.end})

func schedule() -> void:
	for i in range(voices.size()-1,-1,-1):
		if voices[i].end <= position:
			playback.stop_stream(voices[i].id)
			voices.remove_at(i)
	for row in range(layers.size()):
		var layer = layers[row]
		var at = indexes[row]
		while at < layer.notes.size() and layer.notes[at].start <= position:
			var note = layer.notes[at]
			if note.end > position:
				sound_note(note,(position-note.start)/speed)
			at += 1
		indexes[row] = at

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
		var id = playback.play_stream(bank.stream,0,linear_to_db(.23))
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
