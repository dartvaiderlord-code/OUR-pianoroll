extends RefCounted

const MIDI = preload("res://scripts/midi.gd")
const Synth = preload("res://scripts/synth.gd")
const POLYPHONY = 128
const ONSET_WINDOW = .001
const CHORD_PEAK_TARGET = .73
const PREVIEW_STEP = 13
const PREVIEW_LENGTH = Synth.RATE/10

var synth = Synth.new()

# The job owns its output. The transport reads it only after the worker finishes.
func build(job: Dictionary) -> void:
	var cancel: Semaphore = job.cancel
	var candidates: Array = []
	for layer in job.layers:
		if cancel.try_wait():
			return
		var first = MIDI.next_note(layer,job.start)
		if job.resume:
			first = MIDI.from_time(layer,job.start)
		for i in range(first,layer.notes.size()):
			var note: Dictionary = layer.notes[i]
			if note.start > job.end + ONSET_WINDOW*job.speed:
				break
			if note.end > job.start:
				candidates.append(note)
	candidates.sort_custom(func(a,b): return a.start < b.start)

	var ready: Array = []
	var first = 0
	var covered: float = job.end
	while first < candidates.size():
		var onset: float = maxf(candidates[first].start,job.start)
		if onset >= job.end:
			break
		var limit = onset + ONSET_WINDOW*job.speed
		var events: Array = []
		var total = 0.0
		var index = first
		while index < candidates.size() and candidates[index].start <= limit:
			var note: Dictionary = candidates[index]
			if events.size() < POLYPHONY:
				if cancel.try_wait():
					return
				var offset = maxf(0.0,(job.start-note.start)/job.speed)
				var stream = synth.stream_from(note,offset)
				if stream:
					var gain = pow(note.velocity,1.65)*.31
					total += gain
					events.append({"stream":stream,"end":note.end,"gain":gain})
			index += 1
		# Retain a fixed gain for the attack, including chords split across MIDI files.
		var scale = chord_gain(events,onset,job.speed) if total > CHORD_PEAK_TARGET else 1.0
		for event in events:
			event.gain_db = linear_to_db(maxf(.00001,event.gain*scale))
		if not events.is_empty():
			ready.append({"onset":onset,"events":events})
		# Keep an onset that straddles the end of this window in a single batch.
		if index > first and candidates[index-1].start >= job.end:
			covered = candidates[index].start if index < candidates.size() else job.end+ONSET_WINDOW*job.speed
		first = index
	job.result = ready
	job.covered = covered

func chord_gain(events: Array, onset: float, speed: float) -> float:
	var preview = PackedFloat32Array()
	preview.resize(ceili(float(PREVIEW_LENGTH)/PREVIEW_STEP))
	for event in events:
		var pcm: PackedByteArray = event.stream.data
		var frames = mini(pcm.size()/2,roundi((event.end-onset)*Synth.RATE/speed))
		var count = mini(preview.size(),ceili(float(frames)/PREVIEW_STEP))
		var gain: float = event.gain/32767.0
		for frame in range(count):
			preview[frame] += pcm.decode_s16(frame*PREVIEW_STEP*2)*gain
	var peak = CHORD_PEAK_TARGET
	for sample in preview:
		peak = maxf(peak,absf(sample))
	return CHORD_PEAK_TARGET/peak
