extends Control

signal audition(pitch: int, pointer: int, pressed: bool)
const MIDI = preload("res://scripts/midi.gd")
const Design = preload("res://scripts/design.gd")
const PANORAMA = preload("res://assets/soviet-panorama.webp")
const DARK = [1,3,6,8,10]
const SURFACES = {
	"piano":["#ebdff5","#21152a","#7e668e","#4c3357"],
	"soviet":["#ffe3c4","#371019","#ff735c","#5e2a30"],
	"glass":["#fff2ff49","#190e2b70","#ac91d6ba","#ffecfa"],
	"neon":["#201438","#190f2c","#ac8aff","#e2d3ff"],
	"matte":["#6b6d78","#20232b","#959aa5","#f6f4ff"],
	"square":["#292a34","#11121a","#a0a5b0","#f9f7ff"],
	"gold":["#edbd69","#51351c","#f8de9b","#4f260f"],
	"spectrum":["#efffff","#120f26","#f4cfff91","#260f24"],
	"ice":["#bdedf7","#1b465b","#89d9ee","#173a56"],
	"inverted":["#202028","#e2e6ec","#89878f","#edeaf6"]
}
const BACKDROPS = {
	"aurora":["#100b1b","#261540"],"soviet":["#170914","#642326"],
	"orbit":["#060918","#1b2e59"],"ocean":["#07131d","#145c62"],"sunset":["#1c0e21","#6e3149"]
}
var settings = Design.defaults()
var layers: Array = []
var custom_image: Texture2D
var playback_time = 0.0
var keyboard: Dictionary = {}
var whites: Array = []
var blacks: Array = []
var held: Dictionary = {}
var impact = 0.0
var key_width = 0.0
var cached_size = Vector2.ZERO
var cached_range = 0
var note_boxes: Dictionary = {}
var palette: Dictionary = {}
var glow_texture: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,.25,.62,1.0])
	gradient.colors = PackedColorArray([Color(1,1,1,.7),Color(1,1,1,.32),Color(1,1,1,.09),Color(1,1,1,0)])
	glow_texture = GradientTexture2D.new()
	glow_texture.gradient = gradient
	glow_texture.width = 96
	glow_texture.height = 96
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(.5,.5)
	glow_texture.fill_to = Vector2(1,.5)
	resized.connect(queue_redraw)

func configure(new_settings: Dictionary, active: Array, custom: Texture2D) -> void:
	settings = new_settings
	layers = active
	custom_image = custom
	palette = Design.theme_colors(settings)
	note_boxes.clear()
	queue_redraw()

func present(at: float) -> void:
	if not is_equal_approx(at,playback_time):
		playback_time = at
		queue_redraw()

func build_keys() -> void:
	if cached_size == size and cached_range == int(settings.range):
		return
	cached_size = size
	cached_range = int(settings.range)
	impact = size.y - clampf(size.y*.17,48.0, size.y*.28 if size.y >= 172 else 48.0)
	var margin = 10.0 if size.x < 650 else 14.0
	var low = 0 if cached_range == 128 else 21
	var high = 127 if cached_range == 128 else 108
	var count = 0
	for pitch in range(low,high+1):
		if pitch%12 not in DARK:
			count += 1
	key_width = (size.x-margin*2)/count
	keyboard.clear()
	whites.clear()
	blacks.clear()
	var next = 0
	for pitch in range(low,high+1):
		var dark = pitch%12 in DARK
		var width = key_width*(.64 if dark else 1)
		var center = margin+(next+(0.0 if dark else .5))*key_width
		var left = center-width/2 + (0 if dark else .52)
		var height = (size.y-impact-2)*(.61 if dark else 1.0)
		var key_rect = Rect2(left,impact+1,maxf(1.0,width-(.38 if dark else 1.04)),maxf(height,1.0))
		keyboard[pitch] = key_rect
		if dark:
			blacks.append(pitch)
		else:
			whites.append(pitch)
			next += 1
	note_boxes.clear()

func cover(texture: Texture2D, height: float) -> void:
	var target = Vector2(size.x,height)
	var origin = texture.get_size()
	var scale = maxf(target.x/origin.x,target.y/origin.y)
	var crop = target/scale
	draw_texture_rect_region(texture,Rect2(Vector2.ZERO,target),Rect2((origin-crop)*.5,crop))

func paint_background() -> void:
	var name = settings.background
	if name == "theme":
		name = "soviet" if settings.theme == "soviet" else "aurora"
	var glass = settings.keyStyle == "glass"
	draw_rect(Rect2(Vector2.ZERO,size),Color.BLACK)
	if name == "custom" and custom_image:
		cover(custom_image,size.y)
		draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,settings.backgroundShade/100.0))
	elif name == "soviet":
		cover(PANORAMA,size.y if glass else impact)
		draw_rect(Rect2(0,0,size.x,impact),Color(0.08,0.02,0.05,.22))
	elif BACKDROPS.has(name):
		var colors = BACKDROPS[name]
		draw_rect(Rect2(Vector2.ZERO,size),Color(colors[0]))
		draw_texture_rect(glow_texture,Rect2(Vector2(-size.x*.19,-impact*.29),Vector2(size.x*1.42,impact*1.58)),false,Color(colors[1]).lightened(.24))
		if settings.ambient:
			for i in range(75):
				var x = fposmod(sin((i+2)*38.5)*21412.2,1.0)*size.x
				var y = fposmod(sin((i+3)*85.4)*7942.4,1.0)*impact
				draw_circle(Vector2(x,y),.65 if i%5 else 1.15,Color(1,.8,1,.19))
	if settings.lanes:
		for pitch in blacks:
			var r: Rect2 = keyboard[pitch]
			draw_rect(Rect2(r.position.x,0,r.size.x,impact),Color(.02,.01,.04,.13))
		for pitch in whites:
			var x: float = keyboard[pitch].position.x
			draw_line(Vector2(x,0),Vector2(x,impact),Color(1,.75,.72,.22 if pitch%12==0 else .065))
	if settings.bands:
		for i in range(1,8):
			var y = impact*i/8.0
			draw_line(Vector2(0,y),Vector2(size.x,y),Color(1,.74,.8,.13 if i%2==0 else .07))
	if not glass and name != "black":
		draw_rect(Rect2(0,impact,size.x,size.y-impact),Color("#140911") if settings.theme=="soviet" else Color("#100b1a"))

func visual_box(rect: Rect2, flat: Color, outline: Color, pixels: int, radius: int, glow := false) -> void:
	var id = [flat,outline,pixels,radius,glow]
	if not note_boxes.has(id):
		if note_boxes.size() >= 1024:
			note_boxes.clear()
		var box = StyleBoxFlat.new()
		box.bg_color = flat
		box.border_color = outline
		box.set_border_width_all(pixels)
		box.set_corner_radius_all(radius)
		box.corner_detail = 5
		box.anti_aliasing = radius > 0
		box.draw_center = flat.a > 0
		if glow:
			box.shadow_color = Color(outline,.42)
			box.shadow_size = 6
		note_boxes[id] = box
	draw_style_box(note_boxes[id],rect)

func paint_gradient(rect: Rect2, color: Color, radius: float) -> void:
	radius = minf(radius,minf(rect.size.x,rect.size.y)*.499)
	var points = PackedVector2Array()
	var colors = PackedColorArray()
	var centers = [
		rect.position+Vector2(radius,radius),
		Vector2(rect.end.x-radius,rect.position.y+radius),
		rect.end-Vector2(radius,radius),
		Vector2(rect.position.x+radius,rect.end.y-radius)
	]
	for corner in range(4):
		for step in range(4 if radius>0 else 1):
			var angle = PI+(corner+step/3.0)*PI*.5
			var point = centers[corner]+Vector2(cos(angle),sin(angle))*radius
			points.append(point)
			var t = clampf((point.y-rect.position.y)/rect.size.y,0,1)
			colors.append(color.darkened(.48).lerp(color.lightened(.48),t))
	draw_polygon(points,colors)

func paint_note(note: Dictionary, color: Color, pixels_per_second: float) -> void:
	var key: Rect2 = keyboard[note.pitch]
	var top = maxf(0,impact-(note.end-playback_time)*pixels_per_second)
	var bottom = minf(impact,impact-(note.start-playback_time)*pixels_per_second)
	var height = bottom-top
	if height <= .2:
		return
	var rect = Rect2(key.position.x,top,key.size.x,height)
	var radius = roundi(minf(rect.size.x,height)*settings.noteRoundness/200.0)
	var body = color
	match settings.noteFill:
		"outline": body = Color.TRANSPARENT
		"translucent": body = Color(color,.52)
		"gradient": body = Color.TRANSPARENT
	if settings.noteFill == "gradient":
		paint_gradient(rect,color,radius)
	visual_box(rect,body,color,1,radius,settings.glow)
	if settings.glow and settings.noteFill not in ["outline","gradient"] and height > 4 and rect.size.x > 3:
		draw_rect(Rect2(rect.position.x+1,bottom-2.1,rect.size.x-2,1),Color(1,.95,.88,.58))

func paint_key(pitch: int, accent: Color, active: bool, style: String, dark: bool) -> void:
	var rect: Rect2 = keyboard[pitch]
	var surface = SURFACES[style]
	var body = Color(surface[1 if dark else 0])
	if style == "spectrum":
		body = Color(MIDI.RAINBOW[pitch%12]).darkened(.54 if dark else .03)
	var border = Color(surface[2])
	if active and settings.keys:
		body = accent.lightened(.12 if dark else .35)
		if style == "glass":
			body.a = .70
		border = accent.lightened(.32)
	visual_box(rect,body,border,1,0 if style=="square" else mini(3,int(rect.size.x*.35)),active and settings.keys)
	if not dark and pitch%12 == 0 and key_width > 10.0:
		var font = ThemeDB.fallback_font
		var label = "C%d" % (pitch/12-1)
		var width = font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x
		draw_string(font,rect.position+Vector2((rect.size.x-width)*.5,rect.size.y-5),label,HORIZONTAL_ALIGNMENT_LEFT,-1,9, Color(surface[3]))

func _draw() -> void:
	if size.x < 15.0 or size.y < 55.0:
		return
	build_keys()
	paint_background()
	var active: Dictionary = {}
	var shown = []
	var scale = impact/maxf(.5,settings.horizon)
	for track in layers:
		var visible = []
		var base = Design.track_color(settings,track)
		for i in range(MIDI.from_time(track,playback_time),track.notes.size()):
			var note = track.notes[i]
			if note.start > playback_time+settings.horizon:
				break
			if not keyboard.has(note.pitch):
				continue
			var color = base if track.mode=="solid" else Design.note_color(settings,track,note)
			visible.append([note,color])
			if note.start <= playback_time and not active.has(note.pitch):
				active[note.pitch] = color
		shown.append(visible)
	for pitch in held.values():
		active[pitch] = Design.key_color(settings)
	if settings.beams:
		for pitch in active:
			var r: Rect2 = keyboard.get(pitch,Rect2())
			if r.size.x < 1:
				continue
			var cx = r.get_center().x
			var shade = Color(active[pitch],.67)
			var beam_width = maxf(25,r.size.x*4.4)
			draw_texture_rect(glow_texture,Rect2(cx-beam_width*.5,impact*.58,beam_width,impact*.42),false,shade)
	for row in range(shown.size()-1,-1,-1):
		for item in shown[row]:
			paint_note(item[0],item[1],scale)
	if settings.particles or settings.ripples:
		paint_impacts()
	var style: String = settings.keyStyle
	if style == "theme":
		style = "soviet" if settings.theme=="soviet" else "piano"
	var global_key = Design.key_color(settings)
	for pitch in whites:
		paint_key(pitch,active.get(pitch,global_key) if settings.layerKeys else global_key,active.has(pitch),style,false)
	for pitch in blacks:
		paint_key(pitch,active.get(pitch,global_key) if settings.layerKeys else global_key,active.has(pitch),style,true)
	if settings.strikeLine:
		var accent = Color(palette.get("fill","#ff976f"))
		if settings.ambient:
			for offset in range(1,4):
				draw_line(Vector2(0,impact-offset),Vector2(size.x,impact-offset),Color(accent,.16/offset))
		draw_line(Vector2(0,impact),Vector2(size.x,impact),accent,1.4)

func paint_impacts() -> void:
	var remaining = 55
	for track in layers:
		for i in range(MIDI.next_note(track,maxf(0,playback_time-.60)),track.notes.size()):
			var note = track.notes[i]
			var age = playback_time-note.start
			if age < 0:
				break
			if not keyboard.has(note.pitch):
				continue
			var strength = clampf(1.0-age/.60,0,1)
			var center: Vector2 = keyboard[note.pitch].get_center()
			center.y = impact
			var color = Design.note_color(settings,track,note)
			if settings.ripples:
				var radius = 6.0 + age*44.0
				draw_set_transform(center,0,Vector2(1,.33))
				draw_arc(Vector2.ZERO,radius,PI,TAU,14,Color(color,strength*.54),1,true)
				draw_set_transform(Vector2.ZERO)
			if settings.particles:
				for j in range(7):
					var x = sin((j+1)*37.0+i*2.3)*110.0*age
					var y = maxf(0,(45.0+fposmod(sin(j*32.5+i)*18382.0,80.0))*age-30*age*age)
					draw_circle(center+Vector2(x,-y),.6+strength*1.2,Color(color,strength*.87),true)
			remaining -= 1
			if remaining <= 0:
				return

func press_point(pointer: int, point: Vector2, pressed: bool) -> void:
	var pitch = -1
	if pressed:
		for key in blacks:
			if keyboard[key].has_point(point):
				pitch = key
				break
		if pitch < 0:
			for key in whites:
				if keyboard[key].has_point(point):
					pitch = key
					break
	var previous = held.get(pointer,-1)
	if previous == pitch:
		return
	if previous >= 0:
		audition.emit(previous,pointer,false)
		held.erase(pointer)
	if pitch >= 0:
		held[pointer] = pitch
		audition.emit(pitch,pointer,true)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		press_point(event.index,event.position,event.pressed)
		accept_event()
	elif event is InputEventScreenDrag:
		press_point(event.index,event.position,true)
		accept_event()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.device!=InputEvent.DEVICE_ID_EMULATION:
		press_point(-1,event.position,event.pressed)
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and event.device!=InputEvent.DEVICE_ID_EMULATION:
		press_point(-1,event.position,true)
