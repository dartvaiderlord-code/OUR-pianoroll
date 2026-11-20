extends RefCounted

const MIDI = preload("res://scripts/midi.gd")
const SETTINGS_KEYS = ["theme","language","noteColor","keyColor","keyStyle","background","backgroundShade","range","horizon","noteRoundness","noteFill","ambient","bands","lanes","strikeLine","glow","keys","particles","beams","ripples","layerKeys","hitStyle"]
const BACKGROUNDS = {"theme":"matchTheme","aurora":"aurora","black":"black","orbit":"orbit","ocean":"ocean","sunset":"sunset","custom":"customBackground"}
const KEY_STYLES = {"theme":"matchTheme","piano":"pianoKeys","glass":"glassKeys","neon":"neonKeys","matte":"matteKeys","square":"squareKeys","gold":"goldKeys","spectrum":"rainbowKeys","ice":"iceKeys","inverted":"invertedKeys"}
const NOTE_MODES = {"solid":"colorSingle","pitch":"colorByPitch","octave":"colorByOctave","rainbow":"colorRainbow"}
const FILLS = {"translucent":"fillTranslucent","solid":"fillSolid","outline":"fillOutline","gradient":"fillGradient"}
const HIT_STYLES = {
	"classic":"hitClassic","fireworks":"hitFireworks","echo":"hitEcho",
	"stars":"hitStars","pulse":"hitPulse","none":"hitNone"
}

static func defaults() -> Dictionary:
	return {
		"theme":"soviet","language":"ru","noteColor":"","keyColor":"","keyStyle":"theme","background":"theme","backgroundShade":28.0,
		"range":88,"horizon":4.5,"noteRoundness":50.0,"noteFill":"translucent",
		"ambient":true,"bands":true,"lanes":true,"strikeLine":true,"glow":true,"keys":true,
		"particles":true,"beams":true,"ripples":true,"layerKeys":false,"hitStyle":"classic"
	}

static func theme_colors(settings: Dictionary) -> Dictionary:
	if settings.theme == "classic":
		return {"base":"#0b0a11","head":"#100d18","panel":"#12111b","field":"#181523","line":"#30263c","text":"#f6f3fc","sub":"#b6a9ca","accent":"#c795ff","fill":"#b783fa","gold":"#d4aff9","note":"#e86bff","secondary":"#39e7ef","key":"#b993ff"}
	return {"base":"#10070c","head":"#1a0b14","panel":"#1a0d15","field":"#26131b","line":"#663329","text":"#fff2e3","sub":"#d9b9b0","accent":"#ffc98b","fill":"#ff976f","gold":"#ffc685","note":"#ff685d","secondary":"#ffc86f","key":"#ffb16d"}

static func track_color(settings: Dictionary, track: Dictionary) -> Color:
	var colors = theme_colors(settings)
	if not track.color.is_empty():
		return Color(track.color)
	if track.demo == "demoBassFilename":
		return Color(colors.secondary)
	return Color(colors.note if settings.noteColor.is_empty() else settings.noteColor)

static func note_color(settings: Dictionary, track: Dictionary, note: Dictionary) -> Color:
	var base = track_color(settings,track)
	if track.mode == "solid":
		return base
	var color_index = note.index
	if track.mode == "pitch":
		color_index = note.pitch % 12
	elif track.mode == "octave":
		color_index = (note.pitch / 12) * 5
	return base if color_index % MIDI.RAINBOW.size() == 0 else Color(MIDI.RAINBOW[(color_index+roundi(base.h*12.0))%MIDI.RAINBOW.size()])

static func key_color(settings: Dictionary) -> Color:
	return Color(theme_colors(settings).key if settings.keyColor.is_empty() else settings.keyColor)
