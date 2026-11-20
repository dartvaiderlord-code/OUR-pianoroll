extends RefCounted

const MAX_FILE_BYTES = 64 * 1024 * 1024
const MAX_EDGE = 1920

static func load_selected(path: String) -> Image:
	if OS.get_name() == "Android" and path.begins_with("content://"):
		var native_image = read_android_photo(path)
		if native_image:
			return fit(native_image)
	var file = FileAccess.open(path,FileAccess.READ)
	if not file:
		return null
	var length = file.get_length()
	if length <= 0 or length > MAX_FILE_BYTES:
		return null
	return fit(decode_bytes(file.get_buffer(length)))

static func decode_bytes(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var image = Image.new()
	var status = ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes.slice(1,4).get_string_from_ascii() == "PNG":
		status = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xff and bytes[1] == 0xd8:
		status = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(0,4).get_string_from_ascii() == "RIFF" and bytes.slice(8,12).get_string_from_ascii() == "WEBP":
		status = image.load_webp_from_buffer(bytes)
	elif bytes[0] == 0x42 and bytes[1] == 0x4d:
		status = image.load_bmp_from_buffer(bytes)
	return image if status == OK and not image.is_empty() else null

static func fit(image: Image) -> Image:
	if not image:
		return null
	var edge = maxi(image.get_width(),image.get_height())
	if edge > MAX_EDGE:
		var scale = float(MAX_EDGE) / edge
		image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	return image

static func read_android_photo(path: String) -> Image:
	# Gallery results are provider URIs. Their last segment may have no image extension.
	var runtime = Engine.get_singleton("AndroidRuntime")
	var java = Engine.get_singleton("JavaClassWrapper")
	if not runtime or not java:
		return null
	var activity = runtime.getActivity()
	if not activity:
		return null
	var resolver = activity.getContentResolver()
	var uri = java.wrap("android.net.Uri").parse(path)
	var factory = java.wrap("android.graphics.BitmapFactory")
	var options = java.wrap("android.graphics.BitmapFactory$Options").Options()
	options.inJustDecodeBounds = true
	var stream = resolver.openInputStream(uri)
	if not stream or java.get_exception():
		return null
	factory.decodeStream(stream,null,options)
	stream.close()
	var edge = maxi(options.outWidth, options.outHeight)
	if edge <= 0:
		return null
	var sample = 1
	while edge / sample > MAX_EDGE * 2:
		sample *= 2
	options.inJustDecodeBounds = false
	options.inSampleSize = sample
	stream = resolver.openInputStream(uri)
	if not stream or java.get_exception():
		return null
	var bitmap = factory.decodeStream(stream,null,options)
	stream.close()
	if not bitmap:
		return null
	var bytes_out = java.wrap("java.io.ByteArrayOutputStream").ByteArrayOutputStream()
	var png_format = java.wrap("android.graphics.Bitmap$CompressFormat").PNG
	var ok = bitmap.compress(png_format,100,bytes_out)
	bitmap.recycle()
	if not ok:
		return null
	var bytes: PackedByteArray = bytes_out.toByteArray()
	return decode_bytes(bytes)
