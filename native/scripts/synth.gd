extends RefCounted

const MIDI = preload("res://scripts/midi.gd")
const RATE = 32000
const ATTACK_FRAMES = 384
const RELEASE_FRAMES = 576
var samples: Dictionary = {}

static func fade(t: float) -> float:
	var x = clampf(t,0.0,1.0)
	return x*x*(3.0-2.0*x)

func instrument(note: Dictionary) -> Dictionary:
	var drum = note.channel == 9
	var family = note.program >> 3
	var kind = (4 if note.pitch in [35,36,41,43,45] else 5) if drum else (1 if family == 1 else 2 if family in [2,5,6,7,8,9,10,11,12] else 0)
	var cache_key = note.pitch * 8 + kind
	if samples.has(cache_key):
		return samples[cache_key]
	var frequency = 440.0 * pow(2.0,(note.pitch-69)/12.0)
	var damper = .26 if kind == 4 else .16 if kind == 5 else 0.0
	var steady = kind == 2
	var length = int(RATE*damper) if damper > 0 else int(RATE * (2.0 if steady else 2.6))
	var loop_begin = 0
	var loop_end = 0
	if steady:
		var first = maxi(roundi(.30*RATE),roundi(15.0/frequency*RATE))
		var periods = floori((length-first)*frequency/RATE)
		if periods >= 1:
			loop_begin = first
			loop_end = mini(length,first+roundi(periods/frequency*RATE))
			frequency = float(periods)*RATE/(loop_end-loop_begin)
	var values = PackedFloat32Array()
	values.resize(length)
	var pcm = PackedByteArray()
	pcm.resize(length*2)
	var random = RandomNumberGenerator.new()
	random.seed = cache_key
	for i in range(length):
		var time = float(i)/RATE
		var phase = TAU*frequency*time
		var signal_value: float
		var envelope = fade(float(i)/ATTACK_FRAMES) if i < ATTACK_FRAMES else 1.0
		if loop_end == 0 and i >= length-RELEASE_FRAMES:
			envelope *= fade(float(length-1-i)/RELEASE_FRAMES)
		match kind:
			4:
				signal_value = sin(TAU*(46*time+7*(1-exp(-time*17))))
				envelope *= exp(-time*18)
			5:
				signal_value = random.randf_range(-1,1)*.65 + sin(phase)*.15
				envelope *= exp(-time*24)
			1:
				signal_value = sin(phase)*.74+sin(phase*2.76)*.21+sin(phase*4.05)*.05
				envelope *= .66*exp(-time*3.7)+.34*exp(-time*1.2)
			2:
				signal_value = sin(phase)*.72+sin(phase*2)*.2+sin(phase*3)*.08
				envelope *= .72+.28*(1.0-fade(time/.30))
			_:
				signal_value = sin(phase)*.76+sin(phase*2)*.18+sin(phase*3)*.06
				envelope *= .62*exp(-time*5.2)+.38*exp(-time*1.1)
		values[i] = signal_value*envelope
		pcm.encode_s16(i*2,roundi(values[i]*32767.0))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	if loop_end > loop_begin:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = loop_begin
		stream.loop_end = loop_end
	stream.data = pcm
	var result = {"values":values,"stream":stream,"loop_begin":loop_begin,"loop_end":loop_end}
	samples[cache_key] = result
	return result

func stream_from(note: Dictionary, offset: float) -> AudioStreamWAV:
	var bank = instrument(note)
	var base: AudioStreamWAV = bank.stream
	var start = maxi(0,roundi(offset*RATE))
	if start == 0:
		return base
	var loop_begin: int = bank.loop_begin
	var loop_end: int = bank.loop_end
	var loops = loop_end > loop_begin
	if loops and start >= loop_end:
		start = loop_begin+(start-loop_begin)%(loop_end-loop_begin)
	if not loops and start >= bank.values.size():
		return null
	var raw = base.data
	var data = raw.slice(start*2,(loop_end if loops else bank.values.size())*2)
	if loops:
		loop_begin -= start
		loop_end -= start
		if loop_begin < ATTACK_FRAMES:
			# The resumed attack is played once. The repeating section keeps its original samples.
			var cycle = raw.slice(bank.loop_begin*2,bank.loop_end*2)
			while data.size()/2 < ATTACK_FRAMES:
				data.append_array(cycle)
			loop_begin = data.size()/2
			data.append_array(cycle)
			loop_end = data.size()/2
	for i in range(mini(ATTACK_FRAMES,data.size()/2)):
		data.encode_s16(i*2,roundi(data.decode_s16(i*2)*fade(float(i)/ATTACK_FRAMES)))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	if loops:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = loop_begin
		stream.loop_end = loop_end
	return stream

static func fade_clip_edges(data: PackedByteArray, first: int, total: int, rate: int) -> PackedByteArray:
	var ramp = maxi(1,roundi(rate*.012))
	var count = data.size()/2
	if first >= ramp and first+count <= total-ramp:
		return data
	for i in range(count):
		var index = first+i
		var gain = fade(float(mini(index,total-1-index))/ramp)
		if gain < 1.0:
			data.encode_s16(i*2,roundi(data.decode_s16(i*2)*gain))
	return data

func pcm(layers: Array, first: int, count: int, start: float, speed: float, volume: float) -> PackedByteArray:
	var mixed = PackedFloat32Array()
	mixed.resize(count)
	var begin = start + float(first)*speed/RATE
	var last = begin + float(count)*speed/RATE
	for layer in layers:
		for index in range(MIDI.from_time(layer,begin),layer.notes.size()):
			var note = layer.notes[index]
			if note.start >= last:
				break
			var from = maxi(0,ceili((note.start-begin)*RATE/speed))
			var until = mini(count,ceili((note.end-begin)*RATE/speed))
			if until <= from:
				continue
			var bank = instrument(note)
			var tone: PackedFloat32Array = bank.values
			var amplitude = pow(note.velocity,1.65)*.31*volume
			for i in range(from,until):
				var offset = maxi(0,roundi((begin-note.start)*RATE/speed)+i)
				if bank.loop_end > bank.loop_begin and offset >= bank.loop_end:
					offset = bank.loop_begin+(offset-bank.loop_begin)%(bank.loop_end-bank.loop_begin)
				if offset >= tone.size():
					break
				var release = fade(((note.end-begin)*RATE/speed-i)/RELEASE_FRAMES)
				mixed[i] += tone[offset]*amplitude*release
	var data = PackedByteArray()
	data.resize(count*2)
	for i in range(count):
		var s = mixed[i]
		data.encode_s16(i*2,roundi((s/(1.0+absf(s)))*32767.0))
	return data
