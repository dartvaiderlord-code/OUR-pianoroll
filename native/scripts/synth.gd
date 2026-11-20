extends RefCounted

const MIDI = preload("res://scripts/midi.gd")
const RATE = 32000
var samples: Dictionary = {}

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
		var envelope = minf(1.0,time/.009)
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
				envelope *= .72+.28*exp(-time*5)
			_:
				signal_value = sin(phase)*.76+sin(phase*2)*.18+sin(phase*3)*.06
				envelope *= .62*exp(-time*5.2)+.38*exp(-time*1.1)
		values[i] = signal_value*envelope
		pcm.encode_s16(i*2,roundi(values[i]*32767.0))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	if steady:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = roundi(15.0/frequency*RATE)
		var periods = floori((length-stream.loop_begin)*frequency/RATE)
		if periods < 1:
			stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		else:
			stream.loop_end = mini(length,stream.loop_begin+roundi(periods/frequency*RATE))
	stream.data = pcm
	var result = {"values":values,"stream":stream,"damper":damper,"loop_begin":stream.loop_begin,"loop_end":stream.loop_end}
	samples[cache_key] = result
	return result

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
				var release = clampf(((note.end-begin)*RATE/speed-i)/(RATE*.006),0,1)
				mixed[i] += tone[offset]*amplitude*release
	var data = PackedByteArray()
	data.resize(count*2)
	for i in range(count):
		var s = mixed[i]
		data.encode_s16(i*2,roundi((s/(1.0+absf(s)))*32767.0))
	return data
