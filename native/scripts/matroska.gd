extends RefCounted

const TICKS_PER_SECOND = 1000000
const SCALE = 1000
const CLUSTER_TICKS = 30000
var target: FileAccess
var cluster = PackedByteArray()
var cluster_at = -1
var error: Error = OK

static func put(id: int, payload: PackedByteArray) -> PackedByteArray:
	return number(id) + vint(payload.size()) + payload

static func number(value: int) -> PackedByteArray:
	var bytes = PackedByteArray([value & 255])
	value >>= 8
	while value:
		bytes.insert(0,value & 255)
		value >>= 8
	return bytes

static func vint(value: int) -> PackedByteArray:
	var width = 1
	while value >= (1 << (7 * width))-1:
		width += 1
	var bytes = number(value | (1 << (7 * width)))
	assert(bytes.size()==width)
	return bytes

static func ui(id: int, value: int) -> PackedByteArray:
	return put(id,number(value))

static func text_element(id: int, value: String) -> PackedByteArray:
	return put(id,value.to_utf8_buffer())

static func float_element(id: int, value: float) -> PackedByteArray:
	var payload = PackedByteArray()
	payload.resize(8)
	payload.encode_double(0,value)
	payload.reverse()
	return put(id,payload)

func start(path: String, size_data: Vector2i, fps: float, duration: float, sample_rate: int) -> Error:
	target = FileAccess.open(path,FileAccess.WRITE)
	if not target:
		return FileAccess.get_open_error()
	var ebml = ui(0x4286,1)+ui(0x42f7,1)+ui(0x42f2,4)+ui(0x42f3,8)+text_element(0x4282,"matroska")+ui(0x4287,4)+ui(0x4285,2)
	target.store_buffer(put(0x1a45dfa3,ebml))
	target.store_buffer(number(0x18538067)+PackedByteArray([1,255,255,255,255,255,255,255]))
	var info = ui(0x2ad7b1,SCALE)+float_element(0x4489,duration*TICKS_PER_SECOND)
	info += text_element(0x4d80,"OUR-pianoroll")+text_element(0x5741,"OUR-pianoroll")
	target.store_buffer(put(0x1549a966,info))
	var video = ui(0xd7,1)+ui(0x73c5,1)+ui(0x83,1)+ui(0x9c,0)+text_element(0x86,"V_MJPEG")
	video += ui(0x23e383,roundi(1000000000.0/fps))+put(0xe0,ui(0xb0,size_data.x)+ui(0xba,size_data.y))
	var audio = ui(0xd7,2)+ui(0x73c5,2)+ui(0x83,2)+ui(0x9c,0)+text_element(0x86,"A_PCM/INT/LIT")
	audio += put(0xe1,float_element(0xb5,float(sample_rate))+ui(0x9f,1)+ui(0x6264,16))
	target.store_buffer(put(0x1654ae6b,put(0xae,video)+put(0xae,audio)))
	return target.get_error()

func block(track: int, timestamp: int, data: PackedByteArray) -> void:
	if error != OK or data.is_empty():
		return
	if cluster_at < 0 or timestamp < cluster_at or timestamp-cluster_at >= CLUSTER_TICKS or cluster.size() >= 8*1024*1024:
		write_cluster()
		cluster_at = timestamp
		cluster = ui(0xe7,cluster_at)
	var relative = timestamp-cluster_at
	var header = PackedByteArray([0x80|track,(relative>>8)&255,relative&255,0x80])
	cluster.append_array(put(0xa3,header+data))

func write_cluster() -> void:
	if not cluster.is_empty() and target:
		target.store_buffer(put(0x1f43b675,cluster))
		error = target.get_error()
		cluster.clear()

func finish() -> Error:
	write_cluster()
	if target:
		target.flush()
		if error == OK:
			error = target.get_error()
		target.close()
		target = null
	return error
