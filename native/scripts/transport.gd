extends Node

const Synth = preload("res://scripts/synth.gd")
const AudioPlan = preload("res://scripts/audio_plan.gd")
const PLAN_SECONDS = 1.25
const REFILL_SECONDS = .80
var synth = Synth.new()
var planner = AudioPlan.new()
var layers: Array = []
var duration = 0.0
var position = 0.0
var speed = 1.0
var volume = .7
var loop = false
var playing = false
var clock_ready = false
var anchor = 0.0
var anchor_ticks = 0
var player: AudioStreamPlayer
var playback: AudioStreamPlaybackPolyphonic
var voices: Array = []
var auditions: Dictionary = {}
var plan_revision = 0
var plan_until = 0.0
var resume_plan = true
var task = -1
var job: Dictionary = {}
var planned: Array = []
var next_chord = 0

func _ready() -> void:
	player = AudioStreamPlayer.new()
	var poly = AudioStreamPolyphonic.new()
	poly.polyphony = AudioPlan.POLYPHONY
	player.stream = poly
	player.bus = &"Piano"
	add_child(player)
	player.play()
	playback = player.get_stream_playback()
	change_volume(volume)

func _exit_tree() -> void:
	if task != -1:
		job.cancel.post()
		WorkerThreadPool.wait_for_task_completion(task)
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
	layers = []
	for layer in active:
		layers.append({"notes":layer.notes,"prefix":layer.prefix})
	duration = 0
	for layer in active:
		duration = maxf(duration,layer.duration)
	seek(minf(position,duration))

func play() -> void:
	if duration <= 0 or playing:
		return
	if position >= duration-.001:
		seek(0)
	playing = true
	request_plan()

func pause() -> void:
	if not playing:
		return
	playing = false
	stop_notes()
	reset_plan()

func toggle() -> void:
	if playing:
		pause()
	else:
		play()

func seek(at: float) -> void:
	position = clampf(at,0,duration)
	stop_notes()
	if position >= duration:
		playing = false
	reset_plan()

func change_speed(value: float) -> void:
	speed = value
	seek(position)

func reset_plan() -> void:
	clock_ready = false
	plan_revision += 1
	if task != -1:
		job.cancel.post()
	plan_until = position
	resume_plan = true
	planned.clear()
	next_chord = 0
	request_plan()

func request_plan() -> void:
	if task != -1 or plan_until >= duration or (not playing and not resume_plan):
		return
	if plan_until-position >= REFILL_SECONDS*speed:
		return
	job = {"revision":plan_revision,"layers":layers,"speed":speed,"start":plan_until,
		"end":minf(duration,plan_until+PLAN_SECONDS*speed),"resume":resume_plan,"cancel":Semaphore.new()}
	task = WorkerThreadPool.add_task(planner.build.bind(job),true,"Prepare MIDI audio")

func collect_plan() -> void:
	if task == -1 or not WorkerThreadPool.is_task_completed(task):
		return
	WorkerThreadPool.wait_for_task_completion(task)
	task = -1
	if job.revision == plan_revision:
		planned = planned.slice(next_chord)
		planned.append_array(job.result)
		next_chord = 0
		plan_until = minf(duration,job.covered)
		resume_plan = false
	job = {}

func schedule() -> void:
	for i in range(voices.size()-1,-1,-1):
		if voices[i].end <= position:
			playback.stop_stream(voices[i].id)
			voices.remove_at(i)
	if next_chord >= planned.size() or planned[next_chord].onset > position:
		return
	var due: Array = []
	while next_chord < planned.size() and planned[next_chord].onset <= position:
		for note in planned[next_chord].events:
			if due.size() >= AudioPlan.POLYPHONY:
				break
			if note.end > position:
				due.append(note)
		next_chord += 1
	if due.is_empty():
		return
	# Publish the already prepared streams together under a short audio lock.
	AudioServer.lock()
	for note in due:
		var id = playback.play_stream(note.stream,0,note.gain_db,1.0,AudioServer.PLAYBACK_TYPE_STREAM)
		if id == AudioStreamPlaybackPolyphonic.INVALID_ID:
			break
		voices.append({"id":id,"end":note.end})
	AudioServer.unlock()

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
	collect_plan()
	if playing:
		if not clock_ready and plan_until > position:
			anchor = position
			anchor_ticks = Time.get_ticks_usec()
			clock_ready = true
		if clock_ready:
			var target = anchor+(Time.get_ticks_usec()-anchor_ticks)*speed/1000000.0
			position = minf(plan_until,target)
			if position >= duration:
				if loop:
					seek(0)
				else:
					pause()
			else:
				schedule()
				clock_ready = target < plan_until
	request_plan()
