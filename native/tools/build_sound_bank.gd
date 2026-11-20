extends SceneTree

const Synth = preload("res://scripts/synth.gd")

func _initialize() -> void:
	var file = FileAccess.open(Synth.BANK_PATH,FileAccess.WRITE)
	if not file:
		printerr("Cannot write ",Synth.BANK_PATH)
		quit(1)
		return
	# Each index entry contains the compressed block position, length, frame count and loop points.
	var index = PackedInt32Array()
	index.resize(Synth.BANK_INDEX_SIZE)
	file.seek(index.size()*4)
	for pitch in range(128):
		for kind in [0,1,2,4,5]:
			if kind == 4 and pitch != 35:
				continue
			if kind == 5 and pitch in [35,36,41,43,45]:
				continue
			var bank = build_sample(pitch,kind)
			var raw: PackedByteArray = bank.pcm
			var compressed = raw.compress(FileAccess.COMPRESSION_ZSTD)
			var entry = (pitch*8+kind)*5
			index[entry] = file.get_position()
			index[entry+1] = compressed.size()
			index[entry+2] = raw.size()/2
			index[entry+3] = bank.loop_begin
			index[entry+4] = bank.loop_end
			file.store_buffer(compressed)
	for pitch in [36,41,43,45]:
		for field in range(5):
			index[(pitch*8+4)*5+field] = index[(35*8+4)*5+field]
	file.seek(0)
	file.store_buffer(index.to_byte_array())
	file.close()
	print(ProjectSettings.globalize_path(Synth.BANK_PATH))
	quit()

func build_sample(pitch: int, kind: int) -> Dictionary:
	var frequency = 440.0 * pow(2.0,(pitch-69)/12.0)
	var damper = .26 if kind == 4 else .16 if kind == 5 else 0.0
	var steady = kind == 2
	var length = int(Synth.RATE*damper) if damper > 0 else int(Synth.RATE * (2.0 if steady else 2.6))
	var loop_begin = 0
	var loop_end = 0
	if steady:
		var first = maxi(roundi(.30*Synth.RATE),roundi(15.0/frequency*Synth.RATE))
		var periods = floori((length-first)*frequency/Synth.RATE)
		if periods >= 1:
			loop_begin = first
			loop_end = mini(length,first+roundi(periods/frequency*Synth.RATE))
			frequency = float(periods)*Synth.RATE/(loop_end-loop_begin)
	var pcm = PackedByteArray()
	pcm.resize(length*2)
	var random = RandomNumberGenerator.new()
	random.seed = pitch*8+kind
	var sample = PackedFloat32Array([0.0])
	for i in range(length):
		var time = float(i)/Synth.RATE
		var phase = TAU*frequency*time
		var signal_value: float
		var envelope = Synth.fade(float(i)/Synth.ATTACK_FRAMES) if i < Synth.ATTACK_FRAMES else 1.0
		if loop_end == 0 and i >= length-Synth.RELEASE_FRAMES:
			envelope *= Synth.fade(float(length-1-i)/Synth.RELEASE_FRAMES)
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
				envelope *= .72+.28*(1.0-Synth.fade(time/.30))
			_:
				signal_value = sin(phase)*.76+sin(phase*2)*.18+sin(phase*3)*.06
				envelope *= .62*exp(-time*5.2)+.38*exp(-time*1.1)
		sample[0] = signal_value*envelope
		pcm.encode_s16(i*2,roundi(sample[0]*32767.0))
	return {"pcm":pcm,"loop_begin":loop_begin,"loop_end":loop_end}
