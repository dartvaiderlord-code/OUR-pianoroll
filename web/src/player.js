const $ = id => document.getElementById(id);
const state = {
  style:readStyle(), layers:makeDemo(), active:[], limit:4, duration:0, position:0,
  playing:false, starting:false, loop:false, speed:1, volume:.7, lastVolume:.7, run:0
};
const activeTheme = () => themes[state.style.theme];
const primaryNoteColor = () => state.style.noteColor || activeTheme().noteColor;
const activeKeyColor = () => state.style.keyColor || activeTheme().keyColor;
const colorOf = layer => layer.color || (layer.useSecondaryColor ? activeTheme().secondaryColor : primaryNoteColor());
const notePalettes = new WeakMap();
const rgbComponents = color => [1,3,5].map(at => parseInt(color.slice(at,at+2),16));
const rainbowComponents = rainbow.map(rgbComponents);
function paletteOf(layer) {
  const base = colorOf(layer);
  if (layer.noteMode === 'solid') return [base];
  const saved = notePalettes.get(layer);
  if (saved?.base === base) return saved.colors;
  const rgb = rgbComponents(base);
  let nearest = 0, distance = Infinity;
  for (let i = 0; i < rainbow.length; i++) {
    const difference = rainbowComponents[i].reduce((sum,value,index) => sum+(value-rgb[index])**2,0);
    if (difference < distance) { nearest = i; distance = difference; }
  }
  const colors = rainbow.map((_,index) => index === 0 ? base : rainbow[(index+nearest)%rainbow.length]);
  notePalettes.set(layer,{base,colors});
  return colors;
}
function noteColorOf(layer,note) {
  if (layer.noteMode === 'solid') return colorOf(layer);
  const colors = paletteOf(layer);
  if (layer.noteMode === 'pitch') return colors[note.pitch % 12];
  if (layer.noteMode === 'octave') return colors[Math.floor(note.pitch/12)*5 % colors.length];
  return colors[note.index % colors.length];
}
const media = matchMedia('(prefers-reduced-motion: reduce)');
let audio, master, limiter, noise;
let anchorPosition = 0, anchorTime = 0, resumeNotes = false;
const voices = new Set();
const indexes = new Map();
const previews = new Map();

function initAudio() {
  if (audio) return;
  const Audio = window.AudioContext || window.webkitAudioContext;
  if (!Audio) throw new LocalizedError('audioUnavailable');
  audio = new Audio();
  limiter = audio.createDynamicsCompressor();
  limiter.threshold.value = -19;
  limiter.knee.value = 22;
  limiter.ratio.value = 6;
  master = audio.createGain();
  master.gain.value = state.volume;
  master.connect(limiter).connect(audio.destination);
  noise = audio.createBuffer(1, Math.ceil(audio.sampleRate * .4), audio.sampleRate);
  const values = noise.getChannelData(0);
  for (let i = 0; i < values.length; i++) values[i] = Math.random() * 2 - 1;
}

function silence(voice) {
  voices.delete(voice);
  if (voice.ended) return;
  const now = audio.currentTime;
  voice.gain.gain.cancelScheduledValues(now);
  voice.gain.gain.setTargetAtTime(.0001, now, .008);
  for (const node of voice.sources) {
    try { node.stop(now + .035); } catch {}
  }
}

function voiceFor(note, at, span, preview = false) {
  if (voices.size >= 96) {
    const oldest = [...voices].find(voice => !voice.preview);
    if (!oldest) return;
    silence(oldest);
  }
  const duration = clamp(span, .033, 7200);
  const drum = note.channel === 9;
  const kick = drum && [35,36,41,43,45].includes(note.pitch);
  const hz = 440 * 2 ** ((note.pitch - 69) / 12);
  const family = note.program >> 3;
  const bell = family === 1;
  const sustained = !drum && [2,5,6,7,8,9,10,11,12].includes(family);
  const gain = audio.createGain();
  const filter = audio.createBiquadFilter();
  const sources = [];
  const level = (note.velocity ** 1.65) * (drum ? .19 : .125);
  const release = drum ? .05 : sustained ? .095 : .22;
  const gate = at + (drum ? Math.min(duration, kick ? .26 : .16) : duration);
  filter.type = drum && !kick ? 'highpass' : 'lowpass';
  filter.frequency.value = drum ? (kick ? 1100 : note.pitch >= 42 ? 2600 : 850) : Math.min(6000, hz * (7 + note.velocity * 8));
  filter.Q.value = .45;
  filter.connect(gain).connect(master);
  gain.gain.setValueAtTime(.0001, at);
  gain.gain.linearRampToValueAtTime(Math.max(.0002,level), at + .009);
  const decayEnd = Math.min(at + .22, gate);
  const bodyLevel = Math.max(.0002,level * (sustained ? .69 : bell ? .43 : .34));
  gain.gain.exponentialRampToValueAtTime(bodyLevel, decayEnd);
  if (!sustained) gain.gain.exponentialRampToValueAtTime(Math.max(.00012,bodyLevel * Math.exp(-(gate - decayEnd) / (bell ? .87 : 1.7))), gate);
  else gain.gain.setValueAtTime(bodyLevel, gate);
  gain.gain.exponentialRampToValueAtTime(.0001, gate + release);

  function osc(type, frequency, amount) {
    const source = audio.createOscillator();
    const mix = audio.createGain();
    mix.gain.value = amount;
    source.type = type;
    source.frequency.setValueAtTime(Math.min(frequency, audio.sampleRate * .45), at);
    source.connect(mix).connect(filter);
    sources.push(source);
    return source;
  }
  if (kick) {
    osc('sine', 133, .95).frequency.exponentialRampToValueAtTime(43, at + .12);
  } else if (drum) {
    const source = audio.createBufferSource();
    source.buffer = noise;
    source.connect(filter);
    sources.push(source);
  } else if (sustained) {
    osc('triangle',hz,.83);
    osc('sine',hz * 2,.24);
  } else {
    osc('triangle',hz,.88);
    osc('sine',hz * (bell ? 2.76 : 2),bell ? .29 : .18);
    osc('sine',hz * (bell ? 4.05 : 3),.075);
  }
  const voice = { gain, sources, preview, ended:false };
  const end = gate + release + .01;
  sources[0].onended = () => {
    voice.ended = true;
    voices.delete(voice);
    gain.disconnect();
  };
  for (const source of sources) {
    source.start(at);
    source.stop(end);
  }
  voices.add(voice);
  return voice;
}

function stopPlaybackVoices() {
  for (const voice of voices) if (!voice.preview) silence(voice);
}
function position() {
  if (!state.playing) return state.position;
  return clamp(anchorPosition + (audio.currentTime - anchorTime) * state.speed, 0, state.duration);
}

function restartAudio(time, sustain = true) {
  stopPlaybackVoices();
  anchorTime = audio.currentTime + .035;
  anchorPosition = time;
  resumeNotes = sustain;
  indexes.clear();
  for (const layer of state.active) indexes.set(layer, lowerBound(layer.notes,time));
  schedule();
}

function schedule() {
  if (!state.playing) return;
  const now = audio.currentTime;
  const time = position();
  if (time >= state.duration) {
    if (state.loop && state.duration > 0) {
      jump(0);
    } else {
      pause();
      state.position = state.duration;
      markDirty();
      stopRecording();
    }
    return;
  }
  const lookAhead = anchorPosition + (now + .15 - anchorTime) * state.speed;
  for (const layer of state.active) {
    if (resumeNotes) {
      const past = lowerBound(layer.notes,anchorPosition);
      for (let i = firstOverlapping(layer,anchorPosition); i < past; i++) {
        const note = layer.notes[i];
        if (note.end > anchorPosition + .04) voiceFor(note, Math.max(anchorTime,now+.006),(note.end-anchorPosition)/state.speed);
      }
    }
    const notes = layer.notes;
    let i = Math.max(indexes.get(layer) || 0, lowerBound(notes, time - .08 * state.speed));
    while (i < notes.length && notes[i].start <= lookAhead) {
      const note = notes[i++];
      if (note.end > time) {
        const at = anchorTime + (note.start-anchorPosition)/state.speed;
        voiceFor(note,Math.max(now+.006,at),(note.end-Math.max(note.start,time))/state.speed);
      }
    }
    indexes.set(layer,i);
  }
  resumeNotes = false;
}

async function play() {
  if (state.playing || state.starting || !state.duration) return;
  const run = ++state.run;
  state.starting = true;
  try {
    initAudio();
    if (audio.state !== 'running') await audio.resume();
    if (run !== state.run || !state.duration) return;
    if (state.position >= state.duration - .01) state.position = 0;
    state.playing = true;
    restartAudio(state.position);
    updateTransport();
    markDirty();
  } catch (error) {
    notice(errorMessage(error,'audioFailed'));
  } finally {
    if (run === state.run) state.starting = false;
  }
}

function pause() {
  state.position = position();
  state.playing = state.starting = false;
  state.run++;
  stopPlaybackVoices();
  updateTransport();
  markDirty();
}

function jump(time) {
  state.position = clamp(time,0,state.duration);
  if (state.playing) {
    if (state.position >= state.duration) {
      state.playing = false;
      stopPlaybackVoices();
      updateTransport();
    } else restartAudio(state.position);
  }
  clearEffects();
  markDirty();
}

async function previewKey(note, pointer) {
  const preview = { pitch:note, voice:null };
  releaseKey(pointer);
  previews.set(pointer,preview);
  emitImpact(note,activeKeyColor(),.77);
  markDirty();
  try {
    initAudio();
    if (audio.state !== 'running') await audio.resume();
    if (previews.get(pointer) === preview) {
      preview.voice = voiceFor({pitch:note,velocity:.8,program:0,channel:0},audio.currentTime+.008,1.8,true);
    }
  } catch (error) {
    notice(errorMessage(error,'audioFailed'));
  }
}

function releaseKey(pointer) {
  const preview = previews.get(pointer);
  if (preview?.voice) silence(preview.voice);
  previews.delete(pointer);
  markDirty();
}

setInterval(schedule,35);
