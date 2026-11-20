'use strict';

function parseMidi(buffer) {
  let bytes = new Uint8Array(buffer);
  const view = () => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = pos => String.fromCharCode(...bytes.subarray(pos, pos + 4));
  function invalid(key = 'midiDamaged') { throw new LocalizedError(key); }

  if (tag(0) === 'RIFF' && tag(8) === 'RMID') {
    for (let at = 12; at + 8 <= bytes.length;) {
      const size = view().getUint32(at + 4, true);
      if (at + 8 + size > bytes.length) invalid();
      if (tag(at) === 'data') { bytes = bytes.subarray(at + 8, at + 8 + size); break; }
      at += 8 + size + (size & 1);
    }
  }
  if (bytes.length < 14 || tag(0) !== 'MThd') invalid('midiUnrecognized');
  const data = view();
  const headerSize = data.getUint32(4);
  const format = data.getUint16(8);
  const count = data.getUint16(10);
  const division = data.getUint16(12);
  if (headerSize < 6 || format > 2 || !count || !division || (format === 0 && count !== 1)) invalid();
  const smpte = division >> 8;
  const fps = [232, 231, 227, 226].includes(smpte) ? (smpte === 227 ? 30000 / 1001 : 256 - smpte) : 0;
  if (division & 0x8000 && (!fps || !(division & 255))) invalid();

  let offset = 8 + headerSize;
  let order = 0;
  const tracks = [];
  while (tracks.length < count) {
    if (offset + 8 > bytes.length) invalid();
    const type = tag(offset);
    const size = data.getUint32(offset + 4);
    const end = offset + 8 + size;
    if (end > bytes.length) invalid();
    offset += 8;
    if (type !== 'MTrk') { offset = end; continue; }
    let tick = 0;
    let running = 0;
    const events = [];
    const read = () => {
      if (offset >= end) invalid();
      return bytes[offset++];
    };
    const payload = () => {
      const value = read();
      if (value > 127) invalid();
      return value;
    };
    function variable() {
      let value = 0;
      for (let i = 0; i < 4; i++) {
        const byte = read();
        value = value * 128 + (byte & 127);
        if (byte < 128) return value;
      }
      invalid();
    }
    while (offset < end) {
      tick += variable();
      if (!Number.isSafeInteger(tick)) invalid();
      let status = read();
      if (status < 128) {
        if (!running) invalid();
        offset--;
        status = running;
      }
      if (status < 240) {
        running = status;
        const kind = status >> 4;
        const channel = status & 15;
        const key = payload();
        const value = kind === 12 || kind === 13 ? 0 : payload();
        if (kind === 8 || kind === 9 || kind === 11 || kind === 12) {
          events.push({ tick, kind, channel, key, value, order: order++ });
        }
      } else if (status === 255) {
        running = 0;
        const meta = read();
        const length = variable();
        if (offset + length > end) invalid();
        if (meta === 81 && length === 3) {
          const tempo = (bytes[offset] << 16) + (bytes[offset + 1] << 8) + bytes[offset + 2];
          if (tempo) events.push({ tick, tempo, order: order++ });
        }
        offset += length;
        if (meta === 47) break;
      } else if (status === 240 || status === 247) {
        running = 0;
        const length = variable();
        offset += length;
        if (offset > end) invalid();
      } else {
        invalid('midiUnsupportedEvent');
      }
    }
    tracks.push({ events, end: tick });
    offset = end;
  }

  function convert(group) {
    const events = group.flatMap(track => track.events).sort((a, b) => a.tick - b.tick || a.order - b.order);
    const channels = Array.from({length:16}, () => ({ program:0, pedal:false, held:new Map(), sustained:[] }));
    const notes = [];
    let tick = 0;
    let time = 0;
    let secondsPerTick = fps ? 1 / (fps * (division & 255)) : 0.5 / division;
    function finish(note, end) {
      note.end = Math.max(note.start + 0.045, end);
      notes.push(note);
    }
    for (const event of events) {
      time += (event.tick - tick) * secondsPerTick;
      tick = event.tick;
      if (event.tempo) {
        if (!fps) secondsPerTick = event.tempo / 1000000 / division;
        continue;
      }
      const { channel, key, value, kind } = event;
      const state = channels[channel];
      if (kind === 12) { state.program = key; continue; }
      if (kind === 11) {
        if (key === 64 || key === 121) {
          state.pedal = key === 64 && value >= 64;
          if (!state.pedal) {
            for (const note of state.sustained) finish(note, time);
            state.sustained.length = 0;
          }
        } else if (key === 120 || key === 123) {
          for (const pending of state.held.values()) {
            for (const note of pending) {
              if (key === 123 && state.pedal) state.sustained.push(note);
              else finish(note, time);
            }
          }
          state.held.clear();
          if (key === 120) {
            for (const note of state.sustained) finish(note, time);
            state.sustained.length = 0;
          }
        }
        continue;
      }
      const pending = state.held.get(key);
      if (kind === 9 && value) {
        const note = { pitch:key, start:time, end:time, velocity:value / 127, program:state.program, channel };
        if (pending) pending.push(note);
        else state.held.set(key, [note]);
      } else if (pending?.length) {
        const note = pending.shift();
        if (!pending.length) state.held.delete(key);
        if (state.pedal && channel !== 9) state.sustained.push(note);
        else finish(note, time);
      }
    }
    let endTick = tick;
    for (const track of group) endTick = Math.max(endTick, track.end);
    const end = time + (endTick - tick) * secondsPerTick;
    for (const state of channels) {
      for (const pending of state.held.values()) for (const note of pending) finish(note, end);
      for (const note of state.sustained) finish(note, end);
    }
    return { notes, end };
  }
  const notes = [];
  let duration = 0;
  const groups = format === 2 ? tracks.map(track => [track]) : [tracks];
  for (const group of groups) {
    const result = convert(group);
    let length = result.end;
    for (const note of result.notes) {
      length = Math.max(length, note.end);
      note.start += duration;
      note.end += duration;
      notes.push(note);
    }
    duration += length;
  }
  if (!notes.length) invalid('midiNoNotes');
  return { notes, duration };
}

const palette = ['#e86bff','#39e7ef','#9d86ff','#ffae61','#85f696','#fb729d','#79aaff','#f5dd76','#7bffcb','#ff9579','#b3aaff','#f7acff','#a8d25f','#4facec','#ff74c9','#d5efd2'];
const rainbow = ['#ff698e','#ff8968','#ffbf69','#f1ed72','#a3f77c','#57edbd','#4de2fe','#649dff','#8987ff','#bb80ff','#e675ff','#ff78d1'];
const themes = {
  classic:{ noteColor:palette[0], keyColor:'#b993ff', secondaryColor:palette[1], palette, background:'aurora', keyboard:'piano' },
  soviet:{
    noteColor:'#ff685d', keyColor:'#ffb16d', secondaryColor:'#ffc86f',
    palette:['#ff685d','#ffc86f','#ff86a5','#e8ac76',...palette.slice(2)],
    background:'soviet', keyboard:'soviet'
  }
};
const noteModes = { solid:'colorSingle', pitch:'colorByPitch', octave:'colorByOctave', rainbow:'colorRainbow' };
const noteFills = ['translucent','solid','outline','gradient'];
const keyStyles = ['theme','piano','glass','neon','matte','square','gold','spectrum','ice','inverted'];
const backgroundStyles = ['theme','aurora','black','orbit','ocean','sunset','custom'];
const defaultEffects = {
  glow:true, keys:true, particles:true, beams:true, ambient:true, ripples:true,
  bands:true, lanes:true, strikeLine:true, layerKeys:false
};
const defaultStyle = {
  theme:'soviet', noteColor:null, keyColor:null, keyStyle:'theme', background:'theme', backgroundShade:28,
  range:88, horizon:4.5, noteRoundness:50, noteFill:'translucent', effects:{...defaultEffects}
};
const validColor = color => typeof color === 'string' && /^#[\da-f]{6}$/i.test(color);
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

function readStyle() {
  const result = { ...defaultStyle, effects:{...defaultEffects} };
  try {
    const saved = JSON.parse(localStorage.getItem('neon-midi-style-v1'));
    if (!saved) return result;
    const hasTheme = Object.hasOwn(themes,saved.theme);
    if (hasTheme) result.theme = saved.theme;
    for (const key of ['noteColor','keyColor']) {
      if (validColor(saved[key]) && (hasTheme || saved[key].toLowerCase() !== themes.classic[key])) result[key] = saved[key];
    }
    if (keyStyles.includes(saved.keyStyle) && (hasTheme || saved.keyStyle !== 'piano')) result.keyStyle = saved.keyStyle;
    if (backgroundStyles.includes(saved.background) && (hasTheme || saved.background !== 'aurora')) result.background = saved.background;
    if (Number.isFinite(saved.backgroundShade)) result.backgroundShade = clamp(saved.backgroundShade,0,85);
    if (Number.isFinite(saved.noteRoundness)) result.noteRoundness = clamp(Math.round(saved.noteRoundness),0,100);
    if (noteFills.includes(saved.noteFill)) result.noteFill = saved.noteFill;
    if ([88,128].includes(saved.range)) result.range = saved.range;
    if ([2.5,4.5,7].includes(saved.horizon)) result.horizon = saved.horizon;
    if (typeof saved.effects?.grid === 'boolean') {
      result.effects.bands = result.effects.lanes = saved.effects.grid;
    }
    for (const key of Object.keys(defaultEffects)) if (typeof saved.effects?.[key] === 'boolean') result.effects[key] = saved.effects[key];
  } catch {}
  return result;
}

function makeLayer(name, notes, duration, color = null, demo = false) {
  notes.sort((a,b) => a.start - b.start || a.pitch - b.pitch);
  const prefixEnd = new Float64Array(notes.length);
  let latestEnd = 0;
  for (let i = 0; i < notes.length; i++) {
    notes[i].index = i;
    latestEnd = Math.max(latestEnd, notes[i].end);
    prefixEnd[i] = latestEnd;
  }
  return { name, notes, duration, color, noteMode:'solid', demo, enabled:true, prefixEnd };
}

function makeDemo() {
  const bass = [];
  const lead = [];
  const progression = [
    [42,49,54,57,61,66,69,73], [38,45,50,54,57,66,69,74],
    [45,52,57,61,64,69,73,76], [40,47,52,56,59,68,71,76]
  ];
  const beat = .48;
  const bars = 24;
  function add(notes, pitch, start, span, velocity, program) {
    notes.push({pitch,start:start*beat,end:(start+span)*beat,velocity,program,channel:0});
  }
  for (let bar = 0; bar < bars; bar++) {
    const chord = progression[bar % 4];
    const t = bar * 4;
    add(bass,chord[0],t,1.85,.75,0);
    add(bass,chord[1],t+.5,.69,.54,0);
    add(bass,chord[2],t+1,1.14,.6,0);
    add(bass,chord[3],t+1.5,.76,.45,0);
    add(bass,chord[1],t+2,.9,.58,0);
    add(bass,chord[4],t+2.5,1.18,.53,0);
    add(bass,chord[2],t+3.25,.53,.48,0);
    const shape = bar % 4 === 0 ? [[6,0,1.25],[5,.75,.65],[7,1.5,1.05],[6,2.5,.67],[5,3.25,.54]]
      : bar % 4 === 1 ? [[7,0,.82],[6,.64,.65],[5,1.25,1.32],[6,2.25,.57],[4,3,.82]]
      : [[5,0,.79],[6,.5,.64],[7,1.25,1.05],[6,2.35,.66],[5,3,.95]];
    for (const [degree, when, span] of shape) add(lead,chord[degree],t+when,span,.76,11);
    if (bar % 2 === 0) {
      add(lead,chord[7]+12,t+2.15,.9,.39,11);
      add(lead,chord[5]+12,t+3.06,.46,.47,11);
    }
    if (bar % 4 === 0) add(lead,chord[4],t,.6,.34,11);
  }
  const duration = bars * 4 * beat;
  const accompaniment = makeLayer('demoBassFilename',bass,duration,null,true);
  accompaniment.useSecondaryColor = true;
  return [
    makeLayer('demoLeadFilename',lead,duration,null,true),
    accompaniment
  ];
}

function lowerBound(notes, time) {
  let low = 0, high = notes.length;
  while (low < high) {
    const mid = (low + high) >>> 1;
    if (notes[mid].start < time) low = mid + 1;
    else high = mid;
  }
  return low;
}
function firstOverlapping(layer, time) {
  let low = 0, high = layer.notes.length;
  while (low < high) {
    const mid = (low + high) >>> 1;
    if (layer.prefixEnd[mid] <= time) low = mid + 1;
    else high = mid;
  }
  return low;
}
