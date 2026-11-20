extends HSlider

const Design = preload("res://scripts/design.gd")
const BINS = 220
var bars: Array = []
var colors: Array = []
var skin: Dictionary = {}

func configure(layers: Array, duration: float, prefs: Dictionary) -> void:
	bars.resize(BINS)
	bars.fill(0.0)
	colors.resize(BINS)
	colors.fill(Color.TRANSPARENT)
	skin = Design.theme_colors(prefs)
	if duration > 0:
		for layer in layers:
			var base = Design.track_color(prefs,layer)
			for note in layer.notes:
				var index = mini(BINS-1,int(note.start/duration*BINS))
				bars[index] += note.velocity
				if layer.mode == "solid":
					colors[index] = base
				else:
					colors[index] = Design.note_color(prefs,layer,note)
	queue_redraw()

func _ready() -> void:
	value_changed.connect(func(_value): queue_redraw())

func _draw() -> void:
	if skin.is_empty():
		return
	draw_rect(Rect2(0,0,size.x,size.y),Color(skin.base))
	draw_rect(Rect2(0,0,size.x*value,size.y),Color(Color(skin.accent),.1))
	draw_line(Vector2(0,size.y/2),Vector2(size.x,size.y/2),Color(Color(skin.accent),.24))
	var step_x = size.x/BINS
	for i in range(BINS):
		if bars[i] <= 0:
			continue
		var height = minf(size.y-8,4+log(1+bars[i])*17)
		draw_rect(Rect2(i*step_x,(size.y-height)/2,maxf(.7,step_x-1.2),height),Color(colors[i],.85 if i/BINS<value else .54))
	draw_line(Vector2(size.x*value,2),Vector2(size.x*value,size.y-2),Color(skin.gold),1.8)
