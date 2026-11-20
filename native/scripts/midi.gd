extends RefCounted

const ERROR_CORRUPT = "midiDamaged"
const ERROR_TYPE = "midiUnrecognized"
const ERROR_EVENT = "midiUnsupportedEvent"
const ERROR_EMPTY = "midiNoNotes"
const COLORS = ["#e86bff","#39e7ef","#9d86ff","#ffae61","#85f696","#fb729d","#79aaff","#f5dd76","#7bffcb","#ff9579","#b3aaff","#f7acff","#a8d25f","#4facec","#ff74c9","#d5efd2"]
const RAINBOW = ["#ff698e","#ff8968","#ffbf69","#f1ed72","#a3f77c","#57edbd","#4de2fe","#649dff","#8987ff","#bb80ff","#e675ff","#ff78d1"]

var bytes: PackedByteArray
var point = 0
var boundary = 0
var failure = ""

func read(length_data: int) -> int:
	if point + length_data > boundary:
		failure = ERROR_CORRUPT
		return 0
	var value = 0
	for i in range(length_data):
		value = (value << 8) | bytes[point]
		point += 1
	return value

func vlq() -> int:
	var value = 0
	for n in range(4):
		var byte = read(1)
		value = value * 128 + (byte & 127)
		if byte < 128:
			return value
	failure = ERROR_CORRUPT
	return 0

func parse(data: PackedByteArray) -> Dictionary:
	bytes = data
	point = 0
	failure = ""
	if bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "RMID":
		var at = 12
		while at + 8 <= bytes.size():
			var size_data = bytes.decode_u32(at + 4)
			if at + 8 + size_data > bytes.size():
				return {"error": ERROR_CORRUPT}
			if bytes.slice(at, at + 4).get_string_from_ascii() == "data":
				bytes = bytes.slice(at + 8, at + 8 + size_data)
				break
			at += 8 + size_data + (size_data & 1)
	boundary = bytes.size()
	if boundary < 14 or read(4) != 0x4d546864:
		return {"error": ERROR_TYPE}
	var header = read(4)
	var format = read(2)
	var count = read(2)
	var division = read(2)
	if header < 6 or header + 8 > boundary or format > 2 or not count or not division or (format == 0 and count != 1):
		return {"error": ERROR_CORRUPT}
	var seconds_per_tick: float
	if division & 0x8000:
		var code = 256 - (division >> 8)
		if not [24,25,29,30].has(code) or not (division & 255):
			return {"error": ERROR_CORRUPT}
		seconds_per_tick = 1.0 / ((30000.0 / 1001.0 if code == 29 else float(code)) * (division & 255))
	else:
		seconds_per_tick = 0.5 / division
	point = header + 8
	var tracks = []
	var order = 0
	while tracks.size() < count:
		boundary = bytes.size()
		if point + 8 > boundary:
			return {"error": ERROR_CORRUPT}
		var kind = read(4)
		var length_data = read(4)
		var end = point + length_data
		if end > boundary:
			return {"error": ERROR_CORRUPT}
		if kind != 0x4d54726b:
			point = end
			continue
		boundary = end
		var tick = 0
		var running = 0
		var events = []
		while point < end and failure.is_empty():
			tick += vlq()
			var status = read(1)
			if status < 128:
				if not running:
					return {"error": ERROR_CORRUPT}
				point -= 1
				status = running
			if status < 240:
				running = status
				var type = status >> 4
				var key = read(1)
				var value = 0 if type == 12 or type == 13 else read(1)
				if key > 127 or value > 127:
					return {"error": ERROR_CORRUPT}
				if type in [8,9,11,12]:
					events.append([tick, order, type, status & 15, key, value])
					order += 1
			elif status == 255:
				running = 0
				var meta = read(1)
				var size_data = vlq()
				if point + size_data > end:
					return {"error": ERROR_CORRUPT}
				if meta == 81 and size_data == 3:
					var tempo = read(3)
					if tempo:
						events.append([tick, order, 0, tempo])
						order += 1
				else:
					point += size_data
				if meta == 47:
					break
			elif status == 240 or status == 247:
				running = 0
				var size_data = vlq()
				point += size_data
				if point > end:
					return {"error": ERROR_CORRUPT}
			else:
				return {"error": ERROR_EVENT}
		if not failure.is_empty():
			return {"error": failure}
		tracks.append({"events":events,"end":tick})
		point = end

	var groups = []
	if format == 2:
		for track in tracks:
			groups.append([track])
	else:
		groups.append(tracks)
	var output = []
	var duration = 0.0
	for group in groups:
		var converted = convert_tracks(group, seconds_per_tick, division)
		for note in converted.notes:
			note.start += duration
			note.end += duration
			output.append(note)
		duration += converted.duration
	return {"notes":output,"duration":duration} if not output.is_empty() else {"error":ERROR_EMPTY}

static func finish(notes: Array, note: Dictionary, at: float) -> void:
	note.end = maxf(note.start + .045, at)
	notes.append(note)

static func convert_tracks(group: Array, seconds_per_tick: float, division: int) -> Dictionary:
	var events = []
	var track_end = 0
	for track in group:
		events.append_array(track.events)
		track_end = maxi(track_end, track.end)
	events.sort_custom(func(a,b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var channels = []
	for channel in range(16):
		channels.append({"program":0,"pedal":false,"held":{},"sustained":[]})
	var time = 0.0
	var tick = 0
	var notes = []
	for event in events:
		time += (event[0] - tick) * seconds_per_tick
		tick = event[0]
		var type = event[2]
		if type == 0:
			if not (division & 0x8000):
				seconds_per_tick = event[3] / 1000000.0 / division
			continue
		var channel = event[3]
		var state = channels[channel]
		var pitch = event[4]
		var value = event[5]
		if type == 12:
			state.program = pitch
		elif type == 11:
			if pitch in [64,121]:
				state.pedal = pitch == 64 and value >= 64 and channel != 9
				if not state.pedal:
					for note in state.sustained:
						finish(notes, note, time)
					state.sustained.clear()
			elif pitch in [120,123]:
				for stopped in state.held.values():
					for note in stopped:
						if pitch == 123 and state.pedal:
							state.sustained.append(note)
						else:
							finish(notes, note, time)
				state.held.clear()
				if pitch == 120:
					for note in state.sustained:
						finish(notes, note, time)
					state.sustained.clear()
		elif type == 9 and value:
			if not state.held.has(pitch):
				state.held[pitch] = []
			state.held[pitch].append({"pitch":pitch,"start":time,"end":time,"velocity":value/127.0,"program":state.program,"channel":channel})
		elif state.held.has(pitch):
			var note = state.held[pitch].pop_front()
			if state.held[pitch].is_empty():
				state.held.erase(pitch)
			if state.pedal:
				state.sustained.append(note)
			else:
				finish(notes, note, time)
	var last = time + (track_end-tick) * seconds_per_tick
	for state in channels:
		for held in state.held.values():
			for note in held:
				finish(notes, note, last)
		for note in state.sustained:
			finish(notes, note, last)
	for note in notes:
		last = maxf(last, note.end)
	return {"notes":notes,"duration":last}

static func layer(title: String, notes: Array, duration: float, color_scheme := "", demo := "") -> Dictionary:
	notes.sort_custom(func(a,b): return a.start < b.start or (a.start == b.start and a.pitch < b.pitch))
	var prefix = PackedFloat64Array()
	prefix.resize(notes.size())
	var latest = 0.0
	for index in range(notes.size()):
		notes[index].index = index
		latest = maxf(latest, notes[index].end)
		prefix[index] = latest
	return {"name":title,"notes":notes,"prefix":prefix,"duration":duration,"color":color_scheme,"mode":"solid","enabled":true,"demo":demo}

static func from_time(track: Dictionary, time: float) -> int:
	return track.prefix.bsearch(time, false)

static func next_note(track: Dictionary, time: float) -> int:
	var low = 0
	var high = track.notes.size()
	while low < high:
		var mid = (low + high) >> 1
		if track.notes[mid].start < time:
			low = mid + 1
		else:
			high = mid
	return low

static func demo_note(notes: Array, pitch: int, start: float, span: float, velocity: float, program: int) -> void:
	notes.append({"pitch":pitch,"start":start*.48,"end":(start+span)*.48,"velocity":velocity,"program":program,"channel":0})

static func demo() -> Array:
	var lead = []
	var bass = []
	var chords = [[42,49,54,57,61,66,69,73],[38,45,50,54,57,66,69,74],[45,52,57,61,64,69,73,76],[40,47,52,56,59,68,71,76]]
	var shapes = [
		[[6,0,1.25],[5,.75,.65],[7,1.5,1.05],[6,2.5,.67],[5,3.25,.54]],
		[[7,0,.82],[6,.64,.65],[5,1.25,1.32],[6,2.25,.57],[4,3,.82]],
		[[5,0,.79],[6,.5,.64],[7,1.25,1.05],[6,2.35,.66],[5,3,.95]]
	]
	for bar in range(24):
		var chord = chords[bar%4]
		var moment = bar*4.0
		for item in [[0,0,1.85,.75],[1,.5,.69,.54],[2,1,1.14,.6],[3,1.5,.76,.45],[1,2,.9,.58],[4,2.5,1.18,.53],[2,3.25,.53,.48]]:
			demo_note(bass,chord[item[0]],moment+item[1],item[2],item[3],0)
		for item in shapes[mini(bar%4,2)]:
			demo_note(lead,chord[item[0]],moment+item[1],item[2],.76,11)
		if bar%2 == 0:
			demo_note(lead,chord[7]+12,moment+2.15,.9,.39,11)
			demo_note(lead,chord[5]+12,moment+3.06,.46,.47,11)
		if bar%4 == 0:
			demo_note(lead,chord[4],moment,.6,.34,11)
	return [layer("",lead,46.08,"","demoLeadFilename"),layer("",bass,46.08,"","demoBassFilename")]
