extends RefCounted

const MIDI = preload("res://scripts/midi.gd")
const RATE = 32000
const ATTACK_FRAMES = 384
const RELEASE_FRAMES = 576
const BANK_PATH = "res://assets/sound-bank.bin"
const BANK_INDEX_SIZE = 128*8*5
var samples: Dictionary = {}
var sound_bank: FileAccess
var bank_index: PackedInt32Array

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
	if not sound_bank:
		sound_bank = FileAccess.open(BANK_PATH,FileAccess.READ)
		bank_index = sound_bank.get_buffer(BANK_INDEX_SIZE*4).to_int32_array()
	var entry = cache_key*5
	var frame_count = bank_index[entry+2]
	var loop_begin = bank_index[entry+3]
	var loop_end = bank_index[entry+4]
	sound_bank.seek(bank_index[entry])
	var pcm = sound_bank.get_buffer(bank_index[entry+1]).decompress(frame_count*2,FileAccess.COMPRESSION_ZSTD)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	if loop_end > loop_begin:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = loop_begin
		stream.loop_end = loop_end
	stream.data = pcm
	var result = {"frame_count":frame_count,"stream":stream,"loop_begin":loop_begin,"loop_end":loop_end}
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
	if not loops and start >= bank.frame_count:
		return null
	var raw = base.data
	var data = raw.slice(start*2,(loop_end if loops else bank.frame_count)*2)
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
			var tone: PackedByteArray = bank.stream.data
			var amplitude = pow(note.velocity,1.65)*.31*volume
			for i in range(from,until):
				var offset = maxi(0,roundi((begin-note.start)*RATE/speed)+i)
				if bank.loop_end > bank.loop_begin and offset >= bank.loop_end:
					offset = bank.loop_begin+(offset-bank.loop_begin)%(bank.loop_end-bank.loop_begin)
				if offset >= bank.frame_count:
					break
				var release = fade(((note.end-begin)*RATE/speed-i)/RELEASE_FRAMES)
				mixed[i] += (tone.decode_s16(offset*2)/32767.0)*amplitude*release
	var data = PackedByteArray()
	data.resize(count*2)
	for i in range(count):
		var s = mixed[i]
		data.encode_s16(i*2,roundi((s/(1.0+absf(s)))*32767.0))
	return data
